;;; format-on-edit-test.el --- ERT suite for format-on-edit.el -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with:
;;   nix build .#test-format-on-edit -L
;;
;; Every test goes through the entry point the shell hook calls: queue a job,
;; wait for the done marker, read the report.  Dummy major modes stand in for
;; real languages, and the language-server adapters are stubbed, so no server
;; ever runs.  What the tests observe is the report, the file on disk, and
;; whether a server start was asked for.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'flymake)
(require 'lsp-mcp)
(require 'format-on-edit)

;;; Dummy modes

(defun fot--backend (report-fn &rest _)
  "Flymake backend flagging every line that contains BAD, a moment later."
  (let ((buffer (current-buffer)))
    (run-at-time
     0.2 nil
     (lambda ()
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (save-excursion
             (goto-char (point-min))
             (let (diags)
               (while (search-forward "BAD" nil t)
                 (push (flymake-make-diagnostic
                        buffer (line-beginning-position) (line-end-position)
                        :error "fot: bad thing")
                       diags))
               (funcall report-fn diags)))))))))
;; Emacs 31 Flymake disables backends in untrusted files, and the fixtures
;; live in fresh temp directories.  This backend runs no code from the file.
(function-put 'fot--backend 'flymake-always-safe t)

(define-derived-mode fot-base-mode prog-mode "FotBase"
  "Parent of the dummy modes; checks through `fot--backend'."
  (add-hook 'flymake-diagnostic-functions #'fot--backend nil t))

(define-derived-mode fot-plain-mode fot-base-mode "FotPlain"
  "A mode the user never enabled LSP for.")

(define-derived-mode fot-lsp-mode fot-base-mode "FotLsp"
  "A mode whose hook starts lsp-mode.")
(add-hook 'fot-lsp-mode-hook #'lsp-deferred)

(define-derived-mode fot-eglot-mode fot-base-mode "FotEglot"
  "A mode whose hook starts eglot.")
(add-hook 'fot-eglot-mode-hook #'eglot-ensure)

