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
  (let ((file (make-temp-file "walkthrough-draft" nil ".json")))
    (with-temp-file file
      (insert (json-serialize draft)))
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
    (should (walkthrough--hunk-overlaps-p (funcall hunk 12 1) '(12 12)))))

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

(ert-deftest walkthrough-test-finding-navigation ()
  "n and p move between findings across steps; unknown keys survive."
  (walkthrough-test--with-repo
    (with-current-buffer (walkthrough-test--open
                          (walkthrough-test--with-extra-findings
                           (walkthrough-test--draft base head)))
      (goto-char (point-min))
      (let (visited)
        (while (ignore-errors (walkthrough-next-finding) t)
          (push (car (walkthrough--findings-at-point)) visited))
        (should (equal (nreverse visited) '("s1-f2" "s1-f3" "s1-f1" "s2-f1"))))
      (walkthrough-previous-finding)
      (should (equal (walkthrough--findings-at-point) '("s1-f1")))
      ;; Marking rewrites the file; the unknown key is still there.
      (walkthrough--set-state walkthrough--file "s1-f1" "accepted")
      (let ((finding (aref (alist-get 'findings
                                      (aref (alist-get 'steps
                                                       (walkthrough--read walkthrough--file))
                                            1))
                           0)))
        (should (equal (alist-get 'confidence finding) "x"))))))

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
    (walkthrough-next-finding)))

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
          (should (string-prefix-p "@@ -7,7 +7,7 @@" (plist-get item :patch)))
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
