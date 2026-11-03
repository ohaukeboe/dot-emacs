;; -*- lexical-binding: t; -*-
;;; walkthrough-test.el --- ERT suite for walkthrough.el

;;; Commentary:

;; Run with `nix build .#test-walkthrough -L' (tests/walkthrough.nix), or
;; locally with
;;
;;   emacs -batch -L . -l walkthrough-test.el -f ert-run-tests-batch-and-exit
;;
;; Every test runs in a throwaway repository built by
;; `walkthrough-test--with-repo': `main' has a.el (250 lines) and c.el, and
;; the branch `feat/x' adds three commits on top -- b.el is added, a.el is
;; changed near line 10 and near line 200 (two hunks far apart), c.el is
;; deleted and the binary img.bin is added.

;;; Code:

(require 'ert)
(require 'walkthrough)

(defvar walkthrough-test--repo nil
  "Toplevel of the current test repository.")

(defun walkthrough-test--git (&rest args)
  "Run git with ARGS in `default-directory', signalling on failure.
Return its trimmed standard output."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s failed: %s" (string-join args " ") (buffer-string)))
      (string-trim (buffer-string)))))

(defun walkthrough-test--write (file content)
  "Write CONTENT to FILE, relative to `default-directory'."
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert content))))

(defun walkthrough-test--lines (n &optional change)
  "Return N lines \"line I\", with line numbers in CHANGE edited."
  (mapconcat (lambda (i)
               (if (memq i change)
                   (format "line %d changed\n" i)
                 (format "line %d\n" i)))
             (number-sequence 1 n) ""))

(defmacro walkthrough-test--with-repo (&rest body)
  "Run BODY in a fresh fixture repository with `base' and `head' bound."
  (declare (indent 0))
  `(let* ((walkthrough-test--repo (file-name-as-directory
                                   (file-truename
                                    (make-temp-file "walkthrough-test" t))))
          (default-directory walkthrough-test--repo)
          (magit-refresh-verbose nil))
     (unwind-protect
         (progn
           (walkthrough-test--git "init" "--quiet" "-b" "main" ".")
           (walkthrough-test--write "a.el" (walkthrough-test--lines 250))
           (walkthrough-test--write "c.el" "to be deleted\n")
           (walkthrough-test--git "add" ".")
           (walkthrough-test--git "commit" "--quiet" "-m" "base")
           (walkthrough-test--git "checkout" "--quiet" "-b" "feat/x")
           (walkthrough-test--write "b.el" "new file\nsecond line\n")
           (walkthrough-test--write "a.el" (walkthrough-test--lines 250 '(10)))
           (walkthrough-test--git "add" ".")
           (walkthrough-test--git "commit" "--quiet" "-m" "one")
           (walkthrough-test--write "a.el" (walkthrough-test--lines 250 '(10 200)))
           (walkthrough-test--git "rm" "--quiet" "c.el")
           (walkthrough-test--git "add" ".")
           (walkthrough-test--git "commit" "--quiet" "-m" "two")
           (walkthrough-test--write "img.bin" (string 0 1 2 255 0 3))
           (walkthrough-test--git "add" ".")
           (walkthrough-test--git "commit" "--quiet" "-m" "three")
           (let ((base (walkthrough-test--git "rev-parse" "main"))
                 (head (walkthrough-test--git "rev-parse" "HEAD")))
             (ignore base head)
             ,@body))
       (dolist (buffer (buffer-list))
         (with-current-buffer buffer
           (when (and (derived-mode-p 'magit-mode)
                      (string-prefix-p walkthrough-test--repo
                                       (expand-file-name default-directory)))
             (let ((kill-buffer-query-functions nil))
               (kill-buffer buffer)))))
       (delete-directory walkthrough-test--repo t))))

(defun walkthrough-test--draft (base head &rest overrides)
  "Return a valid draft alist for the fixture between BASE and HEAD.
OVERRIDES is a plist of top-level keys to replace, e.g. :steps."
  (let ((draft
         `((version . 1)
           (title . "Fixture change")
           (branch . "feat/x")
           (base . ,base)
           (head . ,head)
           (steps
            . [((title . "Core")
                (explanation . "Adds `b.el` and changes a.el near the top.")
                (files . [((file . "a.el") (ranges . [[1 50]])) "b.el"])
                (findings
                 . [((severity . "high")
                     (title . "Line 10 is wrong")
                     (body . "The changed line breaks the count.")
                     (failure_scenario . "Read line 10, get the wrong value.")
                     (verdict . "CONFIRMED")
                     (anchor . ((file . "a.el") (line . 10))))
                    ((severity . "low")
                     (title . "General remark")
                     (body . "Not tied to a line."))]))
               ((title . "Cleanup")
                (explanation . "Changes a.el near the end, deletes c.el, adds a binary.")
                (files . [((file . "a.el") (ranges . [[150 250]])) "c.el" "img.bin"])
                (findings . []))]))))
    ;; The quasi-quoted parts without a comma are shared constants, so
    ;; overriding in place would leak into every later test.
    (setq draft (copy-tree draft t))
    (cl-loop for (key value) on overrides by #'cddr
             do (setf (alist-get (intern (substring (symbol-name key) 1)) draft)
                      value))
    draft))

(defun walkthrough-test--write-draft (draft)
  "Write DRAFT as JSON to a temporary file and return its name."
  (let ((file (make-temp-file "walkthrough-draft" nil ".json"))
        (coding-system-for-write 'utf-8))
    (with-temp-file file
      (json-insert draft))
    file))

(defun walkthrough-test--step (title files &optional findings)
  "Return a step alist with TITLE, FILES (a vector) and FINDINGS."
  `((title . ,title)
    (explanation . "Explanation.")
    (files . ,files)
    (findings . ,(or findings []))))

(defun walkthrough-test--has-error (errors regexp)
  "Return non-nil when one of ERRORS matches REGEXP; fail otherwise."
  (or (seq-find (lambda (e) (string-match-p regexp e)) errors)
      (ert-fail (list "no error matching" regexp errors))))

;;; Parsing the diff

(ert-deftest walkthrough-test-parse-diff ()
  "One entry per file, in diff order, with each hunk's new-side span."
  (walkthrough-test--with-repo
    (let* ((files (walkthrough--parse-diff base head '("-U3")))
           (by-name (lambda (name)
                      (seq-find (lambda (f) (equal (plist-get f :file) name))
                                files))))
      (should (equal (mapcar (lambda (f) (plist-get f :file)) files)
                     '("a.el" "b.el" "c.el" "img.bin")))
      (should (equal (mapcar (lambda (h) (list (plist-get h :start)
                                               (plist-get h :length)))
                             (plist-get (funcall by-name "a.el") :hunks))
                     '((7 7) (197 7))))
      (should (equal (mapcar (lambda (h) (plist-get h :header))
                             (plist-get (funcall by-name "b.el") :hunks))
                     '("@@ -0,0 +1,2 @@")))
      ;; The deleted file is named by its old path, and its one hunk has no
      ;; lines on the new side.
      (should (equal (mapcar (lambda (h) (list (plist-get h :start)
                                               (plist-get h :length)))
                             (plist-get (funcall by-name "c.el") :hunks))
                     '((0 0))))
      (should (null (plist-get (funcall by-name "img.bin") :hunks))))))

(ert-deftest walkthrough-test-hunk-overlap ()
  "A hunk +c,d covers c..c+d-1; a hunk +c,0 covers the position c."
  (let ((hunk (lambda (start length) (list :start start :length length))))
    (should (walkthrough--hunk-overlaps-p (funcall hunk 7 7) '(1 7)))
    (should (walkthrough--hunk-overlaps-p (funcall hunk 7 7) '(13 20)))
    (should-not (walkthrough--hunk-overlaps-p (funcall hunk 7 7) '(14 20)))
    (should-not (walkthrough--hunk-overlaps-p (funcall hunk 7 7) '(1 6)))
    (should (walkthrough--hunk-overlaps-p (funcall hunk 12 0) '(12 20)))
    (should (walkthrough--hunk-overlaps-p (funcall hunk 12 0) '(1 12)))
    (should-not (walkthrough--hunk-overlaps-p (funcall hunk 12 0) '(13 20)))
    (should (walkthrough--hunk-overlaps-p (funcall hunk 12 1) '(12 12)))
    ;; Emptying a file gives +0,0, which no range starting at 1 would reach
    ;; if it covered line 0.
    (should (walkthrough--hunk-overlaps-p (funcall hunk 0 0) '(1 1)))
    (should-not (walkthrough--hunk-overlaps-p (funcall hunk 0 0) '(2 5)))))

;;; Validation

(ert-deftest walkthrough-test-validate-accepts-split-file ()
  "A valid draft, with a.el split across two steps by ranges, has no errors."
  (walkthrough-test--with-repo
    (should (null (walkthrough-validate (walkthrough-test--draft base head))))))

(ert-deftest walkthrough-test-validate-coverage ()
  "Missing, duplicated and conflicting hunks are named."
  (walkthrough-test--with-repo
    ;; b.el and the binary owned by nobody.
    (let ((errors (walkthrough-validate
                   (walkthrough-test--draft
                    base head
                    :steps (vector (walkthrough-test--step
                                    "Only a and c" ["a.el" "c.el"]))))))
      (walkthrough-test--has-error errors "^hunk b\\.el @@ -0,0 \\+1,2 @@: owned by no step$")
      (walkthrough-test--has-error errors "^file img\\.bin: owned by no step$"))
    ;; a.el whole in one step and by range in another.
    (let ((errors (walkthrough-validate
                   (walkthrough-test--draft
                    base head
                    :steps (vector (walkthrough-test--step
                                    "Whole" ["a.el" "b.el" "c.el" "img.bin"])
                                   (walkthrough-test--step
                                    "Range" [((file . "a.el") (ranges . [[1 20]]))]))))))
      (walkthrough-test--has-error
       errors "^steps\\[1\\]\\.files\\[0\\]: a\\.el is owned by steps\\[0\\] as a whole file$")
      (walkthrough-test--has-error
       errors "^hunk a\\.el @@ -7,7 \\+7,7 @@: owned by steps\\[0\\] and steps\\[1\\]$"))
    ;; A range on the binary file, which has no hunks to split.
    (let ((errors (walkthrough-validate
                   (walkthrough-test--draft
                    base head
                    :steps (vector (walkthrough-test--step
                                    "All" ["a.el" "b.el" "c.el"
                                           ((file . "img.bin") (ranges . [[1 1]]))]))))))
      (walkthrough-test--has-error
       errors "^steps\\[0\\]\\.files\\[3\\]: img\\.bin has no hunks to split; own it whole$"))
    ;; A file that is not changed at all.
    (let ((errors (walkthrough-validate
                   (walkthrough-test--draft
                    base head
                    :steps (vector (walkthrough-test--step
                                    "All" ["a.el" "b.el" "c.el" "img.bin" "z.el"]))))))
      (walkthrough-test--has-error
       errors "^steps\\[0\\]\\.files\\[4\\]: z\\.el is not changed between base and head$"))))

(ert-deftest walkthrough-test-validate-schema ()
  "Schema errors name the field."
  (walkthrough-test--with-repo
    (let ((errors (walkthrough-validate
                   (walkthrough-test--draft
                    base "0000000000000000000000000000000000000000"
                    :version 2 :title ""))))
      (walkthrough-test--has-error errors "^version: must be 1$")
      (walkthrough-test--has-error errors "^title: must be a non-empty string$")
      (walkthrough-test--has-error errors "^head: 0000000000000000000000000000000000000000 is not a commit$"))
    (let* ((bad-finding '((severity . "urgent") (title . "") (body . "x")
                          (anchor . ((file . "img.bin") (line . 1)))))
           (errors (walkthrough-validate
                    (walkthrough-test--draft
                     base head
                     :steps (vector
                             `((title . "")
                               (explanation . "x")
                               (files . ["a.el" "b.el" "c.el"
                                         ((file . "d.el") (ranges . [[5 2]]))])
                               (findings . [,bad-finding]))
                             (walkthrough-test--step "Rest" ["img.bin"]))))))
      (walkthrough-test--has-error errors "^steps\\[0\\]\\.title: must be a non-empty string$")
      (walkthrough-test--has-error errors "^steps\\[0\\]\\.files\\[3\\]\\.ranges\\[0\\]: \\[5, 2\\] must satisfy 1 <= start <= end$")
      (walkthrough-test--has-error errors "^steps\\[0\\]\\.findings\\[0\\]\\.severity: must be one of high, medium, low$")
      (walkthrough-test--has-error errors "^steps\\[0\\]\\.findings\\[0\\]\\.title: must be a non-empty string$")
      (walkthrough-test--has-error errors "^steps\\[0\\]\\.findings\\[0\\]\\.anchor\\.file: img\\.bin is not owned by this step$"))
    ;; A base that is not an ancestor of head.
    (let ((errors (walkthrough-validate (walkthrough-test--draft head base))))
      (walkthrough-test--has-error errors "^base: is not an ancestor of head$"))))

