;;; beads-test.el --- Tests for beads.el -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the beads section in Magit status buffers.
;;
;; The tests build a throwaway git repository with a fake `bd' on PATH, so
;; they need neither a beads database nor the real tracker, and they assert
;; the structural invariants of the Magit section tree rather than the text:
;; the mangling this file guards against (dot-emacs-l3y) showed up as
;; sections whose end marker preceded their start and children lying outside
;; their parent, after a refresh whose insertion point was moved by a diff-hl
;; thread that had the status buffer current.
;;
;; Run from the package directory with:
;;   emacs -batch -L . -l beads-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'magit)
(require 'beads)

;;;; Fixture

(defvar beads-test--repo nil
  "Directory of the throwaway repository of the running test.")

(defun beads-test--run (program &rest args)
  "Run PROGRAM with ARGS in `default-directory', erroring on failure."
  (let ((status (apply #'call-process program nil nil nil args)))
    (unless (eq status 0)
      (error "%s %s exited with %s" program (string-join args " ") status))))

(defun beads-test--write (file contents)
  (let ((file (expand-file-name file beads-test--repo)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert contents))
    file))

(defun beads-test--issue (id priority title &optional assignee)
  "Return the JSON of one issue, as bd prints it."
  (json-serialize `((id . ,id)
                    (title . ,title)
                    (description . ,(format "Description of %s, long enough to be
filled over more than one line when it is inserted." id))
                    (status . "open")
                    (priority . ,priority)
                    (assignee . ,(or assignee :null)))))

(defun beads-test--set-issues (in-progress ready)
  "Make the fake bd print IN-PROGRESS and READY, each a list of issue JSON."
  (beads-test--write "fake-bd/in_progress.json"
                     (concat "[" (string-join in-progress ",") "]"))
  (beads-test--write "fake-bd/ready.json"
                     (concat "[" (string-join ready ",") "]")))

(defmacro beads-test--with-repo (&rest body)
  "Run BODY in a fresh repository with a fake bd first on PATH."
  (declare (indent 0))
  `(let* ((beads-test--repo (file-name-as-directory
                             (make-temp-file "beads-test" t)))
          (default-directory beads-test--repo)
          (bin (expand-file-name "fake-bin" beads-test--repo))
          (process-environment (cons (format "PATH=%s:%s" bin (getenv "PATH"))
                                     process-environment))
          (exec-path (cons bin exec-path)))
     (unwind-protect
         (progn
           (make-directory bin t)
           (make-directory (expand-file-name ".beads" beads-test--repo) t)
           ;; A bd that prints the two lists the section asks for, and bd's
           ;; own stderr noise, so the parsing path is the real one.
           (let ((bd (expand-file-name "bd" bin)))
             (with-temp-file bd
               (insert "#!/bin/sh\n"
                       "echo 'warning: beads.role not configured' >&2\n"
                       "case \"$1\" in\n"
                       "  list)  cat " beads-test--repo "fake-bd/in_progress.json ;;\n"
                       "  ready) cat " beads-test--repo "fake-bd/ready.json ;;\n"
                       "  *)     echo '[]' ;;\n"
                       "esac\n"))
             (set-file-modes bd #o755))
           (beads-test--set-issues nil nil)
           (beads-test--run "git" "init" "--quiet" ".")
           (beads-test--run "git" "config" "user.email" "test@example.com")
           (beads-test--run "git" "config" "user.name" "Test")
           (beads-test--write "tracked.txt" "one\ntwo\nthree\n")
           (beads-test--run "git" "add" "tracked.txt")
           (beads-test--run "git" "commit" "--quiet" "-m" "first commit")
           (beads-test--write "tracked.txt" "one\ntwo changed\nthree\n")
           (beads-test--write "staged.txt" "staged\n")
           (beads-test--run "git" "add" "staged.txt")
           (beads-test--write "untracked.txt" "junk\n")
           ,@body)
       (delete-directory beads-test--repo t))))

(defmacro beads-test--with-status (&rest body)
  "Run BODY in the Magit status buffer of a fresh repository."
  (declare (indent 0))
  `(beads-test--with-repo
     (let ((magit-status-sections-hook
            (append magit-status-sections-hook '(beads-insert-issues)))
           (inhibit-message t)
           (buffer nil))
       (unwind-protect
           (progn
             (setq buffer (magit-status-setup-buffer beads-test--repo))
             (with-current-buffer buffer ,@body))
         (when (buffer-live-p buffer)
           (let ((kill-buffer-query-functions nil))
             (kill-buffer buffer)))))))

;;;; The invariant

(defun beads-test--section-problems (&optional section)
  "Return the structural violations of the section tree under SECTION.
A section's markers must enclose its own content and every child's, and
siblings must not overlap.  A refresh whose insertion point is moved by
something else breaks exactly these."
  (let* ((section (or section magit-root-section))
         (problems nil)
         (name (format "%s/%s" (oref section type) (oref section value)))
         (start (marker-position (oref section start)))
         (end (and (oref section end) (marker-position (oref section end)))))
    (if (not end)
        (push (format "%s: no end marker" name) problems)
      (when (< end start)
        (push (format "%s: ends at %s, before its start %s" name end start)
              problems)))
    (let ((previous nil))
      (dolist (child (oref section children))
        (let ((child-name (format "%s/%s" (oref child type) (oref child value)))
              (child-start (marker-position (oref child start)))
              (child-end (and (oref child end)
                              (marker-position (oref child end)))))
          (when (< child-start start)
            (push (format "%s: child %s starts at %s, before its parent's %s"
                          name child-name child-start start)
                  problems))
          (when (and end child-end (> child-end end))
            (push (format "%s: child %s ends at %s, past its parent's %s"
                          name child-name child-end end)
                  problems))
          (when (and previous (< child-start (cdr previous)))
            (push (format "%s: child %s starts at %s, inside %s which ends at %s"
                          name child-name child-start
                          (car previous) (cdr previous))
                  problems))
          (setq previous (cons child-name (or child-end child-start))))
        (setq problems (append (beads-test--section-problems child) problems))))
    (nreverse problems)))

(defun beads-test--headings ()
  "Return the top-level section identities, in buffer order."
  (mapcar (lambda (section)
            (format "%s" (oref section type)))
          (oref magit-root-section children)))

;;;; Tests

(ert-deftest beads-test-section-absent-without-database ()
  "A repository without .beads gets no section and makes no bd call."
  (beads-test--with-repo
    (delete-directory (expand-file-name ".beads" beads-test--repo) t)
    (should-not (beads-toplevel))))

(ert-deftest beads-test-section-lists-issues ()
  "The section shows the claimed and the ready issues, counted in its heading."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"))
     (list (beads-test--issue "t-2" 2 "A ready issue")
           (beads-test--issue "t-3" 0 "Another ready issue")))
    (magit-refresh-buffer)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (should (string-search "Beads issues (3)" text))
      (should (string-search "In progress (1)" text))
      (should (string-search "Ready (2)" text))
      (should (string-search "t-1" text)))))

(ert-deftest beads-test-tree-stays-consistent-across-refreshes ()
  "Repeated refreshes leave every section's markers enclosing its content.
This is the invariant dot-emacs-l3y broke: the status buffer came back
rotated, with sections whose end preceded their start."
  (beads-test--with-status
    (dotimes (i 6)
      (beads-test--set-issues
       (if (cl-evenp i)
           (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"))
         nil)
       (cl-loop for n from 1 to (+ 2 i)
                collect (beads-test--issue (format "r-%d" n) (mod n 5)
                                           (format "Ready issue %d" n))))
      (magit-refresh-buffer)
      (should (equal (beads-test--section-problems) nil))
      (should (member "beads-issues-section" (beads-test--headings))))))

(ert-deftest beads-test-tree-consistent-past-the-ready-limit ()
  "The capped listing and its \"and N more\" line keep the tree consistent."
  (beads-test--with-status
    (let ((beads-ready-limit 3))
      (beads-test--set-issues
       nil
       (cl-loop for n from 1 to 9
                collect (beads-test--issue (format "r-%d" n) 2
                                           (format "Ready issue %d" n))))
      (magit-refresh-buffer)
      (should (equal (beads-test--section-problems) nil))
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (should (string-search "Ready (9)" text))
        (should (string-search "…and 6 more" text))))))

(ert-deftest beads-test-tree-problems-catch-a-moved-insertion-point ()
  "The invariant is red-capable: it reports a refresh whose point was moved.
Something else making the status buffer current and moving point - a
diff-hl thread, in dot-emacs-l3y - leaves the buffer rotated.  Simulate
that and the checker must notice; otherwise the tests above prove nothing."
  (beads-test--with-status
    (beads-test--set-issues
     nil
     (list (beads-test--issue "r-1" 1 "A ready issue")
           (beads-test--issue "r-2" 2 "Another ready issue")))
    (advice-add 'beads--insert-issue :before #'beads-test--jump-to-top)
    (unwind-protect
        (progn
          (magit-refresh-buffer)
          (should (beads-test--section-problems)))
      (advice-remove 'beads--insert-issue #'beads-test--jump-to-top))
    ;; And it goes quiet again once nothing moves point.
    (magit-refresh-buffer)
    (should (equal (beads-test--section-problems) nil))))

(defun beads-test--jump-to-top (&rest _)
  "Move point to the top of the buffer, as a foreign thread would."
  (goto-char (point-min)))

(provide 'beads-test)

;;; beads-test.el ends here
