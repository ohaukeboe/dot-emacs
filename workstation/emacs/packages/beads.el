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
;; Everything is read-only.  TAB unfolds an issue's description in place,
;; RET opens the full `bd show' output in its own buffer.  Claiming,
;; closing and creating stay in the terminal.

;;; Code:

(require 'ansi-color)
(require 'seq)
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
        (magit-insert-heading (format "%s (%d)" heading (length issues)))
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

(define-derived-mode beads-show-mode special-mode "Beads"
  "Major mode for the output of `bd show'."
  :interactive nil)

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
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert out)
            (ansi-color-apply-on-region (point-min) (point-max))
            (goto-char (point-min))))
        (pop-to-buffer buffer)))))

(defun beads-show-at-point ()
  "Display the beads issue of the section at point."
  (interactive)
  (beads-show (oref (magit-current-section) value)))

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

(provide 'beads)

;;; beads.el ends here
