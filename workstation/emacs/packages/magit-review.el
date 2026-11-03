;; -*- lexical-binding: t; -*-
;;; magit-review.el --- Review comments in Magit, handed off to a coding agent

;; Package-Requires: ((emacs "30.1") (magit "4.0") (transient "0.7"))

;;; Commentary:

;; A hunk.dev-style review loop.  `magit-review-comment' attaches a review
;; comment to the hunk, hunk region or file at point in a Magit buffer, or
;; to the step or passage of its explanation at point in a walkthrough;
;; `magit-review-send' hands every pending comment of the repository to its
;; coding agent as one prompt, together with the findings the user accepted
;; in the repository's walkthroughs, and marks them sent.
;; `magit-review-comment-send' hands one comment off on its own at once (a
;; direct comment), leaving the others pending.  Comments live in memory,
;; per repository toplevel, so a comment made in a worktree goes to that
;; worktree's agent.
;;
;; `magit-review-decorate' draws the comments in status and diff buffers:
;; below the last commented line, unsent ones highlighted and sent ones
;; dimmed, with a count on each file heading.
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
;; `magit-buffer-revision'; the hunk section slots `from-range', `to-range',
;; `content' and `combined'; `magit-diff-type', `magit-diff-hunk-line',
;; `magit-diff-use-hunk-region-p', `magit-diff-hunk-region-beginning' and
;; `magit-diff-hunk-region-patch'.  walkthrough.el's label reads
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
  "Review comments on Magit diffs, newest first.
Each comment is a plist with :repo, :file, :where, :new, :old, :patch,
:text and :sent.  :new and :old are (START . END) line ranges or nil.
A comment on a walkthrough's step or a passage of its explanation also
has :target, what `walkthrough-comment-target' returned, and no :file,
:new, :old or :patch.")

(defun magit-review--step-comment-p (comment)
  "Return non-nil when COMMENT is on a walkthrough step or passage."
  (and (plist-get comment :target) t))