(ert-deftest walkthrough-test-validate-malformed ()
  "Values of the wrong type are errors that name the field, not signals."
  (walkthrough-test--with-repo
    (let* ((walkthrough-open-after-install nil)
           (finding (lambda (anchor)
                      `((severity . "low") (title . "t") (body . "b")
                        (anchor . ,anchor))))
           (result (walkthrough-install
                    (walkthrough-test--write-draft
                     (walkthrough-test--draft
                      base head
                      :steps (vector
                              "not a step"
                              (walkthrough-test--step
                               "Ranges" [((file . "a.el") (ranges . "10-20"))
                                         "b.el" "c.el" "img.bin"]
                               (vector (funcall finding "a.el:3")))
                              `((title . "Findings") (explanation . "x")
                                (files . ["b.el"]) (findings . "none"))
                              (walkthrough-test--step
                               "Finding" ["b.el"] ["just text"])))))))
      (should (eq (car result) 'error))
      (let ((errors (cdr result)))
        (walkthrough-test--has-error errors "^steps\\[0\\]: must be an object$")
        (walkthrough-test--has-error errors "^steps\\[1\\]\\.files\\[0\\]\\.ranges: must be a non-empty array$")
        (walkthrough-test--has-error errors "^steps\\[1\\]\\.findings\\[0\\]\\.anchor: must be an object$")
        (walkthrough-test--has-error errors "^steps\\[2\\]\\.findings: must be an array$")
        (walkthrough-test--has-error errors "^steps\\[3\\]\\.findings\\[0\\]: must be an object$")))))

