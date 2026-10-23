;;; agent-commit-gate.el --- Review an agent's git commit in Magit  -*- lexical-binding: t; -*-

;;; Commentary:

;; The Emacs side of the agent commit gate (workstation/agents/commit-gate.py,
;; docs/adr/0006-agent-commit-gate.md).  When the gate's mode is "emacs", the
;; gate -- a Claude Code hook running outside the agent's sandbox -- calls
;; `agent-commit-gate-review' through emacsclient instead of letting the
;; agent's `git commit' run.  Magit opens its ordinary commit buffer with the
;; agent's message and the staged diff; finishing it makes the commit,
;; cancelling it does not.  The outcome goes back to the gate as
;; REQUEST/result.json, written once git has exited, so it reflects what git
;; did rather than which key was pressed.
;;
;; A review belongs to one waiting gate.  When that gate is gone (the agent
;; was interrupted, or the gate gave up at its deadline) finishing the buffer
;; is refused, so a commit never happens that the agent was not told about.
;;
;; `agent-commit-gate-set' writes the override file the gate reads, to switch
;; the mode per repository or for all of them without a rebuild.

;;; Code:

(require 'json)
(require 'magit)
(require 'with-editor)

(defvar agent-commit-gate--reviews (make-hash-table :test #'equal)
  "Open reviews, keyed by repository toplevel.
Each value is a plist (:request DIR :process PROC :buffer BUF
:cancelled BOOL :done BOOL).")

(defvar-local agent-commit-gate--review nil
  "The review plist of this commit buffer, if it was opened for the gate.")

(defconst agent-commit-gate-modes '("ask" "emacs" "deny")
  "Modes the gate understands.")

;;;; Result

(defun agent-commit-gate--write-result (request result)
  "Write RESULT (an alist) as REQUEST/result.json, atomically."
  (let ((file (expand-file-name "result.json" request))
        (tmp (expand-file-name "result.json.tmp" request)))
    (when (file-directory-p request)
      (with-temp-file tmp
        (insert (json-encode result)))
      (rename-file tmp file t))))

(defun agent-commit-gate--finish (toplevel result)
  "Report RESULT for the review of TOPLEVEL, once, and forget the review."
  (let ((review (gethash toplevel agent-commit-gate--reviews)))
    (when (and review (not (plist-get review :done)))
      (plist-put review :done t)
      (remhash toplevel agent-commit-gate--reviews)
      (agent-commit-gate--write-result (plist-get review :request) result))))

(defun agent-commit-gate--sentinel (toplevel)
  "Return a process sentinel that reports the commit of TOPLEVEL."
  (lambda (process _event)
    (when (memq (process-status process) '(exit signal))
      (let* ((review (gethash toplevel agent-commit-gate--reviews))
             (status (process-exit-status process))
             (default-directory toplevel))
        (agent-commit-gate--finish
         toplevel
         (cond
          ((and (eq (process-status process) 'exit) (zerop status))
           `((status . "committed")
             (sha . ,(magit-rev-parse "HEAD"))
             (subject . ,(magit-rev-format "%s" "HEAD"))))
          ((plist-get review :expired)
           '((status . "not-committed") (reason . "request expired")))
          ((plist-get review :cancelled)
           '((status . "not-committed") (reason . "cancelled by the user")))
          (t
           `((status . "not-committed")
             (reason . ,(format "git commit exited with status %d \
(empty message or a failing commit hook)" status))))))))))

;;;; Stale requests

(defun agent-commit-gate--request-live-p (request)
  "Non-nil while the gate that sent REQUEST is still waiting for it."
  (let ((file (expand-file-name "request.json" request)))
    (when (file-readable-p file)
      (let* ((json-object-type 'plist)
             (data (json-read-file file))
             (pid (plist-get data :gate_pid))
             (deadline (plist-get data :deadline)))
        (and (integerp pid) (process-attributes pid)
             (numberp deadline) (< (float-time) deadline))))))

(defun agent-commit-gate--finish-query (_force)
  "Refuse to finish a review whose gate is no longer waiting.
On `with-editor-finish-query-functions': a nil return aborts the finish."
  (let ((review agent-commit-gate--review))
    (if (or (null review)
            (agent-commit-gate--request-live-p (plist-get review :request)))
        t
      (plist-put review :expired t)
      (message "The agent stopped waiting for this commit; cancelling it")
      (let ((buffer (current-buffer)))
        (run-at-time 0 nil (lambda ()
                             (when (buffer-live-p buffer)
                               (with-current-buffer buffer
                                 (with-editor-cancel t))))))
      nil)))

(defun agent-commit-gate--note-cancel ()
  "Record that the user cancelled this review."
  (when agent-commit-gate--review
    (plist-put agent-commit-gate--review :cancelled t)))

(defun agent-commit-gate--setup-buffer ()
  "Attach a pending review to the commit buffer git just opened.
On `git-commit-setup-hook'."
  (let ((review (gethash (magit-toplevel) agent-commit-gate--reviews)))
    (when (and review (not (plist-get review :buffer)))
      (plist-put review :buffer (current-buffer))
      (setq agent-commit-gate--review review)
      (add-hook 'with-editor-finish-query-functions
                #'agent-commit-gate--finish-query nil t)
      (add-hook 'with-editor-pre-cancel-hook
                #'agent-commit-gate--note-cancel nil t)
      (unless noninteractive
        (select-frame-set-input-focus (window-frame (get-buffer-window nil t)))
        (message "Commit proposed by the agent: C-c C-c commits, C-c C-k declines")))))

;;;; Entry points for the gate

(defun agent-commit-gate--origin-buffer (toplevel)
  "A hidden buffer in TOPLEVEL to start the review's git process from."
  (let ((buffer (get-buffer-create (format " *agent-commit-gate %s*" toplevel))))
    (with-current-buffer buffer
      (setq default-directory toplevel))
    buffer))

;;;###autoload
(defun agent-commit-gate-review (dir request)
  "Open a Magit commit in DIR with the message in REQUEST/msg.
Called by the commit gate through emacsclient; returns t at once.  The
outcome is written to REQUEST/result.json when git exits."
  (let* ((default-directory (file-name-as-directory dir))
         (toplevel (magit-toplevel)))
    (cond
     ((null toplevel)
      (agent-commit-gate--write-result
       request '((status . "not-committed") (reason . "not a git repository"))))
     ((gethash toplevel agent-commit-gate--reviews)
      (agent-commit-gate--write-result
       request '((status . "not-committed")
                 (reason . "review already open in this repository"))))
     (t
      (let ((review (list :request request)))
        (puthash toplevel review agent-commit-gate--reviews)
        (condition-case err
            ;; Magit refreshes the buffer a git command was started from once
            ;; it exits, and fails outside a repository.  The buffer current
            ;; during an emacsclient --eval is arbitrary, so start the commit
            ;; from one that lives in the repository.
            (let ((process
                   (with-current-buffer (agent-commit-gate--origin-buffer toplevel)
                     (magit-commit-create
                      (list "--edit"
                            (concat "--file="
                                    (expand-file-name "msg" request)))))))
              (if (not (processp process))
                  (agent-commit-gate--finish
                   toplevel '((status . "not-committed")
                              (reason . "magit refused: nothing to commit")))
                (plist-put review :process process)
                ;; Before Magit's own sentinel, so an error there cannot
                ;; keep the gate from hearing the outcome.
                (add-function :before (process-sentinel process)
                              (agent-commit-gate--sentinel toplevel))))
          (error
           (agent-commit-gate--finish
            toplevel `((status . "not-committed")
                       (reason . ,(format "magit refused: %s"
                                          (error-message-string err))))))))))
    t))

