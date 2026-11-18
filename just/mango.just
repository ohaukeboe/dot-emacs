# Mango session (modules/mango).

# Load this tree's Quickshell config in the running Wayland session and fail on QML errors
qs-check host="laptop":
    nix run '.#nixosConfigurations.{{ host }}.config.system.build.mangoQsCheck'