(ert-deftest walkthrough-test-validate-unusual-files ()
  "A path with a space, and a file emptied (+0,0), can be owned."
  (walkthrough-test--with-repo
    (walkthrough-test--write "my file.el" "spaced\n")
    ;; c.el is back, emptied: against main that is a hunk -1 +0,0.
    (walkthrough-test--write "c.el" "")
    (walkthrough-test--git "add" ".")
    (walkthrough-test--git "commit" "--quiet" "-m" "four")
    (let* ((head (walkthrough-test--git "rev-parse" "HEAD"))
           (files (walkthrough--parse-diff base head '("-U3"))))
      (should (member "my file.el" (mapcar (lambda (f) (plist-get f :file)) files)))
      (should (null (walkthrough-validate
                     (walkthrough-test--draft
                      base head
                      :steps (vector (walkthrough-test--step
                                      "All" ["a.el" "b.el" "img.bin" "my file.el"
                                             ((file . "c.el") (ranges . [[1 1]]))])))))))))

;;; Installing

(ert-deftest walkthrough-test-install ()
  "A valid draft is installed with repo and ids; an invalid one changes nothing."
  (walkthrough-test--with-repo
    (let* ((walkthrough-open-after-install nil)
           (result (walkthrough-install
                    (walkthrough-test--write-draft (walkthrough-test--draft base head))))
           (file (cdr result)))
      (should (eq (car result) 'ok))
      (should (equal file (expand-file-name ".git/walkthroughs/feat%2Fx.json"
                                            walkthrough-test--repo)))
      (let* ((data (walkthrough--read file))
             (step (aref (alist-get 'steps data) 0)))
        (should (equal (alist-get 'repo data) walkthrough-test--repo))
        (should (equal (mapcar (lambda (f) (alist-get 'id f))
                               (alist-get 'findings step))
                       '("s1-f1" "s1-f2"))))
      ;; An invalid draft returns its errors and leaves the file untouched.
      (let ((before (with-temp-buffer (insert-file-contents-literally file)
                                      (buffer-string)))
            (bad (walkthrough-install
                  (walkthrough-test--write-draft
                   (walkthrough-test--draft base head :title "")))))
        (should (eq (car bad) 'error))
        (walkthrough-test--has-error (cdr bad) "^title: ")
        (should (equal before (with-temp-buffer (insert-file-contents-literally file)
                                                (buffer-string)))))
      ;; Text outside ASCII survives the write, both at install and on a mark.
      (walkthrough-install
       (walkthrough-test--write-draft
        (walkthrough-test--draft base head :title "\u00c6 \u2014 \u00f8")))
      (walkthrough--set-state file "s1-f1" "accepted")
      (should (equal (alist-get 'title (walkthrough--read file)) "\u00c6 \u2014 \u00f8"))
      ;; A file that is not JSON at all is an error, not a signal.
      (let ((junk (make-temp-file "walkthrough-junk" nil ".json" "{nope")))
        (should (eq (car (walkthrough-install junk)) 'error)))
      ;; A re-run replaces the file and carries no marks over.
      (walkthrough--set-state file "s1-f1" "accepted")
      (walkthrough-install
       (walkthrough-test--write-draft (walkthrough-test--draft base head)))
      (let ((finding (aref (alist-get 'findings
                                      (aref (alist-get 'steps (walkthrough--read file)) 0))
                           0)))
        (should (null (alist-get 'state finding)))))))

;;; The buffer

(defun walkthrough-test--open (draft)
  "Install DRAFT without showing it, then open it and return the buffer."
  (let* ((walkthrough-open-after-install nil)
         (result (walkthrough-install (walkthrough-test--write-draft draft))))
    (unless (eq (car result) 'ok)
      (ert-fail (list "install failed" (cdr result))))
    (walkthrough-open (cdr result))))

(defun walkthrough-test--sections (type)
  "Return the sections of TYPE in the current buffer, in buffer order."
  (let (found)
    (magit-map-sections (lambda (s) (when (magit-section-match type s) (push s found))))
    (sort found (lambda (a b) (< (oref a start) (oref b start))))))

(defun walkthrough-test--text (section)
  "Return the text of SECTION without properties."
  (buffer-substring-no-properties (oref section start) (oref section end)))

(defun walkthrough-test--count (regexp &optional section)
  "Count matches of REGEXP in SECTION, or in the whole buffer."
  (let ((text (if section
                  (walkthrough-test--text section)
                (buffer-substring-no-properties (point-min) (point-max))))
        (count 0) (start 0))
    (while (string-match regexp text start)
      (setq count (1+ count) start (match-end 0)))
    count))

(ert-deftest walkthrough-test-buffer-steps ()
  "Steps appear in order, and every hunk once, split files included."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open (walkthrough-test--draft base head))
      (should (derived-mode-p 'magit-diff-mode))
      (should (eq major-mode 'walkthrough-mode))
      (should visual-line-mode)
      (should (eq magit-buffer-diff-type 'committed))
      (should (equal magit-buffer-diff-range (format "%s..%s" base head)))
      (should (null magit-buffer-revision))
      (let ((steps (walkthrough-test--sections 'walkthrough-step)))
        (should (= (length steps) 2))
        (should (string-match-p "Core" (walkthrough-test--text (car steps))))
        (should (string-match-p "Adds `?b\\.el`? and changes a\\.el near the top\\."
                                (walkthrough-test--text (car steps))))
        (should (string-match-p "Cleanup" (walkthrough-test--text (cadr steps))))
        ;; The split file: its first hunk in step 1 only, its second in step 2.
        (should (= 1 (walkthrough-test--count "^@@ -7,7 \\+7,7 @@" (car steps))))
        (should (= 0 (walkthrough-test--count "^@@ -197,7 \\+197,7 @@" (car steps))))
        (should (= 1 (walkthrough-test--count "^@@ -197,7 \\+197,7 @@" (cadr steps))))
        (should (= 0 (walkthrough-test--count "^@@ -7,7 \\+7,7 @@" (cadr steps)))))
      ;; Every hunk of the range, exactly once across the buffer.
      (dolist (file (walkthrough--parse-diff base head '("-U3")))
        (dolist (hunk (plist-get file :hunks))
          (should (= 1 (walkthrough-test--count
                        (concat "^" (regexp-quote (plist-get hunk :header))))))))
      ;; The hunks are Magit's own sections.
      (should (walkthrough-test--sections 'hunk)))))

(ert-deftest walkthrough-test-buffer-empty-step-and-navigation ()
  "A step whose diff is empty keeps its heading; N and P land on headings."
  (walkthrough-test--with-repo
    (let ((draft (walkthrough-test--draft base head)))
      ;; A third step owning a range of a.el that no hunk overlaps.
      (setf (alist-get 'steps draft)
            (vconcat (alist-get 'steps draft)
                     (vector (walkthrough-test--step
                              "Nothing" [((file . "a.el") (ranges . [[100 120]]))]))))
      (with-current-buffer (walkthrough-test--open draft)
        (let ((steps (walkthrough-test--sections 'walkthrough-step)))
          (should (= (length steps) 3))
          (should (string-match-p "Nothing" (walkthrough-test--text (nth 2 steps))))
          (goto-char (point-min))
          (walkthrough-next-step)
          (should (= (point) (oref (nth 0 steps) start)))
          (walkthrough-next-step)
          (should (= (point) (oref (nth 1 steps) start)))
          (walkthrough-next-step)
          (should (= (point) (oref (nth 2 steps) start)))
          (should-error (walkthrough-next-step) :type 'user-error)
          (walkthrough-previous-step)
          (should (= (point) (oref (nth 1 steps) start))))
        ;; A refresh rebuilds the same steps.
        (magit-refresh-buffer)
        (should (= 3 (length (walkthrough-test--sections 'walkthrough-step))))))))

(ert-deftest walkthrough-test-buffer-visits-head ()
  "RET on an added line visits the file as of the head commit."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open (walkthrough-test--draft base head))
      (goto-char (point-min))
      (re-search-forward "^\\+line 10 changed")
      (let ((buffer (save-window-excursion
                      (call-interactively #'magit-diff-visit-file)
                      (current-buffer))))
        (with-current-buffer buffer
          (should (equal (magit-rev-parse magit-buffer-revision) head))
          (should (= (line-number-at-pos) 10)))))))

(ert-deftest walkthrough-test-buffer-moved-and-gone ()
  "A moved branch is noted; a walkthrough whose commits are gone says so."
  (walkthrough-test--with-repo
    (let ((file (cdr (let ((walkthrough-open-after-install nil))
                       (walkthrough-install
                        (walkthrough-test--write-draft
                         (walkthrough-test--draft base head)))))))
      (with-current-buffer (walkthrough-open file)
        (should-not (string-match-p "has moved" (buffer-string))))
      (walkthrough-test--write "b.el" "changed again\n")
      (walkthrough-test--git "commit" "--quiet" "-am" "four")
      (with-current-buffer (walkthrough-open file)
        (magit-refresh-buffer)
        (should (string-match-p "Branch feat/x has moved" (buffer-string))))
      (walkthrough--write (walkthrough--put (walkthrough--read file) 'head
                                            "1111111111111111111111111111111111111111")
                          file)
      (should (string-match-p
               "re-run"
               (cadr (should-error (walkthrough-open file) :type 'user-error)))))))

;;; Comment targets

(defconst walkthrough-test--explanation
  (concat "Splits the lookup in two.\n"
          "The `findByEan` query stays.\n"
          "\n"
          "- **findByEan** inner-joins the EAN table\n"
          "  and orders by item number.\n"
          "  - Nested: returns every match.\n"
          "- Second item.\n"
          "\n"
          "A closing paragraph.")
  "A step explanation with paragraphs, nested bullets and inline code.")

(defun walkthrough-test--explained-draft (base head)
  "Return the fixture draft between BASE and HEAD, step 1 explained at length.
Step 1's explanation is `walkthrough-test--explanation'."
  (let ((draft (walkthrough-test--draft base head)))
    (setf (alist-get 'explanation (aref (alist-get 'steps draft) 0))
          walkthrough-test--explanation)
    draft))

(defun walkthrough-test--pos (string &optional end)
  "Return the position of the start of STRING, or of its end when END.
The search is case-sensitive."
  (save-excursion
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (search-forward string))
    (if end (point) (match-beginning 0))))

(defun walkthrough-test--target-at (string)
  "Return the comment target with point at the start of STRING."
  (goto-char (walkthrough-test--pos string))
  (walkthrough-comment-target))

(ert-deftest walkthrough-test-comment-target-heading ()
  "A step heading is a target for the whole step, with no quote."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (let ((core '(:step 1 :steps 2 :title "Core" :files ("a.el" "b.el") :quote nil)))
        (should (equal (walkthrough-test--target-at "Step 1/2") core))
        (end-of-line)
        (should (equal (walkthrough-comment-target) core)))
      (should (equal (walkthrough-test--target-at "Cleanup")
                     '(:step 2 :steps 2 :title "Cleanup"
                             :files ("a.el" "c.el" "img.bin") :quote nil))))))

(ert-deftest walkthrough-test-comment-target-paragraph ()
  "Outside a list, the passage is the paragraph at point."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (should (equal (walkthrough-test--target-at "query stays")
                     '(:step 1 :steps 2 :title "Core" :files ("a.el" "b.el")
                             :quote "Splits the lookup in two.\nThe `findByEan` query stays.")))
      (should (equal (plist-get (walkthrough-test--target-at "Splits") :quote)
                     "Splits the lookup in two.\nThe `findByEan` query stays."))
      ;; The end of the explanation's last line is still in it.
      (walkthrough-test--target-at "A closing paragraph")
      (end-of-line)
      (should (equal (plist-get (walkthrough-comment-target) :quote)
                     "A closing paragraph."))
      (should (equal (walkthrough-test--target-at "Changes a.el near the end")
                     '(:step 2 :steps 2 :title "Cleanup"
                             :files ("a.el" "c.el" "img.bin")
                             :quote "Changes a.el near the end, deletes c.el, adds a binary."))))))

(ert-deftest walkthrough-test-comment-target-blank-line ()
  "A blank line between blocks of an explanation has no passage."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (dolist (after '("query stays." "- Second item."))
        (goto-char (point-min))
        (search-forward after)
        (forward-line 1)
        (should (looking-at-p "$"))
        (should (equal (cadr (should-error (walkthrough-comment-target)
                                           :type 'user-error))
                       "No passage at point"))))))

(ert-deftest walkthrough-test-comment-target-list-items ()
  "In a list, the passage is the innermost item's own lines."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      ;; A bullet: its marker line and continuation line, not its sub-item.
      (dolist (at '("inner-joins" "and orders by"))
        (should (equal (plist-get (walkthrough-test--target-at at) :quote)
                       "- **findByEan** inner-joins the EAN table\n  and orders by item number.")))
      ;; A nested sub-item: only the sub-item.
      (should (equal (plist-get (walkthrough-test--target-at "Nested") :quote)
                     "  - Nested: returns every match."))
      (should (equal (plist-get (walkthrough-test--target-at "Second item") :quote)
                     "- Second item.")))))

(defun walkthrough-test--target-with-region (mark point)
  "Return the comment target with the region active from MARK to POINT.
Batch Emacs has `transient-mark-mode' off, so it is turned on here."
  (let ((transient-mark-mode t))
    (set-mark mark)
    (goto-char point)
    (unwind-protect (walkthrough-comment-target)
      (deactivate-mark))))

(ert-deftest walkthrough-test-comment-target-region ()
  "A region inside one explanation is exactly the passage."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (let ((from (walkthrough-test--pos "inner-joins"))
            (to (walkthrough-test--pos "EAN" t)))
        (should (equal (walkthrough-test--target-with-region from to)
                       '(:step 1 :steps 2 :title "Core" :files ("a.el" "b.el")
                               :quote "inner-joins the EAN")))
        (should (equal (plist-get (walkthrough-test--target-with-region to from) :quote)
                       "inner-joins the EAN")))
      ;; Across lines, and across an item and its sub-item.
      (should (equal (plist-get (walkthrough-test--target-with-region
                                 (walkthrough-test--pos "orders by")
                                 (walkthrough-test--pos "Nested: returns" t))
                                :quote)
                     "orders by item number.\n  - Nested: returns"))
      ;; A whole last line, its newline included, without the trailing newline.
      (let ((line (walkthrough-test--pos "A closing paragraph.")))
        (should (equal (plist-get (walkthrough-test--target-with-region
                                   line (save-excursion (goto-char line)
                                                        (forward-line 1)
                                                        (point)))
                                  :quote)
                       "A closing paragraph."))))))

(ert-deftest walkthrough-test-comment-target-region-leaves-explanation ()
  "A region with one end outside the explanation is refused."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (let ((inside (walkthrough-test--pos "inner-joins")))
        (dolist (outside (list (walkthrough-test--pos "General remark")
                               (walkthrough-test--pos "+line 10 changed")
                               (walkthrough-test--pos "Step 1/2")
                               (walkthrough-test--pos "Changes a.el near the end")))
          (dolist (ends (list (cons inside outside) (cons outside inside)))
            (should (equal (cadr (should-error (walkthrough-test--target-with-region
                                                (car ends) (cdr ends))
                                               :type 'user-error))
                           "Region must stay within the explanation"))))))))

(ert-deftest walkthrough-test-comment-target-region-blank ()
  "A region of only whitespace inside an explanation has no passage."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (let ((item (walkthrough-test--pos "and orders by")))
        ;; The indentation of a continuation line, and the blank line
        ;; between two blocks with the newlines around it.
        (dolist (ends (list (cons (- item 2) item)
                            (cons (walkthrough-test--pos "query stays." t)
                                  (walkthrough-test--pos "- **findByEan**"))))
          (should (string-blank-p (buffer-substring-no-properties (car ends) (cdr ends))))
          (should (equal (cadr (should-error (walkthrough-test--target-with-region
                                              (car ends) (cdr ends))
                                             :type 'user-error))
                         "No passage at point")))))))

(ert-deftest walkthrough-test-comment-target-elsewhere ()
  "The intro, findings, hunks and file headings are no comment target."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      (dolist (pos (list (point-min)
                         (walkthrough-test--pos "Changes in")
                         (oref (car (walkthrough-test--sections 'walkthrough-finding))
                               start)
                         (walkthrough-test--pos "General remark")
                         ;; The anchored finding's line.
                         (walkthrough-test--pos "+line 10 changed")
                         (oref (car (walkthrough-test--sections 'hunk)) start)
                         (oref (car (walkthrough-test--sections 'file)) start)
                         (oref (car (last (walkthrough-test--sections 'file))) start)))
        (goto-char pos)
        (should-not (walkthrough-comment-target)))
      ;; A region within a hunk is left to the hunk.
      (should-not (walkthrough-test--target-with-region
                   (walkthrough-test--pos "-line 10")
                   (walkthrough-test--pos "+line 10 changed" t))))))

(ert-deftest walkthrough-test-comment-target-keeps-markup ()
  "The quote is the Markdown source, with the markup the buffer hides."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--explained-draft base head))
      ;; The backticks and asterisks are in the text, but not shown.
      (dolist (markup '("`findByEan`" "**findByEan**"))
        (should (invisible-p (walkthrough-test--pos markup))))
      (should (string-match-p "The `findByEan` query"
                              (plist-get (walkthrough-test--target-at "query stays")
                                         :quote)))
      (should (string-prefix-p "- **findByEan** inner"
                               (plist-get (walkthrough-test--target-at "inner-joins")
                                          :quote)))
      (should (equal (plist-get (walkthrough-test--target-with-region
                                 (walkthrough-test--pos "`findByEan`")
                                 (walkthrough-test--pos "`findByEan`" t))
                                :quote)
                     "`findByEan`")))))

;;; Findings

(defun walkthrough-test--finding-overlay (id)
  "Return the overlay drawing finding ID, or nil."
  (seq-find (lambda (ov) (member id (overlay-get ov 'walkthrough-finding)))
            (overlays-in (point-min) (point-max))))

(defun walkthrough-test--finding-section (id)
  "Return the section showing finding ID, or nil."
  (seq-find (lambda (s) (equal (oref s value) id))
            (walkthrough-test--sections 'walkthrough-finding)))

(defun walkthrough-test--with-extra-findings (draft)
  "Return DRAFT with a not-placed finding in step 1 and one in step 2."
  (let* ((steps (alist-get 'steps draft))
         (one (aref steps 0))
         (two (aref steps 1)))
    (aset steps 0 (walkthrough--put
                   one 'findings
                   (vconcat (alist-get 'findings one)
                            [((severity . "medium")
                              (title . "Far away")
                              (body . "Line 120 is not in this step's hunks.")
                              (anchor . ((file . "a.el") (line . 120))))])))
    (aset steps 1 (walkthrough--put
                   two 'findings
                   [((severity . "low")
                     (title . "Binary checked in")
                     (body . "Consider LFS.")
                     (confidence . "x"))]))
    draft))

(ert-deftest walkthrough-test-finding-placement ()
  "Anchored, not placed and unanchored findings each go where they belong."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--with-extra-findings
                           (walkthrough-test--draft base head)))
      (let* ((steps (walkthrough-test--sections 'walkthrough-step))
             (diff (car (walkthrough-test--sections 'walkthrough-diff)))
             (anchored (walkthrough-test--finding-overlay "s1-f1")))
        ;; Anchored: drawn right below its line, inside the hunk.
        (should anchored)
        (save-excursion
          (goto-char (overlay-start anchored))
          (should (looking-at-p "\\+line 10 changed$")))
        (let ((text (overlay-get anchored 'after-string)))
          (should (string-match-p "\\`.*HIGH.*Line 10 is wrong" text))
          (should (string-match-p "Read line 10, get the wrong value\\." text))
          (should (string-match-p "CONFIRMED" text)))
        ;; Unanchored: a section of its step, before the diff.
        (let ((general (walkthrough-test--finding-section "s1-f2")))
          (should general)
          (should (< (oref general start) (oref diff start)))
          (should (> (oref general start) (oref (car steps) start)))
          (should (string-match-p "\\`.*LOW.*General remark"
                                  (walkthrough-test--text general))))
        ;; Anchored to a line the step does not show: at the top, marked.
        (let ((far (walkthrough-test--finding-section "s1-f3")))
          (should far)
          (should-not (walkthrough-test--finding-overlay "s1-f3"))
          (should (string-match-p "not placed" (walkthrough-test--text far))))
        ;; An unknown key is shown as text.
        (should (string-match-p "confidence: x"
                                (walkthrough-test--text
                                 (walkthrough-test--finding-section "s2-f1"))))
        (should-not (string-match-p "No findings" (buffer-string)))))
    ;; With no findings at all, the intro says so.
    (let ((draft (walkthrough-test--draft base head)))
      (seq-doseq (step (alist-get 'steps draft))
        (setf (alist-get 'findings step) []))
      (with-current-buffer (walkthrough-test--open draft)
        (should (string-match-p "No findings" (buffer-string)))))))

(defun walkthrough-test--faces (string pos &optional prop)
  "Return the faces of STRING at POS under PROP (default `face'), as a list."
  (flatten-tree (get-text-property pos (or prop 'face) string)))

(defun walkthrough-test--check-block (text severity prop)
  "Check that TEXT is one finding block of SEVERITY, faces under PROP.
Every line starts with the bar in the severity's bar face, the heading
with ◆ and the severity, and the whole block has the finding face."
  (let ((bar (intern (format "walkthrough-%s-bar" severity)))
        (pos 0))
    (should (string-match-p (format "\\`▎◆ %s " (upcase severity)) text))
    (dolist (line (split-string text "\n" t))
      (should (string-prefix-p "▎" line))
      (should (memq bar (walkthrough-test--faces text pos prop)))
      (setq pos (+ pos (length line) 1)))
    (dotimes (i (length text))
      (should (memq 'walkthrough-finding (walkthrough-test--faces text i prop))))))

(ert-deftest walkthrough-test-finding-blocks ()
  "Placed and unplaced findings are the same block, unlike the diff."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--with-extra-findings
                           (walkthrough-test--draft base head)))
      ;; The finding background is its own, not a diff face's.
      (should-not (memq 'magit-diff-context-highlight
                        (ensure-list (face-attribute 'walkthrough-finding :inherit))))
      (walkthrough-test--check-block
       (overlay-get (walkthrough-test--finding-overlay "s1-f1") 'after-string)
       "high" 'face)
      (let ((general (walkthrough-test--finding-section "s1-f2")))
        (walkthrough-test--check-block
         (buffer-substring (oref general start) (oref general end))
         "low" 'font-lock-face))
      (let* ((far (walkthrough-test--finding-section "s1-f3"))
             (text (buffer-substring (oref far start) (oref far end))))
        (walkthrough-test--check-block text "medium" 'font-lock-face)
        (should (string-match-p "\\`▎◆ MEDIUM +Far away.*not placed" text)))
      ;; A sent finding keeps its block, dimmed, with its state in the heading.
      (walkthrough--set-state walkthrough--file "s1-f1" "sent")
      (magit-refresh-buffer)
      (let ((text (overlay-get (walkthrough-test--finding-overlay "s1-f1")
                               'after-string)))
        (walkthrough-test--check-block text "high" 'face)
        (should (string-match-p "\\`▎◆ HIGH +Line 10 is wrong +\\[sent\\]" text))
        (dotimes (i (length text))
          (should (memq 'walkthrough-sent (walkthrough-test--faces text i))))))))

(ert-deftest walkthrough-test-step-finding-count ()
  "A step heading ends in a dimmed finding count, left out without findings."
  (walkthrough-test--with-repo
    (let ((draft (walkthrough-test--with-extra-findings
                  (walkthrough-test--draft base head))))
      (setf (alist-get 'steps draft)
            (vconcat (alist-get 'steps draft)
                     (vector (walkthrough-test--step
                              "Quiet" [((file . "a.el") (ranges . [[100 120]]))]))))
      (with-current-buffer (walkthrough-test--open draft)
        (let ((headings (mapcar (lambda (s)
                                  (buffer-substring (oref s start)
                                                    (save-excursion
                                                      (goto-char (oref s start))
                                                      (line-end-position))))
                                (walkthrough-test--sections 'walkthrough-step))))
          (should (equal (mapcar #'substring-no-properties headings)
                         '("Step 1/3  Core  3 findings (1 high)"
                           "Step 2/3  Cleanup  1 finding (1 low)"
                           "Step 3/3  Quiet")))
          (let ((first (car headings)))
            (should (memq 'magit-dimmed
                          (walkthrough-test--faces
                           first (string-match "3 findings" first) 'font-lock-face)))))))))

(defun walkthrough-test--stop ()
  "Name the stop at point: a finding's id, or the step heading's index."
  (or (car (walkthrough--findings-at-point))
      (when-let* ((section (magit-current-section))
                  ((magit-section-match 'walkthrough-step section))
                  ((= (point) (oref section start))))
        (oref section value))))

(ert-deftest walkthrough-test-finding-navigation ()
  "n and p stop at step headings and findings, in buffer order, at the window top."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--with-extra-findings
                           (walkthrough-test--draft base head)))
      ;; Window-start is only meaningful for a buffer shown in a window.
      (switch-to-buffer (current-buffer))
      (goto-char (point-min))
      (let (visited)
        (while (ignore-errors (walkthrough-next) t)
          (should (= (window-start) (line-beginning-position)))
          (push (walkthrough-test--stop) visited))
        (should (equal (nreverse visited) '(0 "s1-f2" "s1-f3" "s1-f1" 1 "s2-f1"))))
      (should-error (walkthrough-next) :type 'user-error)
      (walkthrough-previous)
      (should (eql (walkthrough-test--stop) 1))
      (should (= (window-start) (point)))
      (walkthrough-previous)
      (should (equal (walkthrough--findings-at-point) '("s1-f1")))
      (goto-char (point-min))
      (should-error (walkthrough-previous) :type 'user-error)
      ;; N and P still jump by step, also to the window top.
      (walkthrough-next-step)
      (walkthrough-next-step)
      (should (eql (walkthrough-test--stop) 1))
      (should (= (window-start) (point)))
      ;; Marking rewrites the file; the unknown key is still there.
      (walkthrough--set-state walkthrough--file "s1-f1" "accepted")
      (let ((finding (aref (alist-get 'findings
                                      (aref (alist-get 'steps
                                                       (walkthrough--read walkthrough--file))
                                            1))
                           0)))
        (should (equal (alist-get 'confidence finding) "x"))))))

(defun walkthrough-test--header-line ()
  "Return the header line after a command, without properties."
  (run-hooks 'post-command-hook)
  (string-trim (substring-no-properties header-line-format)))

(ert-deftest walkthrough-test-header-line ()
  "The header line names the step point is in and its finding count."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--with-extra-findings
                           (walkthrough-test--draft base head)))
      (let ((steps (walkthrough-test--sections 'walkthrough-step)))
        (goto-char (point-min))
        (should (equal (walkthrough-test--header-line) "Walkthrough: Fixture change"))
        (goto-char (oref (car steps) start))
        (should (equal (walkthrough-test--header-line)
                       "Walkthrough: Fixture change — Step 1/2: Core · 3 findings"))
        ;; Deep inside a step's diff, still that step.
        (goto-char (overlay-start (walkthrough-test--finding-overlay "s1-f1")))
        (should (string-suffix-p "Step 1/2: Core · 3 findings"
                                 (walkthrough-test--header-line)))
        (goto-char (oref (cadr steps) start))
        (should (string-suffix-p "Step 2/2: Cleanup · 1 finding"
                                 (walkthrough-test--header-line)))))))

;;; Highlighting

(defun walkthrough-test--within-p (inner outer)
  "Return non-nil when section INNER lies inside section OUTER."
  (and (>= (oref inner start) (oref outer start))
       (<= (oref inner end) (oref outer end))))

(defun walkthrough-test--masking-overlays ()
  "Return the section highlight overlays that cover lines of a hunk.
Over a hunk they hide the faces of its added and removed lines."
  (seq-filter (lambda (ov)
                (and (eq (overlay-get ov 'font-lock-face) 'magit-section-highlight)
                     (seq-some (lambda (hunk)
                                 (and (< (overlay-start ov) (oref hunk end))
                                      (> (overlay-end ov) (oref hunk content))))
                               (walkthrough-test--sections 'hunk))))
              magit-section-highlight-overlays))

(ert-deftest walkthrough-test-step-highlight ()
  "On a step heading its hunks keep their diff faces and get syntax faces."
  (walkthrough-test--with-repo
    (let ((magit-diff-fontify-hunk t))
      (with-current-buffer (walkthrough-test--open (walkthrough-test--draft base head))
        ;; The first step starts with a finding that has no line, which
        ;; must not decide how the step is highlighted.
        (let ((step (car (walkthrough-test--sections 'walkthrough-step))))
          (goto-char (oref step start))
          (magit-section-update-highlight t)
          (should-not (walkthrough-test--masking-overlays))
          (dolist (hunk (walkthrough-test--sections 'hunk))
            (should (eq (oref hunk fontified)
                        (walkthrough-test--within-p hunk step)))))))))

(ert-deftest walkthrough-test-refresh-fontifies-step ()
  "A refresh with point on a finding leaves the syntax faces of its step."
  (walkthrough-test--with-repo
    (let ((magit-diff-fontify-hunk t))
      (with-current-buffer (walkthrough-test--open (walkthrough-test--draft base head))
        (walkthrough-test--goto-finding "s1-f2")
        (magit-refresh-buffer)
        (should (equal (walkthrough--findings-at-point) '("s1-f2")))
        (let ((step (car (walkthrough-test--sections 'walkthrough-step))))
          (dolist (hunk (walkthrough-test--sections 'hunk))
            (should (eq (oref hunk fontified)
                        (walkthrough-test--within-p hunk step)))))))))

;;; Marks

(defun walkthrough-test--state (file id)
  "Return the state of finding ID in FILE, as stored."
  (seq-some (lambda (step)
              (seq-some (lambda (f) (and (equal (alist-get 'id f) id)
                                         (or (alist-get 'state f) 'unmarked)))
                        (alist-get 'findings step)))
            (alist-get 'steps (walkthrough--read file))))

(defun walkthrough-test--goto-finding (id)
  "Move point to the start of finding ID."
  (goto-char (point-min))
  (while (not (member id (walkthrough--findings-at-point)))
    (walkthrough-next)))

(ert-deftest walkthrough-test-marks ()
  "Marks follow the state machine, land in the file and survive a reload."
  (walkthrough-test--with-repo
    (let* ((buffer (walkthrough-test--open (walkthrough-test--draft base head)))
           (file (buffer-local-value 'walkthrough--file buffer)))
      (with-current-buffer buffer
        (walkthrough-test--goto-finding "s1-f1")
        (walkthrough-accept)
        (should (equal (walkthrough-test--state file "s1-f1") "accepted"))
        (walkthrough-test--goto-finding "s1-f1")
        (walkthrough-dismiss)
        (should (equal (walkthrough-test--state file "s1-f1") "dismissed"))
        (walkthrough-test--goto-finding "s1-f1")
        (walkthrough-accept)
        (should (equal (walkthrough-test--state file "s1-f1") "accepted"))
        (walkthrough-test--goto-finding "s1-f1")
        (walkthrough-unmark)
        (should (eq (walkthrough-test--state file "s1-f1") 'unmarked))
        ;; The state is shown on the finding.
        (walkthrough-test--goto-finding "s1-f2")
        (walkthrough-dismiss)
        (should (string-match-p "\\[dismissed\\]"
                                (walkthrough-test--text
                                 (walkthrough-test--finding-section "s1-f2"))))
        ;; A change made to another finding behind the buffer's back is kept.
        (walkthrough--set-state file "s1-f2" "accepted")
        (walkthrough-test--goto-finding "s1-f1")
        (walkthrough-accept)
        (should (equal (walkthrough-test--state file "s1-f1") "accepted"))
        (should (equal (walkthrough-test--state file "s1-f2") "accepted"))
        ;; A sent finding refuses every mark.
        (walkthrough--set-state file "s1-f1" "sent")
        (magit-refresh-buffer)
        (walkthrough-test--goto-finding "s1-f1")
        (should-error (walkthrough-accept) :type 'user-error)
        (should-error (walkthrough-dismiss) :type 'user-error)
        (should-error (walkthrough-unmark) :type 'user-error))
      ;; Marks survive killing the buffer and opening the file again.
      (kill-buffer buffer)
      (with-current-buffer (walkthrough-open file)
        (should (string-match-p "\\[accepted\\]"
                                (walkthrough-test--text
                                 (walkthrough-test--finding-section "s1-f2"))))))))

(ert-deftest walkthrough-test-accepted-findings ()
  "Accepted, unsent findings come back shaped like review comments."
  (walkthrough-test--with-repo
    (let* ((buffer (walkthrough-test--open (walkthrough-test--draft base head)))
           (file (buffer-local-value 'walkthrough--file buffer)))
      (should (null (walkthrough-accepted-findings walkthrough-test--repo)))
      (walkthrough--set-state file "s1-f1" "accepted")
      (walkthrough--set-state file "s1-f2" "dismissed")
      (let ((items (walkthrough-accepted-findings walkthrough-test--repo)))
        (should (= (length items) 1))
        (let ((item (car items)))
          (should (equal (plist-get item :repo) walkthrough-test--repo))
          (should (eq (plist-get item :kind) 'finding))
          (should (equal (plist-get item :id) "s1-f1"))
          (should (equal (plist-get item :file) "a.el"))
          (should (equal (plist-get item :new) '(10 . 10)))
          (should (null (plist-get item :old)))
          (should (equal (plist-get item :severity) "high"))
          (should (equal (plist-get item :title) "Line 10 is wrong"))
          (should (string-match-p "breaks the count" (plist-get item :text)))
          (should (string-match-p "Read line 10" (plist-get item :text)))
          (should (string-prefix-p "@@ -8,6 +8,6 @@" (plist-get item :patch)))
          (should (string-match-p "^\\+line 10 changed$" (plist-get item :patch)))
          (should (equal (plist-get item :where) (format "diff of %s..%s" base head)))
          (should (equal (plist-get item :walkthrough) file))
          (with-current-buffer buffer
            (should (equal (plist-get item :where) (walkthrough-diff-label)))))
        (walkthrough-mark-sent items)
        (should (equal (walkthrough-test--state file "s1-f1") "sent"))
        (should (null (walkthrough-accepted-findings walkthrough-test--repo)))
        (should (= 1 (length (walkthrough-accepted-findings walkthrough-test--repo t))))
        ;; The open buffer was refreshed and shows the finding as sent.
        (with-current-buffer buffer
          (should (string-match-p
                   "\\[sent\\]"
                   (overlay-get (walkthrough-test--finding-overlay "s1-f1")
                                'after-string))))))))

;;; Replies

(defun walkthrough-test--finding (file id)
  "Return finding ID in FILE, as stored."
  (seq-some (lambda (step)
              (seq-find (lambda (f) (equal (alist-get 'id f) id))
                        (alist-get 'findings step)))
            (alist-get 'steps (walkthrough--read file))))

(ert-deftest walkthrough-test-reply ()
  "A reply is kept in the file, accepts its finding and is drawn in its block."
  (walkthrough-test--with-repo
    (let* ((buffer (walkthrough-test--open (walkthrough-test--draft base head)))
           (file (buffer-local-value 'walkthrough--file buffer)))
      (with-current-buffer buffer
        (walkthrough-test--goto-finding "s1-f2")
        (walkthrough-reply "s1-f2" "Yes, but use json-insert.")
        (should (equal (alist-get 'reply (walkthrough-test--finding file "s1-f2"))
                       "Yes, but use json-insert."))
        (should (equal (walkthrough-test--state file "s1-f2") "accepted"))
        ;; Inside the block, below the body, in the reply face.
        (let* ((general (walkthrough-test--finding-section "s1-f2"))
               (text (buffer-substring (oref general start) (oref general end)))
               (at (string-match "▶ Yes, but use json-insert\\." text)))
          (walkthrough-test--check-block text "low" 'font-lock-face)
          (should (> at (string-match "Not tied to a line" text)))
          (should (memq 'walkthrough-reply
                        (walkthrough-test--faces text at 'font-lock-face))))
        ;; A placed finding draws it too.
        (walkthrough-reply "s1-f1" "Why is this a problem?")
        (should (string-match-p
                 "▶ Why is this a problem\\?"
                 (overlay-get (walkthrough-test--finding-overlay "s1-f1")
                              'after-string))))
      ;; Replies survive killing the buffer and opening the file again.
      (kill-buffer buffer)
      (with-current-buffer (walkthrough-open file)
        (should (string-match-p "▶ Yes, but use json-insert"
                                (walkthrough-test--text
                                 (walkthrough-test--finding-section "s1-f2"))))))))

(ert-deftest walkthrough-test-reply-states ()
  "Replying accepts any finding; an empty reply deletes it, marks keep it."
  (walkthrough-test--with-repo
    (let* ((buffer (walkthrough-test--open (walkthrough-test--draft base head)))
           (file (buffer-local-value 'walkthrough--file buffer)))
      (with-current-buffer buffer
        ;; A dismissed finding is accepted, and not a follow-up.
        (walkthrough--set-state file "s1-f2" "dismissed")
        (walkthrough-reply "s1-f2" "On second thought, fix it.")
        (should (equal (walkthrough-test--state file "s1-f2") "accepted"))
        (should-not (alist-get 'follow_up (walkthrough-test--finding file "s1-f2")))
        ;; Commenting again edits the one reply, the old text pre-filled.
        (walkthrough-test--goto-finding "s1-f2")
        (let (initial)
          (cl-letf (((symbol-function 'read-string)
                     (lambda (_prompt &optional init &rest _)
                       (setq initial init)
                       "Fix it in b.el.")))
            (call-interactively #'walkthrough-reply))
          (should (equal initial "On second thought, fix it.")))
        (should (equal (alist-get 'reply (walkthrough-test--finding file "s1-f2"))
                       "Fix it in b.el."))
        (should (= 1 (walkthrough-test--count "▶")))
        ;; Dismissing and unmarking keep the reply, still shown.
        (walkthrough-test--goto-finding "s1-f2")
        (walkthrough-dismiss)
        (walkthrough-test--goto-finding "s1-f2")
        (walkthrough-unmark)
        (should (equal (alist-get 'reply (walkthrough-test--finding file "s1-f2"))
                       "Fix it in b.el."))
        (should (string-match-p "▶ Fix it in b\\.el\\."
                                (walkthrough-test--text
                                 (walkthrough-test--finding-section "s1-f2"))))
        ;; An empty reply deletes it and leaves the mark.
        (walkthrough-reply "s1-f2" "  ")
        (should-not (alist-get 'reply (walkthrough-test--finding file "s1-f2")))
        (should (eq (walkthrough-test--state file "s1-f2") 'unmarked))
        (should (= 0 (walkthrough-test--count "▶")))
        ;; A sent finding is accepted again, as a follow-up.
        (walkthrough--set-state file "s1-f1" "sent")
        (walkthrough-reply "s1-f1" "That fix was wrong; also handle 0.")
        (should (equal (walkthrough-test--state file "s1-f1") "accepted"))
        (should (alist-get 'follow_up (walkthrough-test--finding file "s1-f1")))))))

(ert-deftest walkthrough-test-reply-hand-off ()
  "A reply is handed off with its finding; sending ends a follow-up."
  (walkthrough-test--with-repo
    (let* ((draft (walkthrough-test--draft base head))
           (buffer (walkthrough-test--open draft))
           (file (buffer-local-value 'walkthrough--file buffer)))
      (with-current-buffer buffer
        (should-not (progn (goto-char (point-min)) (walkthrough-finding-at-point-p)))
        (walkthrough-test--goto-finding "s1-f1")
        (should (walkthrough-finding-at-point-p))
        (walkthrough-reply "s1-f1" "Use json-insert.")
        (let ((item (car (walkthrough-accepted-findings walkthrough-test--repo))))
          (should (equal (plist-get item :reply) "Use json-insert."))
          (should-not (plist-get item :follow-up))
          (walkthrough-mark-sent (list item)))
        (walkthrough-reply "s1-f1" "That was wrong; also handle 0.")
        (let ((items (walkthrough-accepted-findings walkthrough-test--repo)))
          (should (= 1 (length items)))
          (should (equal (plist-get (car items) :reply) "That was wrong; also handle 0."))
          (should (plist-get (car items) :follow-up))
          (walkthrough-mark-sent items))
        (should (equal (walkthrough-test--state file "s1-f1") "sent"))
        (should-not (alist-get 'follow_up (walkthrough-test--finding file "s1-f1")))
        (should (alist-get 'reply (walkthrough-test--finding file "s1-f1"))))
      ;; Replies are Emacs's: installing a walkthrough drops any.
      (let ((finding (aref (alist-get 'findings (aref (alist-get 'steps draft) 0)) 0)))
        (setf (alist-get 'reply finding) "Written by the agent")
        (setf (alist-get 'follow_up finding) t))
      (walkthrough-test--open draft)
      (should-not (alist-get 'reply (walkthrough-test--finding file "s1-f1")))
      (should-not (alist-get 'follow_up (walkthrough-test--finding file "s1-f1"))))))

;;; Patch excerpts

(defconst walkthrough-test--hunk
  (concat "@@ -10,12 +10,13 @@ (defun foo ()\n"
          " l10\n l11\n l12\n l13\n l14\n"
          "-l15\n+l15 new\n+l15b\n"
          " l16\n l17\n l18\n l19\n l20\n l21\n")
  "A hunk replacing old line 15 by new lines 15 and 16.")

(ert-deftest walkthrough-test-excerpt-range ()
  "A range is cut out with three lines of context and a corrected header."
  (should (equal (walkthrough-patch-excerpt walkthrough-test--hunk '(16 . 16))
                 (concat "@@ -14,5 +14,6 @@ (defun foo ()\n"
                         " l14\n-l15\n+l15 new\n+l15b\n l16\n l17\n l18\n"))))

(ert-deftest walkthrough-test-excerpt-old-side-and-edges ()
  "Old-side ranges count old lines; the context stops at the hunk's edges."
  (should (equal (walkthrough-patch-excerpt walkthrough-test--hunk '(15 . 15) "old")
                 (concat "@@ -12,5 +12,6 @@ (defun foo ()\n"
                         " l12\n l13\n l14\n-l15\n+l15 new\n+l15b\n l16\n")))
  (should (equal (walkthrough-patch-excerpt walkthrough-test--hunk '(10 . 10))
                 "@@ -10,4 +10,4 @@ (defun foo ()\n l10\n l11\n l12\n l13\n"))
  ;; A combined diff's hunk is not cut.
  (let ((combined (concat "@@@ -1,2 -1,2 +1,3 @@@\n" (make-string 50 ?x) "\n")))
    (should (equal (walkthrough-patch-excerpt combined) combined)))
  ;; A short hunk comes back whole, its header kept for a side with no lines.
  (let ((new-file "@@ -0,0 +1,2 @@\n+new file\n+second line\n"))
    (should (equal (walkthrough-patch-excerpt new-file '(2 . 2)) new-file)))
  (let ((pure-addition "@@ -4,0 +5,1 @@\n+added\n"))
    (should (equal (walkthrough-patch-excerpt pure-addition '(5 . 5)) pure-addition))))

(defun walkthrough-test--hunk-of (header rows)
  "Return a hunk with HEADER and ROWS, each a string or (FROM TO PREFIX).
(FROM TO PREFIX) stands for the lines PREFIX\"lI\" for I from FROM to TO."
  (concat header "\n"
          (mapconcat (lambda (row)
                       (if (stringp row)
                           (concat row "\n")
                         (pcase-let ((`(,from ,to ,prefix) row))
                           (mapconcat (lambda (i) (format "%sl%d\n" prefix i))
                                      (number-sequence from to) ""))))
                     rows "")))

(ert-deftest walkthrough-test-excerpt-capped-hunk ()
  "A whole hunk is capped at 40 lines around its changes, with … for cuts."
  ;; A hunk within the cap comes back as it is.
  (should (equal (walkthrough-patch-excerpt walkthrough-test--hunk)
                 walkthrough-test--hunk))
  ;; A new file keeps its first 40 lines.
  (let ((excerpt (walkthrough-patch-excerpt
                  (walkthrough-test--hunk-of "@@ -0,0 +1,100 @@" '((1 100 "+"))))))
    (should (equal excerpt (walkthrough-test--hunk-of
                            "@@ -0,0 +1,40 @@" '((1 40 "+") "…")))))
  ;; One change in a long hunk keeps the context nearest it, cut on both ends.
  (let ((excerpt (walkthrough-patch-excerpt
                  (walkthrough-test--hunk-of "@@ -1,60 +1,60 @@ (defun bar ()"
                                             '((1 30 " ") "-l31" "+l31 new" (32 60 " "))))))
    (should (equal excerpt (walkthrough-test--hunk-of
                            "@@ -12,39 +12,39 @@ (defun bar ()"
                            '("…" (12 30 " ") "-l31" "+l31 new" (32 50 " ") "…")))))
  ;; Changes far apart keep the lines around each, the cut between marked.
  (let ((excerpt (walkthrough-patch-excerpt
                  (walkthrough-test--hunk-of "@@ -1,59 +1,61 @@"
                                             '((1 5 " ") "+a" (6 54 " ") "+b" (55 59 " "))))))
    (should (equal excerpt (walkthrough-test--hunk-of
                            "@@ -1,59 +1,61 @@"
                            '((1 5 " ") "+a" (6 19 " ") "…" (41 54 " ") "+b" (55 59 " ")))))))

(ert-deftest walkthrough-test-accepted-finding-excerpt ()
  "A hand-off item's patch is its anchored lines with three lines of context."
  (walkthrough-test--with-repo
    (let* ((draft (walkthrough-test--draft base head))
           (finding (aref (alist-get 'findings (aref (alist-get 'steps draft) 0)) 0)))
      (setf (alist-get 'line (alist-get 'anchor finding)) 8)
      (let ((file (buffer-local-value 'walkthrough--file (walkthrough-test--open draft))))
        (walkthrough--set-state file "s1-f1" "accepted")
        (let ((patch (plist-get (car (walkthrough-accepted-findings walkthrough-test--repo))
                                :patch)))
          (should (string-prefix-p "@@ -7,4 +7,4 @@" patch))
          (should (string-suffix-p "\n line 7\n line 8\n line 9\n-line 10\n+line 10 changed\n"
                                   patch)))))))

;;; Comment identity

(ert-deftest walkthrough-test-diff-label ()
  "A walkthrough and `magit-diff' of the same commits share one label.
The regression case for review comments: the label used to come from
`magit-buffer-range', which Magit renamed, so every range diff was
labelled plain \"diff\"."
  (walkthrough-test--with-repo
    (let ((expected (format "diff of %s..%s" base head)))
      (with-current-buffer (walkthrough-test--open (walkthrough-test--draft base head))
        (should (equal (walkthrough-diff-label) expected)))
      (with-current-buffer (save-window-excursion
                             (magit-diff-range "main..feat/x")
                             (magit-get-mode-buffer 'magit-diff-mode))
        (should (equal magit-buffer-diff-range "main..feat/x"))
        (should (equal (walkthrough-diff-label) expected)))
      ;; Unstaged changes have no committed range.
      (with-current-buffer (save-window-excursion
                             (magit-diff-unstaged)
                             (magit-get-mode-buffer 'magit-diff-mode))
        (should (null (walkthrough-diff-label)))))))

;;; Comments on steps

(defconst walkthrough-test--core-explanation
  (concat "Adds `b.el` and changes a.el near the top.\n"
          "\n"
          "- `b.el` holds the new\n"
          "  helper.\n"
          "  - Its second line is a placeholder.\n"
          "- Keeps the file list sorted.\n"
          "\n"
          "Both files are read at startup.\n")
  "The first step's explanation in the comment tests.
A paragraph, a bullet with a continuation line and a sub-item, a bullet
that the second step repeats, and a closing paragraph.")

(defun walkthrough-test--comment-draft (base head)
  "Return the fixture's draft between BASE and HEAD, with longer explanations."
  (let* ((draft (walkthrough-test--draft base head))
         (steps (alist-get 'steps draft)))
    (setf (alist-get 'explanation (aref steps 0)) walkthrough-test--core-explanation)
    (setf (alist-get 'explanation (aref steps 1))
          (concat "Changes a.el near the end, deletes c.el, adds a binary.\n"
                  "\n"
                  "- Keeps the file list sorted."))
    draft))

(defun walkthrough-test--comment (where step title quote text)
  "Return a review comment on step STEP, titled TITLE, of the diff WHERE.
QUOTE is its passage, nil for a comment on the step as a whole, and TEXT
what the user wrote."
  (list :where where :step step :steps 2 :title title :files '("a.el")
        :quote quote :text text :sent nil))

(defun walkthrough-test--comments (comments)
  "Return a `walkthrough-comments-function' that knows COMMENTS.
Like the configuration's, it returns those whose :where is the label."
  (lambda (label)
    (seq-filter (lambda (c) (equal (plist-get c :where) label)) comments)))

(defun walkthrough-test--below (regexp &optional nth)
  "Return what is drawn below the first line matching REGEXP, or nil.
With NTH, below the NTH line matching it.  What is drawn is the
after-strings of the overlays ending at the line's end."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward regexp nil nil nth)
    (let* ((eol (line-end-position))
           (strings (delq nil (mapcar (lambda (ov)
                                        (and (= (overlay-end ov) eol)
                                             (overlay-get ov 'after-string)))
                                      (overlays-in eol eol)))))
      (and strings (apply #'concat strings)))))

(ert-deftest walkthrough-test-comment-passage ()
  "A passage comment is drawn below the passage's last line."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment
                    where 1 "Core" "- `b.el` holds the new\n  helper." "Why a new file?")
                   (walkthrough-test--comment
                    where 1 "Core" "read at startup" "Lazily?")))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        ;; A list item: below its continuation line, above its sub-item.
        (let ((below (walkthrough-test--below "^  helper\\.$")))
          (should (equal (substring-no-properties below) "\n    ▶ Why a new file?"))
          (should (memq 'walkthrough-review-comment
                        (walkthrough-test--faces below (string-match "Why" below)))))
        (should-not (walkthrough-test--below "holds the new$"))
        (should-not (walkthrough-test--below "placeholder\\.$"))
        ;; A phrase: below the line it ends on.
        (should (equal (substring-no-properties
                        (walkthrough-test--below "read at startup\\.$"))
                       "\n    ▶ Lazily?"))))))

(ert-deftest walkthrough-test-comment-step ()
  "A comment on a step is drawn below the step's heading."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment
                    where 2 "Cleanup" nil "This step mixes two concepts.")))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        (let ((below (walkthrough-test--below "^Step 2/2  Cleanup")))
          (should (string-suffix-p "\n    ▶ This step mixes two concepts."
                                   (substring-no-properties below)))
          (should (memq 'walkthrough-review-comment
                        (walkthrough-test--faces below (string-match "This" below)))))
        (should-not (walkthrough-test--below "^Step 1/2  Core"))))))

(ert-deftest walkthrough-test-comment-sent ()
  "A sent comment is drawn dimmed and marked, once it is redrawn."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (comment (walkthrough-test--comment
                     where 1 "Core" "Keeps the file list sorted." "Sorted how?"))
           (walkthrough-comments-function (walkthrough-test--comments (list comment))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        (should (equal (substring-no-properties
                        (walkthrough-test--below "^- Keeps the file list sorted\\.$"))
                       "\n    ▶ Sorted how?"))
        ;; What the configuration does once it handed the comment off.
        (plist-put comment :sent t)
        (walkthrough-redraw-comments)
        (let ((below (walkthrough-test--below "^- Keeps the file list sorted\\.$")))
          (should (equal (substring-no-properties below) "\n    ▶ Sorted how? (sent)"))
          (dotimes (i (length below))
            (should (memq 'walkthrough-review-sent (walkthrough-test--faces below i)))
            (should-not (memq 'walkthrough-review-comment
                              (walkthrough-test--faces below i)))))))))

(ert-deftest walkthrough-test-comment-count ()
  "A step heading counts the comments on the step and its passages."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (on-step (walkthrough-test--comment where 1 "Core" nil "Split this step."))
           (on-passage (walkthrough-test--comment
                        where 1 "Core" "read at startup" "Lazily?"))
           (walkthrough-comments-function
            (walkthrough-test--comments (list on-step on-passage))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        ;; After the finding count, then the comment on the step.
        (let ((below (walkthrough-test--below "^Step 1/2  Core  2 findings (1 high)$")))
          (should (equal (substring-no-properties below)
                         "  [2 review comments]\n    ▶ Split this step."))
          (should (memq 'walkthrough-review-comment (walkthrough-test--faces below 2))))
        (should-not (walkthrough-test--below "^Step 2/2  Cleanup$"))
        ;; One comment left, on a passage: the count alone.
        (let ((walkthrough-comments-function
               (walkthrough-test--comments (list on-passage))))
          (walkthrough-redraw-comments))
        (should (equal (substring-no-properties
                        (walkthrough-test--below "^Step 1/2  Core  2 findings (1 high)$"))
                       "  [1 review comment]"))))))

(ert-deftest walkthrough-test-comment-label ()
  "Only the comments on the walkthrough's own commits are drawn."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (asked nil)
           (comments (walkthrough-test--comments
                      (list (walkthrough-test--comment
                             where 1 "Core" "read at startup" "Lazily?")
                            (walkthrough-test--comment
                             (format "diff of %s..%s" head base)
                             1 "Core" "Keeps the file list sorted." "Elsewhere")
                            (walkthrough-test--comment
                             "unstaged changes" 2 "Cleanup" nil "Not here either"))))
           (walkthrough-comments-function (lambda (label)
                                            (push label asked)
                                            (funcall comments label))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        (should (equal (delete-dups asked) (list where)))
        (should (walkthrough-test--below "read at startup\\.$"))
        (should-not (walkthrough-test--below "^- Keeps the file list sorted\\.$"))
        (should-not (walkthrough-test--below "^Step 2/2  Cleanup$"))
        (should-not (seq-some (lambda (ov)
                                (string-match-p "Elsewhere\\|Not here"
                                                (or (overlay-get ov 'after-string) "")))
                              (overlays-in (point-min) (point-max))))
        ;; Without a function, nothing is drawn.
        (let ((walkthrough-comments-function nil))
          (magit-refresh-buffer))
        (should-not (walkthrough-test--below "read at startup\\.$"))))))

(ert-deftest walkthrough-test-comment-refresh ()
  "Comments are drawn again, once, whenever the buffer is refreshed."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment where 1 "Core" nil "Split this step.")
                   (walkthrough-test--comment
                    where 1 "Core" "read at startup" "Lazily?")))))
      (with-current-buffer (walkthrough-test--open
                            (walkthrough-test--comment-draft base head))
        (let ((heading (walkthrough-test--below "^Step 1/2  Core  2 findings (1 high)$"))
              (passage (walkthrough-test--below "read at startup\\.$")))
          (magit-refresh-buffer)
          ;; Marking a finding refreshes too.
          (walkthrough-test--goto-finding "s1-f2")
          (walkthrough-accept)
          (should (equal (walkthrough-test--below
                          "^Step 1/2  Core  2 findings (1 high)$")
                         heading))
          (should (equal (walkthrough-test--below "read at startup\\.$") passage))
          (should (= 2 (seq-count (lambda (ov)
                                    (string-search "▶" (or (overlay-get ov 'after-string)
                                                           "")))
                                  (overlays-in (point-min) (point-max))))))))))

(ert-deftest walkthrough-test-comment-rerun-reordered ()
  "After a re-run with the steps reordered, comments follow their text and step."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment where 1 "Core" nil "Split this step.")
                   (walkthrough-test--comment
                    where 1 "Core" "read at startup" "Lazily?"))))
           (draft (walkthrough-test--comment-draft base head)))
      (walkthrough-test--open draft)
      (let ((steps (alist-get 'steps draft)))
        (setf (alist-get 'steps draft) (vector (aref steps 1) (aref steps 0))))
      (with-current-buffer (walkthrough-test--open draft)
        (should (equal (substring-no-properties
                        (walkthrough-test--below "^Step 2/2  Core  2 findings (1 high)$"))
                       "  [2 review comments]\n    ▶ Split this step."))
        (should-not (walkthrough-test--below "^Step 1/2  Cleanup$"))
        (should (equal (substring-no-properties
                        (walkthrough-test--below "read at startup\\.$"))
                       "\n    ▶ Lazily?"))))))

(ert-deftest walkthrough-test-comment-rerun-shared-quote ()
  "A quote that two steps share stays in the step it was made in."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment
                    where 2 "Cleanup" "- Keeps the file list sorted." "Sorted how?"))))
           (draft (walkthrough-test--comment-draft base head)))
      (walkthrough-test--open draft)
      (setf (alist-get 'title (aref (alist-get 'steps draft) 1)) "Tidying up")
      (with-current-buffer (walkthrough-test--open draft)
        (should-not (walkthrough-test--below "^- Keeps the file list sorted\\.$"))
        (should (equal (substring-no-properties
                        (walkthrough-test--below "^- Keeps the file list sorted\\.$" 2))
                       "\n    ▶ Sorted how?"))
        (should (equal (substring-no-properties
                        (walkthrough-test--below "^Step 2/2  Tidying up$"))
                       "  [1 review comment]"))
        (should-not (walkthrough-test--below "^Step 1/2  Core"))))))

(ert-deftest walkthrough-test-comment-rerun-not-placed ()
  "A comment whose passage or step is gone is listed under the intro."
  (walkthrough-test--with-repo
    (let* ((where (format "diff of %s..%s" base head))
           (gone-step (walkthrough-test--comment
                       where 3 "Docs" "Documents the helper." "Where?"))
           (walkthrough-comments-function
            (walkthrough-test--comments
             (list (walkthrough-test--comment
                    where 1 "Core" "read at startup" "Lazily?")
                   (walkthrough-test--comment where 2 "Cleanup" nil "Split this step.")
                   gone-step)))
           (draft (walkthrough-test--comment-draft base head)))
      (walkthrough-test--open draft)
      ;; The re-run drops the closing paragraph and retitles the second step.
      (let ((steps (alist-get 'steps draft)))
        (setf (alist-get 'explanation (aref steps 0))
              (car (split-string walkthrough-test--core-explanation "\n\nBoth")))
        (setf (alist-get 'title (aref steps 1)) "Tidying up"))
      (with-current-buffer (walkthrough-test--open draft)
        (should-not (string-search "read at startup" (buffer-string)))
        (plist-put gone-step :sent t)
        (walkthrough-redraw-comments)
        (let ((below (walkthrough-test--below "^Changes in .* in 2 steps\\.$")))
          (should (equal (substring-no-properties below)
                         (concat "\n    ▶ Lazily? (not placed: step 1, Core)"
                                 "\n    ▶ Split this step. (not placed: step 2, Cleanup)"
                                 "\n    ▶ Where? (not placed: step 3, Docs) (sent)")))
          (should (memq 'walkthrough-review-comment
                        (walkthrough-test--faces below (string-match "Lazily" below))))
          (should (memq 'walkthrough-review-sent
                        (walkthrough-test--faces below (string-match "Where" below)))))
        ;; Comments not placed are on no step.
        (should-not (walkthrough-test--below "^Step 1/2  Core"))
        (should-not (walkthrough-test--below "^Step 2/2  Tidying up$"))))))

;;; Starting and reopening

(ert-deftest walkthrough-test-request ()
  "The request goes through `walkthrough-request-function', or nowhere."
  (let (sent)
    (let ((walkthrough-request-function
           (lambda (text submit) (push (list text submit) sent))))
      (walkthrough-request)
      (walkthrough-request "main")
      (should (equal (nreverse sent) '(("/walkthrough" t) ("/walkthrough main" t)))))
    (let ((walkthrough-request-function nil))
      (should (string-match-p
               "No agent is configured"
               (cadr (should-error (walkthrough-request) :type 'user-error)))))))

(ert-deftest walkthrough-test-open-current ()
  "The current branch's walkthrough opens; without one, a request is offered."
  (walkthrough-test--with-repo
    (let* ((sent nil)
           (walkthrough-request-function (lambda (text _) (push text sent))))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (walkthrough-open-current)
        (should (equal sent '("/walkthrough"))))
      (let ((walkthrough-open-after-install nil))
        (walkthrough-install (walkthrough-test--write-draft
                              (walkthrough-test--draft base head))))
      (with-current-buffer (walkthrough-open-current)
        (should (eq major-mode 'walkthrough-mode))
        (should (string-suffix-p "feat%2Fx.json" walkthrough--file)))
      ;; With a prefix, pick among the repository's walkthroughs by branch.
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (should (equal (mapcar #'car collection) '("feat/x")))
                   "feat/x")))
        (with-current-buffer (walkthrough-open-current t)
          (should (eq major-mode 'walkthrough-mode)))))))

(provide 'walkthrough-test)
;;; walkthrough-test.el ends here
