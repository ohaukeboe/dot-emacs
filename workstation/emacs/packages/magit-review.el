;; -*- lexical-binding: t; -*-
;;; magit-review.el --- Review comments in Magit, handed off to a coding agent

;; Package-Requires: ((emacs "30.1") (magit "4.0") (transient "0.7"))

;;; Commentary:

;; A hunk.dev-style review loop.  `magit-review-comment' attaches a review
;; comment to the thing at point in a Magit buffer: a hunk, hunk region or
;; file; one commit or stash, or every one a region selects; a revision
;; buffer's headers or commit message (its commit, with a region of the
;; message quoted); a stash buffer as a whole or any of its rows (its
;; stash); the staged, unstaged or untracked changes; or any other
;; section, such as a branch, a tag or the upstream's commit list; or, in
;; a walkthrough, a step or a passage of its explanation.
;; `magit-review-send' hands every pending comment of the repository to its
;; coding agent as one prompt, together with the findings the user accepted
;; in the repository's walkthroughs, and marks them sent.
;; `magit-review-comment-send' hands one comment off on its own at once (a
;; direct comment), leaving the others pending.  Comments live in memory,
;; per repository toplevel, so a comment made in a worktree goes to that
;; worktree's agent.  A comment on commits carries no patch and no message
;; body: it names each commit by short id and subject, and the agent reads
;; the commit itself.
;;
;; `magit-review-decorate' draws the comments in status, diff, revision,
;; log, refs and stash buffers, unsent ones highlighted and sent ones
;; dimmed: a hunk comment below its last commented line, with a count on
;; each file heading; a comment on one commit or stash below every line
;; that shows it, and one on several once, below the last of them in the
;; buffer; any other below every heading it is on.  Commits are matched by
;; their full ids, so a comment on a commit that is later rewritten is
;; drawn nowhere but stays pending.
;;
;; The agent is plugged in through `magit-review-send-function'; this file
;; names no agent package.  `magit-review-items' and `magit-review-format'
;; let the configuration show the review to the agent another way, such as
;; an MCP tool.  Loading this file changes nothing: the configuration binds
;; the `magit-review' menu and adds `magit-review-decorate' to
;; `magit-refresh-buffer-hook', e.g.
;;
;;   (setopt magit-review-send-function #'my-agent-paste)
;;   (add-hook 'magit-refresh-buffer-hook #'magit-review-decorate)
;;   (keymap-set magit-mode-map "@" #'magit-review)
;;
;; walkthrough.el is used when it is available, through a soft `require':
;; for the label of a committed range, patch excerpts, comments on steps,
;; replies to findings and the accepted findings handed off with the
;; comments.  `magit-review-walkthrough-comments' is meant for
;; `walkthrough-comments-function', so a walkthrough draws the comments on
;; its steps.
;;
;; Magit internals this file relies on, to recheck when bumping Magit
;; (Magit has renamed buffer-local variables without aliases before):
;; `magit-buffer-revision-oid', the full id of a revision buffer's commit;
;; `magit-buffer-revision', a stash buffer's stash as `stash@{N}'; the
;; hunk section slots `from-range', `to-range', `content' and `combined';
;; `magit-diff-type', `magit-diff-hunk-line',
;; `magit-diff-use-hunk-region-p', `magit-diff-hunk-region-beginning' and
;; `magit-diff-hunk-region-patch'; `magit-region-sections',
;; `magit-root-section' and the section types and values: `commit' valued
;; by an id, abbreviated in logs and status lists, or in a stash buffer by
;; `stash@{N}' and its `^2' and `^3'; `stash' valued `stash@{N}', or nil
;; as a stash buffer's root; a revision buffer's `headers' and
;; `commit-message', whose commit ids are `commit' children; `staged',
;; `unstaged' and `untracked'; and, in a log showing patches, hunks inside
;; their commit's section.  walkthrough.el's label reads
;; `magit-buffer-diff-range' and `magit-buffer-diff-range-oids'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'magit)
(require 'transient)

(declare-function walkthrough-diff-label "walkthrough" ())
(declare-function walkthrough-patch-excerpt "walkthrough" (hunk &optional range side))
(declare-function walkthrough-finding-at-point-p "walkthrough" ())
(declare-function walkthrough-reply "walkthrough" (id text))
(declare-function walkthrough-accepted-findings "walkthrough" (repo &optional include-sent))
(declare-function walkthrough-mark-sent "walkthrough" (items))
(declare-function walkthrough-comment-target "walkthrough" ())
(declare-function walkthrough-redraw-comments "walkthrough" ())
(declare-function gfm-view-mode "markdown-mode")

(defgroup magit-review nil
  "Review comments in Magit, handed off to a coding agent."
  :group 'magit-extensions)

(defcustom magit-review-send-function nil
  "Function that hands a review prompt to the repository's coding agent.
Called as (TEXT SUBMIT) from the Magit buffer the hand-off was made in.
Deliver TEXT to the agent's input as one paste, so a newline in it does
not submit half of it, and press return only when SUBMIT is non-nil.
`current-prefix-arg' is nil during the call, since the hand-off's prefix
argument means \"do not submit\".  Signal `user-error' when there is no
agent.  Return the agent's buffer.  Nil means no agent is configured."
  :type '(choice (const :tag "No agent" nil) function))

(defface magit-review-comment
  '((t :inherit font-lock-warning-face))
  "Face for unsent review comments shown in Magit buffers.")

(defface magit-review-sent
  '((t :inherit shadow))
  "Face for review comments already handed off to the agent.")

;;; Comments

(defvar magit-review-comments nil
  "Review comments on what Magit shows, newest first.
Each comment is a plist with :repo, :target, :text and :sent, and keys
that depend on :target, the kind of thing the comment is on (see
`magit-review-comment' for what each kind covers):

 `diff'     :file, :where (the diff's label), :new and :old, (START . END)
            line ranges or nil, and :patch.
 `commits'  :commits, a list of plists with the full commit :id, the
            :abbrev git showed and the :subject, plus for a stash its
            :stash name at comment time; and :quote, the part of a
            commit message quoted, or nil.
 `group'    :group, the section type `staged', `unstaged' or `untracked'.
 `section'  the section's :type, its :value when that is a string, and
            its :heading line as shown.
 `step'     :where, the walkthrough's diff label, and :step, what
            `walkthrough-comment-target' returned.")

(defun magit-review--step-comment-p (comment)
  "Return non-nil when COMMENT is on a walkthrough step or passage."
  (eq (plist-get comment :target) 'step))

(defun magit-review--step-target ()
  "Return the walkthrough step or passage at point, or nil.
See `walkthrough-comment-target'."
  (and (derived-mode-p 'walkthrough-mode) (walkthrough-comment-target)))

(defun magit-review--region-end ()
  "Return the end of the active region, before a line it only touches.
A region ending at the start of a line does not cover that line, so the
end is then the end of the line before."
  (let ((end (region-end)))
    (if (and (> end (region-beginning))
             (save-excursion (goto-char end) (bolp)))
        (1- end)
      end)))

(defun magit-review--range (section from)
  "Return the (START . END) lines of hunk SECTION on the old side if FROM.
Uses the active region when there is one, else the whole hunk.  Returns
nil when the region has no lines on that side (only additions for the
old side, only removals for the new side)."
  (if (magit-diff-use-hunk-region-p)
      (let ((beg (magit-diff-hunk-region-beginning))
            (end (magit-review--region-end)))
        (when (save-excursion
                (goto-char beg)
                (re-search-forward (if from "^[- ]" "^[+ ]") end t))
          (cons (save-excursion
                  (goto-char beg)
                  (magit-diff-hunk-line section from))
                (save-excursion
                  (goto-char end)
                  (magit-diff-hunk-line section from)))))
    ;; A range is (START LENGTH); LENGTH defaults to 1 and is 0 when
    ;; that side has no lines (new/deleted file, pure removal/addition).
    (when-let* ((range (slot-value section (if from 'from-range 'to-range)))
                (length (or (cadr range) 1))
                ((> length 0)))
      (cons (car range) (+ (car range) length -1)))))

(defvar magit-review--labels nil
  "Diff labels of commits by commit, cached during one drawing pass.")

(defun magit-review--commit-label (rev)
  "Return the label of the diff of commit REV against its first parent.
It names both by their full ids, as `walkthrough-diff-label' names a
range, so a comment on a commit's hunk is the same comment in its
revision buffer, in a log showing patches and in a walkthrough of that
one commit.  A root commit, with no parent, is named by its id alone."
  (or (and magit-review--labels (gethash rev magit-review--labels))
      (let ((label
             (pcase (split-string (or (magit-git-string "rev-list" "--max-count=1"
                                                        "--parents" rev "--")
                                      ""))
               (`(,commit ,parent . ,_) (format "diff of %s..%s" parent commit))
               (`(,commit) (format "diff of %s" commit)))))
        (when magit-review--labels
          (puthash rev label magit-review--labels))
        label)))

(defun magit-review--log-commit-value (section)
  "Return the value of the commit section whose patch in a log has SECTION.
That is the commit's id as the log shows it, abbreviated."
  (when (derived-mode-p 'magit-log-mode)
    (while (and section (not (eq (oref section type) 'commit)))
      (setq section (oref section parent)))
    (and section (oref section value))))

(defun magit-review--revision-id ()
  "Return the full id of a revision buffer's commit, or nil elsewhere."
  (and (derived-mode-p 'magit-revision-mode) magit-buffer-revision-oid))

(defun magit-review--where (section)
  "Describe which diff SECTION belongs to.
One commit's diff, in its revision buffer or in a log showing patches,
is named by the commit and its first parent (`magit-review--commit-label').
Another committed range is named by its commit ids, as
`walkthrough-diff-label' does, so a comment made in a walkthrough is the
same comment in `magit-diff' of the same commits.  Magit renamed
`magit-buffer-range' to `magit-buffer-diff-range' without an alias;
reading the old name made every range diff plain \"diff\"."
  (pcase (magit-diff-type section)
    ('unstaged "unstaged changes")
    ('staged "staged changes")
    ('untracked "untracked file")
    (_ (cond ((when-let* ((commit (or (magit-review--log-commit-value section)
                                      (magit-review--revision-id))))
                (magit-review--commit-label commit)))
             ((and (require 'walkthrough nil t) (walkthrough-diff-label)))
             ((bound-and-true-p magit-buffer-revision-oid)
              (format "diff of %s" magit-buffer-revision-oid))
             ("diff")))))

(defconst magit-review--stash-name-re "\\`stash@{[0-9]+}\\'"
  "Regexp matching a stash's `stash@{N}' name, which Magit uses as value.")

(defconst magit-review--groups
  '((staged . "All staged changes")
    (unstaged . "All unstaged changes")
    (untracked . "All untracked files"))
  "The status buffer's groups of changes, by section type, with headings.")

(defun magit-review--commit-entry (rev &optional stash)
  "Return commit REV as a commit entry of a `commits' comment.
The entry is a plist with the full commit :id, the :abbrev git shows and
the :subject.  If STASH, it is a stash, and the entry also has :stash,
REV's `stash@{N}' name if it is one; the subject is then the stash's
message."
  (pcase-let ((`(,id ,abbrev ,subject)
               (split-string (or (magit-rev-format "%H%x00%h%x00%s" rev)
                                 (user-error "No commit %s" rev))
                             "\0")))
    (append (list :id id :abbrev abbrev :subject subject)
            (and stash
                 (list :stash (and (string-match-p magit-review--stash-name-re rev)
                                   rev))))))

(defun magit-review--section-commit-entry (section)
  "Return the commit entry of commit or stash SECTION.
In a stash buffer every one is the stash it shows: its root and the rows
of the stash's own, staged (`stash@{N}^2') and untracked (`stash@{N}^3')
commits."
  (if (derived-mode-p 'magit-stash-mode)
      (magit-review--commit-entry magit-buffer-revision t)
    (magit-review--commit-entry (substring-no-properties (oref section value))
                                (magit-section-match 'stash section))))

(defun magit-review--in-message-p (&optional pos)
  "Return non-nil when POS, or point, is in a revision's commit message."
  (magit-section-match '[* commit-message] (magit-section-at pos)))

(defun magit-review--quote ()
  "Return the active region if it lies in a revision's commit message."
  (when-let* (((use-region-p))
              ((magit-review--in-message-p (region-beginning)))
              ((magit-review--in-message-p (magit-review--region-end))))
    (buffer-substring-no-properties (region-beginning) (region-end))))

(defun magit-review--target ()
  "Return what a review comment at point is on, as comment keys.
These are :target and the keys that depend on it, as in
`magit-review-comments', for the things `magit-review-comment' lists.
What the section types alone do not say: a revision buffer's headers and
message, even the commit ids the message mentions, are on its commit,
but a parent row of its headers is on the parent; only commits and
stashes widen to every one a region selects; a stash buffer's root is
its stash, and any other root is refused."
  (let ((section (magit-current-section))
        (revision (magit-review--revision-id)))
    (magit-review--refuse-root section)
    (cond
     ((when-let* ((step (magit-review--step-target)))
        (list :target 'step :where (walkthrough-diff-label) :step step)))
     ((and revision (magit-review--in-message-p))
      (append (list :target 'commits
                    :commits (list (magit-review--commit-entry revision)))
              (when-let* ((quote (magit-review--quote)))
                (list :quote quote))))
     ((and revision
           (magit-section-match '[* headers] section)
           (not (magit-section-match 'commit section)))
      (list :target 'commits
            :commits (list (magit-review--commit-entry revision))))
     ;; A stash buffer's root is a `stash' section too.
     ((when-let* ((sections (or (magit-region-sections '(commit stash) t)
                                (and (magit-section-match '(commit stash) section)
                                     (list section)))))
        (list :target 'commits
              ;; A region over a stash buffer's rows is on its stash once.
              :commits (seq-uniq (mapcar #'magit-review--section-commit-entry
                                         sections)))))
     ((magit-section-match (mapcar #'car magit-review--groups) section)
      (list :target 'group :group (oref section type)))
     ((magit-section-match '(hunk file) section)
      (let ((hunk (and (magit-section-match 'hunk section) section)))
        (list :target 'diff
              :file (magit-file-at-point)
              :where (magit-review--where section)
              :new (and hunk (magit-review--range hunk nil))
              :old (and hunk (magit-review--range hunk t))
              ;; A region is sent as it is; a whole hunk
              ;; is capped, a new file's being all of it.
              :patch (and hunk
                          (if (magit-diff-use-hunk-region-p)
                              (magit-diff-hunk-region-patch hunk)
                            (let ((patch (buffer-substring-no-properties
                                          (oref hunk start) (oref hunk end))))
                              (if (require 'walkthrough nil t)
                                  (walkthrough-patch-excerpt patch)
                                patch)))))))
     (t
      (let ((value (oref section value)))
        (list :target 'section
              :type (oref section type)
              :value (and (stringp value) (substring-no-properties value))
              :heading (magit-review--heading-line section)))))))

(defun magit-review--heading-line (section)
  "Return SECTION's heading line as shown, with runs of spaces collapsed.
A section's heading is its first line; a commit's in a graph also owns
the graph-only lines below it."
  (string-clean-whitespace
   (buffer-substring-no-properties
    (oref section start)
    (save-excursion (goto-char (oref section start)) (line-end-position)))))

(defun magit-review--refuse-root (section)
  "Refuse to comment on SECTION when it is the buffer as a whole.
A stash buffer as a whole is the stash it shows, which takes a comment,
and so does a walkthrough's step or passage at point."
  (when (and (eq section magit-root-section)
             (not (derived-mode-p 'magit-stash-mode))
             (not (magit-review--step-target)))
    (user-error "Nothing to comment on here; move to a commit, file, hunk or other item")))

(defun magit-review--read ()
  "Read a review comment for the thing at point."
  (magit-review--refuse-root (magit-current-section))
  (list (read-string "Review comment: ")))

(defun magit-review--add (text)
  "Record review comment TEXT on the thing at point and return it."
  (when (string-empty-p text)
    (user-error "Empty comment"))
  (let ((comment (append (list :repo (magit-toplevel))
                         (magit-review--target)
                         (list :text text :sent nil))))
    (push comment magit-review-comments)
    (deactivate-mark)
    comment))

(defun magit-review--on-finding-p ()
  "Return non-nil when point is on a walkthrough finding."
  (and (derived-mode-p 'walkthrough-mode) (walkthrough-finding-at-point-p)))

(defun magit-review-comment (&optional text)
  "Attach review comment TEXT to the thing at point.
That is a hunk, hunk region or file; a commit or stash, or all the ones
the region selects; a revision buffer's commit, from its headers or its
message, a region of which is quoted; a stash buffer's stash, from
anywhere in it; a group of changes; or any other section; or, in a
walkthrough, a step or a passage of its explanation.
Interactively on a walkthrough finding, TEXT is nil and this replies to
the finding instead (`walkthrough-reply')."
  (interactive (if (magit-review--on-finding-p)
                   (list nil)
                 (magit-review--read)))
  (if (null text)
      (call-interactively #'walkthrough-reply)
    (magit-review--add text)
    (magit-review--redecorate (magit-toplevel))
    (message "%d pending review comment(s)"
             (length (magit-review--pending (magit-toplevel))))))

(defun magit-review-comment-send (text &optional no-submit)
  "Hand review comment TEXT on the thing at point to the agent at once.
Other pending comments stay pending.  With prefix argument NO-SUBMIT,
only paste it and show the agent's buffer."
  (interactive
   (if (magit-review--on-finding-p)
       (user-error "On a finding, reply with `@ c' instead")
     (append (magit-review--read) (list current-prefix-arg))))
  (let ((comment (magit-review--add text)))
    (magit-review--hand-off
     (list comment)
     (if (magit-review--step-comment-p comment)
         "Here is a comment on a walkthrough step: a question or a request.  It names "
       "Here is a review comment: a question or a request.  It names ")
     no-submit)))

(defun magit-review--pending (repo &optional include-sent)
  "Return REPO's review comments, oldest first.
Sent comments are left out unless INCLUDE-SENT."
  (reverse (seq-filter (lambda (c)
                         (and (equal (plist-get c :repo) repo)
                              (or include-sent (not (plist-get c :sent)))))
                       magit-review-comments)))

;;; Handing off

(defun magit-review-items (repo &optional include-sent)
  "Return REPO's pending review comments and accepted findings.
The comments come oldest first, as plists (see `magit-review-comments').
The findings come from the repository's walkthroughs, shaped like
comments with :kind `finding'.  Sent ones are left out unless
INCLUDE-SENT."
  (append (magit-review--pending repo include-sent)
          (and (require 'walkthrough nil t)
               (walkthrough-accepted-findings repo include-sent))))

(defun magit-review--finding-p (item)
  "Return non-nil when hand-off ITEM is a walkthrough finding."
  (eq (plist-get item :kind) 'finding))

(defun magit-review-format (items &optional intro)
  "Format ITEMS as a Markdown review prompt.
ITEMS are review comments and findings, as `magit-review-items' returns
them.  Each is headed by what it is on: a diff comment by its file, line
ranges and diff, followed by its patch; a comment on commits by their
short ids and subjects, and a stash's name and message, followed by a
quoted part of the message; a group by its name; another section by its
type, value and heading.  Accepted walkthrough findings are headed by
their severity and title, followed by the user's reply; one handed off
before is headed as a follow-up.  A comment on a walkthrough's step or
passage is headed by the step, its files and the diff, and quotes the
passage; the prompt then closes by saying how to treat such comments.
INTRO starts the prompt's opening sentence, which goes on to say what
each item names."
  (concat
   (or intro
       (if (seq-some #'magit-review--finding-p items)
           "Please address my review comments and the review findings I accepted.  Each one names "
         "Please address my review comments.  Each one names "))
   "what it is on: a file with its new/old line range and the diff or commit it "
   "refers to, one or more commits, "
   (if (seq-some #'magit-review--step-comment-p items)
       "a walkthrough step, "
     "")
   "or another item Magit shows.\n\n"
   (mapconcat
    (lambda (item)
      (let ((patch (plist-get item :patch)))
        (concat
         (format "## %s%s\n\n%s%s\n"
                 (magit-review--heading item)
                 (if (plist-get item :sent) " [already sent]" "")
                 (if-let* ((preface (magit-review--commits-and-quote item)))
                     (concat preface "\n\n")
                   "")
                 (concat (plist-get item :text)
                         (when-let* ((reply (plist-get item :reply)))
                           (format "\n\nMy reply: %s" reply))))
         (when patch
           (format "\n```diff\n%s%s```\n" patch
                   (if (string-suffix-p "\n" patch) "" "\n"))))))
    items "\n")
   (when (seq-some #'magit-review--step-comment-p items)
     (concat "\nA comment on a walkthrough step quotes the passage of the"
             " step's explanation it answers, or quotes nothing when it is"
             " about the step as a whole.  Answer or act on these comments"
             " here in the conversation; do not rewrite or re-issue the"
             " walkthrough.\n"))))

(defun magit-review--commit-line (entry)
  "Describe commit ENTRY of a `commits' comment in one line."
  (concat (plist-get entry :abbrev)
          (when-let* ((name (plist-get entry :stash)))
            (format " (%s)" name))
          " " (plist-get entry :subject)))

(defun magit-review--commits-and-quote (item)
  "Return hand-off ITEM's list of commits and its quote, or nil.
The list is there only when it is on several commits, and the quote,
the part of a commit message or of a walkthrough step's explanation it
quotes, only when it has one.  They go
between its heading and its text."
  (let ((commits (plist-get item :commits))
        (quote (or (plist-get item :quote)
                   (plist-get (plist-get item :step) :quote))))
    (when (or (cdr commits) quote)
      (string-join
       (delq nil
             (list (when (cdr commits)
                     (mapconcat (lambda (entry)
                                  (concat "- " (magit-review--commit-line entry)))
                                commits "\n"))
                   (when quote
                     (mapconcat (lambda (line) (string-trim-right (concat "> " line)))
                                (split-string (string-trim-right quote "\n+") "\n")
                                "\n"))))
       "\n\n"))))

(defun magit-review--heading (item)
  "Return the prompt heading of hand-off ITEM: what it is on."
  (cl-flet ((lines (label range)
              (if range
                  (format " %s L%d-%d" label (car range) (cdr range))
                "")))
    (pcase (plist-get item :target)
      ('commits
       (let* ((commits (plist-get item :commits))
              (stashes (seq-every-p (lambda (entry) (plist-member entry :stash))
                                    commits)))
         (cond ((cdr commits) (if stashes "Stashes" "Commits"))
               (t (concat (if stashes "Stash " "Commit ")
                          (magit-review--commit-line (car commits)))))))
      ('group (alist-get (plist-get item :group) magit-review--groups))
      ('step
       (let* ((step (plist-get item :step))
              (files (plist-get step :files)))
         (format "Step %d/%d: %s (%s%s)"
                 (plist-get step :step) (plist-get step :steps)
                 (plist-get step :title)
                 (if files (format "files %s; " (string-join files ", ")) "")
                 (plist-get item :where))))
      ('section
       (format "%s%s, shown as \"%s\""
               (plist-get item :type)
               (if-let* ((value (plist-get item :value))) (concat " " value) "")
               (plist-get item :heading)))
      (_
       (format "%s%s%s%s (%s)"
               (if (magit-review--finding-p item)
                   (format "%s [%s%s] %s: "
                           (if (plist-get item :follow-up)
                               "Follow-up on finding"
                             "Finding")
                           (plist-get item :severity)
                           ;; An audit's finding is a defect or a smell.
                           (if-let* ((type (plist-get item :type)))
                               (concat ", " type)
                             "")
                           (plist-get item :title))
                 "")
               (or (plist-get item :file) "no file")
               (lines "new" (plist-get item :new))
               (lines "old" (plist-get item :old))
               (plist-get item :where))))))

(defun magit-review-send (&optional no-submit)
  "Hand pending review comments and accepted findings to the agent.
Mark them sent.  With prefix argument NO-SUBMIT, only paste them and
show the agent's buffer so the prompt can be edited first."
  (interactive "P")
  (let ((repo (or (magit-toplevel) (user-error "Not in a Git repository"))))
    (magit-review--hand-off
     (or (magit-review-items repo)
         (user-error "No pending review comments or accepted findings"))
     nil no-submit)))

(defun magit-review--hand-off (items intro no-submit)
  "Hand ITEMS, review comments and findings, to the agent.
Open the prompt with INTRO and mark them sent.  If NO-SUBMIT, only paste
them and show the agent's buffer."
  (unless magit-review-send-function
    (user-error "No agent is configured; set `magit-review-send-function'"))
  (let* ((repo (magit-toplevel))
         ;; The prefix argument means "don't submit" here, not "ask
         ;; which instance".
         (buffer (let ((current-prefix-arg nil))
                   (funcall magit-review-send-function
                            (magit-review-format items intro)
                            (not no-submit)))))
    ;; Comments live in memory; findings in their walkthrough's file.
    (dolist (comment (seq-remove #'magit-review--finding-p items))
      (plist-put comment :sent t))
    (when-let* ((findings (seq-filter #'magit-review--finding-p items)))
      (walkthrough-mark-sent findings))
    (magit-review--redecorate repo)
    (when no-submit
      (if-let* ((window (get-buffer-window buffer t)))
          (select-window window)
        (pop-to-buffer buffer)))
    (message "%s %d review item(s)"
             (if no-submit "Pasted" "Sent") (length items))))

(defun magit-review-paste ()
  "Paste pending review comments and accepted findings into the agent's input.
Do not submit them, so the prompt can be edited first."
  (interactive)
  (magit-review-send t))

(defun magit-review-list (&optional include-sent)
  "Show this repository's pending review comments and accepted findings.
With prefix argument INCLUDE-SENT, show sent ones too."
  (interactive "P")
  (let* ((repo (or (magit-toplevel) (user-error "Not in a Git repository")))
         (items (or (magit-review-items repo include-sent)
                    (user-error "No review comments"))))
    (with-current-buffer (get-buffer-create "*magit-review*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (magit-review-format items)))
      (if (fboundp 'gfm-view-mode) (gfm-view-mode) (view-mode))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(defun magit-review-discard (&optional all)
  "Discard this repository's pending review comments.
With prefix argument ALL, also forget the sent ones."
  (interactive "P")
  (let* ((repo (or (magit-toplevel) (user-error "Not in a Git repository")))
         (doomed (magit-review--pending repo all)))
    (unless doomed
      (user-error "No review comments to discard"))
    (when (y-or-n-p (format "Discard %d review comment(s)? " (length doomed)))
      (setq magit-review-comments
            (cl-set-difference magit-review-comments doomed :test #'eq))
      (magit-review--redecorate repo))))

;;; Drawing

(defun magit-review--hunk-lines (hunk)
  "Return an alist mapping (SIDE . LINE) to line starts in HUNK.
SIDE is `new' or `old'; context lines are listed under both."
  (let ((new (car (oref hunk to-range)))
        (old (car (oref hunk from-range)))
        lines)
    (save-excursion
      (goto-char (oref hunk content))
      (while (< (point) (oref hunk end))
        (let ((char (char-after)))
          (unless (eq char ?-)
            (push (cons (cons 'new new) (point)) lines)
            (cl-incf new))
          (unless (eq char ?+)
            (push (cons (cons 'old old) (point)) lines)
            (cl-incf old)))
        (forward-line)))
    lines))

(defun magit-review--annotate (pos comments &optional prefix)
  "Show PREFIX and then COMMENTS below the line containing POS."
  (let* ((eol (save-excursion (goto-char pos) (line-end-position)))
         (overlay (make-overlay eol eol)))
    (overlay-put overlay 'magit-review t)
    (overlay-put
     overlay 'after-string
     (concat
      prefix
      (mapconcat
       (lambda (c)
         (let ((sent (plist-get c :sent)))
           (propertize (format "\n    ▶ %s%s" (plist-get c :text)
                               (if sent " (sent)" ""))
                       'face (if sent 'magit-review-sent
                               'magit-review-comment))))
       comments "")))))

(defconst magit-review--modes
  '(magit-status-mode magit-diff-mode magit-log-mode magit-refs-mode
                      magit-stashes-mode)
  "Modes of the Magit buffers review comments are drawn in.
Revision and stash buffers derive from `magit-diff-mode'.")

(defun magit-review--decorate-diff (section comments)
  "Draw the diff COMMENTS on file or hunk SECTION.
A file heading gets a comment count and the file comments; hunk
comments appear below their last commented line."
  (let* ((hunk (and (magit-section-match 'hunk section) section))
         (file (oref (if hunk (oref section parent) section) value))
         (mine (seq-filter (lambda (c) (equal (plist-get c :file) file)) comments))
         ;; Only now, as a log's labels need git.
         (where (and mine (magit-review--where section)))
         (mine (seq-filter (lambda (c) (equal (plist-get c :where) where)) mine)))
    (cond
     ((null mine))
     ((null hunk)
      (magit-review--annotate
       (oref section start)
       (seq-remove (lambda (c)
                     (or (plist-get c :new) (plist-get c :old)))
                   mine)
       (propertize (format "  [%d review comment%s]"
                           (length mine)
                           (if (cdr mine) "s" ""))
                   'face 'magit-review-comment)))
     ((not (oref hunk combined))
      (let ((lines (magit-review--hunk-lines hunk))
            anchored)
        (dolist (c mine)
          (when-let* ((anchor (if-let* ((new (plist-get c :new)))
                                  (cons 'new (cdr new))
                                (and (plist-get c :old)
                                     (cons 'old (cdr (plist-get c :old))))))
                      (pos (alist-get anchor lines nil nil #'equal)))
            (push c (alist-get pos anchored))))
        (pcase-dolist (`(,pos . ,cs) anchored)
          (magit-review--annotate pos (nreverse cs))))))))

(defun magit-review--stash-ids ()
  "Return an alist mapping each stash's `stash@{N}' name to its commit id."
  (mapcar (lambda (line)
            (let ((fields (split-string line "\0")))
              (cons (car fields) (cadr fields))))
          (magit-list-stashes "%gd%x00%H")))

(defun magit-review--section-commit-id (section stashes)
  "Return the commit id, maybe abbreviated, that SECTION's line shows, or nil.
SECTION is a commit or stash section, or a revision buffer's headers.
A `stash@{N}' value is looked up in STASHES, from
`magit-review--stash-ids'.  A commit id mentioned in a commit message
shows nothing: comments made there are on the revision's commit."
  (let ((value (oref section value)))
    (cond ((eq (oref section type) 'headers)
           (magit-review--revision-id))
          ((not (stringp value)) nil)
          ((magit-section-match '[commit commit-message] section) nil)
          ((string-match-p "\\`[[:xdigit:]]\\{4,\\}\\'" value) value)
          ((string-match-p magit-review--stash-name-re value)
           (cdr (assoc value stashes))))))

(defun magit-review--covers-p (comment id)
  "Return non-nil when COMMENT is on the commit ID, which may be abbreviated."
  (seq-some (lambda (entry) (string-prefix-p id (plist-get entry :id)))
            (plist-get comment :commits)))

(defun magit-review-decorate ()
  "Show this repository's review comments in the current Magit buffer.
File headings get a comment count; hunk comments appear below the last
commented line, file comments below the file heading.  A comment on one
commit or stash appears below every line that shows it; one on several,
once, below the last of them in the buffer.  Meant for
`magit-refresh-buffer-hook'."
  (remove-overlays (point-min) (point-max) 'magit-review t)
  (when-let* (((derived-mode-p magit-review--modes))
              (repo (magit-toplevel))
              (comments (magit-review--pending repo t)))
    (let ((diff (seq-filter (lambda (c) (eq (plist-get c :target) 'diff)) comments))
          (commits (seq-filter (lambda (c) (eq (plist-get c :target) 'commits))
                               comments))
          ;; Comments drawn below every heading they are on.
          (others (seq-filter (lambda (c) (memq (plist-get c :target) '(group section)))
                              comments))
          (stashes nil)
          ;; Comment -> the starts of the lines it is drawn below.
          (below (make-hash-table :test #'eq))
          (magit-review--labels (make-hash-table :test #'equal)))
      ;; Magit values stash lines `stash@{N}'; one git call maps them.
      (when (seq-some (lambda (c)
                        (seq-some (lambda (entry) (plist-member entry :stash))
                                  (plist-get c :commits)))
                      commits)
        (setq stashes (magit-review--stash-ids)))
      (save-excursion
        (magit-map-sections
         (lambda (section)
           (pcase (oref section type)
             ((or 'file 'hunk)
              (when diff
                (magit-review--decorate-diff section diff)))
             ((or 'commit 'stash 'headers)
              (when-let* ((commits)
                          (id (magit-review--section-commit-id section stashes))
                          (start (oref section start)))
                (dolist (c commits)
                  (when (magit-review--covers-p c id)
                    ;; Sections come in buffer order, so the last one
                    ;; seen of several commits is the last in the buffer.
                    (if (cdr (plist-get c :commits))
                        (puthash c (list start) below)
                      (push start (gethash c below)))))))
             (type
              (dolist (c others)
                (when (if (eq (plist-get c :target) 'group)
                          (eq (plist-get c :group) type)
                        (and (eq (plist-get c :type) type)
                             (not (eq section magit-root-section))
                             (or (null (plist-get c :value))
                                 (equal (plist-get c :value) (oref section value)))))
                  (push (oref section start) (gethash c below))))))))
        (let (lines)
          (dolist (c comments)
            (dolist (start (gethash c below))
              (push c (alist-get start lines))))
          (pcase-dolist (`(,start . ,cs) lines)
            (magit-review--annotate start (nreverse cs))))))))

(defun magit-review--redecorate (repo)
  "Redraw review comments in every Magit buffer of REPO.
A walkthrough buffer also redraws those on its steps and passages."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p magit-review--modes)
                 (equal (magit-toplevel) repo))
        (magit-review-decorate)
        (when (derived-mode-p 'walkthrough-mode)
          (walkthrough-redraw-comments))))))

(defun magit-review-walkthrough-comments (label)
  "Return this repository's comments on walkthrough steps of diff LABEL.
Pending and sent, oldest first, each its :text and :sent followed by
its target's keys.  Meant for `walkthrough-comments-function'."
  (mapcan (lambda (c)
            (when (and (magit-review--step-comment-p c)
                       (equal (plist-get c :where) label))
              (list (append (list :text (plist-get c :text)
                                  :sent (plist-get c :sent))
                            (plist-get c :step)))))
          (magit-review--pending (magit-toplevel) t)))

;;; The menu

(transient-define-prefix magit-review ()
  "Comment on what Magit shows and hand the review to the agent."
  [["Comment"
    ("c" "Thing at point" magit-review-comment)
    ("d" "Comment and send now" magit-review-comment-send)]
   ["Review"
    ("s" "Send to agent" magit-review-send)
    ("p" "Paste, don't submit" magit-review-paste)
    ("l" "List" magit-review-list)
    ("k" "Discard" magit-review-discard)]
   ["Walkthrough"
    ("w" "Open (C-u: pick)" walkthrough-open-current)
    ("W" "Ask for one (C-u: base)" walkthrough-request)]
   ["Project"
    ("t" "Tour (C-u: pick)" walkthrough-open-tour)
    ("T" "Ask for a tour (C-u: area)" walkthrough-request-tour)
    ("a" "Audit (C-u: pick)" walkthrough-open-audit)
    ("A" "Ask for an audit (C-u: area)" walkthrough-request-audit)]])

(provide 'magit-review)
;;; magit-review.el ends here
