{ lib }:

pkg:
builtins.elem (lib.getName pkg) [
  "terraform"
  "copilot-node-server"
  "claude-code"
  "1password"
  "1password-cli"
]
