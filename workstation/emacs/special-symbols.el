;; Since nix/emacs-overlay struggles with nerd-fonts, I move these to
;; a separate file

(defun my/prettify-symbols-setup ()
      ;; Checkboxes
      (push '("[ ]" . "") prettify-symbols-alist)
      (push '("[X]" . "") prettify-symbols-alist)
      (push '("[-]" . "" ) prettify-symbols-alist)

      ;; org-abel
      (push '("#+BEGIN_SRC" . ?) prettify-symbols-alist)
      (push '("#+END_SRC" . ?) prettify-symbols-alist)
      (push '("#+begin_src" . ?) prettify-symbols-alist)
      (push '("#+end_src" . ?) prettify-symbols-alist)

      (push '("#+BEGIN_QUOTE" . ?❝) prettify-symbols-alist)
      (push '("#+END_QUOTE" . ?❞) prettify-symbols-alist)
      (push '("#+begin_quote" . ?) prettify-symbols-alist)
      (push '("#+end_quote" . ?) prettify-symbols-alist)

      ;; Drawers
      (push '(":PROPERTIES:" . "") prettify-symbols-alist)
      (push '(":properties:" . "") prettify-symbols-alist)
      (push '(":options:" . "") prettify-symbols-alist)

      ;; Tags
      (push '(":projects:" . "") prettify-symbols-alist)
      (push '(":work:"     . "") prettify-symbols-alist)
      (push '(":inbox:"    . "") prettify-symbols-alist)
      (push '(":task:"     . "") prettify-symbols-alist)
      (push '(":thesis:"   . "") prettify-symbols-alist)
      (push '(":uio:"      . "") prettify-symbols-alist)
      (push '(":emacs:"    . "") prettify-symbols-alist)
      (push '(":learn:"    . "") prettify-symbols-alist)
      (push '(":code:"     . "") prettify-symbols-alist)

      (push '(":noexport:"     . "󱙑") prettify-symbols-alist)
      (push '(":attach:"     . "󰁦") prettify-symbols-alist)
      (push '(":ATTACH:"     . "󰁦") prettify-symbols-alist)

      (prettify-symbols-mode))
