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

(defun format-on-edit-test--backend (report-fn &rest _)
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
(function-put 'format-on-edit-test--backend 'flymake-always-safe t)

(define-derived-mode format-on-edit-test-base-mode prog-mode "FotBase"
  "Parent of the dummy modes; checks through `format-on-edit-test--backend'."
  (add-hook 'flymake-diagnostic-functions #'format-on-edit-test--backend nil t))

(define-derived-mode format-on-edit-test-plain-mode
  format-on-edit-test-base-mode "FotPlain"
  "A mode the user never enabled LSP for.")

(define-derived-mode format-on-edit-test-lsp-mode
  format-on-edit-test-base-mode "FotLsp"
  "A mode whose hook starts lsp-mode.")
(add-hook 'format-on-edit-test-lsp-mode-hook #'lsp-deferred)

(define-derived-mode format-on-edit-test-eglot-mode
  format-on-edit-test-base-mode "FotEglot"
  "A mode whose hook starts eglot.")
(add-hook 'format-on-edit-test-eglot-mode-hook #'eglot-ensure)

(dolist (entry '(("\\.fotp\\'" . format-on-edit-test-plain-mode)
                 ("\\.fotl\\'" . format-on-edit-test-lsp-mode)
                 ("\\.fote\\'" . format-on-edit-test-eglot-mode)))
  (add-to-list 'auto-mode-alist entry))

;;; Fixture

(defvar format-on-edit-test--starts nil
  "Clients a server start was asked for, newest first.")

(defvar format-on-edit-test--requests 0
  "Number of formatting requests sent.")

(defvar format-on-edit-test--ready t
  "Whether a started server offers formatting.")

(defvar format-on-edit-test--format-delay 0.1
  "Seconds the stub server takes to answer a formatting request.")

(defvar-local format-on-edit-test--attached nil
  "Client the stub pretends is attached to this buffer.")

(defun format-on-edit-test--stub-start (client)
  (push client format-on-edit-test--starts)
  (setq format-on-edit-test--attached client))

(defun format-on-edit-test--stub-request (_client on-result)
  "Answer with edits that append a formatted-by line, after a delay."
  (let ((n (cl-incf format-on-edit-test--requests)))
    (run-at-time format-on-edit-test--format-delay nil
                 (lambda ()
                   (funcall on-result
                            (lambda ()
                              (goto-char (point-max))
                              (insert (format "formatted %d\n" n))))))))

(defmacro format-on-edit-test--with-stubs (&rest body)
  "Run BODY with the language-server adapters stubbed."
  (declare (indent 0))
  `(let ((format-on-edit-test--starts nil)
         (format-on-edit-test--requests 0)
         (format-on-edit-test--ready t)
         (format-on-edit-test--format-delay 0.1)
         (claude-format-on-edit-server-budget 1.0))
     (cl-letf (((symbol-function 'claude-format-on-edit--start-server)
                #'format-on-edit-test--stub-start)
               ((symbol-function 'claude-format-on-edit--attached-client)
                (lambda () format-on-edit-test--attached))
               ((symbol-function 'claude-format-on-edit--format-ready-p)
                (lambda (_client) format-on-edit-test--ready))
               ((symbol-function 'claude-format-on-edit--request-format)
                #'format-on-edit-test--stub-request))
       ,@body)))

(defun format-on-edit-test--file (name content)
  "Create NAME holding CONTENT in a fresh directory; return its path."
  (let ((file (expand-file-name name (make-temp-file "fot" t))))
    (with-temp-file file (insert content))
    file))

(defun format-on-edit-test--enqueue (file)
  "Queue a job for FILE; return its (REPORT . DONE) paths."
  (let* ((dir (make-temp-file "fot-out" t))
         (report (expand-file-name "report" dir))
         (done (expand-file-name "done" dir)))
    (claude-format-on-edit file report done)
    (cons report done)))

(defun format-on-edit-test--await (job &optional seconds)
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

(defun format-on-edit-test--contents (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

;;; Tests

(ert-deftest format-on-edit-test-plain-mode-gets-checker-pass-and-no-server ()
  "A mode that is not LSP-enabled starts no server but is still checked."
  (format-on-edit-test--with-stubs
    (let* ((file (format-on-edit-test--file "a.fotp" "ok\nBAD\n"))
           (report (format-on-edit-test--await
                    (format-on-edit-test--enqueue file))))
      (should (null format-on-edit-test--starts))
      (should (= format-on-edit-test--requests 0))
      (should (string-match-p "a.fotp:2: error: fot: bad thing" report))
      (should (equal (format-on-edit-test--contents file) "ok\nBAD\n")))))

(ert-deftest format-on-edit-test-lsp-mode-starts-server-and-formats ()
  "A file the hook opens in an LSP-enabled mode gets a server and a format."
  (format-on-edit-test--with-stubs
    (let ((file (format-on-edit-test--file "a.fotl" "x\n")))
      (format-on-edit-test--await (format-on-edit-test--enqueue file))
      (should (equal format-on-edit-test--starts '(lsp-mode)))
      (should (equal (format-on-edit-test--contents file) "x\nformatted 1\n"))
      ;; The hook's buffer is gone again; the user never sees it.
      (should-not (get-file-buffer file)))))

(ert-deftest format-on-edit-test-eglot-mode-starts-eglot ()
  "A mode configured with eglot-ensure gets an eglot server."
  (format-on-edit-test--with-stubs
    (let ((file (format-on-edit-test--file "a.fote" "x\n")))
      (format-on-edit-test--await (format-on-edit-test--enqueue file))
      (should (equal format-on-edit-test--starts '(eglot)))
      (should (equal (format-on-edit-test--contents file)
                     "x\nformatted 1\n")))))

(ert-deftest format-on-edit-test-open-buffer-gets-no-server ()
  "A buffer the user already has open keeps its state: no server start."
  (format-on-edit-test--with-stubs
    (let* ((file (format-on-edit-test--file "b.fotl" "x\nBAD\n"))
           (buffer (find-file-noselect file t)))
      (unwind-protect
          (let ((report (format-on-edit-test--await
                         (format-on-edit-test--enqueue file))))
            (should (null format-on-edit-test--starts))
            (should (= format-on-edit-test--requests 0))
            (should (equal (format-on-edit-test--contents file) "x\nBAD\n"))
            ;; And the user's buffer stays open.
            (should (buffer-live-p buffer))
            ;; No checker was forced on the user's buffer either.
            (should (equal report "")))
        (kill-buffer buffer)))))

(ert-deftest format-on-edit-test-open-buffer-uses-attached-server ()
  "A buffer the user has open with a server attached is still formatted."
  (format-on-edit-test--with-stubs
    (let* ((file (format-on-edit-test--file "c.fotl" "x\n"))
           (buffer (find-file-noselect file t)))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (setq format-on-edit-test--attached 'lsp-mode))
            (format-on-edit-test--await (format-on-edit-test--enqueue file))
            (should (null format-on-edit-test--starts))
            (should (equal (format-on-edit-test--contents file)
                           "x\nformatted 1\n"))
            (should (buffer-live-p buffer)))
        (kill-buffer buffer)))))

(ert-deftest format-on-edit-test-no-server-without-lsp-mcp ()
  "Without lsp-mcp loaded there is no LSP-enabled check, so no server."
  (format-on-edit-test--with-stubs
    (cl-letf (((symbol-function 'lsp-mcp-enabled-mode-p) nil))
      (let ((file (format-on-edit-test--file "d.fotl" "x\n")))
        (format-on-edit-test--await (format-on-edit-test--enqueue file))
        (should (null format-on-edit-test--starts))
        (should (equal (format-on-edit-test--contents file) "x\n"))))))

(ert-deftest format-on-edit-test-emacs-stays-responsive ()
  "Queueing returns at once, and other timers fire while the job runs."
  (format-on-edit-test--with-stubs
    (let* ((format-on-edit-test--format-delay 0.5)
           (file (format-on-edit-test--file "e.fotl" "x\n"))
           (job (format-on-edit-test--enqueue file))
           (fired-in-flight nil))
      ;; Nothing has happened yet when the entry point returns, not even
      ;; opening the file.
      (should-not (get-file-buffer file))
      (should-not (file-exists-p (cdr job)))
      (run-at-time 0.2 nil
                   (lambda ()
                     (setq fired-in-flight (not (file-exists-p (cdr job))))))
      (format-on-edit-test--await job)
      (should fired-in-flight)
      (should (equal (format-on-edit-test--contents file)
                     "x\nformatted 1\n")))))

(ert-deftest format-on-edit-test-late-format-dropped-when-file-changed ()
  "Formatting is not saved when the file changed after the job was queued."
  (format-on-edit-test--with-stubs
    (let* ((file (format-on-edit-test--file "f.fotl" "x\n"))
           (job (format-on-edit-test--enqueue file)))
      ;; The agent's next edit lands before the job has even opened the file,
      ;; so the buffer itself holds the new text and Emacs sees no conflict.
      (with-temp-file file (insert "y\n"))
      (set-file-times file (time-add nil 5))
      (format-on-edit-test--await job)
      (should (= format-on-edit-test--requests 1))
      (should (equal (format-on-edit-test--contents file) "y\n")))))

(ert-deftest format-on-edit-test-superseded-format-dropped ()
  "Only the newest job for a file saves its formatting."
  (format-on-edit-test--with-stubs
    (let* ((format-on-edit-test--format-delay 0.3)
           (file (format-on-edit-test--file "g.fotl" "x\n"))
           (older (format-on-edit-test--enqueue file))
           (newer (format-on-edit-test--enqueue file)))
      (format-on-edit-test--await older)
      (format-on-edit-test--await newer)
      (should (= format-on-edit-test--requests 2))
      ;; The newer job's request was the second one sent.
      (should (equal (format-on-edit-test--contents file) "x\nformatted 2\n"))
      (should-not (get-file-buffer file)))))

(ert-deftest format-on-edit-test-manifest-reminder ()
  "Editing a manifest reminds the agent to restart the language server."
  (format-on-edit-test--with-stubs
    (cl-flet ((run (name content)
                (format-on-edit-test--await
                 (format-on-edit-test--enqueue
                  (format-on-edit-test--file name content)))))
      (let ((manifest (run "package.json" "{}\n"))
            (cargo (run "Cargo.toml" ""))
            (csproj (run "App.csproj" "<x/>\n"))
            (plain (run "h.fotp" "ok\n")))
        (should (string-match-p "lsp-restart-workspace" manifest))
        (should (string-match-p "lsp-restart-workspace" cargo))
        (should (string-match-p "lsp-restart-workspace" csproj))
        (should (equal plain ""))))))

(ert-deftest format-on-edit-test-cold-server-budget ()
  "A server that never offers formatting costs the budget, then the job
reports its diagnostics without formatting."
  (format-on-edit-test--with-stubs
    (let* ((format-on-edit-test--ready nil)
           (claude-format-on-edit-server-budget 0.5)
           (file (format-on-edit-test--file "i.fotl" "BAD\n"))
           (start (float-time))
           (report (format-on-edit-test--await
                    (format-on-edit-test--enqueue file) 5))
           (elapsed (- (float-time) start)))
      (should (equal format-on-edit-test--starts '(lsp-mode)))
      (should (= format-on-edit-test--requests 0))
      (should (>= elapsed 0.5))
      (should (< elapsed 2.0))
      (should (string-match-p "i.fotl:1: error: fot: bad thing" report))
      (should (equal (format-on-edit-test--contents file) "BAD\n")))))

(defun format-on-edit-test--add-save-formatters ()
  "Install lsp-mode's format-on-save hook as lsp-mode itself does."
  (add-hook 'before-save-hook #'lsp--format-buffer-before-save nil t))

(ert-deftest format-on-edit-test-save-skips-format-on-save ()
  "Saving the server's formatting runs no synchronous format-on-save.
The user's `lsp-format-buffer-on-save', or an eglot formatter on
`before-save-hook', would otherwise block Emacs and format twice."
  (format-on-edit-test--with-stubs
    (let ((lsp-format-buffer-on-save t)
          (sync-formats 0)
          (file (format-on-edit-test--file "j.fotl" "x\n")))
      (add-hook 'format-on-edit-test-lsp-mode-hook
                #'format-on-edit-test--add-save-formatters)
      (add-hook 'before-save-hook #'eglot-format-buffer)
      (unwind-protect
          (cl-letf (((symbol-function 'lsp-format-buffer)
                     (lambda () (cl-incf sync-formats)))
                    ((symbol-function 'eglot-format-buffer)
                     (lambda () (cl-incf sync-formats))))
            (format-on-edit-test--await (format-on-edit-test--enqueue file))
            (should (= sync-formats 0))
            (should (equal (format-on-edit-test--contents file)
                           "x\nformatted 1\n")))
        (remove-hook 'before-save-hook #'eglot-format-buffer)
        (remove-hook 'format-on-edit-test-lsp-mode-hook
                     #'format-on-edit-test--add-save-formatters)))))

(ert-deftest format-on-edit-test-truename-buffer-stays ()
  "The user's buffer visiting the file under another name is left alone."
  (format-on-edit-test--with-stubs
    (let* ((file (format-on-edit-test--file "k.fotl" "x\n"))
           (link (make-temp-name
                  (expand-file-name "fot-link" temporary-file-directory)))
           (buffer (find-file-noselect file t)))
      (make-symbolic-link (directory-file-name (file-name-directory file))
                          link)
      (unwind-protect
          (progn
            (format-on-edit-test--await
             (format-on-edit-test--enqueue (expand-file-name "k.fotl" link)))
            (should (buffer-live-p buffer))
            (should-not (memq buffer claude-format-on-edit--owned))
            (should (null format-on-edit-test--starts)))
        (kill-buffer buffer)
        (delete-file link)))))

(ert-deftest format-on-edit-test-run-after-watchdog-opens-nothing ()
  "A job the watchdog finished before it ran opens no buffer."
  (let* ((file (format-on-edit-test--file "l.fotp" "x\n"))
         (dir (make-temp-file "fot-out" t))
         (job (claude-format-on-edit--job-create
               :file file
               :report (expand-file-name "report" dir)
               :done (expand-file-name "done" dir))))
    (claude-format-on-edit--finish job)
    (claude-format-on-edit--run job)
    (should-not (get-file-buffer file))))

(ert-deftest format-on-edit-test-cleanup-of-modified-buffer-never-asks ()
  "A buffer the hook opened is killed without a question, even modified.
Its formatting may have been applied and then failed to save."
  (let* ((file (format-on-edit-test--file "m.fotp" "x\n"))
         (buffer (find-file-noselect file t)))
    (push buffer claude-format-on-edit--owned)
    (with-current-buffer buffer
      (insert "unsaved"))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _) (error "Prompted the user")))
              ((symbol-function 'yes-or-no-p)
               (lambda (&rest _) (error "Prompted the user")))
              ((symbol-function 'y-or-n-p)
               (lambda (&rest _) (error "Prompted the user"))))
      (claude-format-on-edit--cleanup buffer))
    (should-not (buffer-live-p buffer))
    (should (equal (format-on-edit-test--contents file) "x\n"))))

(ert-deftest format-on-edit-test-unsafe-local-variables-never-ask ()
  "Opening a file with unsafe file-local variables asks nobody."
  (format-on-edit-test--with-stubs
    (let ((file (format-on-edit-test--file
                 "n.fotp" "-*- format-on-edit-test-unsafe: 1 -*-\nBAD\n"))
          asked)
      (cl-letf (((symbol-function 'hack-local-variables-confirm)
                 (lambda (&rest _) (setq asked t) nil)))
        (format-on-edit-test--await (format-on-edit-test--enqueue file)))
      (should-not asked))))

(provide 'format-on-edit-test)
;;; format-on-edit-test.el ends here
