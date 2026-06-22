;; -*- lexical-binding: t; -*-
;;; nix-init.el --- Utilities for working with Nix-shell

;;; Commentary:

;; This file provides utilities for working with Nix-shell files. It
;; assumes that the Nix-shell file is in the root of the project and
;; that you use direnv.

;;; Code:

(defvar nix-init--shell-file-content
  "{ pkgs ? import <nixpkgs> {} }:\n  pkgs.mkShell {\n    nativeBuildInputs = with pkgs.buildPackages; [\n      ruby_3_2\n    ];\n}")

(defvar nix-init--flake-file-content
  "{
  description = \"A basic flake with a shell\";
  inputs.nixpkgs.url = \"github:NixOS/nixpkgs/nixpkgs-unstable\";
  inputs.systems.url = \"github:nix-systems/default\";
  inputs.flake-utils = {
    url = \"github:numtide/flake-utils\";
    inputs.systems.follows = \"systems\";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell { packages = [ pkgs.bashInteractive ]; };
      }
    );
}
"
  "Template flake.nix content from nix-direnv.")

(defun nix-init--write-direnv ()
  "Create a .envrc file in the root of the project."
  (write-region "use nix" nil (expand-file-name ".envrc" (project-root (project-current)))))

(defun nix-init--write-flake-direnv ()
  "Create a .envrc file using 'use flake' for flake projects."
  (write-region "use flake" nil (expand-file-name ".envrc" (project-root (project-current)))))

(defun nix-init--write-nix-shell ()
  "Create a shell.nix file in the root of the project."
  (write-region nix-init--shell-file-content nil (expand-file-name "shell.nix" (project-root (project-current)))))

(defun nix-init--write-flake ()
  "Create a flake.nix file in the root of the project."
  (write-region nix-init--flake-file-content nil (expand-file-name "flake.nix" (project-root (project-current)))))

;;;###autoload
(defun nix-init-edit-nix-shell ()
  "Open the shell.nix file in the current project."
  (interactive)
  (find-file (expand-file-name "shell.nix" (project-root (project-current)))))

;;;###autoload
(defun nix-init-edit-flake ()
  "Open the flake.nix file in the current project."
  (interactive)
  (find-file (expand-file-name "flake.nix" (project-root (project-current)))))

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

;;;###autoload
(defun nix-init-flake-project ()
  "Initialize a Nix flake dev environment in current project."
  (interactive)
  (cond
   ((not (project-current))
    (message "No project found."))
   ((file-exists-p (expand-file-name "flake.nix" (project-root (project-current))))
    (message "flake.nix already exists."))
   ((file-exists-p (expand-file-name ".envrc" (project-root (project-current))))
    (message ".envrc already exists."))
   (t
    (nix-init--write-flake)
    (nix-init--write-flake-direnv)
    (nix-init-edit-flake)
    (direnv-allow)
    (message "Nix flake initialized."))))

(provide 'nix-init)

;;; nix-init.el ends here
