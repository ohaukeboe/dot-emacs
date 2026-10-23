;; -*- lexical-binding: t; -*-
;;; walkthrough.el --- Read an agent's walkthrough of a branch in Magit

;; Package-Requires: ((emacs "30.1") (magit "4.0"))

;;; Commentary:

;; A walkthrough is an agent's guided tour of the committed changes between
;; a base and a head commit: steps in reading order, each with an
;; explanation and the diffs it owns, and the agent's findings on them.
;; This file validates a draft walkthrough, installs it under the
;; repository's git directory and shows it in `walkthrough-mode', a mode
;; derived from `magit-diff-mode'.
;;
;; The file stores only the two commits, never a copy of the diff; each
;; step's diff is rebuilt with Magit from them (docs/adr/0007).  Because
;; the hunks are Magit's own sections, everything that works in a diff
;; buffer works here: RET visits the file, TAB folds, and review comments
;; made with the configuration's `@' are drawn as anywhere else.
;;
;; Findings are marked accepted or dismissed in place, and the marks are
;; written back to the file, as is the user's reply to a finding
;; (`walkthrough-reply'), which accepts it.  `walkthrough-accepted-findings' returns the
;; accepted ones shaped like review comments, for the configuration's
;; hand-off to send; `walkthrough-mark-sent' records that it did.  The
;; agent is plugged in through `walkthrough-request-function'; this file
;; names no agent package.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'magit)

(defgroup walkthrough nil
  "Agent walkthroughs of a branch's changes, in Magit."
  :group 'magit-extensions)

(defcustom walkthrough-request-function nil
  "Function that sends a request to the repository's coding agent.
Called as (TEXT SUBMIT) with the slash command that starts a walkthrough
and SUBMIT t.  When nil, `walkthrough-request' says no agent is
configured."
  :type '(choice (const :tag "No agent" nil) function))

(defvar walkthrough-open-after-install t
  "Whether `walkthrough-install' shows the walkthrough it installed.")

;;; The file

(defun walkthrough-directory ()
  "Return the walkthroughs directory of the current repository.
It lives in the common git directory, so every worktree of a repository
shares it, and it is never tracked."
  (let ((common (or (magit-git-string "rev-parse" "--path-format=absolute"
                                      "--git-common-dir")
                    (user-error "Not in a Git repository"))))
    (file-name-as-directory (expand-file-name "walkthroughs" common))))

(defun walkthrough--file-for-branch (branch)
  "Return the installed walkthrough file of BRANCH."
  (expand-file-name (concat (string-replace "/" "%2F" branch) ".json")
                    (walkthrough-directory)))

(defun walkthrough--read (file)
  "Return the walkthrough in FILE as an alist; arrays are vectors."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (json-parse-buffer :object-type 'alist :array-type 'array
                       :null-object nil :false-object nil)))

(defun walkthrough--write (data file)
  "Write walkthrough DATA to FILE atomically.
The new contents go to a temporary file beside FILE first and are then
renamed over it, so a reader never sees half a walkthrough."
  (make-directory (file-name-directory file) t)
  (let ((temp (make-temp-file (expand-file-name ".walkthrough"
                                                (file-name-directory file))
                              nil ".json"))
        (coding-system-for-write 'utf-8))
    (with-temp-file temp
      ;; Not `json-serialize': it returns unibyte UTF-8, whose bytes the
      ;; pretty-printer would write back as octal escapes.
      (json-insert data)
      (json-pretty-print-buffer))
    (rename-file temp file t)))

(defun walkthrough--put (alist key value)
  "Return ALIST with KEY set to VALUE, or removed when VALUE is nil."
  (let ((rest (assq-delete-all key (copy-sequence alist))))
    (if value (cons (cons key value) rest) rest)))

;;; Parsing a diff

(defun walkthrough--parse-diff-region (beg end)
  "Parse the git diff between BEG and END in the current buffer.
Return one plist per file, in order: :file (the new path, or the old one
for a deleted file), :old, :beg, :end and :hunks.  Each hunk is a plist
with :header, :start and :length (the new side), :old-start,
:old-length, :beg and :end.  Positions are buffer positions."
  (let (files file hunks hunk)
    (cl-flet ((close-hunk (pos)
                (when hunk
                  (push (plist-put hunk :end pos) hunks)
                  (setq hunk nil)))
              (close-file (pos)
                (when file
                  (when (plist-get file :deleted)
                    (plist-put file :file (plist-get file :old)))
                  (plist-put file :hunks (nreverse hunks))
                  (push (plist-put file :end pos) files)
                  (setq file nil hunks nil))))
      (save-excursion
        (goto-char beg)
        (while (< (point) end)
          (let ((line (buffer-substring-no-properties
                       (point) (min end (line-end-position))))
                (pos (point)))
            (cond
             ((string-prefix-p "diff --git " line)
              (close-hunk pos)
              (close-file pos)
              (let ((paths (substring line (length "diff --git "))))
                (setq file (list :file (substring paths (/ (1+ (length paths)) 2))
                                 :old nil :deleted nil :beg pos :end nil
                                 :hunks nil))))
             ((null file))
             ((string-match
               "\\`@@ -\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
               line)
              (close-hunk pos)
              (cl-flet ((num (n default)
                          (if (match-string n line)
                              (string-to-number (match-string n line))
                            default)))
                (setq hunk (list :header (match-string 0 line)
                                 :old-start (num 1 nil) :old-length (num 2 1)
                                 :start (num 3 nil) :length (num 4 1)
                                 :beg pos :end nil))))
             ;; Lines of a hunk can look like file headers ("--- x" is a
             ;; removed "-- x"), so headers only count before the first hunk.
             ((or hunk hunks))
             ((string-match "\\`rename from \\(.*\\)" line)
              (plist-put file :old (match-string 1 line)))
             ((string-match "\\`rename to \\(.*\\)" line)
              (plist-put file :file (match-string 1 line)))
             ;; git ends these with a TAB when the path holds a space.
             ((string-match "\\`--- \\([^\t]*\\)" line)
              (unless (equal (match-string 1 line) "/dev/null")
                (plist-put file :old (match-string 1 line))))
             ((string-match "\\`\\+\\+\\+ \\([^\t]*\\)" line)
              (if (equal (match-string 1 line) "/dev/null")
                  (plist-put file :deleted t)
                (plist-put file :file (match-string 1 line))))))
          (forward-line 1))
        (close-hunk (min (point) end))
        (close-file (min (point) end))))
    (nreverse files)))

