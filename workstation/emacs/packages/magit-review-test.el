;; -*- lexical-binding: t; -*-
;;; magit-review-test.el --- ERT suite for magit-review.el

;;; Commentary:

;; Run with `nix build .#test-magit-review -L' (tests/magit-review.nix), or
;; locally, with walkthrough.el beside this file, with
;;
;;   emacs -batch -L . -l magit-review-test.el -f ert-run-tests-batch-and-exit
;;
;; The tests drive the review commands the way the user does, in real Magit
;; buffers, and look only at what the user or the agent sees: the prompt
;; handed to `magit-review-send-function', the comments drawn in the
;; buffers, and `magit-review-items'.
;;
;; Every test runs in a throwaway repository built by
;; `magit-review-test--with-repo': `main' has a.el (30 lines) and b.el, and
;; the branch `feat/x' changes line 20 of a.el in one commit.  In the work
;; tree line 10 of a.el is changed and not staged, and b.el's second line
;; is changed and staged.

;;; Code:

(require 'ert)
(require 'magit-review)
(require 'walkthrough)

(defvar magit-review-test--repo nil
  "Toplevel of the current test repository.")

(defvar magit-review-test--sent nil
  "Hand-offs captured by the test send function, newest first.
Each is (TEXT SUBMIT).")

(defun magit-review-test--git (&rest args)
  "Run git with ARGS in `default-directory', signalling on failure.
Return its trimmed standard output."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (zerop status)
        (error "git %s failed: %s" (string-join args " ") (buffer-string)))
      (string-trim (buffer-string)))))

(defun magit-review-test--write (file content)
  "Write CONTENT to FILE, relative to `default-directory'."
  (with-temp-file file
    (insert content)))

(defun magit-review-test--lines (n &optional change)
  "Return N lines \"line I\", with line numbers in CHANGE edited."
  (mapconcat (lambda (i)
               (if (memq i change)
                   (format "line %d changed\n" i)
                 (format "line %d\n" i)))
             (number-sequence 1 n) ""))

(defun magit-review-test--agent ()
  "Return the buffer standing in for the agent's terminal."
  (get-buffer-create " *magit-review-test-agent*"))