(defun magit-review--range (section from)
  "Return the (START . END) lines of hunk SECTION on the old side if FROM.
Uses the active region when there is one, else the whole hunk.  Returns
nil when the region has no lines on that side (only additions for the
old side, only removals for the new side)."
  (if (magit-diff-use-hunk-region-p)
      (let* ((beg (magit-diff-hunk-region-beginning))
             ;; A region ending at the start of a line doesn't cover it.
             (end (save-excursion
                    (goto-char (region-end))
                    (if (and (bolp) (> (point) beg)) (1- (point)) (point)))))
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

(defun magit-review--where (section)
  "Describe which diff SECTION belongs to.
A committed range is named by its commit ids (`walkthrough-diff-label'),
so a comment made in a walkthrough is the same comment in `magit-diff'
of the same commits.  Magit renamed `magit-buffer-range' to
`magit-buffer-diff-range' without an alias; reading the old name made
every range diff plain \"diff\"."
  (pcase (magit-diff-type section)
    ('unstaged "unstaged changes")
    ('staged "staged changes")
    ('untracked "untracked file")
    (_ (cond ((and (require 'walkthrough nil t) (walkthrough-diff-label)))
             ((bound-and-true-p magit-buffer-revision)
              (format "diff of %s" magit-buffer-revision))
             ("diff")))))

(defun magit-review--read ()
  "Read a review comment for the thing at point.
Return (TEXT TARGET).  In a walkthrough, TARGET is the step heading or
passage of its explanation at point (`walkthrough-comment-target');
elsewhere it is nil and the comment is on the hunk, hunk region or file."
  (let ((target (and (derived-mode-p 'walkthrough-mode)
                     (walkthrough-comment-target))))
    (unless (or target (magit-section-match '(hunk file)))
      (user-error "Not on a diff file or hunk"))
    (list (read-string "Review comment: ") target)))

(defun magit-review--add (text &optional target)
  "Record review comment TEXT on the thing at point and return it.
TARGET, from `magit-review--read', is the walkthrough step or passage
the comment is about.  Such a comment is labelled with the
walkthrough's commits like a hunk comment there, but has no file, lines
or patch, so the hunk and file drawing leaves it alone."
  (when (string-empty-p text)
    (user-error "Empty comment"))
  (let ((comment
         (append
          (list :repo (magit-toplevel) :text text :sent nil)
          (if target
              (list :file nil
                    :where (walkthrough-diff-label)
                    :new nil
                    :old nil
                    :patch nil
                    :target target)
            (let* ((section (magit-current-section))
                   (hunk (and (magit-section-match 'hunk section) section)))
              (list :file (magit-file-at-point)
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
                                      patch))))))))))
    (push comment magit-review-comments)
    (deactivate-mark)
    comment))

(defun magit-review--on-finding-p ()
  "Return non-nil when point is on a walkthrough finding."
  (and (derived-mode-p 'walkthrough-mode) (walkthrough-finding-at-point-p)))

(defun magit-review-comment (&optional text target)
  "Attach review comment TEXT to the thing at point.
That is the walkthrough step or passage TARGET when non-nil, else the
hunk, hunk region or file at point.  Interactively on a walkthrough
finding, TEXT is nil and this replies to the finding instead
(`walkthrough-reply')."
  (interactive (if (magit-review--on-finding-p)
                   (list nil nil)
                 (magit-review--read)))
  (if (null text)
      (call-interactively #'walkthrough-reply)
    (magit-review--add text target)
    (magit-review--redecorate (magit-toplevel))
    (message "%d pending review comment(s)"
             (length (magit-review--pending (magit-toplevel))))))

(defun magit-review-comment-send (text &optional target no-submit)
  "Hand review comment TEXT on the thing at point to the agent at once.
TARGET is as for `magit-review-comment'.  Other pending comments stay
pending.  With prefix argument NO-SUBMIT, only paste it and show the
agent's buffer."
  (interactive
   (if (magit-review--on-finding-p)
       (user-error "On a finding, reply with `@ c' instead")
     (append (magit-review--read) (list current-prefix-arg))))
  (let ((comment (magit-review--add text target)))
    (magit-review--hand-off
     (list comment)
     (if (magit-review--step-comment-p comment)
         "Here is a comment on the walkthrough of this diff: a question or a request.  It names "
       "Here is a comment on this diff: a question or a request.  It names ")
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

(defun magit-review-format (comments &optional intro)
  "Format COMMENTS as a Markdown review prompt.
COMMENTS are items as `magit-review-items' returns them, and may include
accepted walkthrough findings, which are headed by their severity and
title, followed by the user's reply; one handed off before is headed as
a follow-up.  A comment on a walkthrough's step or passage is headed by
the step, its files and the diff, and quotes the passage; the prompt
then closes by saying how to treat such comments.  INTRO starts the
prompt's opening sentence, which goes on to say what each comment
names."
  (let ((on-steps (seq-filter #'magit-review--step-comment-p comments)))
    (cl-flet ((lines (label range)
                (when range
                  (format " %s L%d-%d" label (car range) (cdr range))))
              (sent (c)
                (if (plist-get c :sent) " [already sent]" ""))
              (blockquote (text)
                (mapconcat (lambda (line)
                             (if (string-empty-p line) ">" (concat "> " line)))
                           (split-string text "\n")
                           "\n")))
      (concat
       (or intro
           (if (seq-some #'magit-review--finding-p comments)
               "Please address my review comments and the review findings I accepted.  Each one names "
             "Please address my review comments on this diff.  Each one names "))
       (cond ((null on-steps)
              "the file, the new/old line range and the diff it refers to.\n\n")
             ((length= on-steps (length comments))
              "the walkthrough step it refers to, the step's files and the diff.\n\n")
             (t
              "either the file, the new/old line range and the diff, or the walkthrough step it refers to.\n\n"))
       (mapconcat
        (lambda (c)
          (if (magit-review--step-comment-p c)
              (let* ((target (plist-get c :target))
                     (files (plist-get target :files))
                     (passage (plist-get target :quote)))
                (format "## Step %d/%d: %s (%s%s)%s\n\n%s%s\n"
                        (plist-get target :step) (plist-get target :steps)
                        (plist-get target :title)
                        (if files (format "files %s; " (string-join files ", ")) "")
                        (plist-get c :where)
                        (sent c)
                        (if passage (concat (blockquote passage) "\n\n") "")
                        (plist-get c :text)))
            (let ((patch (plist-get c :patch)))
              (concat
               (format "## %s%s%s%s (%s)%s\n\n%s\n"
                       (if (magit-review--finding-p c)
                           (format "%s [%s] %s: "
                                   (if (plist-get c :follow-up)
                                       "Follow-up on finding"
                                     "Finding")
                                   (plist-get c :severity) (plist-get c :title))
                         "")
                       (or (plist-get c :file) "no file")
                       (or (lines "new" (plist-get c :new)) "")
                       (or (lines "old" (plist-get c :old)) "")
                       (plist-get c :where)
                       (sent c)
                       (concat (plist-get c :text)
                               (when-let* ((reply (plist-get c :reply)))
                                 (format "\n\nMy reply: %s" reply))))
               (when patch
                 (format "\n```diff\n%s%s```\n" patch
                         (if (string-suffix-p "\n" patch) "" "\n")))))))
        comments "\n")
       (when on-steps
         (concat "\nA comment on a walkthrough step quotes the passage of the"
                 " step's explanation it answers, or quotes nothing when it is"
                 " about the step as a whole.  Answer or act on these comments"
                 " here in the conversation; do not rewrite or re-issue the"
                 " walkthrough.\n"))))))

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

(defun magit-review--hand-off (comments intro no-submit)
  "Hand COMMENTS to the agent, opening the prompt with INTRO.
Mark them sent.  If NO-SUBMIT, only paste them and show the agent's
buffer."
  (unless magit-review-send-function
    (user-error "No agent is configured; set `magit-review-send-function'"))
  (let* ((repo (magit-toplevel))
         ;; The prefix argument means "don't submit" here, not "ask
         ;; which instance".
         (buffer (let ((current-prefix-arg nil))
                   (funcall magit-review-send-function
                            (magit-review-format comments intro)
                            (not no-submit)))))
    ;; Comments live in memory; findings in their walkthrough's file.
    (dolist (c (seq-remove #'magit-review--finding-p comments))
      (plist-put c :sent t))
    (when-let* ((findings (seq-filter #'magit-review--finding-p comments)))
      (walkthrough-mark-sent findings))
    (magit-review--redecorate repo)
    (when no-submit
      (if-let* ((window (get-buffer-window buffer t)))
          (select-window window)
        (pop-to-buffer buffer)))
    (message "%s %d review item(s)"
             (if no-submit "Pasted" "Sent") (length comments))))

(defun magit-review-paste ()
  "Paste pending review comments into the agent's input without submitting."
  (interactive)
  (magit-review-send t))

(defun magit-review-list (&optional include-sent)
  "Show this repository's pending review comments.
With prefix argument INCLUDE-SENT, show sent comments too."
  (interactive "P")
  (let* ((repo (or (magit-toplevel) (user-error "Not in a Git repository")))
         (comments (or (magit-review-items repo include-sent)
                       (user-error "No review comments"))))
    (with-current-buffer (get-buffer-create "*magit-review*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (magit-review-format comments)))
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

(defun magit-review-decorate ()
  "Show this repository's review comments in the current Magit buffer.
File headings get a comment count; hunk comments appear below the last
commented line, file comments below the file heading.  Meant for
`magit-refresh-buffer-hook'."
  (remove-overlays (point-min) (point-max) 'magit-review t)
  (when-let* (((derived-mode-p 'magit-status-mode 'magit-diff-mode))
              (repo (magit-toplevel))
              (comments (magit-review--pending repo t)))
    (save-excursion
      (magit-map-sections
       (lambda (section)
         (when (magit-section-match '(file hunk) section)
           (let* ((hunk (and (magit-section-match 'hunk section) section))
                  (file (oref (if hunk (oref section parent) section) value))
                  (where (magit-review--where section))
                  (mine (seq-filter
                         (lambda (c)
                           (and (equal (plist-get c :file) file)
                                (equal (plist-get c :where) where)))
                         comments)))
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
                   (magit-review--annotate pos (nreverse cs)))))))))))))

(defun magit-review--redecorate (repo)
  "Redraw review comments in every Magit buffer of REPO.
A walkthrough buffer also redraws those on its steps and passages."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'magit-status-mode 'magit-diff-mode)
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
                            (plist-get c :target)))))
          (magit-review--pending (magit-toplevel) t)))

;;; The menu

(transient-define-prefix magit-review ()
  "Comment on diffs and hand the review to the agent."
  [["Comment"
    ("c" "Hunk, file, step or passage" magit-review-comment)
    ("d" "Comment and send now" magit-review-comment-send)]
   ["Review"
    ("s" "Send to agent" magit-review-send)
    ("p" "Paste, don't submit" magit-review-paste)
    ("l" "List" magit-review-list)
    ("k" "Discard" magit-review-discard)]
   ["Walkthrough"
    ("w" "Open (C-u: pick)" walkthrough-open-current)
    ("W" "Ask for one (C-u: base)" walkthrough-request)]])

(provide 'magit-review)
;;; magit-review.el ends here
