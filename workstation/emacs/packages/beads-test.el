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

(cl-defun beads-test--issue (id priority title &optional assignee
                                &key parent dependencies dependents (status "open"))
  "Return the JSON of one issue, as bd prints it.
PARENT is the id of the issue's parent, DEPENDENCIES the number of
dependency edges it has and DEPENDENTS the number of issues depending on
it -- the three fields the relation marks are built from."
  (json-serialize
   (append `((id . ,id)
             (title . ,title)
             (description . ,(format "Description of %s, long enough to be
filled over more than one line when it is inserted." id))
             (status . ,status)
             (priority . ,priority)
             (assignee . ,(or assignee :null))
             (dependency_count . ,(or dependencies 0))
             (dependent_count . ,(or dependents 0)))
           (and parent `((parent . ,parent))))))

(defun beads-test--set-issues (in-progress ready)
  "Make the fake bd print IN-PROGRESS and READY, each a list of issue JSON."
  (beads-test--write "fake-bd/in_progress.json"
                     (concat "[" (string-join in-progress ",") "]"))
  (beads-test--write "fake-bd/ready.json"
                     (concat "[" (string-join ready ",") "]")))

(defun beads-test--set-relations (&optional blocked targets)
  "Make the fake bd answer the relation calls.
BLOCKED is an alist of issue id to a list of blocker ids, as
`bd blocked --json\=' reports it; TARGETS is a list of issue JSON, as
`bd list --id=... --all --json\=' returns it."
  (beads-test--write
   "fake-bd/blocked.json"
   (concat "["
           (string-join
            (mapcar (lambda (entry)
                      (json-serialize
                       `((id . ,(car entry))
                         (blocked_by . ,(vconcat (cdr entry)))
                         (blocked_by_count . ,(length (cdr entry))))))
                    blocked)
            ",")
           "]"))
  (beads-test--write "fake-bd/resolve.json"
                     (concat "[" (string-join targets ",") "]")))

(defun beads-test--set-show (&optional issues)
  "Make the fake bd print ISSUES for `bd show\=', as a list of issue JSON."
  (beads-test--write "fake-bd/show.json"
                     (concat "[" (string-join issues ",") "]")))

(defun beads-test--fail (command)
  "Make the fake bd fail COMMAND, one of `blocked\=' or `resolve\='."
  (beads-test--write (format "fake-bd/fail-%s" command) ""))

(defun beads-test--calls ()
  "Return the argument lines of every fake bd invocation so far."
  (let ((file (expand-file-name "fake-bd/calls" beads-test--repo)))
    (and (file-exists-p file)
         (with-temp-buffer
           (insert-file-contents file)
           (split-string (buffer-string) "\n" t)))))

(defun beads-test--forget-calls ()
  "Forget the fake bd invocations recorded so far."
  (beads-test--write "fake-bd/calls" ""))

(defmacro beads-test--with-repo (&rest body)
  "Run BODY in a fresh repository with a fake bd first on PATH."
  (declare (indent 0))
  `(let* ((beads-test--repo (file-name-as-directory
                             (make-temp-file "beads-test" t)))
          (default-directory beads-test--repo)
          (bin (expand-file-name "fake-bin" beads-test--repo))
          ;; The jump history is global and outlives a buffer, so each test
          ;; gets its own rather than inheriting the last one's.
          (beads--jump-history nil)
          (process-environment (cons (format "PATH=%s:%s" bin (getenv "PATH"))
                                     process-environment))
          (exec-path (cons bin exec-path)))
     (unwind-protect
         (progn
           (make-directory bin t)
           (make-directory (expand-file-name ".beads" beads-test--repo) t)
           ;; A bd that prints the two lists the section asks for, and bd's
           ;; own stderr noise, so the parsing path is the real one.
           (let ((bd (expand-file-name "bd" bin))
                 (fake (concat beads-test--repo "fake-bd/")))
             (with-temp-file bd
               (insert "#!/bin/sh\n"
                       "echo \"$@\" >> " fake "calls\n"
                       "echo 'warning: beads.role not configured' >&2\n"
                       ;; `list' answers two different questions: the claimed
                       ;; issues, and the records of the ids a relation names.
                       "if [ \"$1\" = list ]; then\n"
                       "  for a in \"$@\"; do\n"
                       "    case \"$a\" in\n"
                       "      --id=*)\n"
                       "        [ -f " fake "fail-resolve ] &&"
                       " { echo 'Error: bd list failed' >&2; exit 1; }\n"
                       "        cat " fake "resolve.json; exit 0 ;;\n"
                       "    esac\n"
                       "  done\n"
                       "fi\n"
                       "case \"$1\" in\n"
                       "  list)  cat " fake "in_progress.json ;;\n"
                       "  ready) cat " fake "ready.json ;;\n"
                       "  blocked)\n"
                       "    [ -f " fake "fail-blocked ] &&"
                       " { echo 'Error: bd blocked failed' >&2; exit 1; }\n"
                       "    cat " fake "blocked.json ;;\n"
                       "  show)  cat " fake "show.json ;;\n"
                       "  *)     echo '[]' ;;\n"
                       "esac\n"))
             (set-file-modes bd #o755))
           (beads-test--set-issues nil nil)
           (beads-test--set-relations nil nil)
           (beads-test--set-show nil)
           (beads-test--forget-calls)
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

(ert-deftest beads-test-refresh-in-an-unselected-window ()
  "A refresh of a displayed but unselected window keeps the tree consistent.
This is dot-emacs-l3y itself.  `window-max-chars-per-line\' is implemented
with `with-selected-window\', and selecting a window sets its buffer\'s
point to that window\'s point.  Measuring the width that way while Magit
rebuilt the buffer dragged the insertion point back to the window\'s stale
position, so every issue line landed at the top of the buffer and the
sections came out interleaved.  It only bit when the status window was not
the selected one, which is the normal case for the auto-refresh timer, and
never when the user pressed `g\' in that window."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"))
     (cl-loop for n from 1 to 4
              collect (beads-test--issue (format "r-%d" n) 2
                                         (format "Ready issue %d" n))))
    (let ((status (current-buffer))
          (elsewhere (get-buffer-create "*beads-test-elsewhere*")))
      (delete-other-windows)
      (set-window-buffer (selected-window) elsewhere)
      (let ((window (split-window)))
        (set-window-buffer window status)
        ;; What `erase-buffer\' leaves behind at the start of a refresh.
        (set-window-point window 1)
        (with-current-buffer status
          (magit-refresh-buffer)
          (should (equal (beads-test--section-problems) nil))
          (should (string-search "Ready (4)"
                                 (buffer-substring-no-properties
                                  (point-min) (point-max)))))))))

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

(ert-deftest beads-test-marks-name-the-relations ()
  "Parent, blockers and dependents are marked, and named in the body."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"
                              :parent "t-epic" :dependencies 2))
     (list (beads-test--issue "t-2" 2 "A ready issue" nil :dependents 3)))
    (beads-test--set-relations
     '(("t-1" "t-b1" "t-b2"))
     (list (beads-test--issue "t-epic" 1 "The epic")
           (beads-test--issue "t-b1" 2 "First blocker")
           (beads-test--issue "t-b2" 0 "Second blocker" nil :status "in_progress")))
    (magit-refresh-buffer)
    (magit-section-show-children magit-root-section)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      ;; The heading marks, visible without unfolding anything.
      (should (string-match-p "t-1  P1  ↑ ⊘2  A claimed issue" text))
      (should (string-match-p "t-2  P2  ↳3  A ready issue" text))
      ;; The body names the issues the marks stand for.
      (should (string-search "Parent:     t-epic  The epic" text))
      (should (string-search "Blocked by: t-b1  (open)  First blocker" text))
      (should (string-search "t-b2  (in_progress)  Second blocker" text)))))

