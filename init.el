;; Load the configuration from the org file if it exists, otherwise load the
;; already tangled file.
(let ((org-file (expand-file-name (locate-user-emacs-file "configuration.org")))
      (el-file (expand-file-name (locate-user-emacs-file "configuration.el"))))
  (if (file-exists-p el-file)
      (load-file el-file)
    (when (file-exists-p org-file)
      (require 'org)
      (message "Tangling %s" org-file)
      (org-babel-load-file org-file))))
