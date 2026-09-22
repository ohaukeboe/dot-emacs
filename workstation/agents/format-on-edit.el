;;; format-on-edit.el --- Claude Code PostToolUse helper -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by the `claude-format-on-edit' shell hook for each edited file.  It
;; formats the file through its language server and writes the diagnostics the
;; agent should see to a report file.
;;
;; Nothing here may wait for a human: the hook runs inside `emacsclient
;; --eval', so a prompt would stall the agent until its timeout.

;;; Code:

(require 'cl-lib)
(require 'seq)

(defconst claude-format-on-edit--max-lines 20
  "Number of diagnostics reported back to the agent.")

(defun claude-format-on-edit--wait (pred seconds)
  "Block while PRED returns non-nil, for at most SECONDS."
  (let ((deadline (+ (float-time) seconds)))
    (while (and (ignore-errors (funcall pred))
                (< (float-time) deadline))
      (sit-for 0.05))))

(defun claude-format-on-edit--start-lsp ()
  "Attach a language server to the current buffer if one is available."
  (unless (bound-and-true-p lsp-mode)
    (let ((lsp-auto-guess-root t)
          (lsp-restart 'ignore)
          (lsp-enable-file-watchers nil))
      ;; No client for this major mode simply signals; the diagnostics pass
      ;; below still runs.
      (ignore-errors (lsp))))
  ;; A workspace that is up but still negotiating reports no capabilities yet.
  ;; A cold server has no workspace attached at all and is not worth waiting
  ;; for: it will be warm by the next edit.
  (claude-format-on-edit--wait
   (lambda ()
     (and (bound-and-true-p lsp-mode)
          (lsp-workspaces)
          (not (lsp-feature? "textDocument/formatting"))))
   3.0))

(defun claude-format-on-edit--format ()
  "Format the current buffer through its language server, if it can."
  (when (and (bound-and-true-p lsp-mode)
             (fboundp 'lsp-feature?)
             (ignore-errors (lsp-feature? "textDocument/formatting")))
    ;; A formatter refuses to touch a syntactically broken file and
    ;; `lsp-format-buffer' signals.  That is exactly when the diagnostics
    ;; matter, so it must not abort the rest.
    (ignore-errors
      (lsp-format-buffer)
      (save-buffer))))

(defun claude-format-on-edit--enable-checker ()
  "Turn on a diagnostics UI in a buffer this hook opened itself.
Buffers the user already had open keep whatever they were using."
  (unless (or (bound-and-true-p flycheck-mode)
              (bound-and-true-p flymake-mode))
    (cond ((and (fboundp 'flycheck-mode)
                (ignore-errors (flycheck-may-enable-mode)))
           (ignore-errors (flycheck-mode 1)))
          ((and (fboundp 'flymake-mode)
                (or (bound-and-true-p lsp-mode)
                    flymake-diagnostic-functions))
           (ignore-errors (flymake-mode 1))))))

(defun claude-format-on-edit--flycheck ()
  "Diagnostics from Flycheck as (LINE LEVEL MESSAGE) records."
  (when (bound-and-true-p flycheck-mode)
    (ignore-errors (flycheck-buffer))
    (claude-format-on-edit--wait
     (lambda () (memq flycheck-last-status-change '(running not-checked)))
     4.0)
    (delq nil
          (mapcar (lambda (e)
                    (let ((level (flycheck-error-level e)))
                      (when (memq level '(error warning))
                        (list (or (flycheck-error-line e) 0)
                              level
                              (flycheck-error-message e)))))
                  flycheck-current-errors))))

(defun claude-format-on-edit--flymake ()
  "Diagnostics from Flymake as (LINE LEVEL MESSAGE) records."
  (when (bound-and-true-p flymake-mode)
    (ignore-errors (flymake-start))
    (claude-format-on-edit--wait (lambda () (flymake-running-backends)) 4.0)
    (delq nil
          (mapcar
           (lambda (d)
             (let* ((type (flymake-diagnostic-type d))
                    (level (cond ((memq type '(:error error)) 'error)
                                 ((memq type '(:warning warning)) 'warning))))
               (when level
                 (list (line-number-at-pos (flymake-diagnostic-beg d) t)
                       level
                       (flymake-diagnostic-text d)))))
           (ignore-errors (flymake-diagnostics))))))

(defun claude-format-on-edit--lsp (file)
  "Diagnostics lsp-mode holds for FILE as (LINE LEVEL MESSAGE) records.
Read straight from the workspace, so a buffer with no checker UI still
reports."
  (when (and (bound-and-true-p lsp-mode)
             (fboundp 'lsp-diagnostics))
    (let ((table (ignore-errors (lsp-diagnostics t)))
          (diagnostics nil))
      (when table
        ;; Key spelling differs between clients, so match on the file itself.
        (maphash (lambda (path diags)
                   (when (ignore-errors (file-equal-p path file))
                     (setq diagnostics diags)))
                 table)
        ;; Diagnostics are pushed after the edit, so an empty table right
        ;; after a format may only mean they have not arrived yet. The wait is
        ;; short because a clean file pays it in full on every edit.
        (when (null diagnostics)
          (claude-format-on-edit--wait
           (lambda ()
             (let ((again (ignore-errors (lsp-diagnostics t))))
               (maphash (lambda (path diags)
                          (when (ignore-errors (file-equal-p path file))
                            (setq diagnostics diags)))
                        (or again (make-hash-table)))
               (null diagnostics)))
           0.75)))
      (delq nil
            (mapcar
             (lambda (d)
               (let* ((severity (or (ignore-errors (lsp:diagnostic-severity? d))
                                    (plist-get d :severity)))
                      (level (cond ((eq severity 1) 'error)
                                   ((eq severity 2) 'warning)))
                      (line (or (ignore-errors
                                  (lsp:position-line
                                   (lsp:range-start (lsp:diagnostic-range d))))
                                0)))
                 (when level
                   (list (1+ line)
                         level
                         (or (ignore-errors (lsp:diagnostic-message d))
                             (plist-get d :message))))))
             diagnostics)))))

(defun claude-format-on-edit--collect (file)
  "All diagnostics for FILE, deduplicated and ordered by line.
Flycheck commonly republishes what lsp-mode already reported, so the same
finding arrives twice."
  (let ((seen (make-hash-table :test #'equal))
        (out nil))
    (dolist (record (append (claude-format-on-edit--flycheck)
                            (claude-format-on-edit--flymake)
                            (claude-format-on-edit--lsp file)))
      (pcase-let ((`(,line ,level ,message) record))
        (let ((key (list line (string-trim (or message "")))))
          (when (and message (not (gethash key seen)))
            (puthash key t seen)
            (push (list line level (string-trim message)) out)))))
    (sort (nreverse out)
          (lambda (a b) (< (car a) (car b))))))