(defun walkthrough--parse-diff (base head args)
  "Parse `git diff ARGS BASE HEAD' into file plists.
See `walkthrough--parse-diff-region'; positions refer to a buffer that
no longer exists, but each hunk also carries its :text."
  (with-temp-buffer
    (magit-git-insert "diff" "-p" "--no-prefix" "--no-color" "--no-ext-diff"
                      args base head "--")
    (let ((files (walkthrough--parse-diff-region (point-min) (point-max))))
      (dolist (file files)
        (dolist (hunk (plist-get file :hunks))
          (plist-put hunk :text (buffer-substring-no-properties
                                 (plist-get hunk :beg) (plist-get hunk :end)))))
      files)))

(defun walkthrough--hunk-span (hunk)
  "Return the (START . END) new-side lines HUNK covers.
A hunk with no new-side lines covers the single position it starts at,
which is line 1 for one deleting the first lines of a file (+0,0)."
  (let ((start (max 1 (plist-get hunk :start))))
    (cons start (max start (+ start (plist-get hunk :length) -1)))))

(defun walkthrough--hunk-overlaps-p (hunk range)
  "Return non-nil when HUNK overlaps RANGE, a (START END) list."
  (pcase-let ((`(,start . ,end) (walkthrough--hunk-span hunk))
              (`(,from ,to) range))
    (and (<= start to) (>= end from))))

;;; Validation

(defun walkthrough--string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value) (not (string-empty-p (string-trim value)))))

(defun walkthrough--entry (entry)
  "Return ENTRY of a step's files as (FILE . RANGES).
RANGES is nil for a whole file.  Return nil when ENTRY is malformed;
ranges that are not arrays are left out, for the schema check to name."
  (cond ((walkthrough--string-p entry) (cons entry nil))
        ((and (listp entry) (walkthrough--string-p (alist-get 'file entry)))
         (let ((ranges (alist-get 'ranges entry)))
           (cons (alist-get 'file entry)
                 (and (vectorp ranges)
                      (mapcar (lambda (r) (append r nil))
                              (seq-filter #'vectorp ranges))))))))

(defun walkthrough--validate-schema (data)
  "Return the schema errors of walkthrough DATA."
  (let (errors)
    (cl-flet ((err (fmt &rest args) (push (apply #'format fmt args) errors))
              (vec-p (v) (and (vectorp v) (> (length v) 0))))
      (unless (equal (alist-get 'version data) 1)
        (err "version: must be 1"))
      (dolist (key '(title branch base head))
        (unless (walkthrough--string-p (alist-get key data))
          (err "%s: must be a non-empty string" key)))
      (if (not (vec-p (alist-get 'steps data)))
          (err "steps: must be a non-empty array")
        (seq-do-indexed
         (lambda (step i)
           (if (not (listp step))
               (err "steps[%d]: must be an object" i)
             (dolist (key '(title explanation))
               (unless (walkthrough--string-p (alist-get key step))
                 (err "steps[%d].%s: must be a non-empty string" i key)))
             (if (not (vec-p (alist-get 'files step)))
                 (err "steps[%d].files: must be a non-empty array" i)
               (seq-do-indexed
                (lambda (entry j)
                  (if-let* ((parsed (walkthrough--entry entry)))
                      (when (and (listp entry) (not (vec-p (alist-get 'ranges entry))))
                        (err "steps[%d].files[%d].ranges: must be a non-empty array"
                             i j))
                    (err "steps[%d].files[%d]: must be a path or {file, ranges}" i j))
                  (when (and (listp entry) (vectorp (alist-get 'ranges entry)))
                    (seq-do-indexed
                     (lambda (range k)
                       (unless (and (vectorp range) (= (length range) 2)
                                    (natnump (aref range 0)) (natnump (aref range 1))
                                    (<= 1 (aref range 0) (aref range 1)))
                         (err "steps[%d].files[%d].ranges[%d]: %s must satisfy 1 <= start <= end"
                              i j k (if (vectorp range)
                                        (format "[%s]" (mapconcat (lambda (n) (format "%s" n))
                                                                  range ", "))
                                      range))))
                     (alist-get 'ranges entry))))
                (alist-get 'files step)))
             (let ((owned (delq nil (mapcar (lambda (e) (car (walkthrough--entry e)))
                                            (alist-get 'files step))))
                   (findings (alist-get 'findings step)))
               (if (not (vectorp (or findings [])))
                   (err "steps[%d].findings: must be an array" i)
                 (seq-do-indexed
                  (lambda (finding k)
                    (if (not (listp finding))
                        (err "steps[%d].findings[%d]: must be an object" i k)
                      (unless (member (alist-get 'severity finding) '("high" "medium" "low"))
                        (err "steps[%d].findings[%d].severity: must be one of high, medium, low"
                             i k))
                      (dolist (key '(title body))
                        (unless (walkthrough--string-p (alist-get key finding))
                          (err "steps[%d].findings[%d].%s: must be a non-empty string"
                               i k key)))
                      (when-let* ((anchor (alist-get 'anchor finding)))
                        (if (not (listp anchor))
                            (err "steps[%d].findings[%d].anchor: must be an object" i k)
                          (let ((file (alist-get 'file anchor))
                                (line (alist-get 'line anchor))
                                (end (alist-get 'end_line anchor)))
                            (cond ((not (walkthrough--string-p file))
                                   (err "steps[%d].findings[%d].anchor.file: must be a non-empty string"
                                        i k))
                                  ((not (member file owned))
                                   (err "steps[%d].findings[%d].anchor.file: %s is not owned by this step"
                                        i k file)))
                            (unless (and (natnump line) (>= line 1))
                              (err "steps[%d].findings[%d].anchor.line: must be a positive integer"
                                   i k))
                            (when (and end (not (and (natnump line) (natnump end) (>= end line))))
                              (err "steps[%d].findings[%d].anchor.end_line: must be an integer >= line"
                                   i k))
                            (unless (member (alist-get 'side anchor) '(nil "new" "old"))
                              (err "steps[%d].findings[%d].anchor.side: must be new or old"
                                   i k)))))))
                  findings)))))
         (alist-get 'steps data))))
    (nreverse errors)))

(defun walkthrough--validate-commits (data)
  "Return the errors in DATA's base and head commits."
  (let ((base (alist-get 'base data))
        (head (alist-get 'head data))
        errors)
    (dolist (pair `((base . ,base) (head . ,head)))
      (unless (magit-git-success "cat-file" "-e" (concat (cdr pair) "^{commit}"))
        (push (format "%s: %s is not a commit" (car pair) (cdr pair)) errors)))
    (when (and (null errors)
               (not (magit-git-success "merge-base" "--is-ancestor" base head)))
      (push "base: is not an ancestor of head" errors))
    (nreverse errors)))

