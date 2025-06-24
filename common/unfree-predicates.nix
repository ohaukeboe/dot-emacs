{ lib }:

pkg:
builtins.elem (lib.getName pkg) [
  "terraform"
  "copilot-language-server"
  "claude-code"
  "1password"
  "1password-cli"
  "nvidia-x11"
  "nvidia-settings"
  "idea-ultimate"
  "datagrip"
]