(ert-deftest beads-test-a-closed-dependency-is-not-a-blocker ()
  "An issue whose dependencies are all closed carries no blocked mark.
bd leaves such an issue out of `bd blocked\=', and this file asks bd
rather than deciding for itself, so there is nothing here to get wrong --
which is the property worth pinning down."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test" :dependencies 1))
     nil)
    ;; bd was asked, and reported nothing blocked.
    (beads-test--set-relations nil nil)
    (magit-refresh-buffer)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (should (string-search "t-1" text))
      (should-not (string-search "⊘" text))
      (should-not (string-search "Blocked by:" text)))))

(ert-deftest beads-test-a-relation-free-issue-is-untouched ()
  "An issue that takes part in nothing looks exactly as it did before.
Not `roughly as it did\=': the marks must add no separator, no column and
no line to an issue that has no relations."
  (beads-test--with-status
    (beads-test--set-issues nil (list (beads-test--issue "r-1" 2 "A ready issue")))
    (magit-refresh-buffer)
    (goto-char (point-min))
    (should (re-search-forward "^  r-1  P2  A ready issue$" nil t))))

(ert-deftest beads-test-an-unresolved-relation-says-so ()
  "A relation whose issue bd does not return is marked unknown, not dropped."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"
                              :parent "t-gone" :dependencies 1))
     nil)
    ;; bd answers both calls, and knows nothing about either id.
    (beads-test--set-relations '(("t-1" "t-vanished")) nil)
    (magit-refresh-buffer)
    (magit-section-show-children magit-root-section)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (should (string-match-p "t-1  P1  ↑ ⊘1" text))
      (should (string-search "Parent:     t-gone  (unknown)" text))
      (should (string-search "Blocked by: t-vanished  (unknown)" text)))))

