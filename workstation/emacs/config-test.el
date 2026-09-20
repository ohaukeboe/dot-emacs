;;; config-test.el --- Tests for config.org itself -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the few pieces of config.org whose breakage is silent and
;; expensive.  They read the literate configuration rather than loading it:
;; loading config.el in batch would drag in every package.
;;
;; Run from this directory with:
;;   emacs -batch -l config-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'subr-x)

(defvar config-test-file
  (expand-file-name "config.org"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The literate configuration under test.")

(defun config-test--contents ()
  (with-temp-buffer
    (insert-file-contents config-test-file)
    (buffer-string)))

(defun config-test--read-defun (name)
  "Return the source form of the defun NAME in config.org."
  (with-temp-buffer
    (insert-file-contents config-test-file)
    (goto-char (point-min))
    (unless (re-search-forward (format "^ *(defun %s " (regexp-quote name)) nil t)
      (error "config.org defines no %s" name))
    (goto-char (match-beginning 0))
    (read (current-buffer))))

;;;; diff-hl must not touch buffers that do not use it

;; `diff-hl-update' updates whatever buffer is current.  With
;; `diff-hl-update-async' set to `thread' it spawns a thread that makes that
;; buffer current and walks it with `widen', `goto-char' and `forward-line'.
;; Point belongs to the buffer, not to the thread, so running it in a Magit
;; status buffer moves the insertion point of a refresh in progress and
;; leaves the buffer rotated (dot-emacs-l3y).

(ert-deftest config-test-diff-hl-window-hook-is-guarded ()
  "`window-state-change' runs the guard, not a bare `diff-hl-update'."
  (let ((contents (config-test--contents)))
    (should (string-search "(window-state-change . my/diff-hl-update-if-enabled)"
                           contents))
    (should-not (string-search "(window-state-change . (lambda () (diff-hl-update)))"
                               contents))))

(ert-deftest config-test-diff-hl-guard-skips-foreign-buffers ()
  "The guard updates a buffer with `diff-hl-mode' on, and only such a buffer."
  (eval (config-test--read-defun "my/diff-hl-update-if-enabled") t)
  (let ((calls 0))
    (cl-letf (((symbol-function 'diff-hl-update) (lambda () (cl-incf calls))))
      (with-temp-buffer
        ;; A Magit status buffer, or any other buffer diff-hl knows nothing
        ;; about, has no `diff-hl-mode' binding at all.
        (my/diff-hl-update-if-enabled)
        (should (equal calls 0))
        (setq-local diff-hl-mode nil)
        (my/diff-hl-update-if-enabled)
        (should (equal calls 0))
        (setq-local diff-hl-mode t)
        (my/diff-hl-update-if-enabled)
        (should (equal calls 1))))))

(provide 'config-test)

;;; config-test.el ends here
