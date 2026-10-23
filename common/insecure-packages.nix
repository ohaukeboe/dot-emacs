# nixpkgs.config.permittedInsecurePackages, shared by the NixOS and Home
# Manager configs. Entries name an exact version, so any bump fails
# evaluation until it is re-approved here.
[
  # Zotero bundles this EOL Firefox ESR as its runtime (NixOS/nixpkgs#572466).
  # workstation/home.nix warns once zotero no longer uses it; then drop this
  # and its entry in common/unfree-predicates.nix.
  "firefox-esr-140-bin-unwrapped-140.17.0esr"
]
