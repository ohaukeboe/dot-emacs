(global-set-key (kbd "<escape>") 'keyboard-escape-quit)   ;; esc quits the current action

(setq auto-revert-interval 1              ; Refresh buffers fast
      display-line-numbers-type 'relative ; Show relative line numbers
      default-input-method "TeX"          ; Use TeX when toggling input method
      echo-keystrokes 0.1                 ; Show keystrokes asap
      frame-inhibit-implied-resize 1      ; Don't resize frame implicitly
      inhibit-startup-screen t            ; No splash screen please
      initial-scratch-message nil         ; Clean scratch buffer
      recentf-max-saved-items 10000       ; Show more recent files
      ring-bell-function 'ignore          ; Quiet
      scroll-margin 1                     ; Space between cursor and top/bottom
      sentence-end-double-space nil)      ; No double space

(dolist (mode '(tool-bar-mode
                scroll-bar-mode
                menu-bar-mode))
  (funcall mode 0))

(dolist (mode '(global-auto-revert-mode
                global-display-line-numbers-mode))
  (funcall mode t))

(dolist (mode '(org-mode-hook
                  term-mode-hook
                  shell-mode-hook
                  eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

(fset 'yes-or-no-p 'y-or-n-p)
(set-fringe-mode 10)

(setq-default indent-tabs-mode nil              ; Use spaces instead of tabs
              tab-width 4                       ; Smaller tabs
              fill-column 80                    ; Maximum line width
              truncate-lines t                  ; Don't fold lines
              split-width-threshold 160         ; Split verticly by default
              split-height-threshold nil        ; Split verticly by default
              frame-resize-pixelwise t          ; Fine-grained frame resize
              auto-fill-function 'do-auto-fill) ; Auto-fill-mode everywhere

(defvar elpaca-installer-version 0.4)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-repos-directory (expand-file-name "repos/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil
                              :files (:defaults (:exclude "extensions"))
                              :build (:not elpaca--activate-package)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-repos-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (when (< emacs-major-version 28) (require 'subr-x))
    (condition-case-unless-debug err
        (if-let ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                 ((zerop (call-process "git" nil buffer t "clone"
                                       (plist-get order :repo) repo)))
                 ((zerop (call-process "git" nil buffer t "checkout"
                                       (or (plist-get order :ref) "--"))))
                 (emacs (concat invocation-directory invocation-name))
                 ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                       "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                 ((require 'elpaca))
                 ((elpaca-generate-autoloads "elpaca" repo)))
            (kill-buffer buffer)
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (load "./elpaca-autoloads")))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Install use-package support
(elpaca elpaca-use-package
  ;; Enable :elpaca use-package keyword.
  (elpaca-use-package-mode)
  ;; Assume :elpaca t unless otherwise specified.
  (setq elpaca-use-package-by-default t))

;; Block until current queue processed.
(elpaca-wait)

(require 'bind-key)

(use-package use-package-ensure-system-package)
(elpaca-wait)

(use-package general
  :commands general-def
  :init
  (general-create-definer oskah/leader-keys
    :states '(normal insert visual emacs)
    :prefix "SPC"
    :non-normal-prefix "C-SPC"))

;; Wait until this is setup before loading the rest of the config.
;; This is needed for the =:general= flag to work.
(elpaca-wait)

(use-package evil
  :init (evil-mode 1)
  :custom
  (evil-want-integration t)
  (evil-want-keybinding nil)
  (evil-want-C-u-scroll t)
  (evil-want-C-i-jump t)
  (evil-undo-system 'undo-tree)
  :general
  ('(normal visual) "gr" 'eval-region)
  (oskah/leader-keys "w" 'evil-window-map)
  :config
  (evil-global-set-key 'normal (kbd "C-g") 'evil-force-normal-state)

  (evil-global-set-key 'normal (kbd "j") 'evil-next-visual-line)
  (evil-global-set-key 'normal (kbd "k") 'evil-previous-visual-line)

  (dolist (mode '(custom-mode
                      eshell-mode
                      git-rebase-mode
                      term-mode))
          (add-to-list 'evil-emacs-state-modes mode)))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package evil-nerd-commenter
  :config
  (evilnc-default-hotkeys))

(use-package evil-matchit
  :custom
  (evilmi-shortcut "m")
  :config
  (global-evil-matchit-mode 1))

(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

(use-package evil-numbers
  :general
  ('(normal visual)
    "g=" 'evil-numbers/inc-at-pt-incremental
    "g-" 'evil-numbers/dec-at-pt
    "g+" 'evil-numbers/inc-at-pt))

(use-package evil-goggles
  :custom
  (evil-goggles-enable-delete nil)
  :config
  (evil-goggles-mode))

(use-package evil-exchange
  :config
  (evil-exchange-install))

(use-package evil-args
  :ensure t
  :after evil
  :config
  (define-key evil-inner-text-objects-map "a" 'evil-inner-arg)
  (define-key evil-outer-text-objects-map "a" 'evil-outer-arg)
  (define-key evil-normal-state-map "L" 'evil-forward-arg)
  (define-key evil-normal-state-map "H" 'evil-backward-arg)
  (define-key evil-motion-state-map "L" 'evil-forward-arg)
  (define-key evil-motion-state-map "H" 'evil-backward-arg)
  (define-key evil-normal-state-map "K" 'evil-jump-out-args))

(use-package evil-lion
  :config
  (evil-lion-mode))

(use-package hydra
  :ensure t
  :config
  (defhydra hydra-text-scale (:timeout 4)
    "scale text"
    ("k" text-scale-increase "in")
    ("j" text-scale-decrease "out")
    ("r" (text-scale-set 0) "reset")
    ("q" nil "quit" :exit t))

  (oskah/leader-keys
    "ts" '(hydra-text-scale/body :which-key "scale text")))

(oskah/leader-keys "m" '(:ignore t :which-key "localleader")
                   "t" '(:ignore t :which-key "toggle")
                   "b" '(:ignore t :which-key "buffer")
                   "h" '(:ignore t :which-key "help")
                   "o" '(:ignore t :which-key "open"))

(oskah/leader-keys ":" '("M-x" . execute-extended-command)
  ";" '("eval-expression" . pp-eval-expression)
  "wv" '(evil-window-vsplit :which-key "split vertically")
  "wh" '(evil-window-split :which-key "split horizontally"))


;; Scale text
(general-def 'normal
  "C-=" 'text-scale-increase
  "C--" 'text-scale-decrease)

(use-package nano
  :defer t
  :elpaca (nano :host github
                :repo "rougier/nano-emacs")
  :init
  (setq nano-font-size 13)
  ;; Add nano to load path
  (add-to-list 'load-path (locate-user-emacs-file "elpaca/builds/nano-emacs"))

  ;; (require 'nano-layout)
  (require 'nano-base-colors)
  (require 'nano-faces)
  (require 'nano-theme)

  (add-to-list 'default-frame-alist
               '(internal-border-width . 10))

  ;; Turns out [[https://www.colorhexa.com/][colorhexa]] is a great resource
  ;; for finding colors that work well together.
  (setq frame-background-mode 'dark
        nano-color-foreground "#e8d6c6"
        nano-color-background "#171717"
        nano-color-highlight  "#c79972"
        nano-color-critical   "#EBCB8B"
        nano-color-salient    "#aac5dd"
        nano-color-strong     "#e3ccb8"
        nano-color-popout     "#c77276"
        nano-color-subtle     "#212121"
        nano-color-faded      "#c79972"
        ;; to allow for toggling of the themes.
        nano-theme-var "dark")

 (call-interactively 'nano-refresh-theme)

    ;; ;; (require 'nano-defaults)
 (require 'nano-modeline))

(use-package all-the-icons
  :if (display-graphic-p))

(use-package olivetti
  :general
  (oskah/leader-keys "to" 'olivetti-mode))

(use-package magit
  :ensure-system-package
  ((ssh . openssh)
   (git . git))
  :custom
  (magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1)
  :general
  (oskah/leader-keys "gg" 'magit-status))

(use-package forge
  :after magit
  :config
  (setq auth-sources '("~/.authinfo")))

(use-package projectile
  :init
  (projectile-mode 1)
  :custom
  (projectile-completion-system 'ivy)
  :general
  (oskah/leader-keys "p" 'projectile-command-map)
  :init
  (when (file-directory-p "~/projects")
    (setq projectile-project-search-path '("~/projects"))))

(use-package counsel-projectile
  :after (counsel projectile)
  :ensure-system-package (rg . ripgrep)
  :config
  (counsel-projectile-mode))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package rainbow-mode
  :hook prog-mode)

(use-package org
  :elpaca nil
  :general
  (oskah/leader-keys org-mode-map "m '" 'org-edit-special)
  :custom
  (org-hide-emphasis-markers t)
  (org-ellipsis " ↴")

  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (python . t)))

  (defun oh/org-babel-tangle-config ()
    (when (string-equal (buffer-file-name)
                        (expand-file-name
                         (locate-user-emacs-file "configuration.org")))
      ;; Dynamic scoping to the rescue
      (let ((org-confirm-babel-evaluate nil))
        (org-babel-tangle))))

  (add-hook 'org-mode-hook (lambda ()
                             (add-hook 'after-save-hook #'oh/org-babel-tangle-config))))

(use-package org-tempo
  :elpaca nil
  :after org
  :config
  (add-to-list 'org-structure-template-alist '("sh" . "src sh"))
  (add-to-list 'org-structure-template-alist '("el" . "src elisp"))
  (add-to-list 'org-structure-template-alist '("py" . "src python")))

(use-package evil-org
  :after org
  :hook (org-mode .  evil-org-mode)
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :after org
  :custom
  (org-modern-priority nil)
  (org-modern-table nil))

(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (setq! org-appear-inside-latex t)
  (setq! org-appear-autosubmarkers t))

(use-package org-fragtog
  :ensure-system-package
    ((latex . texlive-most))
  :hook (org-mode . org-fragtog-mode))

(use-package ivy
 :init
 (ivy-mode 1))

(use-package ivy-rich
  :config
  (ivy-rich-mode 1))

(use-package fish-completion
  :if (executable-find "fish")
  :config
  (global-fish-completion-mode))

(use-package undo-tree
  :diminish undo-tree-mode
  :config
  (global-undo-tree-mode))

(use-package counsel
  :config
  (counsel-mode 1)
  :general
  (oskah/leader-keys
   "bb" 'counsel-switch-buffer
   "." 'counsel-find-file))

(use-package copilot
  :elpaca (:host github
           :repo "zerolfx/copilot.el"
           :main nil
           :files ("dist" "*.el"))
  :ensure-system-package (node . nodejs)
  :hook (prog-mode . copilot-mode)
  :general
  (oskah/leader-keys "ta" 'copilot-mode)

  :bind (("C-TAB" . 'copilot-accept-completion-by-word)
         ("C-<tab>" . 'copilot-accept-completion-by-word)
         :map copilot-completion-map
         ("<tab>" . 'copilot-accept-completion)
         ("TAB" . 'copilot-accept-completion)))

(use-package editorconfig
  :commands editorconfig-mode)

(use-package helpful
  :custom
  (counsel-describe-function-function #'helpful-callable)
  (counsel-describe-variable-function #'helpful-variable)
  :general
  ('normal "K" 'helpful-at-point)
  :bind
    ([remap describe-function] . counsel-describe-function)
    ([remap describe-variable] . counsel-describe-variable)
    ([remap describe-key] . helpful-key)
    ([remap describe-command] . helpful-command))

(oskah/leader-keys
  "hp" 'describe-package
  "ht" 'describe-theme
  "hv" 'describe-variable
  "hf" 'describe-function
  "hk" 'describe-key)

(use-package which-key
  :defer 3
  :custom
  (which-key-idle-delay 0.3)
  :config
  (which-key-mode))

(use-package wakatime-mode
  :defer 5
  :init (global-wakatime-mode)
  :config
  (setq wakatime-disable-on-error t)
  (setq wakatime-cli-path "~/.wakatime/wakatime-cli"))
