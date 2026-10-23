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
  "steam"
  "steam-unwrapped"
  "kotlin-lsp"
  "oslo-sans"
  # zotero runtime, see common/insecure-packages.nix
  "firefox-esr-140-bin-unwrapped"
  "rtk"
]