(dolist (entry '(("\\.fotp\\'" . fot-plain-mode)
                 ("\\.fotl\\'" . fot-lsp-mode)
                 ("\\.fote\\'" . fot-eglot-mode)))
  (add-to-list 'auto-mode-alist entry))

;;; Fixture

(defvar fot--starts nil
  "Clients a server start was asked for, newest first.")

(defvar fot--requests 0
  "Number of formatting requests sent.")

(defvar fot--ready t
  "Whether a started server offers formatting.")

(defvar fot--format-delay 0.1
  "Seconds the stub server takes to answer a formatting request.")

(defvar-local fot--attached nil
  "Client the stub pretends is attached to this buffer.")

(defun fot--stub-start (client)
  (push client fot--starts)
  (setq fot--attached client))

(defun fot--stub-request (_client on-result)
  "Answer with edits that append a formatted-by line, after a delay."
  (let ((n (cl-incf fot--requests)))
    (run-at-time fot--format-delay nil
                 (lambda ()
                   (funcall on-result
                            (lambda ()
                              (goto-char (point-max))
                              (insert (format "formatted %d\n" n))))))))

(defmacro fot--with-stubs (&rest body)
  "Run BODY with the language-server adapters stubbed."
  (declare (indent 0))
  `(let ((fot--starts nil)
         (fot--requests 0)
         (fot--ready t)
         (fot--format-delay 0.1)
         (claude-format-on-edit-server-budget 1.0))
     (cl-letf (((symbol-function 'claude-format-on-edit--start-server)
                #'fot--stub-start)
               ((symbol-function 'claude-format-on-edit--attached-client)
                (lambda () fot--attached))
               ((symbol-function 'claude-format-on-edit--format-ready-p)
                (lambda (_client) fot--ready))
               ((symbol-function 'claude-format-on-edit--request-format)
                #'fot--stub-request))
       ,@body)))

(defun fot--file (name content)
  "Create NAME holding CONTENT in a fresh directory; return its path."
  (let ((file (expand-file-name name (make-temp-file "fot" t))))
    (with-temp-file file (insert content))
    file))

(defun fot--enqueue (file)
  "Queue a job for FILE; return its (REPORT . DONE) paths."
  (let* ((dir (make-temp-file "fot-out" t))
         (report (expand-file-name "report" dir))
         (done (expand-file-name "done" dir)))
    (claude-format-on-edit file report done)
    (cons report done)))

(defun fot--await (job &optional seconds)
  "Wait up to SECONDS for JOB's done marker; return the report text.
Signals if the marker never appears."
  (let ((deadline (+ (float-time) (or seconds 10))))
    (while (and (not (file-exists-p (cdr job)))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (unless (file-exists-p (cdr job))
      (error "No done marker after %ss" (or seconds 10)))
    (if (file-exists-p (car job))
        (with-temp-buffer
          (insert-file-contents (car job))
          (buffer-string))
      "")))

(defun fot--contents (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

;;; Tests

(ert-deftest fot-plain-mode-gets-checker-pass-and-no-server ()
  "A mode that is not LSP-enabled starts no server but is still checked."
  (fot--with-stubs
    (let* ((file (fot--file "a.fotp" "ok\nBAD\n"))
           (report (fot--await (fot--enqueue file))))
      (should (null fot--starts))
      (should (= fot--requests 0))
      (should (string-match-p "a.fotp:2: error: fot: bad thing" report))
      (should (equal (fot--contents file) "ok\nBAD\n")))))

(ert-deftest fot-lsp-mode-starts-server-and-formats ()
  "A file the hook opens in an LSP-enabled mode gets a server and a format."
  (fot--with-stubs
    (let ((file (fot--file "a.fotl" "x\n")))
      (fot--await (fot--enqueue file))
      (should (equal fot--starts '(lsp-mode)))
      (should (equal (fot--contents file) "x\nformatted 1\n"))
      ;; The hook's buffer is gone again; the user never sees it.
      (should-not (get-file-buffer file)))))

(ert-deftest fot-eglot-mode-starts-eglot ()
  "A mode configured with eglot-ensure gets an eglot server."
  (fot--with-stubs
    (let ((file (fot--file "a.fote" "x\n")))
      (fot--await (fot--enqueue file))
      (should (equal fot--starts '(eglot)))
      (should (equal (fot--contents file) "x\nformatted 1\n")))))

(ert-deftest fot-open-buffer-gets-no-server ()
  "A buffer the user already has open keeps its state: no server start."
  (fot--with-stubs
    (let* ((file (fot--file "b.fotl" "x\nBAD\n"))
           (buffer (find-file-noselect file t)))
      (unwind-protect
          (let ((report (fot--await (fot--enqueue file))))
            (should (null fot--starts))
            (should (= fot--requests 0))
            (should (equal (fot--contents file) "x\nBAD\n"))
            ;; And the user's buffer stays open.
            (should (buffer-live-p buffer))
            ;; No checker was forced on the user's buffer either.
            (should (equal report "")))
        (kill-buffer buffer)))))

(ert-deftest fot-open-buffer-uses-attached-server ()
  "A buffer the user has open with a server attached is still formatted."
  (fot--with-stubs
    (let* ((file (fot--file "c.fotl" "x\n"))
           (buffer (find-file-noselect file t)))
      (unwind-protect
          (progn
            (with-current-buffer buffer (setq fot--attached 'lsp-mode))
            (fot--await (fot--enqueue file))
            (should (null fot--starts))
            (should (equal (fot--contents file) "x\nformatted 1\n"))
            (should (buffer-live-p buffer)))
        (kill-buffer buffer)))))

(ert-deftest fot-no-server-without-lsp-mcp ()
  "Without lsp-mcp loaded there is no LSP-enabled check, so no server."
  (fot--with-stubs
    (cl-letf (((symbol-function 'lsp-mcp-enabled-mode-p) nil))
      (let ((file (fot--file "d.fotl" "x\n")))
        (fot--await (fot--enqueue file))
        (should (null fot--starts))
        (should (equal (fot--contents file) "x\n"))))))

(ert-deftest fot-emacs-stays-responsive ()
  "Queueing returns at once, and other timers fire while the job runs."
  (fot--with-stubs
    (let* ((fot--format-delay 0.5)
           (file (fot--file "e.fotl" "x\n"))
           (job (fot--enqueue file))
           (fired-in-flight nil))
      ;; Nothing has happened yet when the entry point returns, not even
      ;; opening the file.
      (should-not (get-file-buffer file))
      (should-not (file-exists-p (cdr job)))
      (run-at-time 0.2 nil
                   (lambda ()
                     (setq fired-in-flight (not (file-exists-p (cdr job))))))
      (fot--await job)
      (should fired-in-flight)
      (should (equal (fot--contents file) "x\nformatted 1\n")))))

(ert-deftest fot-late-format-dropped-when-file-changed ()
  "Formatting is not saved when the file changed after the job was queued."
  (fot--with-stubs
    (let* ((file (fot--file "f.fotl" "x\n"))
           (job (fot--enqueue file)))
      ;; The agent's next edit lands before the job has even opened the file,
      ;; so the buffer itself holds the new text and Emacs sees no conflict.
      (with-temp-file file (insert "y\n"))
      (set-file-times file (time-add nil 5))
      (fot--await job)
      (should (= fot--requests 1))
      (should (equal (fot--contents file) "y\n")))))

(ert-deftest fot-superseded-format-dropped ()
  "Only the newest job for a file saves its formatting."
  (fot--with-stubs
    (let* ((fot--format-delay 0.3)
           (file (fot--file "g.fotl" "x\n"))
           (older (fot--enqueue file))
           (newer (fot--enqueue file)))
      (fot--await older)
      (fot--await newer)
      (should (= fot--requests 2))
      ;; The newer job's request was the second one sent.
      (should (equal (fot--contents file) "x\nformatted 2\n"))
      (should-not (get-file-buffer file)))))

(ert-deftest fot-manifest-reminder ()
  "Editing a manifest reminds the agent to restart the language server."
  (fot--with-stubs
    (let ((manifest (fot--await (fot--enqueue (fot--file "package.json" "{}\n"))))
          (cargo (fot--await (fot--enqueue (fot--file "Cargo.toml" ""))))
          (csproj (fot--await (fot--enqueue (fot--file "App.csproj" "<x/>\n"))))
          (plain (fot--await (fot--enqueue (fot--file "h.fotp" "ok\n")))))
      (should (string-match-p "lsp-restart-workspace" manifest))
      (should (string-match-p "lsp-restart-workspace" cargo))
      (should (string-match-p "lsp-restart-workspace" csproj))
      (should (equal plain "")))))

(ert-deftest fot-cold-server-budget ()
  "A server that never offers formatting costs the budget, then the job
reports its diagnostics without formatting."
  (fot--with-stubs
    (let* ((fot--ready nil)
           (claude-format-on-edit-server-budget 0.5)
           (file (fot--file "i.fotl" "BAD\n"))
           (start (float-time))
           (report (fot--await (fot--enqueue file) 5))
           (elapsed (- (float-time) start)))
      (should (equal fot--starts '(lsp-mode)))
      (should (= fot--requests 0))
      (should (>= elapsed 0.5))
      (should (< elapsed 2.0))
      (should (string-match-p "i.fotl:1: error: fot: bad thing" report))
      (should (equal (fot--contents file) "BAD\n")))))

(provide 'format-on-edit-test)
;;; format-on-edit-test.el ends here