(defmacro magit-review-test--with-repo (&rest body)
  "Run BODY in a fresh fixture repository with `base' and `head' bound.
Hand-offs go to `magit-review-test--sent' instead of an agent, and Magit
buffers draw review comments on refresh, as the configuration has them."
  (declare (indent 0))
  `(let* ((magit-review-test--repo (file-name-as-directory
                                    (file-truename
                                     (make-temp-file "magit-review-test" t))))
          (default-directory magit-review-test--repo)
          (magit-refresh-verbose nil)
          ;; Off in batch Emacs, and a region is only active with it.
          (transient-mark-mode t)
          (magit-review-comments nil)
          (magit-review-test--sent nil)
          (magit-review-send-function
           (lambda (text submit)
             (push (list text submit) magit-review-test--sent)
             (magit-review-test--agent)))
          (magit-refresh-buffer-hook
           (cons #'magit-review-decorate magit-refresh-buffer-hook)))
     (unwind-protect
         (progn
           (magit-review-test--git "init" "--quiet" "-b" "main" ".")
           (magit-review-test--write "a.el" (magit-review-test--lines 30))
           (magit-review-test--write "b.el" "b line 1\nb line 2\n")
           (magit-review-test--git "add" ".")
           (magit-review-test--git "commit" "--quiet" "-m" "base")
           (magit-review-test--git "checkout" "--quiet" "-b" "feat/x")
           (magit-review-test--write "a.el" (magit-review-test--lines 30 '(20)))
           (magit-review-test--git "commit" "--quiet" "-am" "one")
           (magit-review-test--write "b.el" "b line 1\nb line 2 staged\n")
           (magit-review-test--git "add" "b.el")
           (magit-review-test--write "a.el" (magit-review-test--lines 30 '(10 20)))
           (let ((base (magit-review-test--git "rev-parse" "main"))
                 (head (magit-review-test--git "rev-parse" "HEAD")))
             (ignore base head)
             ,@body))
       (dolist (buffer (buffer-list))
         (with-current-buffer buffer
           (when (and (derived-mode-p 'magit-mode)
                      (string-prefix-p magit-review-test--repo
                                       (expand-file-name default-directory)))
             (let ((kill-buffer-query-functions nil))
               (kill-buffer buffer)))))
       (dolist (name '(" *magit-review-test-agent*" "*magit-review*"))
         (when-let* ((buffer (get-buffer name)))
           (kill-buffer buffer)))
       (delete-directory magit-review-test--repo t))))

(defun magit-review-test--expand ()
  "Expand every file section of the current buffer, as the user would."
  (magit-map-sections (lambda (section)
                        (when (magit-section-match 'file section)
                          (magit-section-show section)))))

(defun magit-review-test--status ()
  "Show the fixture's status buffer with its files expanded; return it."
  (let ((buffer (save-window-excursion
                  (magit-status-setup-buffer magit-review-test--repo)
                  (magit-get-mode-buffer 'magit-status-mode))))
    (with-current-buffer buffer
      (magit-review-test--expand))
    buffer))

(defun magit-review-test--goto (regexp &optional section-type)
  "Move point to the start of the first line matching REGEXP.
With SECTION-TYPE, skip lines outside a section of that type, such as
`staged'.  Fail when there is no such line."
  (goto-char (point-min))
  (let (found)
    (while (and (not found) (re-search-forward regexp nil t))
      (when (or (null section-type)
                (let ((section (magit-current-section)))
                  (while (and section
                              (not (magit-section-match section-type section)))
                    (setq section (oref section parent)))
                  section))
        (setq found (line-beginning-position))))
    (unless found
      (ert-fail (list "no line matching" regexp section-type)))
    (goto-char found)))

(defun magit-review-test--select (from to)
  "Select from the line matching FROM to the end of the line matching TO."
  (magit-review-test--goto from)
  (push-mark (point) t t)
  (magit-review-test--goto to)
  (goto-char (line-end-position)))

(defun magit-review-test--prompt ()
  "Return the text of the latest hand-off; fail when there was none."
  (or (car (car magit-review-test--sent))
      (ert-fail "nothing was handed off")))

;;; Commenting and handing off

(ert-deftest magit-review-test-hunk-comment ()
  "A hunk comment names its file, both line ranges and the diff, with the hunk."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "Rename this")
      (magit-review-send))
    (should (equal magit-review-test--sent
                   `((,(concat
                        "Please address my review comments on this diff.  "
                        "Each one names the file, the new/old line range and "
                        "the diff it refers to.\n"
                        "\n"
                        "## a.el new L7-13 old L7-13 (unstaged changes)\n"
                        "\n"
                        "Rename this\n"
                        "\n"
                        "```diff\n"
                        "@@ -7,7 +7,7 @@ line 6\n"
                        " line 7\n line 8\n line 9\n"
                        "-line 10\n+line 10 changed\n"
                        " line 11\n line 12\n line 13\n"
                        "```\n")
                      t))))))

(ert-deftest magit-review-test-region-comments ()
  "A region names the lines it covers on each side, with only its patch.
The comments are handed off oldest first."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--select "^\\+line 10 changed$" "^\\+line 10 changed$")
      (magit-review-comment "Added line")
      (magit-review-test--select "^-line 10$" "^-line 10$")
      (magit-review-comment "Removed line")
      (magit-review-test--select "^-line 10$" "^ line 11$")
      (magit-review-comment "Both sides")
      ;; Commenting ends the region, so the next comment is on the hunk.
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "Whole hunk")
      (magit-review-send))
    (should (equal (magit-review-test--prompt)
                   (concat
                    "Please address my review comments on this diff.  "
                    "Each one names the file, the new/old line range and "
                    "the diff it refers to.\n"
                    "\n"
                    "## a.el new L10-10 (unstaged changes)\n"
                    "\n"
                    "Added line\n"
                    "\n"
                    "```diff\n"
                    "@@ -7,7 +7,8 @@ line 6\n"
                    " line 7\n line 8\n line 9\n"
                    " line 10\n+line 10 changed\n"
                    " line 11\n line 12\n line 13\n"
                    "```\n"
                    "\n"
                    "## a.el old L10-10 (unstaged changes)\n"
                    "\n"
                    "Removed line\n"
                    "\n"
                    "```diff\n"
                    "@@ -7,7 +7,6 @@ line 6\n"
                    " line 7\n line 8\n line 9\n"
                    "-line 10\n"
                    " line 11\n line 12\n line 13\n"
                    "```\n"
                    "\n"
                    "## a.el new L10-11 old L10-11 (unstaged changes)\n"
                    "\n"
                    "Both sides\n"
                    "\n"
                    "```diff\n"
                    "@@ -7,7 +7,7 @@ line 6\n"
                    " line 7\n line 8\n line 9\n"
                    "-line 10\n+line 10 changed\n"
                    " line 11\n line 12\n line 13\n"
                    "```\n"
                    "\n"
                    "## a.el new L7-13 old L7-13 (unstaged changes)\n"
                    "\n"
                    "Whole hunk\n"
                    "\n"
                    "```diff\n"
                    "@@ -7,7 +7,7 @@ line 6\n"
                    " line 7\n line 8\n line 9\n"
                    "-line 10\n+line 10 changed\n"
                    " line 11\n line 12\n line 13\n"
                    "```\n")))))

(ert-deftest magit-review-test-file-and-staged-comments ()
  "A file comment carries no range or patch; staged hunks are labelled so."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^modified +a\\.el$" 'unstaged)
      (magit-review-comment "Whole file")
      (magit-review-test--goto "^@@ -1,2 \\+1,2 @@" 'staged)
      (magit-review-comment "Staged hunk")
      (magit-review-send))
    (should (equal (magit-review-test--prompt)
                   (concat
                    "Please address my review comments on this diff.  "
                    "Each one names the file, the new/old line range and "
                    "the diff it refers to.\n"
                    "\n"
                    "## a.el (unstaged changes)\n"
                    "\n"
                    "Whole file\n"
                    "\n"
                    "## b.el new L1-2 old L1-2 (staged changes)\n"
                    "\n"
                    "Staged hunk\n"
                    "\n"
                    "```diff\n"
                    "@@ -1,2 +1,2 @@\n"
                    " b line 1\n-b line 2\n+b line 2 staged\n"
                    "```\n")))))

(ert-deftest magit-review-test-empty-comment ()
  "An empty comment is refused and nothing is queued."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (should-error (magit-review-comment "") :type 'user-error)
      (should (null (magit-review-items magit-review-test--repo t))))))

(defun magit-review-test--texts (&optional include-sent)
  "Return the texts of the fixture's review items, oldest first.
Sent items are left out unless INCLUDE-SENT; each sent one is marked
\"(sent)\"."
  (mapcar (lambda (item)
            (concat (plist-get item :text)
                    (if (plist-get item :sent) " (sent)" "")))
          (magit-review-items magit-review-test--repo include-sent)))

(ert-deftest magit-review-test-direct-comment ()
  "A direct comment goes out alone at once; the queued ones stay pending."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "Queued")
      (magit-review-test--goto "^@@ -1,2 \\+1,2 @@" 'staged)
      (magit-review-comment-send "Why staged?")
      (should (equal magit-review-test--sent
                     `((,(concat
                          "Here is a comment on this diff: a question or a "
                          "request.  It names the file, the new/old line range "
                          "and the diff it refers to.\n"
                          "\n"
                          "## b.el new L1-2 old L1-2 (staged changes)\n"
                          "\n"
                          "Why staged?\n"
                          "\n"
                          "```diff\n"
                          "@@ -1,2 +1,2 @@\n"
                          " b line 1\n-b line 2\n+b line 2 staged\n"
                          "```\n")
                        t))))
      (should (equal (magit-review-test--texts) '("Queued")))
      (should (equal (magit-review-test--texts t) '("Queued" "Why staged? (sent)")))
      ;; With a prefix argument it is only pasted, and the agent is shown.
      (magit-review-comment-send "Just paste" nil t)
      (should (equal (cadr (car magit-review-test--sent)) nil))
      (should (get-buffer-window (magit-review-test--agent)))
      (should (equal (magit-review-test--texts) '("Queued"))))))

(ert-deftest magit-review-test-send-marks-sent ()
  "A hand-off marks what it sent, which is not handed off again."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "First")
      (magit-review-send)
      (should (null (magit-review-test--texts)))
      (should (equal (magit-review-test--texts t) '("First (sent)")))
      (should (string-match-p
               "No pending review comments"
               (cadr (should-error (magit-review-send) :type 'user-error))))
      ;; Pasting hands off only what is new, without submitting it.
      (magit-review-comment "Second")
      (magit-review-paste)
      (should (equal (cadr (car magit-review-test--sent)) nil))
      (should (string-match-p "^Second$" (magit-review-test--prompt)))
      (should-not (string-match-p "^First$" (magit-review-test--prompt)))
      (should (equal (magit-review-test--texts t) '("First (sent)" "Second (sent)"))))))

(ert-deftest magit-review-test-list ()
  "The list shows pending comments, and sent ones too with a prefix."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (should-error (magit-review-list) :type 'user-error)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "First")
      (magit-review-send)
      (magit-review-test--goto "^@@ -1,2 \\+1,2 @@" 'staged)
      (magit-review-comment "Second")
      (cl-flet ((listed (&optional include-sent)
                  (magit-review-list include-sent)
                  (with-current-buffer "*magit-review*"
                    (buffer-substring-no-properties (point-min) (point-max)))))
        (let ((pending (listed)))
          (should-not (string-match-p "^First$" pending))
          (should (string-match-p
                   "^## b\\.el new L1-2 old L1-2 (staged changes)\n\nSecond$"
                   pending)))
        (let ((all (listed t)))
          (should (string-match-p
                   (concat "^## a\\.el new L7-13 old L7-13 (unstaged changes)"
                           " \\[already sent\\]\n\nFirst$")
                   all))
          (should (string-match-p "^Second$" all))))
      ;; Listing hands nothing off.
      (should (= 1 (length magit-review-test--sent))))))

(ert-deftest magit-review-test-discard ()
  "Discarding forgets pending comments after asking; a prefix forgets sent ones."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment-send "Sent")
      (magit-review-comment "Pending one")
      (magit-review-comment "Pending two")
      (let (asked)
        (cl-letf (((symbol-function 'y-or-n-p)
                   (lambda (prompt) (push prompt asked) nil)))
          (magit-review-discard))
        (should (equal asked '("Discard 2 review comment(s)? ")))
        (should (equal (magit-review-test--texts) '("Pending one" "Pending two"))))
      (cl-letf (((symbol-function 'y-or-n-p) #'always))
        (magit-review-discard)
        (should (null (magit-review-test--texts)))
        (should (equal (magit-review-test--texts t) '("Sent (sent)")))
        (magit-review-discard t)
        (should (null (magit-review-test--texts t)))
        (should-error (magit-review-discard t) :type 'user-error)))))

(ert-deftest magit-review-test-no-agent ()
  "Without a send function the hand-off says so."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "First")
      (let ((magit-review-send-function nil))
        (should (string-match-p
                 "No agent is configured"
                 (cadr (should-error (magit-review-send) :type 'user-error)))))
      (should (equal (magit-review-test--texts) '("First"))))))

;;; Drawing

(defun magit-review-test--drawn ()
  "Return the review comments drawn in the current buffer, in buffer order.
Each is (LINE . TEXT): the line they are drawn below, its runs of spaces
collapsed, and the text drawn there, with its faces."
  (mapcar (lambda (overlay)
            (cons (save-excursion
                    (goto-char (overlay-start overlay))
                    (replace-regexp-in-string
                     "  +" " " (buffer-substring-no-properties
                                (line-beginning-position) (line-end-position))))
                  (overlay-get overlay 'after-string)))
          (sort (seq-filter (lambda (overlay) (overlay-get overlay 'magit-review))
                            (overlays-in (point-min) (point-max)))
                (lambda (a b) (< (overlay-start a) (overlay-start b))))))

(defun magit-review-test--plain (drawn)
  "Return DRAWN, from `magit-review-test--drawn', without text properties."
  (mapcar (lambda (entry) (cons (car entry) (substring-no-properties (cdr entry))))
          drawn))

(defun magit-review-test--face-at (text needle)
  "Return the face of TEXT where NEEDLE starts in it."
  (get-text-property (or (string-search needle text)
                         (ert-fail (list "not drawn" needle text)))
                     'face text))

(ert-deftest magit-review-test-drawn-in-status ()
  "Comments are drawn below their last line, unsent highlighted, sent dimmed."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^modified +a\\.el$" 'unstaged)
      (magit-review-comment "File note")
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "Hunk note")
      (magit-review-test--select "^\\+line 10 changed$" "^\\+line 10 changed$")
      (magit-review-comment "Added note")
      (magit-review-test--select "^-line 10$" "^-line 10$")
      (magit-review-comment "Removed note")
      (should (equal (magit-review-test--plain (magit-review-test--drawn))
                     '(("modified a.el" . "  [4 review comments]\n    ▶ File note")
                       ("-line 10" . "\n    ▶ Removed note")
                       ("+line 10 changed" . "\n    ▶ Added note")
                       (" line 13" . "\n    ▶ Hunk note"))))
      (dolist (entry (magit-review-test--drawn))
        (should (eq (magit-review-test--face-at (cdr entry) "▶")
                    'magit-review-comment)))
      (should (eq (magit-review-test--face-at (cdar (magit-review-test--drawn)) "[4")
                  'magit-review-comment))
      ;; Once sent, they stay drawn, dimmed; the count still counts them.
      (magit-review-send)
      (should (equal (magit-review-test--plain (magit-review-test--drawn))
                     '(("modified a.el" . "  [4 review comments]\n    ▶ File note (sent)")
                       ("-line 10" . "\n    ▶ Removed note (sent)")
                       ("+line 10 changed" . "\n    ▶ Added note (sent)")
                       (" line 13" . "\n    ▶ Hunk note (sent)"))))
      (dolist (entry (magit-review-test--drawn))
        (should (eq (magit-review-test--face-at (cdr entry) "▶")
                    'magit-review-sent)))
      ;; A refresh draws them again, and discarding removes them.
      (magit-refresh-buffer)
      (should (= 4 (length (magit-review-test--drawn))))
      (cl-letf (((symbol-function 'y-or-n-p) #'always))
        (magit-review-discard t))
      (should (null (magit-review-test--drawn))))))

(defun magit-review-test--show (mode command &rest args)
  "Call Magit COMMAND with ARGS and return its MODE buffer, files expanded."
  (let ((buffer (save-window-excursion
                  (apply command args)
                  (magit-get-mode-buffer mode))))
    (with-current-buffer buffer
      (magit-review-test--expand))
    buffer))

(defun magit-review-test--walkthrough (base head)
  "Install a walkthrough of the fixture from BASE to HEAD; return its buffer.
Its one step owns a.el, with a finding anchored at line 20 and a general
finding not tied to a line."
  (let ((draft (make-temp-file "magit-review-draft" nil ".json"))
        (walkthrough-open-after-install nil))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'utf-8))
            (with-temp-file draft
              (json-insert
               `((version . 1)
                 (title . "Fixture change")
                 (branch . "feat/x")
                 (base . ,base)
                 (head . ,head)
                 (steps
                  . [((title . "Line 20")
                      (explanation . "Changes line 20 of a.el.")
                      (files . ["a.el"])
                      (findings
                       . [((severity . "high")
                           (title . "Line 20 is wrong")
                           (body . "The changed line breaks the count.")
                           (anchor . ((file . "a.el") (line . 20))))
                          ((severity . "low")
                           (title . "General remark")
                           (body . "Not tied to a line."))]))])))))
          (let ((result (walkthrough-install draft)))
            (unless (eq (car result) 'ok)
              (ert-fail (list "walkthrough not installed" (cdr result))))
            (save-window-excursion
              (walkthrough-open (cdr result)))))
      (delete-file draft))))

(ert-deftest magit-review-test-drawn-in-diff-buffers ()
  "A comment is drawn in every buffer that shows the same diff, only there.
A committed range is labelled by its commits, so a walkthrough of the
same commits shows a comment made in `magit-diff'."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--status)
      (magit-review-test--goto "^@@ -7,7 \\+7,7 @@")
      (magit-review-comment "Unstaged note"))
    (with-current-buffer (magit-review-test--show 'magit-diff-mode #'magit-diff-unstaged)
      (should (equal (assoc " line 13" (magit-review-test--plain (magit-review-test--drawn)))
                     '(" line 13" . "\n    ▶ Unstaged note"))))
    (with-current-buffer (magit-review-test--show 'magit-diff-mode #'magit-diff-range
                                                  "main..feat/x")
      (should (null (magit-review-test--drawn)))
      (magit-review-test--goto "^@@ -17,7 \\+17,7 @@")
      (magit-review-comment "Range note")
      (should (equal (assoc " line 23" (magit-review-test--plain (magit-review-test--drawn)))
                     '(" line 23" . "\n    ▶ Range note"))))
    (with-current-buffer (magit-review-test--walkthrough base head)
      (should (equal (assoc " line 23" (magit-review-test--plain (magit-review-test--drawn)))
                     '(" line 23" . "\n    ▶ Range note"))))
    (with-current-buffer (magit-review-test--status)
      (should-not (seq-find (lambda (entry) (string-search "Range note" (cdr entry)))
                            (magit-review-test--plain (magit-review-test--drawn))))
      (magit-review-send))
    (should (string-match-p
             (concat "^## a\\.el new L17-23 old L17-23 (diff of "
                     base "\\.\\." head ")\n\nRange note$")
             (magit-review-test--prompt)))))

(ert-deftest magit-review-test-revision-comment ()
  "A hunk comment in a commit's revision buffer is labelled with its commits.
Magit records the revision's diff as the range from its parent, so the
label is that range's."
  (magit-review-test--with-repo
    (with-current-buffer (magit-review-test--show 'magit-revision-mode
                                                  #'magit-show-commit head)
      (magit-review-test--goto "^@@ -17,7 \\+17,7 @@")
      (magit-review-comment "Commit note")
      (should (equal (assoc " line 23" (magit-review-test--plain (magit-review-test--drawn)))
                     '(" line 23" . "\n    ▶ Commit note")))
      (magit-review-send))
    (should (string-match-p
             (concat "^## a\\.el new L17-23 old L17-23 (diff of " base "\\.\\." head
                     ")\n\nCommit note\n\n```diff\n@@ -17,7 \\+17,7 @@ line 16\n")
             (magit-review-test--prompt)))))

;;; Walkthrough findings

(defun magit-review-test--goto-finding (title)
  "Move point to the walkthrough finding titled TITLE, the way `n' does."
  (goto-char (point-min))
  (while (not (and (walkthrough-finding-at-point-p)
                   (string-search
                    title
                    (mapconcat
                     #'identity
                     (cons (buffer-substring-no-properties
                            (line-beginning-position) (line-end-position))
                           (mapcan (lambda (overlay)
                                     (delq nil (list (overlay-get overlay 'before-string)
                                                     (overlay-get overlay 'after-string))))
                                   (overlays-at (point))))
                     ""))))
    (walkthrough-next)))

(defun magit-review-test--reply (text)
  "Write TEXT with `@ c' on the finding at point, as the user would."
  (cl-letf (((symbol-function 'read-string) (lambda (&rest _) text)))
    (call-interactively #'magit-review-comment)))

(ert-deftest magit-review-test-findings-and-replies ()
  "Accepted findings and replies go out after the comments, in one prompt.
A reply to a finding already handed off sends it again, as a follow-up."
  (magit-review-test--with-repo
    (let ((label (format "diff of %s..%s" base head))
          (hunk (concat "```diff\n"
                        "@@ -17,7 +17,7 @@ line 16\n"
                        " line 17\n line 18\n line 19\n"
                        "-line 20\n+line 20 changed\n"
                        " line 21\n line 22\n line 23\n"
                        "```\n"))
          ;; walkthrough.el cuts a finding's patch to three rows around
          ;; its anchored line, the removed line counting as one.
          (excerpt (concat "```diff\n"
                           "@@ -18,6 +18,6 @@ line 16\n"
                           " line 18\n line 19\n"
                           "-line 20\n+line 20 changed\n"
                           " line 21\n line 22\n line 23\n"
                           "```\n"))
          (walkthrough (magit-review-test--walkthrough base head)))
      (with-current-buffer walkthrough
        (magit-review-test--goto-finding "Line 20 is wrong")
        (walkthrough-accept)
        (magit-review-test--goto-finding "General remark")
        (magit-review-test--reply "Do it anyway.")
        ;; A finding takes a reply, never a direct comment.
        (should (string-match-p
                 "reply with .@ c. instead"
                 (cadr (should-error (call-interactively #'magit-review-comment-send)
                                     :type 'user-error))))
        (magit-review-test--goto "^@@ -17,7 \\+17,7 @@")
        (magit-review-comment "Hunk note")
        (magit-review-send))
      (should (equal (magit-review-test--prompt)
                     (concat
                      "Please address my review comments and the review "
                      "findings I accepted.  Each one names the file, the "
                      "new/old line range and the diff it refers to.\n"
                      "\n"
                      "## a.el new L17-23 old L17-23 (" label ")\n"
                      "\n"
                      "Hunk note\n"
                      "\n"
                      hunk
                      "\n"
                      "## Finding [high] Line 20 is wrong: a.el new L20-20 (" label ")\n"
                      "\n"
                      "The changed line breaks the count.\n"
                      "\n"
                      excerpt
                      "\n"
                      "## Finding [low] General remark: no file (" label ")\n"
                      "\n"
                      "Not tied to a line.\n"
                      "\n"
                      "My reply: Do it anyway.\n")))
      (should (null (magit-review-test--texts)))
      (with-current-buffer walkthrough
        (magit-review-test--goto-finding "Line 20 is wrong")
        (magit-review-test--reply "Still wrong.")
        (magit-review-send))
      (should (equal (magit-review-test--prompt)
                     (concat
                      "Please address my review comments and the review "
                      "findings I accepted.  Each one names the file, the "
                      "new/old line range and the diff it refers to.\n"
                      "\n"
                      "## Follow-up on finding [high] Line 20 is wrong: "
                      "a.el new L20-20 (" label ")\n"
                      "\n"
                      "The changed line breaks the count.\n"
                      "\n"
                      "My reply: Still wrong.\n"
                      "\n"
                      excerpt)))
      (should (null (magit-review-test--texts))))))

(provide 'magit-review-test)
;;; magit-review-test.el ends here