(ert-deftest beads-test-blockers-past-the-relation-limit-are-summarized ()
  "A long list of blockers is capped in the body and counted on the heading."
  (beads-test--with-status
    (let ((beads-relation-limit 2))
      (beads-test--set-issues
       (list (beads-test--issue "t-1" 1 "A claimed issue" "Test" :dependencies 5))
       nil)
      (beads-test--set-relations
       '(("t-1" "b-1" "b-2" "b-3" "b-4" "b-5"))
       (cl-loop for n from 1 to 5
                collect (beads-test--issue (format "b-%d" n) 2
                                           (format "Blocker %d" n))))
      (magit-refresh-buffer)
      (magit-section-show-children magit-root-section)
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (should (string-search "⊘5" text))
        (should (string-search "Blocker 1" text))
        (should (string-search "Blocker 2" text))
        (should-not (string-search "Blocker 3" text))
        (should (string-search "…and 3 more" text))))))

(ert-deftest beads-test-tree-stays-consistent-with-marks ()
  "The marks add text to exactly the headings dot-emacs-l3y mangled.
So the structural invariant has to be re-asserted with them in place,
across refreshes whose relations change."
  (beads-test--with-status
    (dotimes (i 4)
      (beads-test--set-issues
       (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"
                                :parent "t-epic" :dependencies (mod i 2)))
       (cl-loop for n from 1 to (+ 2 i)
                collect (beads-test--issue (format "r-%d" n) 2
                                           (format "Ready issue %d" n)
                                           nil :dependents (mod n 3))))
      (beads-test--set-relations
       (and (cl-oddp i) '(("t-1" "t-b1")))
       (list (beads-test--issue "t-epic" 1 "The epic")
             (beads-test--issue "t-b1" 2 "A blocker")))
      (magit-refresh-buffer)
      (magit-section-show-children magit-root-section)
      (should (equal (beads-test--section-problems) nil)))))

(ert-deftest beads-test-no-relations-means-no-extra-bd-call ()
  "A tracker whose listed issues have no relations pays nothing for them.
The two calls the section has always made, and not one more: no
`blocked\=', no `list --id=\='."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test"))
     (list (beads-test--issue "t-2" 2 "A ready issue")))
    (beads-test--forget-calls)
    (magit-refresh-buffer)
    (let ((calls (beads-test--calls)))
      (should (equal calls '("list --status=in_progress --json -n 0"
                             "ready --json -n 0"))))))

