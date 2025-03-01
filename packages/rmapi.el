(require 'elfeed)
(require 'org)
(require 'async)

(defgroup rmapi nil
  "Send elfeed entries to reMarkable tablet."
  :group 'elfeed)

(defcustom rmapi-temp-dir "/tmp/rmapiel/"
  "Temporary directory for storing generated epubs."
  :type 'string
  :group 'rmapi)

;; TODO: make this general
(defcustom rmapi-css-file (expand-file-name "~/.config/emacs/packages/custom.css")
  "Path to CSS file for weasyprint styling."
  :type 'string
  :group 'rmapi)

(defun rmapi--ensure-temp-dir ()
  "Ensure temporary directory exists."
  (unless (file-exists-p rmapi-temp-dir)
    (make-directory rmapi-temp-dir t)))

(defun rmapi--sanitize-filename (title)
  "Make TITLE safe for filename."
  (replace-regexp-in-string "[^a-zA-Z0-9]" "-" title))

(defun rmapi--get-elfeed-entry ()
  "Get url and title from elfeed entry at point."
  (let* ((entry (cond
                ((eq major-mode 'elfeed-show-mode)
                 (bound-and-true-p elfeed-show-entry))
                ((eq major-mode 'elfeed-search-mode)
                 (get-text-property (point) 'elfeed-entry))
                (t
                 (error "Not in an elfeed buffer"))))
        (url (elfeed-entry-link entry))
        (title (elfeed-entry-title entry)))
    (list :url url :title title)))

(defun rmapi--send-to-remarkable (file)
  "Send FILE to reMarkable using rmapi."
  (async-start
   `(lambda ()
      (call-process "rmapi" nil nil nil
                    "put" ,file))))

(defun rmapi--url-to-remarkable (url title)
  "Send pdf with TITLE from URL to reMarkable."
  (let* ((filename (rmapi--sanitize-filename title))
         (pdf-file (concat rmapi-temp-dir filename ".pdf"))
         (html-file (concat rmapi-temp-dir filename ".html")))
    (rmapi--ensure-temp-dir)
    (message "Converting URL to PDF...")
    (async-start
     `(lambda ()
        (async-send :status "Converting URL to HTML...")
        (unless (zerop (call-process "readable" nil nil nil
                            ,url "-o" ,html-file))
          (error "Failed to convert URL to HTML"))
        (async-send :status (format "Converted URL to PDF: %s" ,pdf-file))
        (unless (zerop (call-process "weasyprint" nil nil nil
                            ,html-file ,pdf-file "-s" ,rmapi-css-file "-D" "300"))
          (error "Failed to convert HTML to PDF"))
        (async-send :status (format "Sending PDF file to ReMarkable: %s" ,pdf-file))
        (unless (zerop (call-process "rmapi" nil nil nil
                            "put" ,pdf-file))
          (error "Failed to send PDF to reMarkable"))
        (delete-file ,pdf-file)
        (delete-file ,html-file))
     `(lambda (result)
        (if (async-message-p result)
            (message (plist-get result :status)))
        (message "Sent '%s' to reMarkable!" ,pdf-file)))))

;;;###autoload
(defun rmapi-send-pdf (pdf-file)
    "Send a PDF file to reMarkable.
   If called from a PDF buffer, use the current buffer's file."
    (interactive
     (list (if (derived-mode-p 'pdf-view-mode)
               (buffer-file-name)
             (read-file-name "PDF file to send: "))))
    (unless (and pdf-file (file-exists-p pdf-file))
      (error "Invalid PDF file: %s" pdf-file))
    (message "Sending '%s' to reMarkable..." pdf-file)
    (rmapi--send-to-remarkable pdf-file)
    (message "Sent '%s' to reMarkable!" (file-name-nondirectory pdf-file)))

;;;###autoload
(defun rmapi-send-eww-page ()
  "Send current EWW page to reMarkable asynchronously."
  (interactive)
  (if (eq major-mode 'eww-mode)
      (let* ((url (plist-get eww-data :url))
             (title (plist-get eww-data :title))
             (filename (rmapi--sanitize-filename title))
             (pdf-file (concat rmapi-temp-dir filename ".pdf"))
             (html-file (concat rmapi-temp-dir filename ".html")))
        (rmapi--ensure-temp-dir)
        (rmapi--url-to-remarkable url title))

    (error "Not in EWW buffer")))

;;;###autoload
(defun rmapi-send-elfeed-entry ()
  "Send current elfeed entry to reMarkable asynchronously."
  (interactive)
  (let* ((entry (rmapi--get-elfeed-entry))
         (_ (message "Title: %s, URL: %s" (plist-get entry :title) (plist-get entry :url)))
         (url (plist-get entry :url))
         (title (plist-get entry :title)))
    (rmapi--ensure-temp-dir)
    (rmapi--url-to-remarkable url title)))

(provide 'rmapi)
