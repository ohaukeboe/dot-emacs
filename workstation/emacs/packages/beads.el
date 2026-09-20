;; -*- lexical-binding: t; -*-
;;; beads.el --- Beads issues in Magit status buffers

;;; Commentary:

;; Lists the issues of the beads tracker in the Magit status buffer of the
;; repository they belong to: what is claimed, and what is ready to claim.
;; The database lives in .beads/ next to the worktree, so a repository
;; without one gets no section and pays nothing for this file.
;;
;; Both lists come from `bd' itself -- `bd list --status=in_progress' and
;; `bd ready' -- never from reading .beads/issues.jsonl.  "Ready" means
;; open and unblocked, and resolving blockers is bd's job; a second
;; implementation here would drift from it.
;;
;; TAB unfolds an issue's description in place and RET opens the full
;; `bd show' output in its own buffer.  `#' opens a transient that acts on
;; the issue at point -- claim, close, comment, assign, set priority -- or
;; on every issue in the region for the two operations bd itself takes
;; several ids for.  Prose is written in a buffer rather than the
;; minibuffer and reaches bd through a temp file.

;;; Code:

(require 'ansi-color)
(require 'cl-lib)
(require 'seq)
(require 'transient)
(require 'magit-git)
(require 'magit-section)

(defgroup beads nil
  "Beads issues in Magit buffers."
  :group 'magit-extensions)

(defcustom beads-ready-limit 10
  "Number of ready issues to list before summarizing the rest.
The heading always reports the full count; only the listing is capped.
Activating the summary line lifts the cap for that buffer."
  :type 'natnum
  :group 'beads)

(defface beads-critical '((t :inherit error))
  "Face for the priority of a P0 issue."
  :group 'beads)

(defface beads-high '((t :inherit warning))
  "Face for the priority of a P1 issue."
  :group 'beads)

(defface beads-low '((t :inherit magit-dimmed))
  "Face for the priority of a P3 or P4 issue."
  :group 'beads)

;;; Talking to bd

(defun beads-toplevel ()
  "Return the root of the current repository if it has a beads database.
Return nil when bd is not installed, when there is no repository, when
it has no .beads directory, or when it is remote -- running bd over
Tramp is not worth the round trip during a refresh."
  (and (not (file-remote-p default-directory))
       (executable-find "bd")
       (when-let* ((top (magit-toplevel)))
         (and (file-directory-p (expand-file-name ".beads" top)) top))))

(defun beads--failure-line (string)
  "Return the line of STRING that explains a failure, or nil.
Prefer the last line bd marks as an error: it writes advisory warnings
to stderr even on success, and follows a real error with usage
boilerplate, so neither end of the output is reliable on its own."
  (let ((lines (split-string (or string "") "\n" t "[ \t]+")))
    (or (car (last (seq-filter (lambda (line)
                                 (string-match-p "\\`[Ee]rror\\|\\`fatal" line))
                               lines)))
        (car (last lines)))))

(defun beads--run (&rest args)
  "Run bd with ARGS in `default-directory'.
Return a list of the exit status, stdout and stderr."
  (let ((stderr (make-temp-file "beads-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (apply #'call-process "bd" nil (list t stderr) nil args)))
            (list status
                  (buffer-string)
                  (with-temp-buffer
                    (insert-file-contents stderr)
                    (buffer-string)))))
      (delete-file stderr))))

(defun beads--issues (&rest args)
  "Return the issues bd prints for ARGS as a list of alists.
Return a string describing the failure instead when bd exits non-zero
or prints something that is not JSON.  bd keeps stdout clean and puts
its warnings on stderr, so parsing failures are real failures."
  (pcase-let ((`(,status ,out ,err) (apply #'beads--run args)))
    (if (not (eq status 0))
        (or (beads--failure-line err) (format "bd exited with status %s" status))
      (condition-case nil
          (json-parse-string out
                             :object-type 'alist
                             :array-type 'list
                             :null-object nil
                             :false-object nil)
        (error "bd printed unparsable JSON")))))

(defun beads--sort (issues)
  "Return ISSUES ordered by priority, ties broken by id.
Priority is the field shown on every line, so any other order reads as
a bug, and the id keeps it stable across refreshes."
  (sort (copy-sequence issues)
        (lambda (a b)
          (let ((pa (or (alist-get 'priority a) 9))
                (pb (or (alist-get 'priority b) 9)))
            (if (= pa pb)
                (string< (alist-get 'id a) (alist-get 'id b))
              (< pa pb))))))

;;; Formatting

(defun beads--width ()
  "Return the number of columns available for an issue line."
  (max 40 (1- (if-let* ((window (get-buffer-window (current-buffer))))
                  (window-max-chars-per-line window)
                fill-column))))

(defun beads--priority-face (priority)
  "Return the face for PRIORITY, or nil for the ordinary ones."
  (pcase priority
    (0 'beads-critical)
    (1 'beads-high)
    ((or 3 4) 'beads-low)))

(defun beads--format-issue (issue indent)
  "Return the one-line listing of ISSUE, prefixed by INDENT spaces."
  (let* ((id (alist-get 'id issue))
         (priority (alist-get 'priority issue))
         (prefix (format "%s%s  %s  "
                         (make-string indent ?\s)
                         id
                         (if priority (format "P%d" priority) "P?")))
         (title (or (alist-get 'title issue) "")))
    (concat (make-string indent ?\s)
            (propertize id 'font-lock-face 'magit-hash)
            "  "
            (propertize (if priority (format "P%d" priority) "P?")
                        'font-lock-face (beads--priority-face priority))
            "  "
            (truncate-string-to-width title (max 20 (- (beads--width)
                                                       (length prefix)))
                                      nil nil t))))

(defun beads--self-p (assignee)
  "Return non-nil when ASSIGNEE names the user of this Emacs."
  (and assignee
       (or (equal assignee user-full-name)
           (equal assignee user-mail-address))))

(defun beads--fill (text indent)
  "Return TEXT filled to the window width and indented by INDENT spaces."
  (with-temp-buffer
    (insert text)
    (let ((fill-column (max 40 (- (beads--width) indent))))
      (fill-region (point-min) (point-max)))
    (indent-rigidly (point-min) (point-max) indent)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (buffer-string)))

;;; Sections

(defclass beads-issues-section (magit-section) ())

(defclass beads-group-section (magit-section) ())

(defclass beads-issue-section (magit-section)
  ((keymap :initform 'beads-issue-section-map)))

(defclass beads-more-section (magit-section)
  ((keymap :initform 'beads-more-section-map)))

(defvar-keymap beads-issue-section-map
  :doc "Keymap for the section of a single beads issue."
  "<remap> <magit-visit-thing>" #'beads-show-at-point)

(defvar-keymap beads-more-section-map
  :doc "Keymap for the line summarizing the ready issues that are not listed."
  "<remap> <magit-visit-thing>" #'beads-list-all-ready)

(defvar-local beads--ready-limit-lifted nil
  "Whether this buffer lists every ready issue, ignoring `beads-ready-limit'.")

(defun beads--insert-issue (issue)
  "Insert ISSUE as a foldable section, its description in the body."
  (magit-insert-section (beads-issue-section (alist-get 'id issue) t)
    (magit-insert-heading (beads--format-issue issue 2))
    (let ((assignee (alist-get 'assignee issue)))
      (unless (beads--self-p assignee)
        (insert (propertize (format "    Assignee: %s\n" (or assignee "nobody"))
                            'font-lock-face 'magit-dimmed))))
    (insert (beads--fill (or (alist-get 'description issue) "No description.")
                         4))))

(defun beads--insert-group (ident heading issues limit)
  "Insert ISSUES under HEADING as a subsection identified by IDENT.
List at most LIMIT of them, or all of them when LIMIT is nil, and
summarize the rest on a line of its own.  Insert nothing when ISSUES is
empty: an empty heading is permanent furniture for a passing fact."
  (when issues
    (let* ((shown (if (and limit (> (length issues) limit))
                      (take limit issues)
                    issues))
           (hidden (- (length issues) (length shown))))
      (magit-insert-section (beads-group-section ident)
        (magit-insert-heading
          (propertize (format "%s (%d)" heading (length issues))
                      'font-lock-face 'magit-section-secondary-heading))
        (mapc #'beads--insert-issue shown)
        (when (> hidden 0)
          (magit-insert-section (beads-more-section hidden)
            (insert (propertize (format "  …and %d more\n" hidden)
                                'font-lock-face 'magit-dimmed))))))))

;;;###autoload
(defun beads-insert-issues ()
  "Insert a section listing the beads issues of the current repository.
Meant for `magit-status-sections-hook'.  A repository whose tracker is
empty of claimed and ready work gets no section at all."
  (when-let* ((default-directory (beads-toplevel)))
    (let ((in-progress (beads--issues "list" "--status=in_progress" "--json"
                                      "-n" "0"))
          (ready (beads--issues "ready" "--json" "-n" "0")))
      (cond
       ((or (stringp in-progress) (stringp ready))
        ;; bd ran and failed.  Say so, rather than looking like zero issues.
        (magit-insert-section (beads-issues-section 'beads)
          (insert (propertize
                   (format "Beads issues: %s\n\n"
                           (if (stringp in-progress) in-progress ready))
                   'font-lock-face 'error))))
       ((or in-progress ready)
        (magit-insert-section (beads-issues-section 'beads t)
          (magit-insert-heading
            (format "Beads issues (%d)"
                    (+ (length in-progress) (length ready))))
          (beads--insert-group 'in-progress "In progress"
                               (beads--sort in-progress) nil)
          (beads--insert-group 'ready "Ready"
                               (beads--sort ready)
                               (and (not beads--ready-limit-lifted)
                                    beads-ready-limit))
          (insert "\n")))))))

(defun beads-list-all-ready ()
  "List every ready issue in this buffer, ignoring `beads-ready-limit'."
  (interactive)
  (setq beads--ready-limit-lifted t)
  (magit-refresh-buffer))

;;; Showing one issue

(defvar-local beads--issue nil
  "The id of the issue a `beads-show-mode' buffer displays.")

(defvar-keymap beads-show-mode-map
  :doc "Keymap for `beads-show-mode'."
  :parent special-mode-map
  "#" #'beads-dispatch)

(define-derived-mode beads-show-mode special-mode "Beads"
  "Major mode for the output of `bd show'."
  :interactive nil
  (setq-local revert-buffer-function #'beads-show-revert))

(defun beads-show-revert (&rest _)
  "Re-read the issue this buffer displays."
  (beads-show beads--issue))

;;;###autoload
(defun beads-show (id)
  "Display the beads issue ID in its own buffer.
The buffer holds the output of `bd show' verbatim: bd already decides
what an issue looks like, and every field it gains shows up here."
  (interactive (list (beads--read-issue)))
  (let ((root (or (beads-toplevel)
                  (user-error "No beads database in this repository"))))
    (pcase-let* ((default-directory root)
                 (`(,status ,out ,err) (beads--run "show" id)))
      (unless (eq status 0)
        (user-error "bd show %s: %s" id (or (beads--failure-line err)
                                            (format "exited with status %s"
                                                    status))))
      (let ((buffer (get-buffer-create (format "*beads: %s*" id))))
        (with-current-buffer buffer
          (beads-show-mode)
          (setq default-directory root)
          (setq beads--issue id)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert out)
            (ansi-color-apply-on-region (point-min) (point-max))
            (goto-char (point-min))))
        (pop-to-buffer buffer)))))

(defun beads-show-at-point ()
  "Display the beads issue at point, reading one when there is none."
  (interactive)
  (beads-show (or (beads--issue-at-point) (beads--read-issue))))

(defun beads--read-issue ()
  "Read the id of an open beads issue, titles shown as annotations."
  (let* ((default-directory (or (beads-toplevel)
                                (user-error "No beads database in this repository")))
         (issues (beads--issues "list" "--json" "-n" "0")))
    (when (stringp issues)
      (user-error "bd list: %s" issues))
    (unless issues
      (user-error "No open beads issues"))
    (let* ((table (mapcar (lambda (issue)
                            (cons (alist-get 'id issue)
                                  (alist-get 'title issue)))
                          (beads--sort issues)))
           (completion-extra-properties
            (list :annotation-function
                  (lambda (id)
                    (concat "  " (alist-get id table nil nil #'equal))))))
      (completing-read "Issue: " table nil t))))

;;; Acting on issues

(defun beads--issue-at-point ()
  "Return the id of the issue at point, or nil."
  (cond
   ((derived-mode-p 'magit-section-mode)
    (and-let* ((section (magit-current-section))
               ((cl-typep section 'beads-issue-section)))
      (oref section value)))
   ((derived-mode-p 'beads-show-mode) beads--issue)))

(defun beads--issues-at-point ()
  "Return the ids of the issues the region covers, or of the one at point.
Return nil when point is not on an issue.  Never prompts, so the
transient can name its target while building its description."
  (or (and (derived-mode-p 'magit-section-mode)
           (and-let* ((sections (magit-region-sections 'beads-issue-section t)))
             (mapcar (lambda (section) (oref section value)) sections)))
      (and-let* ((id (beads--issue-at-point))) (list id))))

(defun beads--targets (&optional multiple)
  "Return the issue ids to act on, reading one when point is not on an issue.
Unless MULTIPLE, act on a single issue even when the region covers
several: one comment or one assignee for three issues is rarely what
was meant, while one close reason for three is."
  (let ((ids (beads--issues-at-point)))
    (cond ((and ids multiple) ids)
          (ids (list (car ids)))
          (t (list (beads--read-issue))))))

(defun beads--fetch-issue (id)
  "Return the issue ID as an alist, or nil when bd cannot find it."
  (and id
       (let ((issues (beads--issues "show" id "--json")))
         (and (consp issues) (car issues)))))

(defun beads--mutate (&rest args)
  "Run bd with ARGS, signalling bd's own message when it fails.
Return stdout."
  (pcase-let ((`(,status ,out ,err) (apply #'beads--run args)))
    (unless (eq status 0)
      (user-error "bd %s: %s" (car args)
                  (or (beads--failure-line err)
                      (format "exited with status %s" status))))
    out))

(defun beads--refresh (format-string &rest args)
  "Show the mutation FORMAT-STRING with ARGS and re-read what is on screen.
Only the current buffer: other Magit buffers pick the change up through
the beads mtime in `my/magit-auto-refresh-mode's fingerprint."
  (cond ((derived-mode-p 'magit-mode) (magit-refresh))
        ((derived-mode-p 'beads-show-mode) (beads-show beads--issue)))
  (message "%s" (apply #'format format-string args)))

(defun beads--read-assignee ()
  "Read an assignee, completing over the ones the tracker already knows.
Matching is not required: the first issue assigned to someone new has to
be possible."
  (let* ((issues (beads--issues "list" "--all" "--json" "-n" "0"))
         (known (and (consp issues)
                     (seq-uniq (delq nil (mapcar (lambda (issue)
                                                   (alist-get 'assignee issue))
                                                 issues))))))
    (completing-read "Assignee: " known nil nil nil nil user-full-name)))

;;; The message buffer

(defvar-local beads-message--submit nil
  "Function called with the text of a `beads-message-mode' buffer.")

(defvar-local beads-message--origin nil
  "Buffer the message buffer was opened from, and returns to.")

(defvar-keymap beads-message-mode-map
  :doc "Keymap for `beads-message-mode'."
  "C-c C-c" #'beads-message-submit
  "C-c C-k" #'beads-message-abort)

(define-derived-mode beads-message-mode text-mode "Beads Message"
  "Major mode for prose on its way to bd."
  :interactive nil
  (setq-local comment-start "#"))

(defun beads--read-message (name headers submit)
  "Pop to a buffer named NAME for prose, HEADERS shown as comments.
On \\[beads-message-submit] call SUBMIT with the text, in the buffer the
message was started from."
  (let ((origin (current-buffer))
        (buffer (get-buffer-create (format "*beads: %s*" name))))
    (with-current-buffer buffer
      (beads-message-mode)
      (setq beads-message--submit submit)
      (setq beads-message--origin origin)
      (setq default-directory (buffer-local-value 'default-directory origin))
      (erase-buffer)
      (dolist (header headers)
        (insert "# " header "\n"))
      (insert "# Lines starting with # are ignored."
              "  C-c C-c to send, C-c C-k to abort.\n\n")
      (goto-char (point-min)))
    (pop-to-buffer buffer)))

(defun beads-message--text ()
  "Return the buffer's text without its comment lines."
  (string-trim
   (mapconcat #'identity
              (seq-remove (lambda (line) (string-prefix-p "#" line))
                          (split-string (buffer-string) "\n"))
              "\n")))

(defun beads-message-submit ()
  "Hand the text of this buffer to the command that asked for it."
  (interactive)
  (let ((text (beads-message--text))
        (submit beads-message--submit)
        (origin beads-message--origin))
    (quit-window t)
    (with-current-buffer (if (buffer-live-p origin) origin (current-buffer))
      (funcall submit text))))

(defun beads-message-abort ()
  "Abandon this message."
  (interactive)
  (quit-window t)
  (message "Abandoned"))

(defun beads--with-text-file (text function)
  "Call FUNCTION with the name of a file holding TEXT."
  (let ((file (make-temp-file "beads-message")))
    (unwind-protect
        (progn (write-region text nil file nil 'silent)
               (funcall function file))
      (delete-file file))))

;;; Commands

(defun beads-claim (ids)
  "Claim the issues IDS: assignee becomes you, status in progress.
Ask first when somebody else holds one -- taking an issue from a running
agent should not be silent.  bd refuses to claim an issue another
assignee holds, so a confirmed takeover sets the two fields itself."
  (interactive (list (beads--targets t)))
  (dolist (id ids)
    (let ((assignee (alist-get 'assignee (beads--fetch-issue id))))
      (cond
       ((or (null assignee) (beads--self-p assignee))
        (beads--mutate "update" id "--claim"))
       ((yes-or-no-p (format "%s is assigned to %s; claim anyway? " id assignee))
        (beads--mutate "update" id
                       "--assignee" user-full-name
                       "--status" "in_progress"))
       (t (user-error "Not claimed")))))
  (beads--refresh "Claimed %s" (string-join ids ", ")))

(defun beads-close (ids)
  "Close the issues IDS, with one reason for all of them."
  (interactive (list (beads--targets t)))
  (beads--read-message
   (format "close %s" (string-join ids ", "))
   (cons "Reason for closing:"
         (mapcar (lambda (id)
                   (format "  %s  %s" id
                           (or (alist-get 'title (beads--fetch-issue id)) "")))
                 ids))
   (lambda (text)
     (beads--with-text-file
      text
      (lambda (file)
        (apply #'beads--mutate "close" (append ids (list "--reason-file" file)))))
     (beads--refresh "Closed %s" (string-join ids ", ")))))

(defun beads-comment (id)
  "Add a comment to the issue ID."
  (interactive (list (car (beads--targets))))
  (beads--read-message
   (format "comment on %s" id)
   (list (format "Comment on %s  %s" id
                 (or (alist-get 'title (beads--fetch-issue id)) "")))
   (lambda (text)
     (when (string-empty-p text)
       (user-error "Empty comment"))
     (beads--with-text-file
      text
      (lambda (file) (beads--mutate "comment" id "--file" file)))
     (beads--refresh "Commented on %s" id))))

(defun beads-assign (id assignee)
  "Assign the issue ID to ASSIGNEE."
  (interactive (list (car (beads--targets)) (beads--read-assignee)))
  (beads--mutate "assign" id assignee)
  (beads--refresh "%s assigned to %s" id assignee))

(defun beads--set-priority (priority ids)
  "Set the priority of the issues IDS to PRIORITY."
  (dolist (id ids)
    (beads--mutate "update" id "--priority" (number-to-string priority)))
  (beads--refresh "%s set to P%d" (string-join ids ", ") priority))

(defmacro beads--define-priority-command (priority meaning)
  "Define the command setting an issue's priority to PRIORITY, meaning MEANING."
  `(defun ,(intern (format "beads-set-priority-%d" priority)) (ids)
     ,(format "Set the priority of the issue at point to P%d (%s)."
              priority meaning)
     (interactive (list (beads--targets)))
     (beads--set-priority ,priority ids)))

(beads--define-priority-command 0 "critical")
(beads--define-priority-command 1 "high")
(beads--define-priority-command 2 "medium")
(beads--define-priority-command 3 "low")
(beads--define-priority-command 4 "backlog")

(defun beads-create (type priority)
  "Create an issue of TYPE with PRIORITY.
The first line of the message buffer is the title, the rest the
description."
  (interactive
   (let ((default-directory (or (beads-toplevel)
                                (user-error "No beads database in this repository"))))
     (list (completing-read "Type: " (beads--types) nil t nil nil "task")
           (string-to-number
            (completing-read "Priority: "
                             '("0" "1" "2" "3" "4") nil t nil nil "2")))))
  (beads--read-message
   "new issue"
   (list "First line is the title, the rest is the description."
         (format "Type: %s  Priority: P%d" type priority))
   (lambda (text)
     (pcase-let ((`(,title . ,description) (beads--split-message text)))
       (when (string-empty-p title)
         (user-error "An issue needs a title"))
       (let ((id (beads--with-text-file
                  description
                  (lambda (file)
                    (alist-get 'id
                               (json-parse-string
                                (beads--mutate "create" title
                                               "--type" type
                                               "--priority" (number-to-string priority)
                                               "--body-file" file
                                               "--json")
                                :object-type 'alist
                                :null-object nil
                                :false-object nil))))))
         (beads--refresh "Created %s" id))))))

(defun beads--split-message (text)
  "Split TEXT into its first line and the rest."
  (let ((lines (split-string text "\n")))
    (cons (string-trim (or (car lines) ""))
          (string-trim (mapconcat #'identity (cdr lines) "\n")))))

(defun beads--types ()
  "Return the issue types bd accepts."
  (let ((out (ignore-errors (beads--mutate "types"))))
    (or (and out
             (seq-keep (lambda (line)
                         (and (string-match "\\`  \\([a-z][a-z-]*\\) " line)
                              (match-string 1 line)))
                       (split-string out "\n")))
        '("task" "bug" "feature" "chore" "epic"))))

;;; The transient

(defun beads--dispatch-description ()
  "Return a heading naming what the transient is about to act on."
  (let ((ids (beads--issues-at-point)))
    (cond ((null ids) "Beads (no issue at point)")
          ((cdr ids) (format "Beads (%d issues in region)" (length ids)))
          (t (format "Beads: %s  %s"
                     (car ids)
                     (or (alist-get 'title (beads--fetch-issue (car ids))) ""))))))

;;;###autoload
(transient-define-prefix beads-dispatch ()
  "Act on the beads issue at point."
  [:description beads--dispatch-description
   ["Issue"
    ("k" "Claim" beads-claim)
    ("c" "Close" beads-close)
    ("m" "Comment" beads-comment)
    ("a" "Assign" beads-assign)]
   ["Priority"
    ("0" "critical" beads-set-priority-0)
    ("1" "high" beads-set-priority-1)
    ("2" "medium" beads-set-priority-2)
    ("3" "low" beads-set-priority-3)
    ("4" "backlog" beads-set-priority-4)]
   ["Tracker"
    ("n" "New issue" beads-create)
    ("RET" "Show" beads-show-at-point)]])

(provide 'beads)

;;; beads.el ends here
