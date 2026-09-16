;; -*- lexical-binding: t; -*-
;;; nix-init.el --- Scaffold Nix dev environments for a project

;;; Commentary:

;; Writes the files a project needs to get a Nix development environment,
;; picked from four `nix-init-kinds': a bare shell.nix, a flake, devenv, or
;; services-flake.  Every kind also gets an .envrc, so this assumes direnv on
;; the shell side and `envrc' on the Emacs side.
;;
;; Nothing here starts a service.  direnv only ever enters an environment;
;; the services a kind declares are started by their own supervisor -- `just
;; up' for services-flake, `devenv up' for devenv.
;;
;; Secrets are an orthogonal axis: any kind can carry any of
;; `nix-init-backends', or none, added after the fact by `nix-init-secrets'.
;; Only the dotenv backend is load-time -- direnv exports it into every
;; process under the project, which under `envrc' means everything Emacs
;; spawns there.  sops and secretspec are explicit-run: their secrets reach
;; the one child process that asked, via `nix-init-secrets-run'.

;;; Code:

(require 'project)
(require 'seq)
(require 'subr-x)

(declare-function envrc-allow "envrc" ())

(defconst nix-init-kinds
  '(("shell" .
     (:files (("shell.nix" . "shell.nix"))
      :marker "shell.nix"
      :open "shell.nix"
      :envrc "use nix\n"
      :ignore ()))
    ("flake" .
     (:files (("flake.nix" . "flake.nix"))
      :marker "flake.nix"
      :open "flake.nix"
      :envrc "use flake\n"
      :ignore ()))
    ("devenv" .
     (:files (("devenv.nix" . "devenv.nix")
              ("devenv.justfile" . "justfile"))
      :marker "devenv.nix"
      :open "devenv.nix"
      :envrc "eval \"$(devenv direnvrc)\"\nuse devenv\n"
      :ignore (".devenv*" "devenv.local.nix" "devenv.local.yaml")
      ;; devenv has no streaming mode: `up' renders a TUI and writes
      ;; nothing to a pipe, so Emacs starts it detached.
      :up "up-detached"))
    ("services-flake" .
     (:files (("services-flake.nix" . "flake.nix")
              ("services-flake.justfile" . "justfile"))
      :marker "flake.nix"
      ;; Shares its marker with the plain `flake' kind, so identifying an
      ;; existing project needs the file's content, not just its name.
      :detect "services-flake"
      :open "flake.nix"
      :envrc "use flake\n"
      :ignore ("data/" ".process-compose.sock" ".process-compose.log")
      ;; process-compose streams plain prefixed logs with its TUI off,
      ;; which is exactly what a compilation buffer wants.
      :up "up-headless")))
  "Environment kinds `nix-init-project' can scaffold.

Each entry maps a kind's name to a plist:

  :files   alist of (TEMPLATE . DESTINATION), both relative names.
  :marker  file whose presence means this kind is already set up.
  :detect  regexp that must also match the marker's contents, for kinds
           that share a marker with another kind.
  :open    file to visit once scaffolding finishes.
  :envrc   loader directive written to .envrc.
  :ignore  .gitignore entries this kind needs, beyond the shared ones.
  :up      just recipe that starts this kind's services, nil when it has none.")

(defconst nix-init-shared-ignore '(".direnv/")
  "Entries every kind adds to .gitignore.  direnv caches into .direnv.")

(defgroup nix-init nil
  "Scaffolding for a project's Nix development environment."
  :group 'tools
  :prefix "nix-init-")

(defcustom nix-init-sops-recipient nil
  "Age recipient that scaffolded projects encrypt their secrets to.

Deliberately not the shared host key that provisions machines: a project
repository should never carry that.  See docs/adr/0002 in the workstation
config.  When nil, `nix-init-secrets' writes a placeholder into .sops.yaml
and says so rather than falling back to another key."
  :type '(choice (const :tag "Unset (write a placeholder)" nil) string)
  :group 'nix-init)

(defconst nix-init-backends
  '(("secretspec" .
     (:files (("secretspec.toml" . "secretspec.toml")
              ("secrets.sops.yaml" . ".sops.yaml")
              ("secretspec.justfile" . "secrets.justfile"))
      ;; devenv resolves secretspec itself, and needs to be told to.
      :kind-files (("devenv" . (("devenv.yaml" . "devenv.yaml"))))
      :marker "secretspec.toml"
      :open "secretspec.toml"
      :ignore ()
      :run "run"
      ;; devenv resolves secretspec natively; every other kind is better
      ;; served by sops directly.
      :default-for ("devenv")
      :next-steps "declare names in secretspec.toml, then `just -f secrets.justfile check'"))
    ("sops" .
     (:files (("secrets.sops.yaml" . ".sops.yaml")
              ("secrets.justfile" . "secrets.justfile"))
      :marker ".sops.yaml"
      :open ".sops.yaml"
      :ignore ()
      :run "run"
      :next-steps "`just -f secrets.justfile edit' creates secrets.enc.yaml"))
    ("dotenv" .
     (:files (("secrets.env" . ".env"))
      :marker ".env"
      ;; .env is not ours the way .sops.yaml and secretspec.toml are -- Node,
      ;; docker-compose and pytest all use it -- so the file has to say so, or
      ;; an unrelated .env would be reported as a backend nobody added.
      :detect "^# nix-init: dotenv"
      :open ".env"
      :envrc-append "dotenv_if_exists .env"
      :ignore (".env")
      :next-steps ".env is plaintext and gitignored, and direnv exports it to every process here")))
  "Secrets backends `nix-init-secrets' can add to a project.

A backend is orthogonal to the environment kind: any kind can carry any
backend, or none.  Each entry maps a backend's name to a plist:

  :files         alist of (TEMPLATE . DESTINATION), both relative names.
  :kind-files    alist of (KIND . FILES), written only for that kind.
  :marker        file whose presence means this backend is already set up.
  :open          file to visit once the backend is written.
  :ignore        .gitignore entries this backend needs.  Empty for the
                 encrypted backends: their secrets file is meant to be
                 committed, which is the whole point of encrypting it.
  :detect        regexp the marker's contents must match too, for a marker
                 that other tools also use.
  :envrc-append  line to add to .envrc, for load-time backends only.
  :run           secrets.justfile recipe that wraps a command, nil for a
                 load-time backend, which has nothing to wrap.
  :default-for   kinds this backend is offered as the default for.
  :next-steps    what is left for you to do once the files are written.

Order matters for detection: secretspec also writes the .sops.yaml that
identifies the sops backend, so it has to be tried first.")

(defvar nix-init-template-directory
  (let ((lib (locate-library "nix-init")))
    (when lib
      (expand-file-name "nix-init-templates" (file-name-directory lib))))
  "Directory holding the template files, resolved next to this library.")

(defun nix-init--detect (root)
  "Return the (NAME . SPEC) entry describing the environment at ROOT, or nil.

Kinds carrying a :detect regexp are tried first: `flake\' and
`services-flake\' share the flake.nix marker, and only the content tells
them apart.  A kind without :detect matches on its marker alone, so it acts
as the fallback."
  (let ((matches (lambda (entry want-detect)
                   (let* ((spec (cdr entry))
                          (marker (expand-file-name (plist-get spec :marker) root))
                          (detect (plist-get spec :detect)))
                     (and (file-exists-p marker)
                          (if want-detect
                              (and detect
                                   (with-temp-buffer
                                     (insert-file-contents marker)
                                     (goto-char (point-min))
                                     (re-search-forward detect nil t)))
                            (null detect))
                          entry)))))
    (or (seq-some (lambda (e) (funcall matches e t)) nix-init-kinds)
        (seq-some (lambda (e) (funcall matches e nil)) nix-init-kinds))))

(defun nix-init--require-kind (root)
  "Return the (NAME . SPEC) kind entry at ROOT, or signal if there is none."
  (or (nix-init--detect root)
      (user-error "No Nix environment in %s; run `nix-init-project'"
                  (abbreviate-file-name root))))

(defun nix-init--root ()
  "Return the current project's root, or signal if there is none."
  (let ((proj (project-current)))
    (unless proj (user-error "No project found"))
    (project-root proj)))

(defun nix-init--template (name &optional replacements)
  "Return the contents of template NAME.

REPLACEMENTS is an alist of (PLACEHOLDER . VALUE), each replaced literally.
Kind templates carry no placeholders and pass nil; only the backends need
to splice in a project name and an age recipient."
  (unless nix-init-template-directory
    (user-error "Cannot locate nix-init-templates; is nix-init on `load-path'?"))
  (let ((file (expand-file-name name nix-init-template-directory)))
    (unless (file-readable-p file)
      (user-error "No template at %s" file))
    (with-temp-buffer
      (insert-file-contents file)
      (pcase-dolist (`(,placeholder . ,value) replacements)
        (goto-char (point-min))
        (while (search-forward placeholder nil t)
          (replace-match value t t)))
      (buffer-string))))

(defun nix-init--envrc-directive (root)
  "Return the first non-blank, non-comment line of ROOT's .envrc, or nil."
  (let ((file (expand-file-name ".envrc" root)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (catch 'found
          (while (not (eobp))
            (let ((line (string-trim (buffer-substring-no-properties
                                      (line-beginning-position) (line-end-position)))))
              (unless (or (string-empty-p line) (string-prefix-p "#" line))
                (throw 'found line)))
            (forward-line 1))
          nil)))))

(defun nix-init--file-lines (file)
  "Return FILE's lines, or nil when it cannot be read."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (split-string (buffer-string) "\n"))))

(defun nix-init--append-gitignore (root entries)
  "Append each of ENTRIES missing from ROOT's .gitignore.
Creates the file when absent and never rewrites lines already there, so
scaffolding a second kind into the same project stays idempotent."
  (let* ((file (expand-file-name ".gitignore" root))
         (existing (nix-init--file-lines file))
         (missing (seq-remove (lambda (e) (member e existing)) entries)))
    (when missing
      (with-temp-buffer
        (when (file-readable-p file) (insert-file-contents file))
        (goto-char (point-min))
        (if (re-search-forward "^# nix-init$" nil t)
            ;; Extend the block we already own rather than starting a second
            ;; one: adding a secrets backend to a scaffolded project makes a
            ;; second call the normal case, not the exception.
            (progn
              (forward-line 1)
              (while (and (not (eobp)) (not (looking-at-p "^[ \t]*$")))
                (forward-line 1))
              ;; A file with no trailing newline leaves point mid-line, which
              ;; would glue the first new entry onto the last existing one.
              (unless (bolp) (insert "\n"))
              (dolist (entry missing) (insert entry "\n")))
          (goto-char (point-max))
          (unless (bobp)
            ;; Keep exactly one blank line between our block and whatever
            ;; precedes it, whether or not the file ended in a newline.
            (unless (bolp) (insert "\n"))
            (unless (looking-back "\n\n" 2) (insert "\n")))
          (insert "# nix-init\n")
          (dolist (entry missing) (insert entry "\n")))
        (write-region (point-min) (point-max) file)))
    missing))

(defun nix-init--append-envrc (root line)
  "Append LINE to ROOT's .envrc unless it is already there.
A load-time backend has to add its directive to an .envrc the kind already
wrote, so unlike the files a kind or backend owns, this one is edited rather
than replaced."
  (let* ((file (expand-file-name ".envrc" root))
         (existing (nix-init--file-lines file)))
    (unless (member line existing)
      (with-temp-buffer
        (when (file-readable-p file)
          (insert-file-contents file)
          (goto-char (point-max))
          (unless (bolp) (insert "\n")))
        (insert line "\n")
        (write-region (point-min) (point-max) file)))))

;;;###autoload
(defun nix-init-project (kind)
  "Scaffold a Nix development environment of KIND in the current project.

Writes the kind's files, an .envrc carrying its loader directive, and the
.gitignore entries it needs, then visits the kind's main file.  Refuses a
kind whose marker file is already present, and refuses outright if an
.envrc exists, since a project has only one."
  (interactive
   (list (completing-read "Environment kind: "
                          (mapcar #'car nix-init-kinds) nil t nil nil "flake")))
  (let* ((spec (or (cdr (assoc kind nix-init-kinds))
                   (user-error "Unknown environment kind: %s" kind)))
         (root (nix-init--root))
         (marker (plist-get spec :marker))
         (directive (nix-init--envrc-directive root)))
    (when (file-exists-p (expand-file-name marker root))
      (user-error "Cannot scaffold %s: %s already exists" kind marker))
    (when directive
      (user-error "%s already has an .envrc (%s); remove it first"
                  (abbreviate-file-name root) directive))
    (pcase-dolist (`(,template . ,destination) (plist-get spec :files))
      (write-region (nix-init--template template) nil
                    (expand-file-name destination root)))
    (write-region (plist-get spec :envrc) nil (expand-file-name ".envrc" root))
    (nix-init--append-gitignore
     root (append nix-init-shared-ignore (plist-get spec :ignore)))
    (find-file (expand-file-name (plist-get spec :open) root))
    (envrc-allow)
    (message "Scaffolded %s environment in %s" kind (abbreviate-file-name root))))

;;;###autoload
(defun nix-init-edit ()
  "Visit the main file of whichever environment this project has."
  (interactive)
  (let* ((root (nix-init--root))
         (hit (nix-init--require-kind root)))
    (find-file (expand-file-name (plist-get (cdr hit) :open) root))))


;;; Secrets
;;
;; Orthogonal to the kind: `nix-init-secrets' works on whatever environment
;; the project already has, so secrets can be added the day they are first
;; needed rather than at scaffold time.  A backend replaces only files it
;; owns; the two files it shares with the kind -- .envrc and .gitignore -- it
;; appends to instead, idempotently.
;;
;; The backend never creates key material.  It writes configuration that
;; references a key and tells you what is left to do; generating an age key,
;; and choosing where it lives, stays a deliberate act.

(defun nix-init--default-backend (kind)
  "Return the backend offered by default for KIND.
Falls back to sops, which is the one that survives a fresh clone on another
machine."
  (or (car (seq-find (lambda (entry)
                       (member kind (plist-get (cdr entry) :default-for)))
                     nix-init-backends))
      "sops"))

(defun nix-init--detect-backend (root)
  "Return the (NAME . SPEC) entry for ROOT's secrets backend, or nil.
A backend carrying :detect must match the marker's contents as well, so a
file another tool happens to use is not mistaken for one of ours."
  (seq-find (lambda (entry)
              (let* ((spec (cdr entry))
                     (marker (expand-file-name (plist-get spec :marker) root))
                     (detect (plist-get spec :detect)))
                (and (file-exists-p marker)
                     (or (null detect)
                         (with-temp-buffer
                           (insert-file-contents marker)
                           (goto-char (point-min))
                           (and (re-search-forward detect nil t) t))))))
            nix-init-backends))

(defun nix-init--secrets-next-steps (backend spec)
  "Return the message describing what BACKEND, described by SPEC, still needs.
An unset `nix-init-sops-recipient' is worth saying out loud: the backend
wrote a placeholder rather than encrypting to the wrong key."
  (concat (format "Added %s secrets: %s" backend (plist-get spec :next-steps))
          (unless (or nix-init-sops-recipient (null (plist-get spec :run)))
            "; set `nix-init-sops-recipient' and fix the recipient in .sops.yaml")))

;;;###autoload
(defun nix-init-secrets (backend)
  "Add a secrets BACKEND to this project's Nix environment.

Refuses a project with no environment, one that already has a backend, and
one where any file the backend would write is already present, all before
writing anything."
  (interactive
   (let* ((root (nix-init--root))
          (kind (car (nix-init--require-kind root))))
     (list (completing-read "Secrets backend: "
                            (mapcar #'car nix-init-backends) nil t nil nil
                            (nix-init--default-backend kind)))))
  (let* ((spec (or (cdr (assoc backend nix-init-backends))
                   (user-error "Unknown secrets backend: %s" backend)))
         (root (nix-init--root))
         (kind (car (nix-init--require-kind root)))
         (existing (nix-init--detect-backend root))
         (files (append (plist-get spec :files)
                        (cdr (assoc kind (plist-get spec :kind-files)))))
         (replacements
          `(("@PROJECT@" . ,(file-name-nondirectory (directory-file-name root)))
            ("@AGE_RECIPIENT@" . ,(or nix-init-sops-recipient
                                      "REPLACE_WITH_AN_AGE_RECIPIENT")))))
    (when existing
      (user-error "%s already has a %s secrets backend"
                  (abbreviate-file-name root) (car existing)))
    (pcase-dolist (`(,_template . ,destination) files)
      (when (file-exists-p (expand-file-name destination root))
        (user-error "Cannot add %s secrets: %s already exists" backend destination)))
    (pcase-dolist (`(,template . ,destination) files)
      (write-region (nix-init--template template replacements) nil
                    (expand-file-name destination root)))
    (when-let* ((line (plist-get spec :envrc-append)))
      (nix-init--append-envrc root line)
      (envrc-allow))
    (nix-init--append-gitignore root (plist-get spec :ignore))
    (find-file (expand-file-name (plist-get spec :open) root))
    (message "%s" (nix-init--secrets-next-steps backend spec))))

;;;###autoload
(defun nix-init-secrets-run (command)
  "Run COMMAND with this project's secrets in its environment.

Goes through the backend's secrets.justfile, so a terminal and Emacs run
the same thing.  Signals for a load-time backend, whose secrets direnv has
already exported and which has nothing to wrap."
  (interactive (list (read-shell-command "Run with secrets: ")))
  (let* ((root (nix-init--root))
         (hit (or (nix-init--detect-backend root)
                  (user-error "No secrets backend in %s; run `nix-init-secrets'"
                              (abbreviate-file-name root))))
         (recipe (or (plist-get (cdr hit) :run)
                     (user-error "%s secrets are load-time; direnv has already exported them"
                                 (car hit))))
         (default-directory root))
    (compile (format "just -f secrets.justfile %s %s"
                     recipe (shell-quote-argument command)))))


;;; Services
;;
;; Both service-capable kinds ship a justfile, so every command here is `just
;; RECIPE' run from the project root -- Emacs and a terminal do the same
;; thing.  The two differ in one way that is worth knowing rather than hiding:
;; services-flake streams plain logs when its TUI is off, so `up' keeps a live
;; compilation buffer, while devenv has no streaming mode at all and starts
;; detached, so its buffer exits immediately and you read state back with
;; `nix-init-services-status' or by attaching.

(declare-function eat-mode "eat" ())
(declare-function eat-exec "eat" (buffer name command startfile switches))

(defun nix-init--services-kind ()
  "Return (ROOT . SPEC) for this project's kind, or signal if it has no services."
  (let* ((root (nix-init--root))
         (hit (nix-init--require-kind root)))
    (unless (plist-get (cdr hit) :up)
      (user-error "A %s environment declares no services" (car hit)))
    (cons root (cdr hit))))

(defun nix-init--services-buffer-name (root)
  "Name of the services buffer for the project at ROOT."
  (format "*services: %s*"
          (file-name-nondirectory (directory-file-name root))))

(defun nix-init--services-run (recipe)
  "Run `just RECIPE' in a compilation buffer for the current project.
Pops to an existing live buffer instead of starting a second group."
  (pcase-let* ((`(,root . ,_spec) (nix-init--services-kind))
               (name (nix-init--services-buffer-name root))
               (buffer (get-buffer name)))
    (if (and buffer (get-buffer-process buffer))
        (progn (pop-to-buffer buffer)
               (message "Services already running here; `nix-init-services-down' to stop"))
      (let ((default-directory root)
            (compilation-buffer-name-function (lambda (&rest _) name)))
        (compile (format "just %s" recipe))))))

;;;###autoload
(defun nix-init-services-up ()
  "Start this project's services."
  (interactive)
  (nix-init--services-run (plist-get (cdr (nix-init--services-kind)) :up)))

;;;###autoload
(defun nix-init-services-down ()
  "Stop this project's services."
  (interactive)
  (pcase-let ((`(,root . ,_spec) (nix-init--services-kind)))
    (let ((default-directory root))
      (compile "just down"))))

;;;###autoload
(defun nix-init-services-status ()
  "Show this project's processes and their states."
  (interactive)
  (pcase-let ((`(,root . ,_spec) (nix-init--services-kind)))
    (let ((default-directory root))
      (compile "just status"))))

;;;###autoload
(defun nix-init-services-attach ()
  "Attach a terminal to this project's running services.
The process-compose TUI needs a tty, so this runs in `eat' rather than in a
compilation buffer."
  (interactive)
  (unless (require 'eat nil t)
    (user-error "Attaching needs the `eat' package"))
  (pcase-let* ((`(,root . ,_spec) (nix-init--services-kind))
               (default-directory root)
               (buffer (get-buffer-create
                        (format "*services attach: %s*"
                                (file-name-nondirectory (directory-file-name root))))))
    (with-current-buffer buffer
      (unless (get-buffer-process buffer)
        (eat-mode)
        (eat-exec buffer (buffer-name) "just" nil (list "attach"))))
    (pop-to-buffer buffer)))

(provide 'nix-init)

;;; nix-init.el ends here