(defun claude-format-on-edit--report (file report)
  "Write diagnostics for FILE to REPORT, one per line."
  (let ((records (claude-format-on-edit--collect file)))
    (when records
      (with-temp-file report
        (insert
         (mapconcat
          (lambda (r)
            (format "%s:%s: %s: %s"
                    (file-name-nondirectory file)
                    (nth 0 r) (nth 1 r) (nth 2 r)))
          (seq-take records claude-format-on-edit--max-lines)
          "\n"))))))

(defun claude-format-on-edit--cleanup (buffer)
  "Kill BUFFER and any language server left without one."
  (when (buffer-live-p buffer)
    (kill-buffer buffer))
  ;; Covers servers this hook started, including ones still initializing,
  ;; which are not attached to a buffer yet.
  (ignore-errors
    (dolist (w (lsp--session-workspaces (lsp-session)))
      (when (null (seq-filter #'buffer-live-p (lsp--workspace-buffers w)))
        (lsp-workspace-shutdown w)))))

;;;###autoload
(defun claude-format-on-edit (file report)
  "Format FILE and write its diagnostics to REPORT.
Leaves Emacs as it was found: a buffer opened here is killed again, and a
buffer the user already had open keeps its modes."
  (let* ((existing (get-file-buffer file))
         ;; NOWARN: a file that changed on disk must not raise a prompt.
         (buffer (or existing (ignore-errors (find-file-noselect file t)))))
    (when (and buffer (not (buffer-modified-p buffer)))
      (unwind-protect
          (with-current-buffer buffer
            ;; Nothing below may wait for a human.  Anything that asks gets a
            ;; "no" and carries on.
            (cl-letf (((symbol-function 'y-or-n-p) #'ignore)
                      ((symbol-function 'yes-or-no-p) #'ignore))
              (when existing
                (revert-buffer :ignore-auto :noconfirm :preserve-modes))
              (claude-format-on-edit--start-lsp)
              (claude-format-on-edit--format)
              (unless existing
                (claude-format-on-edit--enable-checker))
              (claude-format-on-edit--report file report)))
        (unless existing
          (claude-format-on-edit--cleanup buffer))))))

(provide 'format-on-edit)
;;; format-on-edit.el ends here
