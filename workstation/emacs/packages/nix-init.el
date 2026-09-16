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

(defun nix-init--root ()
  "Return the current project's root, or signal if there is none."
  (let ((proj (project-current)))
    (unless proj (user-error "No project found"))
    (project-root proj)))

(defun nix-init--template (name)
  "Return the contents of template NAME."
  (unless nix-init-template-directory
    (user-error "Cannot locate nix-init-templates; is nix-init on `load-path'?"))
  (let ((file (expand-file-name name nix-init-template-directory)))
    (unless (file-readable-p file)
      (user-error "No template at %s" file))
    (with-temp-buffer
      (insert-file-contents file)
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

(defun nix-init--append-gitignore (root entries)
  "Append each of ENTRIES missing from ROOT's .gitignore.
Creates the file when absent and never rewrites lines already there, so
scaffolding a second kind into the same project stays idempotent."
  (let* ((file (expand-file-name ".gitignore" root))
         (existing (when (file-readable-p file)
                     (with-temp-buffer
                       (insert-file-contents file)
                       (split-string (buffer-string) "\n"))))
         (missing (seq-remove (lambda (e) (member e existing)) entries)))
    (when missing
      (with-temp-buffer
        (when (file-readable-p file)
          (insert-file-contents file)
          (goto-char (point-max))
          ;; Keep exactly one blank line between our block and whatever
          ;; precedes it, whether or not the file ended in a newline.
          (unless (bolp) (insert "\n"))
          (unless (looking-back "\n\n" 2) (insert "\n")))
        (insert "# nix-init\n")
        (dolist (entry missing) (insert entry "\n"))
        (write-region (point-min) (point-max) file)))
    missing))

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
         (hit (nix-init--detect root)))
    (unless hit
      (user-error "No Nix environment in %s; run `nix-init-project'"
                  (abbreviate-file-name root)))
    (find-file (expand-file-name (plist-get (cdr hit) :open) root))))


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
         (hit (nix-init--detect root)))
    (unless hit
      (user-error "No Nix environment in %s; run `nix-init-project'"
                  (abbreviate-file-name root)))
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