(defun walkthrough--validate-coverage (data)
  "Return the errors in how DATA's steps cover the diff.
Every hunk of `git diff -U3 BASE HEAD' must be owned by exactly one step,
and every file without hunks by exactly one whole-file entry."
  (let* ((diff (walkthrough--parse-diff (alist-get 'base data)
                                        (alist-get 'head data) '("-U3")))
         (whole (make-hash-table :test #'equal))
         (owners (make-hash-table :test #'eq))
         errors)
    (cl-flet ((err (fmt &rest args) (push (apply #'format fmt args) errors))
              (diff-file (name)
                (seq-find (lambda (f) (equal (plist-get f :file) name)) diff))
              (steps (idxs)
                (mapconcat (lambda (i) (format "steps[%d]" i))
                           (sort (delete-dups (copy-sequence idxs)) #'<) " and ")))
      ;; Whole-file owners first, so a range entry can name them.
      (seq-do-indexed
       (lambda (step i)
         (seq-doseq (entry (alist-get 'files step))
           (pcase (walkthrough--entry entry)
             (`(,file . nil) (push i (gethash file whole))))))
       (alist-get 'steps data))
      (seq-do-indexed
       (lambda (step i)
         (seq-do-indexed
          (lambda (entry j)
            (pcase-let ((`(,file . ,ranges) (walkthrough--entry entry)))
              (when file
                (if-let* ((changed (diff-file file)))
                    (let ((hunks (plist-get changed :hunks)))
                      (when ranges
                        (when-let* ((others (remq i (gethash file whole))))
                          (err "steps[%d].files[%d]: %s is owned by %s as a whole file"
                               i j file (steps others)))
                        (unless hunks
                          (err "steps[%d].files[%d]: %s has no hunks to split; own it whole"
                               i j file)))
                      (dolist (hunk hunks)
                        (when (or (null ranges)
                                  (seq-some (lambda (r)
                                              (walkthrough--hunk-overlaps-p hunk r))
                                            ranges))
                          (push i (gethash hunk owners)))))
                  (err "steps[%d].files[%d]: %s is not changed between base and head"
                       i j file)))))
          (alist-get 'files step)))
       (alist-get 'steps data))
      (dolist (file diff)
        (let ((name (plist-get file :file)))
          (if-let* ((hunks (plist-get file :hunks)))
              (dolist (hunk hunks)
                (let ((idxs (delete-dups (copy-sequence (gethash hunk owners)))))
                  (cond ((null idxs)
                         (err "hunk %s %s: owned by no step" name (plist-get hunk :header)))
                        ((cdr idxs)
                         (err "hunk %s %s: owned by %s" name (plist-get hunk :header)
                              (steps idxs))))))
            (let ((idxs (delete-dups (copy-sequence (gethash name whole)))))
              (cond ((null idxs) (err "file %s: owned by no step" name))
                    ((cdr idxs) (err "file %s: owned by %s" name (steps idxs)))))))))
    (nreverse errors)))

(defun walkthrough-validate (data)
  "Return the list of errors in walkthrough DATA, or nil when it is valid.
Each error reads \"WHERE: PROBLEM\".  Coverage is only checked once the
schema and the commits are sound, since it needs both."
  (let ((errors (append (walkthrough--validate-schema data)
                        (and (walkthrough--string-p (alist-get 'base data))
                             (walkthrough--string-p (alist-get 'head data))
                             (walkthrough--validate-commits data)))))
    (or errors (walkthrough--validate-coverage data))))

;;; Installing

(defun walkthrough--assign-ids (data)
  "Return DATA with an id on every finding and no marks or replies."
  (let ((steps (copy-sequence (alist-get 'steps data))))
    (dotimes (i (length steps))
      (let* ((step (aref steps i))
             (findings (copy-sequence (alist-get 'findings step))))
        (dotimes (k (length findings))
          (aset findings k
                (seq-reduce (lambda (finding key) (walkthrough--put finding key nil))
                            '(state reply follow_up)
                            (walkthrough--put (aref findings k)
                                              'id (format "s%d-f%d" (1+ i) (1+ k))))))
        (aset steps i (walkthrough--put step 'findings findings))))
    (walkthrough--put data 'steps steps)))

(defun walkthrough-install (draft-file)
  "Validate the walkthrough in DRAFT-FILE and install it.
Return (ok . FILE) with the installed file, or (error . MESSAGES).  A
draft with errors changes nothing; a valid one replaces the branch's
earlier walkthrough, marks and all.  Never signals for a bad draft."
  (condition-case err
      (let* ((data (walkthrough--read draft-file))
             (errors (if (listp data)
                         (walkthrough-validate data)
                       (list "draft: must be a JSON object"))))
        (if errors
            (cons 'error errors)
          (let ((file (walkthrough--file-for-branch (alist-get 'branch data))))
            (walkthrough--write
             (walkthrough--assign-ids
              (walkthrough--put
               (walkthrough--put
                (walkthrough--put data 'repo (magit-toplevel))
                'base (magit-rev-parse (alist-get 'base data)))
               'head (magit-rev-parse (alist-get 'head data))))
             file)
            (when walkthrough-open-after-install
              (walkthrough-open file))
            (cons 'ok file))))
    ((json-error file-error)
     (cons 'error (list (format "draft: %s" (error-message-string err)))))))

;;; Finding states

(defun walkthrough--map-findings (data fn)
  "Return DATA with each finding replaced by (FN FINDING)."
  (let ((steps (copy-sequence (alist-get 'steps data))))
    (dotimes (i (length steps))
      (let ((step (aref steps i)))
        (aset steps i (walkthrough--put
                       step 'findings
                       (seq-into (seq-map fn (alist-get 'findings step)) 'vector)))))
    (walkthrough--put data 'steps steps)))

(defun walkthrough--set-state (file id state)
  "Set the state of finding ID in FILE to STATE (nil for unmarked).
Re-reads FILE first, so a change made to another finding since this
buffer last read it is kept."
  (walkthrough--write
   (walkthrough--map-findings
    (walkthrough--read file)
    (lambda (finding)
      (if (equal (alist-get 'id finding) id)
          (walkthrough--put finding 'state state)
        finding)))
   file))

;;; Rendering text

;; markdown-mode is optional, so its options are declared special here for
;; the `let' below to bind them dynamically when it is loaded.
(defvar markdown-hide-markup)
(defvar markdown-fontify-code-blocks-natively)
(declare-function markdown-mode "markdown-mode")

(defun walkthrough--render-markdown (text)
  "Return Markdown TEXT fontified for display, with its markup hidden.
Faces are copied to `font-lock-face', which Magit buffers keep.  Without
`markdown-mode' the text is returned as it is."
  (let ((text (concat (string-trim-right text) "\n")))
    (if (not (require 'markdown-mode nil t))
        text
      (with-temp-buffer
        (insert text)
        (let ((markdown-hide-markup t)
              (markdown-fontify-code-blocks-natively nil))
          (delay-mode-hooks (markdown-mode))
          (font-lock-ensure))
        (let ((pos (point-min)))
          (while (< pos (point-max))
            (let ((next (next-single-property-change pos 'face nil (point-max))))
              (when-let* ((face (get-text-property pos 'face)))
                (put-text-property pos next 'font-lock-face face))
              (setq pos next))))
        (buffer-string)))))

;;; Rendering findings

(defface walkthrough-high '((t :inherit error :weight bold))
  "Face for the severity of a high-severity finding.")

(defface walkthrough-medium '((t :inherit warning :weight bold))
  "Face for the severity of a medium-severity finding.")

(defface walkthrough-low '((t :inherit shadow :weight bold))
  "Face for the severity of a low-severity finding.")

;; The finding background is not derived from the diff faces, so a finding
;; never reads as a highlighted diff line.
(defface walkthrough-finding
  '((((class color) (min-colors 88) (background light)) :background "#eef0f7" :extend t)
    (((class color) (min-colors 88) (background dark)) :background "#262a38" :extend t)
    (t :inherit secondary-selection :extend t))
  "Face for the background of a finding.")

(defface walkthrough-high-bar '((t :inherit error))
  "Face for the gutter bar of a high-severity finding.")

(defface walkthrough-medium-bar '((t :inherit warning))
  "Face for the gutter bar of a medium-severity finding.")

(defface walkthrough-low-bar '((t :inherit shadow))
  "Face for the gutter bar of a low-severity finding.")

(defface walkthrough-sent '((t :inherit shadow :extend t))
  "Face that dims a finding that was handed off.")

;; The look of the configuration's review comments, which this file does
;; not depend on.
(defface walkthrough-reply '((t :inherit font-lock-warning-face))
  "Face for the user's reply to a finding.")

(defconst walkthrough--known-keys
  '(id state severity title body failure_scenario verdict category anchor
       reply follow_up)
  "Finding keys this file knows; any other key is shown as text.")

(defvar-keymap walkthrough-finding-map
  :doc "Keys that act on the finding at point.")

(defun walkthrough--indent (text prefix)
  "Return TEXT with PREFIX before each of its lines.
The empty line after a final newline gets none."
  (replace-regexp-in-string "^\\(?:.\\|\n\\)" (concat prefix "\\&") text t))

(defun walkthrough--finding-block (finding &optional note)
  "Return FINDING rendered as a block of lines, ending in a newline.
Each line starts with a gutter bar in the severity's colour, so the text
after it sits in the code column of a diff.  NOTE, when non-nil, is
appended to the heading.  Faces are set as `font-lock-face'."
  (let* ((severity (alist-get 'severity finding))
         (state (alist-get 'state finding))
         (meta (delq nil (list (when-let* ((v (alist-get 'verdict finding)))
                                 (format "verdict %s" v))
                               (when-let* ((c (alist-get 'category finding)))
                                 (format "category %s" c)))))
         (extra (seq-remove (lambda (pair) (memq (car pair) walkthrough--known-keys))
                            finding))
         (bar (propertize "▎" 'font-lock-face
                          (intern (format "walkthrough-%s-bar" severity))))
         ;; The lines below the heading, the user's reply last.
         (lines
          (concat
           (walkthrough--indent (walkthrough--render-markdown (alist-get 'body finding))
                                "  ")
           (when-let* ((failure (alist-get 'failure_scenario finding)))
             (walkthrough--indent
              (walkthrough--render-markdown (concat "Failure: " failure)) "  "))
           (when meta
             (format "  %s\n" (string-join meta " · ")))
           (mapconcat (lambda (pair) (format "  %s: %s\n" (car pair) (cdr pair)))
                      extra "")
           (when-let* ((reply (alist-get 'reply finding)))
             (walkthrough--indent
              (propertize (concat "▶ " (string-trim-right reply) "\n")
                          'font-lock-face 'walkthrough-reply)
              "  "))))
         (text
          (mapconcat
           (lambda (line) (concat bar line "\n"))
           (cons (concat
                  "◆ "
                  (propertize (upcase severity)
                              'font-lock-face (intern (format "walkthrough-%s" severity)))
                  "  " (propertize (alist-get 'title finding) 'font-lock-face 'bold)
                  (if state (format "  [%s]" state) "")
                  (if note (propertize (format "  (%s)" note) 'font-lock-face 'italic) ""))
                 (split-string (string-remove-suffix "\n" lines) "\n"))
           "")))
    ;; Wrapped lines keep the bar, so the block's extent stays visible.
    (put-text-property 0 (length text) 'wrap-prefix
                       (walkthrough--display-string (concat bar "  "))
                       text)
    (add-face-text-property 0 (length text) 'walkthrough-finding t text)
    (when (equal state "sent")
      (add-face-text-property 0 (length text) 'walkthrough-sent nil text))
    ;; `add-face-text-property' sets `face'; Magit buffers keep only
    ;; `font-lock-face', so move it there, merged with what is there.
    (let ((pos 0))
      (while (< pos (length text))
        (let ((next (next-property-change pos text (length text))))
          (when-let* ((face (get-text-property pos 'face text)))
            (put-text-property pos next 'font-lock-face
                               (delete-dups
                                (flatten-tree (list (get-text-property pos 'font-lock-face text)
                                                    face)))
                               text))
          (setq pos next))))
    (remove-text-properties 0 (length text) '(face nil) text)
    text))

(defun walkthrough--display-string (text)
  "Return TEXT with `font-lock-face' turned into `face', for an overlay."
  (let ((text (copy-sequence text)) (pos 0))
    (while (< pos (length text))
      (let ((next (next-single-property-change pos 'font-lock-face text (length text))))
        (when-let* ((face (get-text-property pos 'font-lock-face text)))
          (put-text-property pos next 'face face text))
        (setq pos next)))
    text))

(defun walkthrough--insert-finding (finding &optional note)
  "Insert FINDING as a section of its own, with NOTE on its first line."
  (let ((id (alist-get 'id finding)))
    (magit-insert-section (walkthrough-finding id)
      (insert (propertize (walkthrough--finding-block finding note)
                          'walkthrough-finding (list id)
                          'keymap walkthrough-finding-map)))))

(defun walkthrough--line-in-hunk-p (hunk line side)
  "Return non-nil when HUNK (a parsed hunk) shows LINE on SIDE."
  (pcase-let ((`(,start . ,length)
               (if (equal side "old")
                   (cons (plist-get hunk :old-start) (plist-get hunk :old-length))
                 (cons (plist-get hunk :start) (plist-get hunk :length)))))
    (and (> length 0) (<= start line (+ start length -1)))))

(defun walkthrough--shown-hunks (step diff)
  "Return an alist from file names to the hunks of DIFF that STEP shows."
  (let ((entries (delq nil (mapcar #'walkthrough--entry (alist-get 'files step))))
        shown)
    (pcase-dolist (`(,name . ,ranges) entries)
      (when-let* ((file (walkthrough--diff-file diff name)))
        (let ((hunks (if (and ranges (not (assoc name (seq-remove #'cdr entries))))
                         (seq-filter (lambda (hunk)
                                       (seq-some (lambda (range)
                                                   (walkthrough--hunk-overlaps-p hunk range))
                                                 ranges))
                                     (plist-get file :hunks))
                       (plist-get file :hunks))))
          (setf (alist-get name shown nil nil #'equal)
                (delete-dups (append (alist-get name shown nil nil #'equal) hunks))))))
    shown))

(defun walkthrough--anchor-line (finding)
  "Return (FILE LINE SIDE) of FINDING's anchor, or nil.
LINE is the last anchored line, below which the finding is drawn."
  (when-let* ((anchor (alist-get 'anchor finding)))
    (list (alist-get 'file anchor)
          (or (alist-get 'end_line anchor) (alist-get 'line anchor))
          (or (alist-get 'side anchor) "new"))))

(defun walkthrough--placed-p (finding shown)
  "Return non-nil when FINDING's anchor is in a hunk of SHOWN."
  (pcase (walkthrough--anchor-line finding)
    (`(,file ,line ,side)
     (seq-some (lambda (hunk) (walkthrough--line-in-hunk-p hunk line side))
               (alist-get file shown nil nil #'equal)))))

(defun walkthrough--hunk-line-position (hunk line side)
  "Return the position of LINE on SIDE in the washed HUNK section, or nil."
  (save-excursion
    (goto-char (oref hunk content))
    (let ((new (car (oref hunk to-range)))
          (old (car (oref hunk from-range)))
          found)
      (while (and (not found) (< (point) (oref hunk end)))
        (pcase (char-after)
          (?\s (when (if (equal side "old") (= old line) (= new line))
                 (setq found (point)))
               (cl-incf new) (cl-incf old))
          (?+ (when (and (not (equal side "old")) (= new line))
                (setq found (point)))
              (cl-incf new))
          (?- (when (and (equal side "old") (= old line))
                (setq found (point)))
              (cl-incf old)))
        (forward-line 1))
      found)))

(defun walkthrough--draw-anchored (findings diff-section)
  "Draw anchored FINDINGS below their lines in DIFF-SECTION's hunks."
  (let ((at (make-hash-table :test #'eql)))
    (magit-map-sections
     (lambda (section)
       (when (magit-section-match 'hunk section)
         (let ((file (oref (oref section parent) value)))
           (dolist (finding findings)
             (pcase (walkthrough--anchor-line finding)
               ((and `(,name ,line ,side) (guard (equal name file)))
                (when-let* ((pos (walkthrough--hunk-line-position section line side)))
                  (push finding (gethash pos at)))))))))
     diff-section)
    (maphash
     (lambda (pos found)
       (let* ((found (nreverse found))
              (end (save-excursion (goto-char pos) (min (point-max) (1+ (line-end-position)))))
              (ov (make-overlay pos end nil t nil)))
         (overlay-put ov 'walkthrough t)
         (overlay-put ov 'walkthrough-finding (mapcar (lambda (f) (alist-get 'id f)) found))
         (overlay-put ov 'keymap walkthrough-finding-map)
         (overlay-put ov 'after-string
                      (walkthrough--display-string
                       (mapconcat #'walkthrough--finding-block found "")))))
     at)))

;;; The buffer

(defvar-local walkthrough--file nil
  "The walkthrough file the current buffer shows.")

(defvar-local walkthrough--data nil
  "The walkthrough as the last refresh read it from `walkthrough--file'.")

(defvar-local walkthrough--header-line nil
  "The text `walkthrough--update-header-line' last put in the header line.")

(defvar-keymap walkthrough-mode-map
  :doc "Keymap for `walkthrough-mode'."
  "n" #'walkthrough-next
  "p" #'walkthrough-previous
  "N" #'walkthrough-next-step
  "P" #'walkthrough-previous-step)

(define-derived-mode walkthrough-mode magit-diff-mode "Walkthrough"
  "Mode for reading an agent's walkthrough of a branch.

The buffer is a Magit diff of the walkthrough's two commits, arranged in
the walkthrough's steps; diff commands work as in any other diff buffer.

\\{walkthrough-mode-map}"
  (add-to-invisibility-spec 'markdown-markup)
  ;; Explanations and findings are prose, often longer than the window is
  ;; wide; wrapping them is what makes them readable at all.
  (visual-line-mode 1)
  (add-hook 'post-command-hook #'walkthrough--update-header-line nil t))

(with-eval-after-load 'magit-mode
  (add-to-list 'magit-xref-modes 'walkthrough-mode))

(cl-defmethod magit-buffer-value (&context (major-mode walkthrough-mode))
  "Identify a walkthrough buffer by its file, not by its range."
  walkthrough--file)

(defun walkthrough--check-commits (data file)
  "Signal a `user-error' when the commits of DATA (read from FILE) are gone."
  (unless (and (magit-git-success "cat-file" "-e"
                                  (concat (alist-get 'base data) "^{commit}"))
               (magit-git-success "cat-file" "-e"
                                  (concat (alist-get 'head data) "^{commit}")))
    (user-error "The commits of walkthrough %s are gone; re-run /walkthrough on %s"
                (file-name-nondirectory file) (alist-get 'branch data))))

(defun walkthrough--diff-args (&optional args)
  "Return diff ARGS, or the default diff arguments, without --stat.
A diffstat per step would repeat itself; each step shows its own files."
  (seq-remove (lambda (arg) (member arg '("--stat" "--no-index")))
              (or args (car (magit-diff-arguments 'magit-diff-mode)))))

(defun walkthrough-open (file)
  "Show the walkthrough in FILE and return its buffer."
  (interactive (list (walkthrough--read-installed)))
  (let* ((data (walkthrough--read file))
         (repo (alist-get 'repo data))
         (default-directory (if (and repo (file-directory-p repo))
                                (file-name-as-directory repo)
                              default-directory)))
    (walkthrough--check-commits data file)
    (magit-setup-buffer #'walkthrough-mode t
      (walkthrough--file file)
      (magit-buffer-diff-range (format "%s..%s" (alist-get 'base data)
                                       (alist-get 'head data)))
      (magit-buffer-diff-typearg nil)
      (magit-buffer-diff-type 'committed)
      (magit-buffer-diff-args (walkthrough--diff-args))
      (magit-buffer-diff-files nil)
      (magit-buffer-diff-files-suspended nil))))

(defun walkthrough--branch-moved (data)
  "Return the branch tip of DATA when it is no longer DATA's head."
  (when-let* ((tip (magit-rev-parse "--verify" "--quiet"
                                    (concat "refs/heads/" (alist-get 'branch data)))))
    (unless (equal tip (alist-get 'head data))
      tip)))

(defun walkthrough--insert-intro (data)
  "Insert the walkthrough's title and notices about DATA."
  (magit-insert-section (walkthrough-intro)
    (magit-insert-heading (alist-get 'title data))
    (insert (format "Changes in %s..%s on %s, in %d steps.\n"
                    (magit-rev-abbrev (alist-get 'base data))
                    (magit-rev-abbrev (alist-get 'head data))
                    (alist-get 'branch data)
                    (length (alist-get 'steps data))))
    (when-let* ((tip (walkthrough--branch-moved data)))
      (insert (propertize
               (format "Branch %s has moved since this walkthrough (now at %s).\n"
                       (alist-get 'branch data) (magit-rev-abbrev tip))
               'font-lock-face 'warning)))
    (when (seq-every-p (lambda (step) (seq-empty-p (alist-get 'findings step)))
                       (alist-get 'steps data))
      (insert "No findings.\n"))
    (insert "\n")))

(defun walkthrough--diff-file (diff name)
  "Return the file plist called NAME in DIFF."
  (seq-find (lambda (f) (equal (plist-get f :file) name)) diff))

(defun walkthrough--drop-hunks (beg end ranged)
  "Drop the hunks between BEG and END that no range in RANGED overlaps.
RANGED maps file names to their ranges; other files are kept whole.  A
file left with no hunks is dropped entirely."
  (dolist (file (reverse (walkthrough--parse-diff-region beg end)))
    (when-let* ((ranges (cdr (assoc (plist-get file :file) ranged))))
      (let* ((hunks (plist-get file :hunks))
             (kept (seq-filter (lambda (hunk)
                                 (seq-some (lambda (range)
                                             (walkthrough--hunk-overlaps-p hunk range))
                                           ranges))
                               hunks)))
        (if (null kept)
            (delete-region (plist-get file :beg) (plist-get file :end))
          (dolist (hunk (reverse hunks))
            (unless (memq hunk kept)
              (delete-region (plist-get hunk :beg) (plist-get hunk :end)))))))))

(defun walkthrough--insert-step-diff (step diff args)
  "Insert and wash the diff of STEP's files.
DIFF is the parsed diff of the whole range and ARGS the diff arguments.
Files owned by line ranges keep only the hunks overlapping them; the
raw text is cut before Magit washes it, so its sections stay sound."
  (let* ((entries (delq nil (mapcar #'walkthrough--entry (alist-get 'files step))))
         (whole (mapcar #'car (seq-remove #'cdr entries)))
         (ranged (seq-remove (lambda (e) (member (car e) whole))
                             (seq-filter #'cdr entries)))
         ;; A renamed file is only seen as a rename with both of its names.
         (paths (delete-dups
                 (mapcan (lambda (entry)
                           (let ((file (walkthrough--diff-file diff (car entry))))
                             (delq nil (list (car entry) (plist-get file :old)))))
                         entries)))
         (git-args (list "diff" magit-buffer-diff-range "-p" "--no-prefix"
                         args "--" paths)))
    (if (null ranged)
        (magit-git-wash #'magit-diff-wash-diffs git-args)
      (let ((beg (point)))
        (magit-git-insert git-args)
        (walkthrough--drop-hunks beg (point) ranged)
        (if (= (point) beg)
            (magit-cancel-section)
          (unless (bolp)
            (insert "\n"))
          (let ((end (point-marker)))
            (set-marker-insertion-type end t)
            (save-restriction
              (narrow-to-region beg end)
              (goto-char beg)
              (magit-diff-wash-diffs (flatten-tree git-args)))
            (goto-char end)
            (set-marker end nil)))))))

(defun walkthrough--findings-noun (count)
  "Return \"COUNT findings\", or \"1 finding\" when COUNT is 1."
  (format "%d finding%s" count (if (= count 1) "" "s")))

(defun walkthrough--finding-count (findings)
  "Return \"K findings (J SEVERITY)\" for FINDINGS, or nil when there are none.
SEVERITY is the highest one present and J how many have it."
  (when-let* ((severity (seq-find (lambda (severity)
                                    (seq-some (lambda (f) (equal (alist-get 'severity f) severity))
                                              findings))
                                  '("high" "medium" "low"))))
    (format "%s (%d %s)"
            (walkthrough--findings-noun (length findings))
            (seq-count (lambda (f) (equal (alist-get 'severity f) severity)) findings)
            severity)))

(defun walkthrough--insert-step (step index count diff args)
  "Insert STEP, number INDEX of COUNT, with DIFF and diff ARGS."
  (magit-insert-section (walkthrough-step index)
    (magit-insert-heading
      (propertize (format "Step %d/%d  " (1+ index) count)
                  'font-lock-face 'magit-dimmed)
      (propertize (alist-get 'title step) 'font-lock-face 'magit-section-heading)
      (when-let* ((found (walkthrough--finding-count
                          (append (alist-get 'findings step) nil))))
        (propertize (concat "  " found) 'font-lock-face 'magit-dimmed)))
    (insert (walkthrough--render-markdown (alist-get 'explanation step)) "\n")
    (let* ((shown (walkthrough--shown-hunks step diff))
           (findings (append (alist-get 'findings step) nil))
           (placed (seq-filter (lambda (f) (walkthrough--placed-p f shown)) findings)))
      ;; Findings without a line to sit under come first, in their order.
      (dolist (finding findings)
        (unless (memq finding placed)
          (walkthrough--insert-finding
           finding
           (pcase (walkthrough--anchor-line finding)
             (`(,file ,line ,_) (format "not placed: %s:%d" file line))))))
      (when (seq-difference findings placed)
        (insert "\n"))
      ;; Its own section, because an empty diff cancels the section it is
      ;; inserted into and would take the step's heading with it.
      (let ((diff-section (magit-insert-section (walkthrough-diff index)
                            (walkthrough--insert-step-diff step diff args))))
        (when (and placed diff-section)
          (walkthrough--draw-anchored placed diff-section))))
    (insert "\n")))

(defun walkthrough-refresh-buffer ()
  "Refresh the current walkthrough buffer from its file."
  (let ((data (walkthrough--read walkthrough--file)))
    (walkthrough--check-commits data walkthrough--file)
    (setq walkthrough--data data)
    (setq magit-buffer-diff-range-oids (magit-hash-range magit-buffer-diff-range))
    (remove-overlays (point-min) (point-max) 'walkthrough t)
    (let* ((args (walkthrough--diff-args magit-buffer-diff-args))
           (steps (alist-get 'steps data))
           (diff (walkthrough--parse-diff (alist-get 'base data)
                                          (alist-get 'head data) args)))
      (magit-insert-section (diffbuf)
        (walkthrough--insert-intro data)
        (seq-do-indexed (lambda (step index)
                          (walkthrough--insert-step step index (length steps)
                                                    diff args))
                        steps))))
  ;; The refresh may have reset the header line, so set it again.
  (setq walkthrough--header-line nil)
  (walkthrough--update-header-line))

(defun walkthrough--step-at-point ()
  "Return the index of the step whose section contains point, or nil."
  (let ((section (magit-current-section)))
    (while (and section (not (magit-section-match 'walkthrough-step section)))
      (setq section (oref section parent)))
    (and section (oref section value))))

(defun walkthrough--update-header-line ()
  "Name the walkthrough, and the step point is in, in the header line."
  (let* ((title (format "Walkthrough: %s" (alist-get 'title walkthrough--data)))
         (steps (alist-get 'steps walkthrough--data))
         (index (walkthrough--step-at-point))
         (line (if-let* ((step (and index (elt steps index))))
                   (format "%s — Step %d/%d: %s · %s"
                           title (1+ index) (length steps) (alist-get 'title step)
                           (walkthrough--findings-noun
                            (length (alist-get 'findings step))))
                 title)))
    ;; After every command, so only touch it when it changes.
    (unless (equal line walkthrough--header-line)
      (setq walkthrough--header-line line)
      (magit-set-header-line-format line))))

;;; Moving around

(defun walkthrough--starts (type)
  "Return the start positions of the sections of TYPE, in order."
  (let (starts)
    (magit-map-sections (lambda (section)
                          (when (magit-section-match type section)
                            (push (oref section start) starts))))
    (sort starts #'<)))

(defun walkthrough--goto-top (pos)
  "Move to POS and, when the buffer is shown, put its line at the window top."
  (goto-char pos)
  (when (eq (window-buffer) (current-buffer))
    (set-window-start nil (line-beginning-position))))

(defun walkthrough--next-of (starts what)
  "Move to the first of STARTS after point, or say there is no next WHAT."
  (walkthrough--goto-top (or (seq-find (lambda (pos) (> pos (point))) starts)
                             (user-error "No next %s" what))))

(defun walkthrough--previous-of (starts what)
  "Move to the last of STARTS before point, or say there is no previous WHAT."
  (walkthrough--goto-top (or (car (last (seq-filter (lambda (pos) (< pos (point)))
                                                    starts)))
                             (user-error "No previous %s" what))))

(defun walkthrough-next-step ()
  "Move to the heading of the next step."
  (interactive)
  (walkthrough--next-of (walkthrough--starts 'walkthrough-step) "step"))

(defun walkthrough-previous-step ()
  "Move to the heading of the previous step."
  (interactive)
  (walkthrough--previous-of (walkthrough--starts 'walkthrough-step) "step"))

(defun walkthrough--findings-at-point ()
  "Return the ids of the findings at point, or nil."
  (get-char-property (point) 'walkthrough-finding))

(defun walkthrough--stops ()
  "Return the positions of step headings and findings, in order."
  (sort (delete-dups
         (append (walkthrough--starts '(walkthrough-step walkthrough-finding))
                 (mapcar #'overlay-start
                         (seq-filter (lambda (ov) (overlay-get ov 'walkthrough-finding))
                                     (overlays-in (point-min) (point-max))))))
        #'<))

(defun walkthrough-next ()
  "Move to the next step heading or finding."
  (interactive)
  (walkthrough--next-of (walkthrough--stops) "step or finding"))

(defun walkthrough-previous ()
  "Move to the previous step heading or finding."
  (interactive)
  (walkthrough--previous-of (walkthrough--stops) "step or finding"))

;;; Marking findings

(defun walkthrough--finding-by-id (data id)
  "Return the finding ID in walkthrough DATA."
  (seq-some (lambda (step)
              (seq-find (lambda (f) (equal (alist-get 'id f) id))
                        (alist-get 'findings step)))
            (alist-get 'steps data)))

(defun walkthrough-finding-at-point-p ()
  "Return non-nil when point is on a finding."
  (and (walkthrough--findings-at-point) t))

(defun walkthrough--finding-for-command ()
  "Return the id of the finding a mark command acts on.
With several findings on the line, ask which."
  (let ((ids (or (walkthrough--findings-at-point)
                 (user-error "No finding at point"))))
    (if (null (cdr ids))
        (car ids)
      (let ((choices (mapcar (lambda (id)
                               (cons (alist-get 'title (walkthrough--finding-by-id
                                                        walkthrough--data id))
                                     id))
                             ids)))
        (cdr (assoc (completing-read "Finding: " choices nil t) choices))))))

(defun walkthrough--refresh-file-buffers (file)
  "Refresh every walkthrough buffer that shows FILE."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and (derived-mode-p 'walkthrough-mode)
                 (equal walkthrough--file file))
        (magit-refresh-buffer)))))

(defun walkthrough--mark (state allowed)
  "Set the finding at point to STATE when its state is in ALLOWED.
A sent finding cannot be marked again."
  (let* ((id (walkthrough--finding-for-command))
         ;; The file, not the buffer, is the truth: it may have changed.
         (current (alist-get 'state (walkthrough--finding-by-id
                                     (walkthrough--read walkthrough--file) id))))
    (cond ((equal current "sent")
           (user-error "That finding was already handed off"))
          ((not (member current allowed))
           (user-error "Cannot mark a %s finding %s" current (or state "unmarked"))))
    (walkthrough--set-state walkthrough--file id state)
    (walkthrough--refresh-file-buffers walkthrough--file)))

(defun walkthrough-accept ()
  "Accept the finding at point: the next review hand-off sends it."
  (interactive)
  (walkthrough--mark "accepted" '(nil "accepted" "dismissed")))

(defun walkthrough-dismiss ()
  "Dismiss the finding at point: it is never handed off."
  (interactive)
  (walkthrough--mark "dismissed" '(nil "accepted" "dismissed")))

(defun walkthrough-unmark ()
  "Remove the mark from the finding at point."
  (interactive)
  (walkthrough--mark nil '(nil "accepted" "dismissed")))

(defun walkthrough-reply (id text)
  "Reply TEXT to finding ID, by default the finding at point.
The reply is kept with the finding and accepts it, even a dismissed or
sent one; a sent one is then handed off again as a follow-up.  Empty
TEXT deletes the reply and leaves the mark as it is."
  (interactive
   (let ((id (walkthrough--finding-for-command)))
     (list id (read-string "Reply: "
                           (alist-get 'reply (walkthrough--finding-by-id
                                              (walkthrough--read walkthrough--file)
                                              id))))))
  (let ((text (string-trim text)))
    ;; Re-read, like the marks, so other changes to the file are kept.
    (walkthrough--write
     (walkthrough--map-findings
      (walkthrough--read walkthrough--file)
      (lambda (finding)
        (cond ((not (equal (alist-get 'id finding) id)) finding)
              ((string-empty-p text) (walkthrough--put finding 'reply nil))
              (t (walkthrough--put
                  (walkthrough--put
                   (walkthrough--put finding 'reply text)
                   'follow_up (or (alist-get 'follow_up finding)
                                  (equal (alist-get 'state finding) "sent")))
                  'state "accepted")))))
     walkthrough--file))
  (walkthrough--refresh-file-buffers walkthrough--file))

(keymap-set walkthrough-finding-map "a" #'walkthrough-accept)
(keymap-set walkthrough-finding-map "x" #'walkthrough-dismiss)
(keymap-set walkthrough-finding-map "u" #'walkthrough-unmark)

;;; Patch excerpts

(defcustom walkthrough-excerpt-context 3
  "Lines of context `walkthrough-patch-excerpt' keeps around a range."
  :type 'natnum)

(defcustom walkthrough-excerpt-max-lines 40
  "About how many lines of a hunk `walkthrough-patch-excerpt' keeps.
Only a whole hunk is capped; an excerpt of a range is not."
  :type 'natnum)

(defun walkthrough--hunk-rows (hunk)
  "Split HUNK, a hunk's text, into its header's tail and its rows.
Return (TAIL . ROWS): TAIL is what follows the second @@ of the header,
and each row is (LINE OLD NEW), where OLD and NEW are the numbers of the
next line on each side at that row, which is the row's own line on the
sides it belongs to.  Return nil when HUNK is not a two-sided hunk,
such as a combined diff's."
  (let* ((lines (split-string hunk "\n"))
         (header (car lines)))
    (when (string-match
           "\\`@@ -\\([0-9]+\\)\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,[0-9]+\\)? @@"
           header)
      (let ((tail (substring header (match-end 0)))
            ;; A side with no lines names the line before the hunk.
            (old (string-to-number (match-string 1 header)))
            (new (string-to-number (match-string 2 header)))
            (body (cdr lines))
            rows)
        (when (string-match-p "\\`@@ -[0-9]+,0 " header) (cl-incf old))
        (when (string-match-p " \\+[0-9]+,0 @@" header) (cl-incf new))
        (when (equal (car (last body)) "")
          (setq body (butlast body)))
        (dolist (line body)
          (push (list line old new) rows)
          (pcase (and (> (length line) 0) (aref line 0))
            (?\s (cl-incf old) (cl-incf new))
            (?- (cl-incf old))
            (?+ (cl-incf new))))
        (cons tail (nreverse rows))))))

(defun walkthrough--row-line (row)
  "Return the diff line of ROW (see `walkthrough--hunk-rows')."
  (car row))

(defun walkthrough--row-number (row side)
  "Return the number of ROW's next line on SIDE, \"old\" or \"new\"."
  (if (equal side "old") (nth 1 row) (nth 2 row)))

(defun walkthrough--row-on-side-p (row side)
  "Return non-nil when ROW (see `walkthrough--hunk-rows') is a line of SIDE."
  (let ((line (walkthrough--row-line row)))
    (memq (and (> (length line) 0) (aref line 0))
          (if (equal side "old") '(?\s ?-) '(?\s ?+)))))

(defun walkthrough--indices (pred seq)
  "Return the indices of the elements of SEQ that satisfy PRED, in order."
  (delq nil (seq-map-indexed (lambda (elt i) (and (funcall pred elt) i)) seq)))

(defun walkthrough--excerpt (tail rows kept &optional mark-cuts)
  "Return the ROWS whose index is in KEPT as a hunk with header TAIL.
The header spans the first to the last kept row.  With MARK-CUTS, a line
\"…\" stands for each run of rows left out."
  (let* ((first (seq-min kept))
         (span (seq-subseq rows first (1+ (seq-max kept)))))
    (cl-flet ((side-range (side)
                (let ((start (walkthrough--row-number (car span) side))
                      (count (seq-count (lambda (row) (walkthrough--row-on-side-p row side))
                                        span)))
                  (format "%d,%d" (if (zerop count) (1- start) start) count))))
      (concat
       (format "@@ -%s +%s @@%s\n" (side-range "old") (side-range "new") tail)
       (mapconcat
        #'identity
        (delq nil (seq-map-indexed
                   (lambda (row i)
                     (cond ((memq i kept) (concat (walkthrough--row-line row) "\n"))
                           ((and mark-cuts (or (zerop i) (memq (1- i) kept))) "…\n")))
                   rows))
        "")))))

(defun walkthrough-patch-excerpt (hunk &optional range side)
  "Return an excerpt of HUNK, a hunk's text: its @@ header and its lines.
RANGE is a (START . END) range of lines on SIDE, \"old\" or \"new\" (the
default).  The excerpt is the lines of RANGE with
`walkthrough-excerpt-context' lines of context around them, under a
header recomputed for them.  Without RANGE, or when no line of the hunk
is in it, the whole hunk is returned, cut to about
`walkthrough-excerpt-max-lines' lines kept around its changed lines,
with \"…\" where lines were left out; its header then spans the first to
the last line kept.  A hunk that is not two-sided is returned as it is."
  (pcase-let* ((parsed (walkthrough--hunk-rows hunk))
               (`(,tail . ,rows) parsed)
               (in-range (and range
                              (walkthrough--indices
                               (lambda (row)
                                 (and (walkthrough--row-on-side-p row side)
                                      (<= (car range)
                                          (walkthrough--row-number row side)
                                          (cdr range))))
                               rows))))
    (cond
     ((null parsed) hunk)
     (in-range
      (walkthrough--excerpt
       tail rows
       (number-sequence (max 0 (- (seq-min in-range) walkthrough-excerpt-context))
                        (min (1- (length rows))
                             (+ (seq-max in-range) walkthrough-excerpt-context)))))
     ((<= (length rows) walkthrough-excerpt-max-lines) hunk)
     (t
      ;; Keep the rows within the widest distance of a change that fits;
      ;; when even the changes alone do not, the first of them.
      (let* ((changes (walkthrough--indices
                       (lambda (row) (string-match-p "\\`[-+]" (walkthrough--row-line row)))
                       rows))
             (distance (seq-map-indexed
                        (lambda (_ i)
                          (if changes
                              (seq-min (mapcar (lambda (c) (abs (- c i))) changes))
                            i))
                        rows))
             (reach 0))
        (cl-flet ((rows-within (reach)
                    (walkthrough--indices (lambda (d) (<= d reach)) distance)))
          (while (<= (length (rows-within (1+ reach))) walkthrough-excerpt-max-lines)
            (cl-incf reach))
          (walkthrough--excerpt
           tail rows (seq-take (rows-within reach) walkthrough-excerpt-max-lines) t)))))))

;;; Handing findings off

(defun walkthrough--range-label (base head)
  "Return the label of the committed range BASE..HEAD.
Review comments use the same label, so a comment and a finding on the
same commits name the same diff."
  (format "diff of %s..%s" base head))

(defun walkthrough-diff-label ()
  "Return the label of the current buffer's committed range, or nil.
The range is named by its commit ids, not by how it was spelled, so a
walkthrough and `magit-diff' of `main..topic' agree when they show the
same commits."
  (when-let* ((range (or magit-buffer-diff-range-oids
                         (and magit-buffer-diff-range
                              (ignore-errors (magit-hash-range magit-buffer-diff-range))))))
    (when (string-match "\\`\\([^.]+\\)\\.\\.\\([^.]+\\)\\'" range)
      (walkthrough--range-label (match-string 1 range) (match-string 2 range)))))

(defun walkthrough--hand-off-item (data file finding diff)
  "Return FINDING of DATA (installed in FILE) as a hand-off item.
DIFF is the parsed diff of DATA's range, from whose anchored hunk the
patch excerpt is cut."
  (pcase-let* ((`(,name ,line ,side) (walkthrough--anchor-line finding))
               (anchor (alist-get 'anchor finding))
               (range (and anchor (cons (alist-get 'line anchor)
                                        (or (alist-get 'end_line anchor)
                                            (alist-get 'line anchor)))))
               (hunk (and name
                          (seq-find (lambda (h) (walkthrough--line-in-hunk-p h line side))
                                    (plist-get (walkthrough--diff-file diff name) :hunks)))))
    (list :repo (alist-get 'repo data)
          :kind 'finding
          :id (alist-get 'id finding)
          :walkthrough file
          :file name
          :new (and range (not (equal side "old")) range)
          :old (and range (equal side "old") range)
          :where (walkthrough--range-label (alist-get 'base data) (alist-get 'head data))
          :patch (and hunk (walkthrough-patch-excerpt (plist-get hunk :text) range side))
          :severity (alist-get 'severity finding)
          :title (alist-get 'title finding)
          :text (concat (string-trim-right (alist-get 'body finding))
                        (when-let* ((failure (alist-get 'failure_scenario finding)))
                          (concat "\n\nFailure scenario: " failure)))
          :reply (alist-get 'reply finding)
          :follow-up (and (alist-get 'follow_up finding) t)
          :sent (equal (alist-get 'state finding) "sent"))))

(defun walkthrough-accepted-findings (repo &optional include-sent)
  "Return the accepted findings of REPO's walkthroughs as hand-off items.
Each is a plist shaped like a review comment (:repo :file :new :old
:where :patch :text :sent) plus :kind `finding', :id, :severity, :title,
:reply, :follow-up (handed off before, accepted again by a reply) and
:walkthrough, the file it came from.  :patch is the anchored lines'
excerpt (`walkthrough-patch-excerpt').  Sent findings are included
only when INCLUDE-SENT.  Oldest walkthrough first."
  (let ((default-directory (file-name-as-directory repo)))
    (mapcan
     (lambda (file)
       (let* ((data (walkthrough--read file))
              (wanted (seq-filter
                       (lambda (finding)
                         (member (alist-get 'state finding)
                                 (if include-sent '("accepted" "sent") '("accepted"))))
                       (seq-mapcat (lambda (step) (append (alist-get 'findings step) nil))
                                   (alist-get 'steps data))))
              (diff (and wanted
                         (ignore-errors
                           (walkthrough--parse-diff (alist-get 'base data)
                                                    (alist-get 'head data) '("-U3"))))))
         (mapcar (lambda (finding)
                   (walkthrough--hand-off-item data file finding diff))
                 wanted)))
     (sort (walkthrough--installed)
           (lambda (a b) (time-less-p (file-attribute-modification-time (file-attributes a))
                                      (file-attribute-modification-time (file-attributes b))))))))

(defun walkthrough-mark-sent (items)
  "Mark the findings of hand-off ITEMS sent, in their files.
That ends a follow-up.  Items that are not findings are ignored.  Open
walkthrough buffers are refreshed."
  (let ((by-file (seq-group-by (lambda (item) (plist-get item :walkthrough))
                               (seq-filter (lambda (item) (eq (plist-get item :kind) 'finding))
                                           items))))
    (pcase-dolist (`(,file . ,file-items) by-file)
      (let ((ids (mapcar (lambda (item) (plist-get item :id)) file-items)))
        (walkthrough--write
         (walkthrough--map-findings
          (walkthrough--read file)
          (lambda (finding)
            (if (member (alist-get 'id finding) ids)
                (walkthrough--put (walkthrough--put finding 'state "sent")
                                  'follow_up nil)
              finding)))
         file))
      (walkthrough--refresh-file-buffers file))))

;;; Finding walkthroughs

(defun walkthrough--installed ()
  "Return the installed walkthrough files of the current repository."
  (let ((dir (walkthrough-directory)))
    (and (file-directory-p dir)
         (seq-filter (lambda (file)
                       (equal (alist-get 'repo (ignore-errors (walkthrough--read file)))
                              (magit-toplevel)))
                     (directory-files dir t "\\`[^.].*\\.json\\'")))))

(defun walkthrough--read-installed ()
  "Read one of the repository's walkthroughs, by branch."
  (let ((files (mapcar (lambda (file)
                         (cons (string-replace
                                "%2F" "/" (file-name-base file))
                               file))
                       (or (walkthrough--installed)
                           (user-error "No walkthroughs in this repository")))))
    (cdr (assoc (completing-read "Walkthrough of branch: " files nil t) files))))

(defun walkthrough-request (&optional base)
  "Ask the coding agent for a walkthrough of the current branch.
With a prefix argument, read the BASE to compare against; otherwise the
agent uses the merge-base with the default branch."
  (interactive (list (and current-prefix-arg
                          (magit-read-branch-or-commit "Walkthrough since"))))
  (unless walkthrough-request-function
    (user-error "No agent is configured; set `walkthrough-request-function'"))
  (funcall walkthrough-request-function
           (if base (concat "/walkthrough " base) "/walkthrough")
           t))

(defun walkthrough-open-current (&optional pick)
  "Open the walkthrough of the current branch and return its buffer.
With prefix argument PICK, choose among the repository's walkthroughs.
Without a walkthrough for the branch, offer to ask the agent for one."
  (interactive "P")
  (if pick
      (walkthrough-open (walkthrough--read-installed))
    (let* ((branch (or (magit-get-current-branch)
                       (user-error "No branch is checked out")))
           (file (walkthrough--file-for-branch branch)))
      (cond ((file-exists-p file) (walkthrough-open file))
            ((y-or-n-p (format "No walkthrough of %s yet.  Ask the agent for one? "
                               branch))
             (walkthrough-request)
             nil)))))

(provide 'walkthrough)
;;; walkthrough.el ends here
