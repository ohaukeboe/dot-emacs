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
;;
;; The same transient hands the issue at point to a coding agent: a quick
;; prompt pastes a reference to it into the agent's input for the rest to
;; be typed there, and explore submits a prepared prompt asking the agent
;; to study the issue and ask what has to be decided, without implementing
;; it.  The agent is plugged in through `beads-agent-available-function'
;; and `beads-agent-send-function'; this file names no agent package.

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

(defcustom beads-relation-limit 5
  "Number of blockers to list in an issue's body before summarizing the rest.
The mark on the heading always reports the full count; only the listing
is capped, as `beads-ready-limit' caps the ready listing."
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

(defface beads-relation '((t :inherit magit-dimmed))
  "Face for the mark naming a parent, and for the count of dependents."
  :group 'beads)

(defface beads-blocked '((t :inherit warning))
  "Face for the mark of an issue something open is holding up."
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

(defun beads--relation-target (id map)
  "Return the relation target for ID, resolved through MAP.
An id MAP does not hold is not an error: bd was asked about it and said
nothing, so the relation is real but its issue cannot be read."
  (or (and map (gethash id map))
      `((id . ,id) (title . nil) (status . nil) (resolved . nil))))

(defun beads--relation-target-of (issue)
  "Return the relation target naming ISSUE."
  `((id . ,(alist-get 'id issue))
    (title . ,(alist-get 'title issue))
    (status . ,(alist-get 'status issue))
    (resolved . t)))

(defun beads--blocked-map ()
  "Return a hash of issue id to the ids blocking it, as bd resolves them.
Return the string describing the failure instead when bd cannot answer.

Deliberately `bd blocked\=' rather than a walk over the dependency edges:
what counts as blocking is the tracker\='s decision, and a second
implementation here would drift from it.  It is also how a dependency on
a closed issue stops being a blocker without any status logic of our own."
  (let ((issues (beads--issues "blocked" "--json")))
    (if (stringp issues)
        issues
      (let ((map (make-hash-table :test #'equal)))
        (dolist (issue issues map)
          (puthash (alist-get 'id issue)
                   (append (alist-get 'blocked_by issue) nil)
                   map))))))

(defun beads--resolve-targets (ids)
  "Return a hash of id to relation target for IDS, in one bd call.
Return the string describing the failure instead when bd cannot answer.

`--all\=' is what makes a relation pointing at a closed issue resolve;
without it a closed issue and a deleted one look alike.  One call for
every id, because `bd show\=' costs about a tenth of a second per id while
this costs the same for one as for fifty."
  (let ((issues (beads--issues "list" (concat "--id=" (string-join ids ","))
                               "--all" "--json" "-n" "0")))
    (if (stringp issues)
        issues
      (let ((map (make-hash-table :test #'equal)))
        (dolist (issue issues map)
          (puthash (alist-get 'id issue) (beads--relation-target-of issue) map))))))

(defun beads--relation-set (issue blocked targets)
  "Return what ISSUE takes part in, or nil when it takes part in nothing.
BLOCKED maps issue ids to blocker ids, TARGETS resolves an id to a
relation target.  An issue with no relations gets no set, so it renders
exactly as it did before this file knew about relations."
  (let ((parent (alist-get 'parent issue))
        (blockers (and blocked (gethash (alist-get 'id issue) blocked)))
        (dependents (or (alist-get 'dependent_count issue) 0)))
    (when (or parent blockers (> dependents 0))
      `((parent . ,(and parent (beads--relation-target parent targets)))
        (blockers . ,(mapcar (lambda (id) (beads--relation-target id targets)) blockers))
        (dependent-count . ,dependents)))))

(defun beads--relations (in-progress ready)
  "Return (TABLE . FAILURE) for the issues IN-PROGRESS and READY list.
TABLE is a hash of issue id to relation set holding only the issues that
have relations; FAILURE is bd\='s own message when a relation call did not
answer, and then TABLE is nil and nothing is marked.

Every call here is conditional, so a tracker whose listed issues have no
relations asks bd for nothing beyond the two lists it already asked for.
Ready beads are unblocked by construction, so only the claimed ones can
need the blocked set at all."
  (let ((listed (append in-progress ready))
        (blocked nil)
        (failure nil))
    (when (seq-some (lambda (issue)
                      (> (or (alist-get 'dependency_count issue) 0) 0))
                    in-progress)
      (let ((map (beads--blocked-map)))
        (if (stringp map) (setq failure map) (setq blocked map))))
    (if failure
        (cons nil failure)
      (let ((ids (seq-uniq
                  (delq nil
                        (append
                         (mapcar (lambda (issue) (alist-get 'parent issue)) listed)
                         (mapcan (lambda (issue)
                                   (copy-sequence
                                    (and blocked
                                         (gethash (alist-get 'id issue) blocked))))
                                 listed))))))
        (let ((targets (and ids (beads--resolve-targets ids))))
          (if (stringp targets)
              (cons nil targets)
            (let ((table (make-hash-table :test #'equal)))
              (dolist (issue listed)
                (when-let* ((set (beads--relation-set issue blocked targets)))
                  (puthash (alist-get 'id issue) set table)))
              (cons table nil))))))))

;;; Formatting

(defun beads--width ()
  "Return the number of columns available for an issue line.
Deliberately `window-body-width\' rather than `window-max-chars-per-line\':
the latter is implemented with `with-selected-window\', and selecting a
window sets its buffer\'s point to that window\'s point.  Called while
Magit is rebuilding the buffer -- from a timer, with the status window
displayed but not selected -- that drags the insertion point back to the
window\'s stale position, and the rest of the refresh lands at the top of
the buffer."
  (max 40 (1- (if-let* ((window (get-buffer-window (current-buffer))))
                  (window-body-width window)
                fill-column))))

(defun beads--priority-face (priority)
  "Return the face for PRIORITY, or nil for the ordinary ones."
  (pcase priority
    (0 'beads-critical)
    (1 'beads-high)
    ((or 3 4) 'beads-low)))

(defun beads--relation-marks (relations)
  "Return the marks summarizing RELATIONS, or the empty string.
The empty string is the point of this function: an issue that takes part
in nothing must come out of `beads--format-issue' exactly as it did
before the file knew about relations, separator included."
  (let ((parts nil))
    (when (alist-get 'parent relations)
      (push (propertize "↑" 'font-lock-face 'beads-relation) parts))
    (when-let* ((blockers (alist-get 'blockers relations)))
      (push (propertize (format "⊘%d" (length blockers))
                        'font-lock-face 'beads-blocked)
            parts))
    ;; The count bd puts in the listing, which is the issues that depend on
    ;; this one through a `blocks' edge.  Its children are not in it: only
    ;; `bd show' counts those, and one call per issue is not a refresh.
    (let ((dependents (or (alist-get 'dependent-count relations) 0)))
      (when (> dependents 0)
        (push (propertize (format "↳%d" dependents)
                          'font-lock-face 'beads-relation)
              parts)))
    (if parts (concat (string-join (nreverse parts) " ") "  ") "")))

(defun beads--format-issue (issue indent &optional relations)
  "Return the one-line listing of ISSUE, prefixed by INDENT spaces.
RELATIONS, when the issue has any, is marked between its priority and
its title and is counted against the width the title is truncated to."
  (let* ((id (alist-get 'id issue))
         (priority (alist-get 'priority issue))
         (marks (beads--relation-marks relations))
         (prefix (format "%s%s  %s  %s"
                         (make-string indent ?\s)
                         id
                         (if priority (format "P%d" priority) "P?")
                         marks))
         (title (or (alist-get 'title issue) "")))
    (concat (make-string indent ?\s)
            (propertize id 'font-lock-face 'magit-hash)
            "  "
            (propertize (if priority (format "P%d" priority) "P?")
                        'font-lock-face (beads--priority-face priority))
            "  "
            marks
            (truncate-string-to-width title (max 20 (- (beads--width)
                                                       (string-width prefix)))
                                      nil nil t))))

(defun beads--format-relation-target (target &optional with-status)
  "Return TARGET as a line naming the issue it points at.
An id bd did not return is rendered as unknown rather than dropped: the
relation is real, and hiding it would say the issue has none."
  (let ((id (alist-get 'id target)))
    (if (not (alist-get 'resolved target))
        (concat (propertize id 'font-lock-face 'magit-hash)
                "  " (propertize "(unknown)" 'font-lock-face 'magit-dimmed))
      (concat (propertize id 'font-lock-face 'magit-hash)
              (if with-status (format "  (%s)" (alist-get 'status target)) "")
              "  " (or (alist-get 'title target) "")))))

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

(defvar-local beads--relation-table nil
  "Hash of issue id to relation set for the issues this buffer lists.
Rebuilt from scratch on every refresh rather than merged, so an issue
whose last blocker was closed loses its mark instead of keeping a stale
one.  Held here rather than in the section object because the section's
value is the issue id, and every command in this file reads it as one.")

(defun beads--relations-at (id)
  "Return the relation set of the issue ID in this buffer, or nil."
  (and id beads--relation-table (gethash id beads--relation-table)))

(defconst beads--relation-label-width (length "Blocked by: ")
  "Column the relation lines of an issue's body align their issues at.")

(defun beads--insert-relations (relations indent)
  "Insert the relation lines of RELATIONS, indented by INDENT spaces.
The marks on the heading say that a relation exists; these lines say
which issue it points at, in the shape of the `Assignee:' line above
them.  Nothing is inserted for a relation the issue does not have."
  (let ((pad (make-string indent ?\s))
        (gap (make-string beads--relation-label-width ?\s)))
    (when-let* ((parent (alist-get 'parent relations)))
      (insert pad
              (propertize "Parent:     " 'font-lock-face 'magit-dimmed)
              (beads--format-relation-target parent)
              "\n"))
    (when-let* ((blockers (alist-get 'blockers relations)))
      (let* ((shown (if (and beads-relation-limit
                             (> (length blockers) beads-relation-limit))
                        (take beads-relation-limit blockers)
                      blockers))
             (hidden (- (length blockers) (length shown)))
             (label (propertize "Blocked by: " 'font-lock-face 'beads-blocked)))
        (dolist (target shown)
          (insert pad label (beads--format-relation-target target t) "\n")
          (setq label gap))
        (when (> hidden 0)
          (insert pad gap
                  (propertize (format "…and %d more\n" hidden)
                              'font-lock-face 'magit-dimmed)))))))

(defun beads--insert-issue (issue)
  "Insert ISSUE as a foldable section, its description in the body."
  (let ((relations (beads--relations-at (alist-get 'id issue))))
    (magit-insert-section (beads-issue-section (alist-get 'id issue) t)
      (magit-insert-heading (beads--format-issue issue 2 relations))
      (let ((assignee (alist-get 'assignee issue)))
        (unless (beads--self-p assignee)
          (insert (propertize (format "    Assignee: %s\n" (or assignee "nobody"))
                              'font-lock-face 'magit-dimmed))))
      (beads--insert-relations relations 4)
      (insert (beads--fill (or (alist-get 'description issue) "No description.")
                           4)))))

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
        ;; A relation call that fails costs the marks, never the listing: the
        ;; issues are what the section is for, and their relations are a
        ;; garnish that has to be able to go missing.
        (pcase-let ((`(,table . ,failure) (beads--relations in-progress ready)))
          (setq beads--relation-table table)
          (magit-insert-section (beads-issues-section 'beads t)
            (magit-insert-heading
              (format "Beads issues (%d)"
                      (+ (length in-progress) (length ready))))
            (when failure
              (insert (propertize (format "  Relations unavailable: %s\n" failure)
                                  'font-lock-face 'magit-dimmed)))
            (beads--insert-group 'in-progress "In progress"
                                 (beads--sort in-progress) nil)
            (beads--insert-group 'ready "Ready"
                                 (beads--sort ready)
                                 (and (not beads--ready-limit-lifted)
                                      beads-ready-limit))
            (insert "\n"))))))))

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
          (setq beads--relations-cache nil)
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

(defun beads--relations-of-issue (id)
  "Return the relation set of the issue ID, read from bd directly.
For the buffers that have no relation table: a `beads-show-mode' buffer
displays one issue and never builds one.  Interactive paths only -- `bd
show' costs about a tenth of a second per id, which is fine for a command
and not for a refresh."
  (when-let* ((issue (beads--fetch-issue id)))
    (let ((parent nil)
          (blockers nil)
          (dependents (or (alist-get 'dependent_count issue) 0)))
      (dolist (dep (alist-get 'dependencies issue))
        (pcase (alist-get 'dependency_type dep)
          ("parent-child" (setq parent (beads--relation-target-of dep)))
          ("blocks" (unless (equal (alist-get 'status dep) "closed")
                      (push (beads--relation-target-of dep) blockers)))))
      ;; bd names the parent in a field of its own as well.  Trust the field
      ;; for whether there is one, and the edge for what it is called.
      (when-let* ((named (alist-get 'parent issue)))
        (unless parent (setq parent (beads--relation-target named nil))))
      (when (or parent blockers (> dependents 0))
        `((parent . ,parent)
          (blockers . ,(nreverse blockers))
          (dependent-count . ,dependents))))))

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

(defvar beads--jump-history nil
  "Locations relation jumps started from, most recent first.
Each entry is a buffer and a marker into it.  A marker rather than a
position because Magit rewrites the status buffer on every refresh, and
the place to come back to should survive that.  One list for the whole
session rather than one per buffer: a jump can leave the status buffer
for a `beads-show-mode\=' one, and the way back crosses with it.  Not
persisted.")

(defun beads--push-location (buffer marker)
  "Record BUFFER and MARKER as somewhere to come back to."
  (push (cons buffer marker) beads--jump-history))

(defun beads--relations-at-point ()
  "Return the relation set of the issue at point.
In a Magit buffer that is a lookup in the table the refresh built; in a
`beads-show-mode\=' buffer, which has no table, it is a question for bd."
  (cond
   ((derived-mode-p 'magit-section-mode)
    (beads--relations-at (beads--issue-at-point)))
   ((derived-mode-p 'beads-show-mode)
    (beads--relations-of-issue beads--issue))))

(defun beads--section-for (id)
  "Return the section of this buffer listing the issue ID, or nil."
  (and (derived-mode-p 'magit-section-mode)
       magit-root-section
       (catch 'found
         (letrec ((walk (lambda (section)
                          (when (and (cl-typep section 'beads-issue-section)
                                     (equal (oref section value) id))
                            (throw 'found section))
                          (mapc walk (oref section children)))))
           (funcall walk magit-root-section))
         nil)))

(defun beads--goto (target)
  "Move to the issue TARGET names, and record where the move started.
An issue this buffer already lists is moved to in place: opening a second
view of something three lines up would be a worse answer to `move to it\='
than moving.  Anything else opens in its own buffer.  The location is
pushed only once the move has happened, so a `bd show\=' that fails leaves
the history alone along with everything else."
  (let ((id (alist-get 'id target))
        (origin (point-marker))
        (buffer (current-buffer)))
    (if-let* ((section (beads--section-for id)))
        (progn (magit-section-show section)
               (goto-char (oref section start)))
      (beads-show id))
    (beads--push-location buffer origin)))

(defun beads--read-relation (prompt targets)
  "Read one of TARGETS with PROMPT, or return the only one there is."
  (cond
   ((null targets) nil)
   ((null (cdr targets)) (car targets))
   (t
    (let* ((table (mapcar (lambda (target) (cons (alist-get 'id target) target))
                          targets))
           (completion-extra-properties
            (list :annotation-function
                  (lambda (id)
                    (let ((target (alist-get id table nil nil #'equal)))
                      (if (alist-get 'resolved target)
                          (format "  (%s)  %s"
                                  (alist-get 'status target)
                                  (or (alist-get 'title target) ""))
                        "  (unknown)"))))))
      (alist-get (completing-read prompt table nil t) table nil nil #'equal)))))

(defun beads--dependents-of (id)
  "Return the issues depending on ID, as relation targets.
Read on demand rather than during a refresh: bd warns that this is the
slow question to ask of an issue many others hang off, and the count that
the mark needs is already in the listing."
  (let ((issues (beads--issues "show" id "--json" "--include-dependents")))
    (when (stringp issues)
      (user-error "bd show %s: %s" id issues))
    (mapcar #'beads--relation-target-of (alist-get 'dependents (car issues)))))

(defun beads--issue-at-point-or-error ()
  "Return the id of the issue at point, or say there is none."
  (or (beads--issue-at-point) (user-error "No beads issue at point")))

;;;###autoload
(defun beads-goto-parent ()
  "Move to the parent of the issue at point."
  (interactive)
  (let* ((id (beads--issue-at-point-or-error))
         (parent (alist-get 'parent (beads--relations-at-point))))
    (unless parent
      (user-error "%s has no parent" id))
    (unless (alist-get 'resolved parent)
      (user-error "%s: the parent %s could not be read"
                  id (alist-get 'id parent)))
    (beads--goto parent)))

;;;###autoload
(defun beads-goto-blocker ()
  "Move to one of the issues blocking the issue at point."
  (interactive)
  (let* ((id (beads--issue-at-point-or-error))
         (blockers (alist-get 'blockers (beads--relations-at-point))))
    (unless blockers
      (user-error "Nothing is blocking %s" id))
    (when-let* ((target (beads--read-relation (format "Blocker of %s: " id)
                                              blockers)))
      (unless (alist-get 'resolved target)
        (user-error "%s: the blocker %s could not be read"
                    id (alist-get 'id target)))
      (beads--goto target))))

;;;###autoload
(defun beads-goto-dependent ()
  "Move to one of the issues depending on the issue at point.
Deliberately not gated on the count the mark shows.  `bd list' and `bd
ready' count only the issues that depend on one through a `blocks' edge,
while `bd show' also counts its children -- an epic of seven tasks is
reported as having no dependents by the first two and seven by the third.
The mark can only say what the listing knows; this command asks the
question that knows more, so an epic's children stay reachable."
  (interactive)
  (let ((id (beads--issue-at-point-or-error)))
    (let ((targets (beads--dependents-of id)))
      (unless targets
        (user-error "Nothing depends on %s" id))
      (when-let* ((target (beads--read-relation (format "Depends on %s: " id)
                                                targets)))
        (beads--goto target)))))


;;;###autoload
(defun beads-go-back ()
  "Return to where the last relation jump started.
Repeatedly, in reverse order.  An entry whose buffer or marker has died
is skipped rather than reported: a killed buffer is the ordinary course
of things, not a failure worth a message."
  (interactive)
  (let ((location nil))
    (while (and beads--jump-history (null location))
      (pcase-let ((`(,buffer . ,marker) (pop beads--jump-history)))
        (when (and (buffer-live-p buffer) (marker-position marker))
          (setq location (cons buffer marker)))))
    (unless location
      (user-error "Nowhere to go back to"))
    (pop-to-buffer (car location))
    (goto-char (cdr location))))

;;; Prompting the agent

;; This file names no agent package.  The configuration plugs one in
;; through the two functions below, so the tests can put a recorder in
;; their place and the package loads without any agent installed.

(defcustom beads-agent-available-function nil
  "Function telling whether the repository has an agent session.
Called with no arguments and `default-directory' at the repository root;
return non-nil when a session exists for that project.  Must be cheap
and must not prompt: the transient calls it while drawing itself.  Nil
means no agent is configured, and the agent commands are unavailable."
  :type '(choice (const nil) function)
  :group 'beads)

(defcustom beads-agent-send-function nil
  "Function delivering a prompt to the repository's agent session.
Called with TEXT and SUBMIT, and `default-directory' at the repository
root.  Deliver TEXT to the chosen session's input as one paste, so a
newline in it does not submit half of it, and press return only when
SUBMIT is non-nil.  May prompt to choose among several sessions.  Signal
`user-error' when no session can be chosen.  Return the session's
buffer.  Nil means no agent is configured."
  :type '(choice (const nil) function)
  :group 'beads)

(defun beads--agent-root ()
  "Return the directory the agent functions are called in."
  (or (beads-toplevel) default-directory))

(defun beads--agent-available-p ()
  "Return non-nil when an agent session can receive a prompt."
  (and beads-agent-available-function
       beads-agent-send-function
       (let ((default-directory (beads--agent-root)))
         (funcall beads-agent-available-function))
       t))

(defun beads--agent-send (text submit)
  "Send TEXT to the agent, pressing return if SUBMIT; return its buffer.
Refuses before anything is sent, so a refusal leaves the agent's input
exactly as it was."
  (unless (beads--agent-available-p)
    (user-error "No agent session for this repository"))
  (let ((default-directory (beads--agent-root)))
    (funcall beads-agent-send-function text submit)))

(defun beads--agent-ids ()
  "Return the ids to prompt about, or say there is no issue here.
Unlike `beads--targets', never reads one: a prompt reaches the agent
before a mis-chosen completion would be noticed."
  (or (beads--issues-at-point) (user-error "No beads issue at point")))

(defcustom beads-agent-quick-prompt-format "Beads issue %s: "
  "Format of the quick prompt; %s is the ids, separated by commas.
It names what the ids are, since the agent may not know the tracker's
prefix, and it must not start with /, ! or #, which the agent reads as
commands."
  :type 'string
  :group 'beads)

;;;###autoload
(defun beads-agent-prompt ()
  "Start a prompt to the agent about the issue at point, and switch to it.
Paste a reference to the issue -- or to every issue in the region --
into the agent's input without submitting it, so the rest is typed
there.  Text already in the input is kept; the reference is pasted at
the terminal's cursor, which is its end unless it was moved."
  (interactive)
  (let* ((ids (beads--agent-ids))
         (buffer (beads--agent-send
                  (format beads-agent-quick-prompt-format
                          (string-join ids ", "))
                  nil)))
    (if-let* ((window (get-buffer-window buffer t)))
        (select-window window)
      (pop-to-buffer buffer))))

(defcustom beads-agent-explore-prompt
  "Explore beads issue %i before any work on it starts.

Read it with `bd show %i`, including its parent, its blockers, the issues that
depend on it and its comments. Then read the parts of this repository the issue
concerns, enough to know how it would be implemented here.

Reply with:
1. Your understanding of what the issue asks for and why.
2. Every decision that has to be made before implementing it, each as a
   question, with the options you see and the one you would choose. If nothing
   needs deciding, say so plainly instead of inventing questions.

Do not implement anything. Do not create, edit or delete files. Do not claim,
update, comment on or close any issue. Do not commit. Do not start any skill or
workflow that implements the issue. After your questions, stop and wait for my
answers: I will choose how the work is done, and with which skills if any."
  "Prompt `beads-agent-explore' submits; %i is the issue id.
It asks the agent to study the issue and ask what has to be decided,
and forbids it to implement anything, so that how the work is then done
-- and with which skills -- stays the developer's choice.  When the
text does not end up naming the issue, \"Beads issue ID:\" is put in
front of it.  Other % sequences are left as they are."
  :type 'string
  :group 'beads)

(defun beads--agent-explore-text (id)
  "Return `beads-agent-explore-prompt' for the issue ID."
  (require 'format-spec)
  (let ((text (format-spec beads-agent-explore-prompt `((?i . ,id)) 'ignore)))
    (if (string-search id text)
        text
      (concat "Beads issue " id ":\n\n" text))))

;;;###autoload
(defun beads-agent-explore ()
  "Have the agent explore the issue at point and ask what must be decided.
Submit `beads-agent-explore-prompt' for the issue, leaving the windows
as they are.  Works on one issue: with several in the region, says so."
  (interactive)
  (let ((ids (beads--agent-ids)))
    (when (cdr ids)
      (user-error "Explore works on one issue; the region covers %d"
                  (length ids)))
    (let ((buffer (beads--agent-send (beads--agent-explore-text (car ids)) t)))
      (message "Sent explore prompt for %s to %s"
               (car ids) (buffer-name buffer)))))

;;; The transient

(defvar beads--relations-cache nil
  "The relation set last read for a `beads-show-mode\=' buffer.
A cons of the buffer and issue it was read for, and the set itself.  The
transient asks four times whether an entry applies while it draws itself,
and in a show buffer each of those is a `bd show\=' -- worth remembering
for as long as point stays on the same issue.")

(defun beads--relations-cached ()
  "Return the relation set at point, reading bd at most once per issue.
In a Magit buffer nothing is cached: the set is a hash lookup into the
table the refresh built, and a stale answer there would outlive a
refresh that changed it."
  (if (derived-mode-p 'magit-section-mode)
      (beads--relations-at-point)
    (let ((key (cons (current-buffer) beads--issue)))
      (unless (equal (car beads--relations-cache) key)
        (setq beads--relations-cache (cons key (beads--relations-at-point))))
      (cdr beads--relations-cache))))

(defun beads--has-parent-p ()
  "Return non-nil when the issue at point has a parent."
  (and (alist-get 'parent (beads--relations-cached)) t))

(defun beads--has-blockers-p ()
  "Return non-nil when something is blocking the issue at point."
  (and (alist-get 'blockers (beads--relations-cached)) t))

(defun beads--has-dependents-p ()
  "Return non-nil when the listing says anything depends on the issue at point.
Only what the listing knows: children are not counted there, so the entry
is grey on an epic whose tasks are its only dependents.  The command
itself is not gated on this -- see `beads-goto-dependent'."
  (> (or (alist-get 'dependent-count (beads--relations-cached)) 0) 0))

(defun beads--went-somewhere-p ()
  "Return non-nil when there is a relation jump to come back from."
  (and beads--jump-history t))

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
   ["Relations"
    ;; `:inapt-if-not' rather than `:if': an entry that disappears when it
    ;; does not apply makes the menu a different shape for every issue, and
    ;; there is nothing left to learn the position of.
    ("p" "Parent" beads-goto-parent :inapt-if-not beads--has-parent-p)
    ("b" "Blocker" beads-goto-blocker :inapt-if-not beads--has-blockers-p)
    ("d" "Dependent" beads-goto-dependent :inapt-if-not beads--has-dependents-p)
    ("B" "Back" beads-go-back :inapt-if-not beads--went-somewhere-p)]
   ["Agent"
    ;; Grey rather than gone without a session, as for the relations.
    ("i" "Prompt" beads-agent-prompt :inapt-if-not beads--agent-available-p)
    ("e" "Explore" beads-agent-explore :inapt-if-not beads--agent-available-p)]
   ["Tracker"
    ("n" "New issue" beads-create)
    ("RET" "Show" beads-show-at-point)]])

(provide 'beads)

;;; beads.el ends here
