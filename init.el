;; Emacs init file responsible for either loading a pre-compiled configuration
;; file or tangling and loading a literate org configuration file.

;; Because nix home-manager uses symlinks and sets the changed time
;; for the actual file being pointed at to 0 (unix epoch) we have to
;; make sure to read the time of the symlink itself

;; Don't attempt to find/apply special file handlers to files loaded during
;; startup.
(let ((file-name-handler-alist nil)
      (config-org (expand-file-name "config.org" user-emacs-directory))
      (config-elc (expand-file-name "config.el" user-emacs-directory)))
  (let* ((org-time (nth 5 (file-attributes config-org 'integer)))
         (elc-time (and (file-exists-p config-elc)
                        (nth 5 (file-attributes config-elc 'integer)))))
    ;; If config is pre-compiled, then load that
    (if (and elc-time
             (time-less-p org-time elc-time))
        (load-file config-elc)
      ;; Otherwise use org-babel to tangle and load the configuration
      (require 'org)
      (org-babel-load-file config-org))))