(ert-deftest beads-test-relations-cost-two-calls-however-many-issues ()
  "With relations the section makes two extra calls, and only two.
Not one per issue: the blocked set is one question, and every id a
relation names is resolved in a single `list --id=\='."
  (beads-test--with-status
    (beads-test--set-issues
     (cl-loop for n from 1 to 12
              collect (beads-test--issue (format "t-%d" n) 2
                                         (format "Claimed issue %d" n)
                                         "Test" :parent "t-epic" :dependencies 1))
     nil)
    (beads-test--set-relations
     (cl-loop for n from 1 to 12 collect (list (format "t-%d" n) "t-b1"))
     (list (beads-test--issue "t-epic" 1 "The epic")
           (beads-test--issue "t-b1" 2 "A blocker")))
    (beads-test--forget-calls)
    (magit-refresh-buffer)
    (let ((calls (beads-test--calls)))
      (should (equal (length calls) 4))
      (should (equal (nth 2 calls) "blocked --json"))
      (should (string-prefix-p "list --id=" (nth 3 calls))))))

(defun beads-test--goto (id)
  "Put point on the section listing the issue ID, erroring when there is none."
  (goto-char (point-min))
  (let ((section (beads--section-for id)))
    (unless section (error "No section for %s" id))
    (goto-char (oref section start))))

(defmacro beads-test--with-related (&rest body)
  "Run BODY in a status buffer listing an epic, a child and a blocker.
The child is claimed, has the epic as its parent and is blocked by the
blocker; the epic and the blocker are ready and each has one dependent."
  (declare (indent 0))
  `(beads-test--with-status
     (beads-test--set-issues
      (list (beads-test--issue "t-child" 2 "The child" "Test"
                               :parent "t-epic" :dependencies 2))
      (list (beads-test--issue "t-epic" 1 "The epic" nil :dependents 1)
            (beads-test--issue "t-block" 2 "The blocker" nil :dependents 1)))
     (beads-test--set-relations
      '(("t-child" "t-block"))
      (list (beads-test--issue "t-epic" 1 "The epic")
            (beads-test--issue "t-block" 2 "The blocker")))
     (magit-refresh-buffer)
     ,@body))

