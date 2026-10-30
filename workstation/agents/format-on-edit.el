;;; format-on-edit.el --- Claude Code PostToolUse helper -*- lexical-binding: t; -*-

;;; Commentary:

;; Loaded by the `claude-format-on-edit' shell hook for each edited file.  It
;; formats the file through its language server and writes what the agent
;; should see (diagnostics, and a reminder for manifests) to a report file.
;;
;; Emacs must never block here.  `emacsclient --eval' only queues a job and
;; returns; the job then runs from timers and server callbacks while the user
;; keeps typing.  When it is done it writes the report and then a separate
;; done marker, which the shell side polls for.  See
;; docs/adr/0009-async-format-on-edit.md.
;;
;; Nothing here may wait for a human either: a prompt would stall the agent
;; until the hook's timeout.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst claude-format-on-edit--max-lines 20
  "Number of diagnostics reported back to the agent.")

(defvar claude-format-on-edit-server-budget 10.0
  "Seconds a job waits for a server to offer formatting.
Counted from when the job was queued.  A cold server usually makes it, so the
first edit in a project is formatted too.  Past it the job skips formatting,
reports the diagnostics it has, and leaves the server starting.")

(defvar claude-format-on-edit-request-timeout 5.0
  "Seconds a job waits for the answer to its formatting request.")

(defvar claude-format-on-edit-checker-timeout 4.0
  "Seconds a job waits for Flycheck or Flymake to finish a run.")

(defvar claude-format-on-edit-lsp-diagnostics-timeout 0.75
  "Seconds a job waits for lsp-mode to publish diagnostics.
Short because a clean file pays it in full on every edit.")

(defvar claude-format-on-edit-job-deadline 22.0
  "Seconds after which a job reports whatever it has and finishes.
Below the shell side's own deadline, so the agent gets the report rather
than nothing.")

(defconst claude-format-on-edit--manifest-regexp
  (rx bos
      (or "package.json" "deno.json" "deno.jsonc" "jsconfig.json"
          (seq "tsconfig" (* nonl) ".json")
          "Cargo.toml" "go.mod" "go.work"
          "pyproject.toml" "setup.py" "setup.cfg" "Pipfile"
          (seq "requirements" (* nonl) ".txt")
          "Gemfile" (seq (+ nonl) ".gemspec")
          "composer.json" "pom.xml"
          (seq (or "build" "settings") ".gradle" (? ".kts"))
          (seq (+ nonl) "." (or "csproj" "fsproj" "vbproj" "sln"))
          "Directory.Build.props" "Directory.Packages.props"
          "flake.nix" "CMakeLists.txt" "meson.build"
          "mix.exs" "deps.edn" "project.clj" (seq (+ nonl) ".cabal")
          "stack.yaml" "dune-project" "Package.swift")
      eos)
  "File names of dependency and project manifests.
Editing one usually means the language server needs a restart once the
dependencies are installed.")

;;; Jobs

(cl-defstruct (claude-format-on-edit--job
               (:constructor claude-format-on-edit--job-create)
               (:copier nil))
  file report done id mtime queued
  buffer opened client finished timer watchdog)

(defvar claude-format-on-edit--latest (make-hash-table :test #'equal)
  "Newest job ID per file.  An older job never saves formatting.")

(defvar claude-format-on-edit--counter 0
  "Source of job IDs.")

(defvar claude-format-on-edit--active nil
  "Jobs in flight.  A buffer the hook opened outlives every job using it.")

(defvar claude-format-on-edit--owned nil
  "Buffers the hook opened itself, as opposed to the user's own.")

(defmacro claude-format-on-edit--quietly (&rest body)
  "Run BODY so that anything asking a question gets a \"no\"."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'y-or-n-p) #'ignore)
             ((symbol-function 'yes-or-no-p) #'ignore))
     ,@body))

(defun claude-format-on-edit--mtime (file)
  "Modification time of FILE, or nil if it is gone."
  (file-attribute-modification-time (file-attributes file)))

(defun claude-format-on-edit--step (job fn &rest args)
  "Call FN with ARGS in JOB's buffer, unless JOB is already finished.
An error anywhere finishes the job, so the done marker is always written."
  (unless (claude-format-on-edit--job-finished job)
    (condition-case err
        (let ((buffer (claude-format-on-edit--job-buffer job)))
          (if (buffer-live-p buffer)
              (with-current-buffer buffer
                (claude-format-on-edit--quietly (apply fn args)))
            (claude-format-on-edit--finish job)))
      (error
       (message "claude-format-on-edit: %s" (error-message-string err))
       (claude-format-on-edit--finish job)))))

(defun claude-format-on-edit--poll (job pred seconds then)
  "Call THEN in JOB's buffer once PRED returns nil, or after SECONDS.
PRED is tried from a timer, so Emacs keeps running while it holds."
  (let ((deadline (+ (float-time) seconds)))
    (cl-labels
        ((tick ()
           (claude-format-on-edit--step
            job
            (lambda ()
              (if (and (ignore-errors (funcall pred))
                       (< (float-time) deadline))
                  (setf (claude-format-on-edit--job-timer job)
                        (run-at-time 0.05 nil #'tick))
                (funcall then))))))
      (tick))))

;;; Language-server adapters
;;
;; The only places that talk to lsp-mode or eglot.  Everything here returns at
;; once; answers arrive through callbacks.

(defun claude-format-on-edit--attached-client ()
  "The client with a server attached to the current buffer, or nil."
  (cond ((bound-and-true-p lsp-mode) 'lsp-mode)
        ((and (fboundp 'eglot-managed-p) (eglot-managed-p)) 'eglot)))

(defun claude-format-on-edit--start-server (client)
  "Start CLIENT's server for the current buffer without waiting for it.
`lsp-deferred' never fires in a buffer nobody displays, hence the explicit
start."
  (pcase client
    ('lsp-mode
     (let ((lsp-auto-guess-root t)
           (lsp-restart 'ignore)
           (lsp-enable-file-watchers nil))
       ;; No client for this major mode simply signals; the diagnostics pass
       ;; still runs.
       (ignore-errors (lsp))))
    ('eglot
     (when (and (fboundp 'eglot--guess-contact) (fboundp 'eglot--connect))
       ;; The default is to block for a few seconds on the connection.
       (let ((eglot-sync-connect nil))
         (ignore-errors (apply #'eglot--connect (eglot--guess-contact))))))))

(defun claude-format-on-edit--format-ready-p (client)
  "Non-nil when CLIENT's server can format the current buffer now."
  (pcase client
    ('lsp-mode
     (and (bound-and-true-p lsp-mode)
          (lsp-workspaces)
          (lsp-feature? "textDocument/formatting")))
    ('eglot
     (and (fboundp 'eglot-managed-p)
          (eglot-managed-p)
          (eglot-server-capable :documentFormattingProvider)))))

(defun claude-format-on-edit--request-format (client on-result)
  "Ask CLIENT's server to format the current buffer.
Returns at once.  ON-RESULT is later called with a function that applies the
edits to the current buffer, or with nil when the server reported an error."
  (pcase client
    ('lsp-mode
     (lsp-request-async
      "textDocument/formatting"
      (lsp--make-document-formatting-params)
      (lambda (edits)
        (funcall on-result
                 (lambda () (when edits (lsp--apply-text-edits edits 'format)))))
      :error-handler (lambda (&rest _) (funcall on-result nil))
      :mode 'alive))
    ('eglot
     (jsonrpc-async-request
      (eglot--current-server-or-lose)
      :textDocument/formatting
      (list :textDocument (eglot--TextDocumentIdentifier)
            :options (list :tabSize tab-width
                           :insertSpaces (if indent-tabs-mode :json-false t)))
      :success-fn
      (lambda (edits)
        (funcall on-result
                 (lambda () (when edits (eglot--apply-text-edits edits)))))
      :error-fn (lambda (&rest _) (funcall on-result nil))
      :timeout-fn (lambda (&rest _) (funcall on-result nil))))))

;;; Formatting

(defconst claude-format-on-edit--save-formatters
  '(lsp-format-buffer lsp--format-buffer-before-save
    eglot-format eglot-format-buffer
    apheleia-format-after-save)
  "Save hooks that format the buffer again, mostly synchronously.")

(defun claude-format-on-edit--without-formatters (hook)
  "The functions HOOK runs in the current buffer, minus the formatters."
  (seq-remove (lambda (fn) (memq fn claude-format-on-edit--save-formatters))
              (mapcan (lambda (fn)
                        (if (eq fn t)
                            (copy-sequence (default-value hook))
                          (list fn)))
                      (copy-sequence (symbol-value hook)))))

(defvar lsp-format-buffer-on-save)

(defun claude-format-on-edit--save ()
  "Save the current buffer without the user's format-on-save.
The buffer holds the server's formatting already.  lsp-mode's
`lsp-format-buffer-on-save', an eglot formatter or apheleia on the save
hooks would format it a second time, synchronously for the first two,
blocking Emacs for up to `lsp-response-timeout'."
  (let ((lsp-format-buffer-on-save nil)
        (before-save-hook
         (claude-format-on-edit--without-formatters 'before-save-hook))
        (after-save-hook
         (claude-format-on-edit--without-formatters 'after-save-hook)))
    (save-buffer)))

(defun claude-format-on-edit--server (job)
  "Start a server for JOB if it may, then wait for formatting.
Only a buffer the hook opened itself, in an LSP-enabled mode, gets a new
server.  The user's own buffers use a server only if one is attached."
  (let ((client (claude-format-on-edit--attached-client)))
    (when (and (not client)
               (claude-format-on-edit--job-opened job)
               (fboundp 'lsp-mcp-enabled-mode-p))
      (setq client (lsp-mcp-enabled-mode-p))
      (when client
        (claude-format-on-edit--start-server client)))
    (setf (claude-format-on-edit--job-client job) client)
    (if (not client)
        (claude-format-on-edit--checkers job)
      ;; The budget runs from when the job was queued, not from now.
      (claude-format-on-edit--poll
       job
       (lambda () (not (claude-format-on-edit--format-ready-p client)))
       (- (+ (claude-format-on-edit--job-queued job)
             claude-format-on-edit-server-budget)
          (float-time))
       (lambda ()
         (if (claude-format-on-edit--format-ready-p client)
             (claude-format-on-edit--format job)
           (claude-format-on-edit--checkers job)))))))

(defun claude-format-on-edit--current-p (job)
  "Non-nil when formatting for JOB may still be saved.
It may not when a newer job exists for the file, the file changed on disk
since JOB was queued, or someone edited the buffer meanwhile."
  (let ((file (claude-format-on-edit--job-file job)))
    (and (eql (gethash file claude-format-on-edit--latest)
              (claude-format-on-edit--job-id job))
         (time-equal-p (claude-format-on-edit--mtime file)
                       (claude-format-on-edit--job-mtime job))
         (not (buffer-modified-p)))))

(defun claude-format-on-edit--format (job)
  "Send JOB's formatting request and apply the answer if still current."
  (let ((answered nil))
    (cl-flet ((next ()
                (unless answered
                  (setq answered t)
                  (when-let* ((timer (claude-format-on-edit--job-timer job)))
                    (cancel-timer timer))
                  (claude-format-on-edit--checkers job))))
      (setf (claude-format-on-edit--job-timer job)
            (run-at-time claude-format-on-edit-request-timeout nil
                         (lambda ()
                           (claude-format-on-edit--step job #'next))))
      (claude-format-on-edit--request-format
       (claude-format-on-edit--job-client job)
       (lambda (apply-edits)
         (claude-format-on-edit--step
          job
          (lambda ()
            (unless answered
              ;; A formatter refuses to touch a syntactically broken file.
              ;; That is exactly when the diagnostics matter, so a failed
              ;; format must not abort the rest.
              (when (and apply-edits (claude-format-on-edit--current-p job))
                (ignore-errors
                  (funcall apply-edits)
                  (when (buffer-modified-p)
                    (claude-format-on-edit--save))))
              (next)))))))))

;;; Diagnostics

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

(defun claude-format-on-edit--checkers (job)
  "Run Flycheck and Flymake for JOB, then wait for lsp-mode's diagnostics."
  (when (claude-format-on-edit--job-opened job)
    (claude-format-on-edit--enable-checker))
  (when (bound-and-true-p flycheck-mode)
    (ignore-errors (flycheck-buffer)))
  (when (bound-and-true-p flymake-mode)
    (ignore-errors (flymake-start)))
  (claude-format-on-edit--poll
   job
   (lambda ()
     (or (and (bound-and-true-p flycheck-mode)
              (memq flycheck-last-status-change '(running not-checked)))
         (and (bound-and-true-p flymake-mode)
              (flymake-running-backends)
              ;; Running but not yet reported.
              (seq-difference (flymake-running-backends)
                              (flymake-reporting-backends)))))
   claude-format-on-edit-checker-timeout
   (lambda ()
     (let ((file (claude-format-on-edit--job-file job)))
       ;; Diagnostics are pushed after the edit, so an empty table right after
       ;; a format may only mean they have not arrived yet.
       (claude-format-on-edit--poll
        job
        (lambda ()
          (and (bound-and-true-p lsp-mode)
               (null (claude-format-on-edit--lsp-raw file))))
        claude-format-on-edit-lsp-diagnostics-timeout
        (lambda () (claude-format-on-edit--finish job)))))))

(defun claude-format-on-edit--flycheck ()
  "Diagnostics from Flycheck as (LINE LEVEL MESSAGE) records."
  (when (bound-and-true-p flycheck-mode)
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
    (delq nil
          (mapcar
           (lambda (d)
             (let* ((type (flymake-diagnostic-type d))
                    (level (cond ((memq type '(:error error eglot-error))
                                  'error)
                                 ((memq type '(:warning warning eglot-warning))
                                  'warning))))
               (when level
                 (list (line-number-at-pos (flymake-diagnostic-beg d) t)
                       level
                       (flymake-diagnostic-text d)))))
           (ignore-errors (flymake-diagnostics))))))

(defun claude-format-on-edit--lsp-raw (file)
  "The diagnostics lsp-mode holds for FILE, unconverted."
  (when (fboundp 'lsp-diagnostics)
    (let ((table (ignore-errors (lsp-diagnostics t)))
          (diagnostics nil))
      (when table
        ;; Key spelling differs between clients, so match on the file itself.
        (maphash (lambda (path diags)
                   (when (ignore-errors (file-equal-p path file))
                     (setq diagnostics diags)))
                 table))
      diagnostics)))

(defun claude-format-on-edit--lsp (file)
  "Diagnostics lsp-mode holds for FILE as (LINE LEVEL MESSAGE) records.
Read straight from the workspace, so a buffer with no checker UI still
reports."
  (when (bound-and-true-p lsp-mode)
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
           (claude-format-on-edit--lsp-raw file)))))

(defun claude-format-on-edit--collect (file)
  "All diagnostics for FILE, deduplicated and ordered by line.
Flycheck commonly republishes what lsp-mode already reported, so the same
finding arrives twice."
  (let ((seen (make-hash-table :test #'equal))
        (out nil))
    (dolist (record (append (ignore-errors (claude-format-on-edit--flycheck))
                            (ignore-errors (claude-format-on-edit--flymake))
                            (ignore-errors (claude-format-on-edit--lsp file))))
      (pcase-let ((`(,line ,level ,message) record))
        (let ((key (list line (string-trim (or message "")))))
          (when (and message (not (gethash key seen)))
            (puthash key t seen)
            (push (list line level (string-trim message)) out)))))
    (sort (nreverse out)
          (lambda (a b) (< (car a) (car b))))))

;;; Report

(defun claude-format-on-edit--manifest-p (file)
  "Non-nil when FILE is a dependency or project manifest."
  (let ((case-fold-search nil))
    (string-match-p claude-format-on-edit--manifest-regexp
                    (file-name-nondirectory file))))

(defun claude-format-on-edit--report-text (job)
  "What the agent should read about JOB's file, or nil for nothing."
  (let* ((file (claude-format-on-edit--job-file job))
         (buffer (claude-format-on-edit--job-buffer job))
         (records (and (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (claude-format-on-edit--collect file))))
         (parts nil))
    (when records
      (push (concat
             "Diagnostics for the file just edited:\n"
             (mapconcat
              (lambda (r)
                (format "%s:%s: %s: %s"
                        (file-name-nondirectory file)
                        (nth 0 r) (nth 1 r) (nth 2 r)))
              (seq-take records claude-format-on-edit--max-lines)
              "\n"))
            parts))
    (when (claude-format-on-edit--manifest-p file)
      (push (concat
             "This is a dependency or project manifest.  Once the "
             "dependencies are installed, call the lsp-restart-workspace "
             "tool for this file so the language server sees them.")
            parts))
    (when parts
      (string-join (nreverse parts) "\n\n"))))

(defun claude-format-on-edit--cleanup (buffer)
  "Kill BUFFER but leave its language server running.
The next edit in the same project then finds a warm server instead of paying
for a cold start, and the user finds it already up when they open a file."
  (when (buffer-live-p buffer)
    (setq claude-format-on-edit--owned
          (delq buffer claude-format-on-edit--owned))
    (let ((lsp-keep-workspace-alive t))
      (kill-buffer buffer))))

(defun claude-format-on-edit--finish (job)
  "Write JOB's report, then its done marker, and let go of its buffer.
Safe to call more than once; only the first call does anything."
  (unless (claude-format-on-edit--job-finished job)
    (setf (claude-format-on-edit--job-finished job) t)
    (dolist (timer (list (claude-format-on-edit--job-timer job)
                         (claude-format-on-edit--job-watchdog job)))
      (when timer (cancel-timer timer)))
    (setq claude-format-on-edit--active
          (delq job claude-format-on-edit--active))
    (let ((text (ignore-errors
                  (claude-format-on-edit--quietly
                    (claude-format-on-edit--report-text job)))))
      ;; The shell side may have given up and removed the directory.
      (ignore-errors
        (when text
          (with-temp-file (claude-format-on-edit--job-report job)
            (insert text))))
      (ignore-errors
        (with-temp-file (claude-format-on-edit--job-done job))))
    (let ((buffer (claude-format-on-edit--job-buffer job)))
      (when (and (claude-format-on-edit--job-opened job)
                 (not (seq-some (lambda (other)
                                  (eq (claude-format-on-edit--job-buffer other)
                                      buffer))
                                claude-format-on-edit--active)))
        (claude-format-on-edit--quietly
          (ignore-errors (claude-format-on-edit--cleanup buffer)))))))

(defun claude-format-on-edit--run (job)
  "Open JOB's file and start its work.  Runs from a timer."
  (let* ((file (claude-format-on-edit--job-file job))
         (existing (get-file-buffer file))
         (opened (or (not existing)
                     (memq existing claude-format-on-edit--owned)))
         ;; NOWARN: a file that changed on disk must not raise a prompt.
         (buffer (or existing
                     (claude-format-on-edit--quietly
                       (ignore-errors (find-file-noselect file t))))))
    (setf (claude-format-on-edit--job-buffer job) buffer
          (claude-format-on-edit--job-opened job) opened)
    (when (and buffer (not existing))
      (push buffer claude-format-on-edit--owned))
    ;; A buffer with unsaved changes is left alone entirely.
    (if (or (not buffer) (buffer-modified-p buffer))
        (claude-format-on-edit--finish job)
      (claude-format-on-edit--step
       job
       (lambda ()
         (when (and existing (not (verify-visited-file-modtime buffer)))
           (revert-buffer :ignore-auto :noconfirm :preserve-modes))
         (claude-format-on-edit--server job))))))

;;;###autoload
(defun claude-format-on-edit (file report done)
  "Queue a job that formats FILE and reports on it, and return at once.
The job writes what the agent should see to REPORT, if anything, and then
creates DONE.  A buffer opened for it is killed again, and a buffer the user
already had open keeps its modes.  A language server started here stays
running."
  (let* ((file (expand-file-name file))
         (job (claude-format-on-edit--job-create
               :file file :report report :done done
               :id (cl-incf claude-format-on-edit--counter)
               :mtime (claude-format-on-edit--mtime file)
               :queued (float-time))))
    (puthash file (claude-format-on-edit--job-id job)
             claude-format-on-edit--latest)
    (push job claude-format-on-edit--active)
    (setf (claude-format-on-edit--job-watchdog job)
          (run-at-time claude-format-on-edit-job-deadline nil
                       #'claude-format-on-edit--finish job))
    (run-at-time 0 nil
                 (lambda ()
                   (condition-case nil
                       (claude-format-on-edit--run job)
                     (error (claude-format-on-edit--finish job)))))
    nil))

(provide 'format-on-edit)
;;; format-on-edit.el ends here
