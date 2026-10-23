;;; agent-commit-gate-test.el --- Tests for agent-commit-gate.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by tests/agent-commit-review.nix:
;;
;;   nix build .#test-agent-commit-review -L
;;
;; Each test drives a real Magit commit in a throwaway repository, the way
;; the gate does through emacsclient, and checks result.json and git log.  In
;; batch Emacs with-editor falls back to its sleeping editor, so git's editor
;; request still reaches a `git-commit-mode' buffer here.

;;; Code:

(require 'ert)
(require 'agent-commit-gate)

;; Use with-editor's sleeping editor rather than starting a server: a batch
;; Emacs in a build sandbox has nowhere to put the socket.  The buffer, the
;; hooks and git's exit status are the same either way.
(setq with-editor-emacsclient-executable nil)

(defvar agent-commit-gate-test--root nil)

(defun agent-commit-gate-test--git (&rest args)
  "Run git with ARGS in `default-directory' and return its trimmed output."
  (with-temp-buffer
    (unless (zerop (apply #'process-file "git" nil t nil args))
      (error "git %S failed: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun agent-commit-gate-test--wait (predicate what)
  "Process output until PREDICATE holds; fail after 20 seconds naming WHAT."
  (let ((end (+ (float-time) 20)))
    (while (and (not (funcall predicate)) (< (float-time) end))
      (accept-process-output nil 0.1))
    (unless (funcall predicate)
      (ert-fail (format "timed out waiting for %s" what)))))

(defun agent-commit-gate-test--commit-buffer ()
  "The live COMMIT_EDITMSG buffer, or nil."
  (seq-find (lambda (b) (with-current-buffer b (bound-and-true-p git-commit-mode)))
            (buffer-list)))

(defmacro agent-commit-gate-test--with-review (pid &rest body)
  "Stage a change, open a review whose gate pid is PID, and run BODY.
BODY sees `repo', `request' and `buffer' (the commit buffer)."
  (declare (indent 1))
  `(let* ((root (make-temp-file "acg" t))
          (repo (file-name-as-directory (expand-file-name "repo" root)))
          (request (expand-file-name "req" root))
          (magit-commit-show-diff nil))
     (make-directory repo)
     (make-directory request)
     (let ((default-directory repo))
       (agent-commit-gate-test--git "init" "-q")
       (write-region "one\n" nil (expand-file-name "a.txt" repo))
       (agent-commit-gate-test--git "add" "a.txt")
       (agent-commit-gate-test--git "commit" "-qm" "init")
       (write-region "two\n" nil (expand-file-name "a.txt" repo))
       (agent-commit-gate-test--git "add" "a.txt"))
     (write-region "feat: proposed by the agent\n" nil
                   (expand-file-name "msg" request))
     (write-region (json-encode `((dir . ,repo) (gate_pid . ,,pid)
                                  (deadline . ,(+ (float-time) 600))))
                   nil (expand-file-name "request.json" request))
     (should (eq t (agent-commit-gate-review repo request)))
     (agent-commit-gate-test--wait #'agent-commit-gate-test--commit-buffer
                                   "the commit buffer")
     (let ((buffer (agent-commit-gate-test--commit-buffer)))
       (with-current-buffer buffer
         (should (string-match-p "feat: proposed by the agent" (buffer-string))))
       ,@body)))

(defun agent-commit-gate-test--result (request)
  "Wait for and return REQUEST/result.json as an alist."
  (let ((file (expand-file-name "result.json" request)))
    (agent-commit-gate-test--wait (lambda () (file-exists-p file)) "result.json")
    (let ((json-object-type 'alist))
      (json-read-file file))))

(ert-deftest agent-commit-gate-test-finish-commits-edited-message ()
  (agent-commit-gate-test--with-review (emacs-pid)
    (with-current-buffer buffer
      (goto-char (point-min))
      (delete-region (point) (line-end-position))
      (insert "feat: edited by the user")
      (with-editor-finish nil))
    (let ((result (agent-commit-gate-test--result request))
          (default-directory repo))
      (should (equal (alist-get 'status result) "committed"))
      (should (equal (alist-get 'subject result) "feat: edited by the user"))
      (should (equal (agent-commit-gate-test--git "log" "-1" "--format=%s")
                     "feat: edited by the user")))))

(ert-deftest agent-commit-gate-test-cancel-commits-nothing ()
  (agent-commit-gate-test--with-review (emacs-pid)
    (with-current-buffer buffer (with-editor-cancel nil))
    (let ((result (agent-commit-gate-test--result request))
          (default-directory repo))
      (should (equal (alist-get 'status result) "not-committed"))
      (should (equal (alist-get 'reason result) "cancelled by the user"))
      (should (equal (agent-commit-gate-test--git "log" "-1" "--format=%s") "init")))))

(ert-deftest agent-commit-gate-test-finish-refused-when-gate-is-gone ()
  ;; No process has this pid: the gate that asked has gone away.
  (agent-commit-gate-test--with-review 999999999
    (with-current-buffer buffer (with-editor-finish nil))
    (let ((result (agent-commit-gate-test--result request))
          (default-directory repo))
      (should (equal (alist-get 'status result) "not-committed"))
      (should (equal (alist-get 'reason result) "request expired"))
      (should (equal (agent-commit-gate-test--git "log" "-1" "--format=%s") "init")))))

(ert-deftest agent-commit-gate-test-cancel-from-the-gate ()
  (agent-commit-gate-test--with-review (emacs-pid)
    (agent-commit-gate-review-cancel request)
    (let ((result (agent-commit-gate-test--result request)))
      (should (equal (alist-get 'reason result) "request expired")))))

(ert-deftest agent-commit-gate-test-override-file ()
  (let* ((state (make-temp-file "acg-state" t))
         (process-environment (cons (concat "XDG_STATE_HOME=" state)
                                    process-environment)))
    (agent-commit-gate-set "*" "emacs")
    (agent-commit-gate-set "/r/.git" "deny")
    (should (equal (agent-commit-gate--read-overrides)
                   '(("/r/.git" . "deny") ("*" . "emacs"))))
    (agent-commit-gate-set "*" "default")
    (should (equal (agent-commit-gate--read-overrides) '(("/r/.git" . "deny"))))))

(provide 'agent-commit-gate-test)
;;; agent-commit-gate-test.el ends here
