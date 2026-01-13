;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((nix-mode . ((compile-command . "home-manager switch")
              (lsp-format-buffer-on-save . t)))
 (nil . ((eval . (progn (require 'agent-shell)
                        (make-local-variable 'agent-shell-mcp-servers)
                        (add-to-list 'agent-shell-mcp-servers
                                     '((name . "mcp-nixos")
                                       (type . "stdio")
                                       (command . "uvx")
                                       (args . ("mcp-nixos"))
                                       (env . []))
                                     t))))))
