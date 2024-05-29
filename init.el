;; Emacs init file responsible for either loading a pre-compiled configuration
;; file or tangling and loading a literate org configuration file.

;; Don't attempt to find/apply special file handlers to files loaded during
;; startup.
(let ((file-name-handler-alist nil))
  ;; If config is pre-compiled, then load that
  (if (file-exists-p (expand-file-name "config.elc" user-emacs-directory))
      (load-file (expand-file-name "config.elc" user-emacs-directory))
    ;; Otherwise use org-babel to tangle and load the configuration
    (require 'org)
    (org-babel-load-file (expand-file-name "config.org" user-emacs-directory))))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(auctex benchmark-init cdlatex citar-embark citar-org-roam
            consult-lsp consult-org-roam corfu-terminal dap-mode
            dashboard diff-hl direnv doom-modeline doom-themes eat
            editorconfig evil-collection evil-goggles evil-lion
            evil-nerd-commenter evil-surround forge general gptel
            graphviz-dot-mode helpful jtsx lsp-ui magit-todos
            makefile-executor marginalia mu4e-marker-icons
            nerd-icons-completion nix-mode olivetti orderless
            org-appear org-download org-fragtog org-inline-pdf
            org-modern org-msg org-noter org-present org-roam-ui
            ox-pandoc parinfer-rust-mode pdf-tools plantuml-mode
            powerthesaurus projectile rainbow-mode rust-mode sharper
            sicp treesit-auto undo-fu undo-fu-session use-package
            vertico vundo wakatime-mode which-key)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "Roboto Mono" :height 120))))
 '(fixed-pitch ((t (:family "Roboto Mono" :height 0.9))))
 '(variable-pitch ((t (:family "Roboto Serif" :height 1.3)))))
