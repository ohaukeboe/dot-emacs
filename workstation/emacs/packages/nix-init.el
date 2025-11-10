;;; nix-init.el --- Utilities for working with Nix-shell -*- lexical-binding: t; -*-

;;; Commentary:

;; This file provides utilities for working with Nix-shell files. It
;; assumes that the Nix-shell file is in the root of the project and
;; that you use direnv.

;; TODO: Add a function to add a package to the shell.nix file.
;; TODO: nix-direnv has a template flake which could be used for flake projects.

;;; Code:

(defvar nix-init--shell-file-content
  "{ pkgs ? import <nixpkgs> {} }:\n  pkgs.mkShell {\n    nativeBuildInputs = with pkgs.buildPackages; [\n      ruby_3_2\n    ];\n}")

(defun nix-init--write-direnv ()
  "Create a .envrc file in the root of the project."
  (write-region "use nix" nil (expand-file-name ".envrc" (project-root (project-current)))))

(defun nix-init--write-nix-shell ()
  "Create a shell.nix file in the root of the project."
  (write-region nix-init--shell-file-content nil (expand-file-name "shell.nix" (project-root (project-current)))))

;;;###autoload
(defun nix-init-edit-nix-shell ()
  "Open the shell.nix file in the current project."
  (interactive)
  (find-file (expand-file-name "shell.nix" (project-root (project-current)))))

;;;###autoload
(defun nix-init-project ()
  "Initialize a nix shell environment in current project."
  (interactive)

  (cond
   ((not (project-current))
    (message "No project found."))
   ((file-exists-p (expand-file-name "shell.nix" (project-root (project-current))))
    (message "shell.nix file already exists."))
   ((file-exists-p (expand-file-name ".envrc" (project-root (project-current))))
    (message ".envrc file already exists."))
   (t
    (progn
      (nix-init--write-nix-shell)
      (nix-init--write-direnv)
      (nix-init-edit-nix-shell)
      (direnv-allow)
      (message "Nix shell initialized.")))))

(provide 'nix-init)

;;; nix-init.el ends here