(ert-deftest beads-test-goto-lands-in-place-on-a-listed-issue ()
  "A relation whose issue is already listed is moved to, not reopened."
  (beads-test--with-related
    (beads-test--goto "t-child")
    (beads-goto-parent)
    (should (equal (beads--issue-at-point) "t-epic"))
    ;; In this very buffer: no second view of something three lines up.
    (should (derived-mode-p 'magit-status-mode))
    (should-not (get-buffer "*beads: t-epic*"))))

(ert-deftest beads-test-goto-opens-an-unlisted-issue ()
  "A relation whose issue is not listed opens in its own buffer."
  (beads-test--with-related
    (beads-test--set-show (list (beads-test--issue "t-gone" 2 "Not listed")))
    (beads-test--set-relations
     '(("t-child" "t-gone"))
     (list (beads-test--issue "t-epic" 1 "The epic")
           (beads-test--issue "t-gone" 2 "Not listed" nil :status "closed")))
    (magit-refresh-buffer)
    (beads-test--goto "t-child")
    (unwind-protect
        (progn
          (beads-goto-blocker)
          (should (get-buffer "*beads: t-gone*"))
          (with-current-buffer "*beads: t-gone*"
            (should (derived-mode-p 'beads-show-mode))
            (should (equal beads--issue "t-gone"))))
      (when-let* ((buffer (get-buffer "*beads: t-gone*")))
        (let ((kill-buffer-query-functions nil)) (kill-buffer buffer))))))

(ert-deftest beads-test-goto-without-the-relation-changes-nothing ()
  "A jump the issue has no relation for reports it and leaves the buffer alone."
  (beads-test--with-related
    (beads-test--goto "t-epic")
    (let ((point (point))
          (text (buffer-substring-no-properties (point-min) (point-max)))
          (history beads--jump-history))
      (should-error (beads-goto-parent) :type 'user-error)
      (should (equal (point) point))
      (should (equal (buffer-substring-no-properties (point-min) (point-max)) text))
      ;; Nothing happened, so there is nothing to come back from either.
      (should (eq beads--jump-history history)))))

(ert-deftest beads-test-goto-dependent-reads-them-on-demand ()
  "The dependents of an issue are fetched when asked for, not on refresh."
  (beads-test--with-related
    (beads-test--set-show
     (list (json-serialize
            `((id . "t-epic")
              (title . "The epic")
              (dependent_count . 1)
              (dependents . [((id . "t-child")
                              (title . "The child")
                              (status . "in_progress")
                              (dependency_type . "parent-child"))])))))
    (beads-test--goto "t-epic")
    (beads-test--forget-calls)
    (beads-goto-dependent)
    (should (equal (beads--issue-at-point) "t-child"))
    (should (equal (beads-test--calls)
                   '("show t-epic --json --include-dependents")))))

(ert-deftest beads-test-goto-dependent-reaches-uncounted-children ()
  "An epic\='s children are reachable even though the listing counts none.
`bd list\=' and `bd ready\=' count only `blocks\=' dependents, so an epic of
seven tasks arrives with `dependent_count\=' zero and carries no mark.
`bd show --include-dependents\=' counts the children too, and the command
asks that question rather than the mark\='s."
  (beads-test--with-related
    (beads-test--set-show
     (list (json-serialize
            `((id . "t-epic")
              (title . "The epic")
              (dependent_count . 0)
              (dependents . [((id . "t-child")
                              (title . "The child")
                              (status . "in_progress")
                              (dependency_type . "parent-child"))])))))
    ;; The epic is listed with nothing depending on it, so it has no mark.
    (beads-test--set-issues
     (list (beads-test--issue "t-child" 2 "The child" "Test" :parent "t-epic"))
     (list (beads-test--issue "t-epic" 1 "The epic")))
    (beads-test--set-relations nil (list (beads-test--issue "t-epic" 1 "The epic")))
    (magit-refresh-buffer)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (should-not (string-search "↳" text)))
    (beads-test--goto "t-epic")
    (should-not (beads--has-dependents-p))
    ;; And the child is still reachable.
    (beads-goto-dependent)
    (should (equal (beads--issue-at-point) "t-child"))))

(ert-deftest beads-test-a-cycle-does-not-loop ()
  "A blocks B and B blocks A: each shows its own relations, and jumps end."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-a" 2 "Issue A" "Test" :dependencies 1 :dependents 1)
           (beads-test--issue "t-b" 2 "Issue B" "Test" :dependencies 1 :dependents 1))
     nil)
    (beads-test--set-relations
     '(("t-a" "t-b") ("t-b" "t-a"))
     (list (beads-test--issue "t-a" 2 "Issue A")
           (beads-test--issue "t-b" 2 "Issue B")))
    (magit-refresh-buffer)
    (magit-section-show-children magit-root-section)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      ;; Each issue names the other once, and neither names itself.
      (should (equal 1 (cl-count "Blocked by: t-b  (open)  Issue B" (split-string text "\n")
                                 :test (lambda (a b) (string-search a b)))))
      (should (equal 1 (cl-count "Blocked by: t-a  (open)  Issue A" (split-string text "\n")
                                 :test (lambda (a b) (string-search a b))))))
    (beads-test--goto "t-a")
    (beads-goto-blocker)
    (should (equal (beads--issue-at-point) "t-b"))
    (beads-goto-blocker)
    (should (equal (beads--issue-at-point) "t-a"))))

