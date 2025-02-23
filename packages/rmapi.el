(require 'elfeed)
(require 'org)

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
  "Make title safe for filename."
  (replace-regexp-in-string "[^a-zA-Z0-9]" "-" title))

(defun rmapi--get-current-entry ()
  "Get elfeed entry at point from either search or show buffer."
  (cond
   ((eq major-mode 'elfeed-show-mode)
    (bound-and-true-p elfeed-show-entry))
   ((eq major-mode 'elfeed-search-mode)
    (get-text-property (point) 'elfeed-entry))
   (t
    (error "Not in an elfeed buffer"))))

(defun rmapi--entry-to-pdf (entry)
  "Convert elfeed entry directly to epub."
  (let* ((title (elfeed-entry-title entry))
         (content (elfeed-deref (elfeed-entry-content entry)))
         (link (elfeed-entry-link entry))
         (date (elfeed-entry-date entry))
         (feed (elfeed-entry-feed entry))
         (html-file (concat rmapi-temp-dir
                            (rmapi--sanitize-filename title)
                            ".html"))
         (pdf-file (concat rmapi-temp-dir
                            (rmapi--sanitize-filename title)
                            ".pdf")))
    ;; Create HTML file with metadata
    (with-temp-file html-file
      (insert "<!DOCTYPE html>\n<html>\n<head>\n")
      (insert (format "<title>%s</title>\n" title))
      (insert (format "<meta name=\"date\" content=\"%s\">\n"
                      (format-time-string "%Y-%m-%d" date)))
      (when feed
        (insert (format "<meta name=\"author\" content=\"%s\">\n"
                        (elfeed-feed-title feed))))
      (insert "</head>\n<body>\n")
      (insert content)
      (insert "\n</body>\n</html>"))

    ;; Convert HTML to PDF using pandoc
    (call-process "pandoc" nil nil nil
                  html-file
                  "-V" "geometry:margin=2cm"
                  "-V" "papersize=a4paper"
                  "-V" "fontsize=12pt"
                  "-o" pdf-file
                  "--from" "html"
                  "--to" "pdf"
                  "--dpi=300"
                  "--pdf-engine=xelatex")

    ;; Clean up HTML file
    ;; (delete-file html-file)
    pdf-file))

(defun rmapi--send-to-remarkable (file)
  "Send FILE to reMarkable using rmapi."
  (call-process "rmapi" nil nil nil
                "put" file))

;;;###autoload
(defun rmapi-send-eww-page ()
  "Send current EWW page to reMarkable."
  (interactive)
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
  (if (eq major-mode 'eww-mode)
      (let* ((url (plist-get eww-data :url))
             (title (plist-get eww-data :title))
             (filename (rmapi--sanitize-filename title))
             (pdf-file (concat rmapi-temp-dir filename ".pdf")))
        (rmapi--ensure-temp-dir)
        (message "Converting URL to PDF...")
        (message "PDF file: %s" pdf-file)
        (message "CSS file: %s" rmapi-css-file)
        (call-process "weasyprint" nil nil nil
                      url
                      pdf-file
                      "-D" "300"
                      "-p"
                      "-s" rmapi-css-file)
        (message "Sending to reMarkable...")
        (rmapi--send-to-remarkable pdf-file)
        (message "Sent '%s' to reMarkable!" filename))
    (error "Not in EWW buffer")))

(provide 'rmapi)