;;;###autoload
(defun agent-commit-gate-review-cancel (request)
  "Withdraw the review for REQUEST, which the gate stopped waiting for."
  (maphash
   (lambda (_toplevel review)
     (when (equal (plist-get review :request) request)
       (plist-put review :expired t)
       (let ((buffer (plist-get review :buffer))
             (process (plist-get review :process)))
         (cond ((buffer-live-p buffer)
                (with-current-buffer buffer (with-editor-cancel t)))
               ((process-live-p process)
                (kill-process process))))))
   agent-commit-gate--reviews)
  t)

(add-hook 'git-commit-setup-hook #'agent-commit-gate--setup-buffer)

;;;; Mode override

(defun agent-commit-gate-override-file ()
  "The override file the gate reads; see commit-gate.py `override_path'."
  (expand-file-name "agent-commit-gate/override.json"
                    (or (getenv "XDG_STATE_HOME") "~/.local/state")))

(defun agent-commit-gate--read-overrides ()
  "The override file as an alist of (KEY . MODE), or nil."
  (let ((file (agent-commit-gate-override-file)))
    (when (file-readable-p file)
      (condition-case nil
          (let ((json-object-type 'alist) (json-key-type 'string))
            (json-read-file file))
        (error nil)))))

(defun agent-commit-gate--repository-key ()
  "The gate's key for the current repository: its absolute common git dir."
  (when-let* ((dir (magit-git-string "rev-parse" "--path-format=absolute"
                                     "--git-common-dir")))
    (directory-file-name (file-truename dir))))

;;;###autoload
(defun agent-commit-gate-set (scope mode)
  "Set the agent commit gate MODE for SCOPE.
SCOPE is the current repository's key or \"*\".  MODE \"default\" removes
the override, so the next source applies.  The gate reads the file on
every commit, so the change takes effect at once."
  (interactive
   (let ((key (agent-commit-gate--repository-key)))
     (list (if (and key (y-or-n-p (format "Only for %s? " key))) key "*")
           (completing-read "Agent commit mode: "
                            (append agent-commit-gate-modes '("default"))
                            nil t))))
  (let* ((file (agent-commit-gate-override-file))
         (overrides (assoc-delete-all scope (agent-commit-gate--read-overrides))))
    (unless (equal mode "default")
      (push (cons scope mode) overrides))
    (make-directory (file-name-directory file) t)
    (let ((tmp (concat file ".tmp")))
      (with-temp-file tmp
        (insert (if overrides (json-encode overrides) "{}")))
      (rename-file tmp file t))
    (message "Agent commits for %s: %s" scope mode)))

;;;###autoload
(defun agent-commit-gate-show ()
  "Show the override that applies to the current repository.
A session started with AGENT_COMMIT_GATE set takes precedence over this,
and Emacs cannot see that; without an override the Nix default applies."
  (interactive)
  (let* ((overrides (agent-commit-gate--read-overrides))
         (key (agent-commit-gate--repository-key))
         (repo (and key (cdr (assoc key overrides))))
         (all (cdr (assoc "*" overrides))))
    (message "Agent commits: %s (AGENT_COMMIT_GATE at launch would override)"
             (cond (repo (format "%s, set for this repository" repo))
                   (all (format "%s, set for all repositories" all))
                   (t "the Nix default (agents.commitGate.mainCheckout)")))))

(provide 'agent-commit-gate)
;;; agent-commit-gate.el ends here