(ert-deftest beads-test-go-back-retraces-the-jumps ()
  "Two jumps and two returns land on the issues they started from."
  (beads-test--with-related
    (beads-test--set-show
     (list (json-serialize
            `((id . "t-block")
              (title . "The blocker")
              (dependent_count . 1)
              (dependents . [((id . "t-child")
                              (title . "The child")
                              (status . "in_progress")
                              (dependency_type . "blocks"))])))))
    (beads-test--goto "t-child")
    (beads-goto-parent)
    (should (equal (beads--issue-at-point) "t-epic"))
    (beads-test--goto "t-block")
    (beads-goto-dependent)
    (should (equal (beads--issue-at-point) "t-child"))
    (beads-go-back)
    (should (equal (beads--issue-at-point) "t-block"))
    (beads-go-back)
    (should (equal (beads--issue-at-point) "t-child"))))

(ert-deftest beads-test-go-back-with-nowhere-to-go ()
  "Going back without having jumped says so and changes nothing."
  (beads-test--with-related
    (beads-test--goto "t-child")
    (let ((point (point)))
      (should-error (beads-go-back) :type 'user-error)
      (should (equal (point) point)))))

(ert-deftest beads-test-go-back-skips-a-killed-buffer ()
  "An entry whose buffer is gone is stepped over, not reported."
  (beads-test--with-related
    (beads-test--goto "t-child")
    ;; A jump that started in a buffer which no longer exists.
    (let ((dead (get-buffer-create "*beads-test-dead*")))
      (with-current-buffer dead
        (beads--push-location dead (point-marker)))
      (let ((kill-buffer-query-functions nil)) (kill-buffer dead)))
    (beads-goto-parent)
    (should (equal (beads--issue-at-point) "t-epic"))
    (beads-go-back)
    (should (equal (beads--issue-at-point) "t-child"))
    (should-error (beads-go-back) :type 'user-error)))

(ert-deftest beads-test-transient-greys-out-what-does-not-apply ()
  "The relation entries are present on every issue, and inapt on some.
Present is the point: an entry that vanished when it did not apply would
make the menu a different shape for every issue."
  (beads-test--with-related
    (let ((suffixes (lambda ()
                      (mapcar (lambda (entry) (cons (car entry) (funcall (cdr entry))))
                              `(("p" . ,#'beads--has-parent-p)
                                ("b" . ,#'beads--has-blockers-p)
                                ("d" . ,#'beads--has-dependents-p)
                                ("B" . ,#'beads--went-somewhere-p))))))
      (beads-test--goto "t-child")
      (should (equal (funcall suffixes)
                     '(("p" . t) ("b" . t) ("d" . nil) ("B" . nil))))
      (beads-test--goto "t-epic")
      (should (equal (funcall suffixes)
                     '(("p" . nil) ("b" . nil) ("d" . t) ("B" . nil))))
      ;; And a jump makes going back apply.
      (beads-test--goto "t-child")
      (beads-goto-parent)
      (should (equal (cdr (assoc "B" (funcall suffixes))) t)))
    ;; The entries themselves are in the prefix, all four of them.
    (pcase-dolist (`(,key . ,command)
                   '(("p" . beads-goto-parent)
                     ("b" . beads-goto-blocker)
                     ("d" . beads-goto-dependent)
                     ("B" . beads-go-back)))
      (should (memq command
                    (flatten-tree (transient-get-suffix 'beads-dispatch key)))))))

(ert-deftest beads-test-relation-failure-keeps-the-listing ()
  "A relation call that fails costs the marks, not the issues.
The section is for the issues; their relations are a garnish that has to
be able to go missing without taking the listing with it."
  (beads-test--with-status
    (beads-test--set-issues
     (list (beads-test--issue "t-1" 1 "A claimed issue" "Test" :dependencies 1))
     (list (beads-test--issue "t-2" 2 "A ready issue")))
    (beads-test--fail "blocked")
    (magit-refresh-buffer)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (should (string-search "Beads issues (2)" text))
      (should (string-search "t-1" text))
      (should (string-search "t-2" text))
      (should (string-search "Relations unavailable" text))
      (should-not (string-search "⊘" text)))
    (should (equal (beads-test--section-problems) nil))))

(defun beads-test--jump-to-top (&rest _)
  "Move point to the top of the buffer, as a foreign thread would."
  (goto-char (point-min)))

;;;; Prompting the agent

(defvar beads-test--agent-calls nil
  "The (TEXT . SUBMIT) pairs the fake agent received, in call order.")

(defvar beads-test--agent-up t
  "Whether the fake agent reports a session.")

(defmacro beads-test--with-agent (&rest body)
  "Run BODY with a recording fake agent in place of the real one.
The agent's buffer is *fake-agent*; what it was sent is in
`beads-test--agent-calls'."
  (declare (indent 0))
  `(let* ((beads-test--agent-calls nil)
          (beads-test--agent-up t)
          (beads-agent-available-function (lambda () beads-test--agent-up))
          (beads-agent-send-function
           (lambda (text submit)
             (setq beads-test--agent-calls
                   (append beads-test--agent-calls (list (cons text submit))))
             (get-buffer-create "*fake-agent*"))))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buffer (get-buffer "*fake-agent*")))
         (let ((kill-buffer-query-functions nil)) (kill-buffer buffer))))))

(defmacro beads-test--with-two-ready (&rest body)
  "Run BODY in a status buffer listing two ready issues, t-one and t-two."
  (declare (indent 0))
  `(beads-test--with-status
     (beads-test--set-issues
      nil
      (list (beads-test--issue "t-one" 1 "The first")
            (beads-test--issue "t-two" 2 "The second")))
     (magit-refresh-buffer)
     ,@body))

(defun beads-test--select-both ()
  "Activate a region spanning the sections of t-one and t-two."
  (transient-mark-mode 1)
  (beads-test--goto "t-one")
  (push-mark (point) t t)
  (goto-char (oref (beads--section-for "t-two") start)))

(defmacro beads-test--in-show-buffer (id &rest body)
  "Run BODY in a `beads-show-mode' buffer displaying ID, then kill it."
  (declare (indent 1))
  `(progn
     (beads-test--set-show (list (beads-test--issue ,id 2 "Shown")))
     (beads-show ,id)
     (unwind-protect
         (with-current-buffer (format "*beads: %s*" ,id) ,@body)
       (when-let* ((buffer (get-buffer (format "*beads: %s*" ,id))))
         (let ((kill-buffer-query-functions nil)) (kill-buffer buffer))))))

(ert-deftest beads-test-agent-prompt-names-the-issue ()
  "The quick prompt pastes the id unsent and hands focus to the agent."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (beads-test--goto "t-one")
      (beads-agent-prompt)
      (should (equal beads-test--agent-calls '(("Beads issue t-one: " . nil))))
      (should (equal (buffer-name (window-buffer (selected-window)))
                     "*fake-agent*")))))

(ert-deftest beads-test-agent-prompt-takes-the-region ()
  "Every issue in the region is named, in the order they are listed."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (beads-test--select-both)
      (beads-agent-prompt)
      (should (equal beads-test--agent-calls
                     '(("Beads issue t-one, t-two: " . nil)))))))

(ert-deftest beads-test-agent-prompt-from-a-show-buffer ()
  "In an issue's own buffer the quick prompt names that issue."
  (beads-test--with-status
    (beads-test--with-agent
      (beads-test--in-show-buffer "t-shown"
        (beads-agent-prompt)
        (should (equal beads-test--agent-calls
                       '(("Beads issue t-shown: " . nil))))))))

(ert-deftest beads-test-agent-prompt-refuses-without-issue ()
  "Off an issue nothing is sent, and no issue is asked for."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (goto-char (point-min))
      (should-error (beads-agent-prompt) :type 'user-error)
      (should-not beads-test--agent-calls))))

(ert-deftest beads-test-agent-prompt-refuses-without-agent ()
  "Without a session nothing is sent and the window stays."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (setq beads-test--agent-up nil)
      (beads-test--goto "t-one")
      (let ((window-buffer (window-buffer (selected-window))))
        (should (equal (cadr (should-error (beads-agent-prompt)
                                           :type 'user-error))
                       "No agent session for this repository"))
        (should-not beads-test--agent-calls)
        (should (eq (window-buffer (selected-window)) window-buffer))))))

(ert-deftest beads-test-agent-quick-prompt-default-is-plain-text ()
  "The default does not start with a character Claude Code treats specially."
  (should-not (string-match-p "\\`[/!#]"
                              (default-value 'beads-agent-quick-prompt-format))))

(ert-deftest beads-test-agent-explore-submits-the-prompt ()
  "Explore submits the prepared prompt with the id filled in."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (beads-test--goto "t-one")
      (beads-agent-explore)
      (should (= (length beads-test--agent-calls) 1))
      (pcase-let ((`(,text . ,submit) (car beads-test--agent-calls)))
        (should (eq submit t))
        (should (string-search "Explore beads issue t-one" text))
        (should (string-search "bd show t-one" text))
        (should-not (string-search "%i" text))))))

(ert-deftest beads-test-agent-explore-leaves-windows-alone ()
  "Explore changes no window and says where the prompt went."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (beads-test--goto "t-one")
      ;; The echo area is not there in batch mode, so the message is read
      ;; back from the log instead.
      (let ((before (current-window-configuration))
            (logged (with-current-buffer (messages-buffer) (point-max))))
        (beads-agent-explore)
        (should (compare-window-configurations
                 before (current-window-configuration)))
        (should (with-current-buffer (messages-buffer)
                  (save-excursion
                    (goto-char logged)
                    (search-forward
                     "Sent explore prompt for t-one to *fake-agent*" nil t))))))))

(ert-deftest beads-test-agent-explore-from-a-show-buffer ()
  "In an issue's own buffer explore works on that issue."
  (beads-test--with-status
    (beads-test--with-agent
      (beads-test--in-show-buffer "t-shown"
        (beads-agent-explore)
        (should (string-search "bd show t-shown"
                               (caar beads-test--agent-calls)))))))

(ert-deftest beads-test-agent-explore-refuses-a-region ()
  "Explore takes one issue, and says so rather than picking one."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (beads-test--select-both)
      (should (string-match-p
               "Explore works on one issue; the region covers 2"
               (cadr (should-error (beads-agent-explore) :type 'user-error))))
      (should-not beads-test--agent-calls))))

(ert-deftest beads-test-agent-explore-refuses-without-issue ()
  "Off an issue explore sends nothing."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (goto-char (point-min))
      (should-error (beads-agent-explore) :type 'user-error)
      (should-not beads-test--agent-calls))))

(ert-deftest beads-test-agent-explore-refuses-without-agent ()
  "Without a session explore sends nothing."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (setq beads-test--agent-up nil)
      (beads-test--goto "t-one")
      (should-error (beads-agent-explore) :type 'user-error)
      (should-not beads-test--agent-calls))))

(ert-deftest beads-test-agent-explore-adds-a-missing-id ()
  "A customised prompt without %i still names the issue, and a stray % is text."
  (beads-test--with-two-ready
    (beads-test--with-agent
      (let ((beads-agent-explore-prompt "Look at this 100% carefully"))
        (beads-test--goto "t-one")
        (beads-agent-explore)
        (should (equal (caar beads-test--agent-calls)
                       "Beads issue t-one:\n\nLook at this 100% carefully"))))))

(ert-deftest beads-test-agent-explore-default-keeps-its-clauses ()
  "The default prompt keeps every clause the spec asks of it.
See specs/003-beads-agent-prompts/contracts/explore-prompt.md."
  (let ((prompt (default-value 'beads-agent-explore-prompt)))
    (dolist (phrase '("bd show %i" "comments" "parts of this repository"
                      "each as a" "question" "say so plainly"
                      "Do not implement anything" "Do not commit"
                      "stop and wait"))
      (should (string-search phrase prompt)))
    (should-not (string-match-p "\\`[/!#]" prompt))))

(ert-deftest beads-test-transient-offers-the-agent ()
  "Both agent entries are in the menu, and grey without a session."
  (should (memq 'beads-agent-prompt
                (flatten-tree (transient-get-suffix 'beads-dispatch "i"))))
  (should (memq 'beads-agent-explore
                (flatten-tree (transient-get-suffix 'beads-dispatch "e"))))
  (beads-test--with-two-ready
    (beads-test--with-agent
      (should (eq (beads--agent-available-p) t))
      (setq beads-test--agent-up nil)
      (should-not (beads--agent-available-p)))
    ;; With no agent configured the check asks nobody.
    (let* ((asked nil)
           (beads-agent-available-function (lambda () (setq asked t)))
           (beads-agent-send-function nil))
      (should-not (beads--agent-available-p))
      (should-not asked))))

(provide 'beads-test)

;;; beads-test.el ends here
