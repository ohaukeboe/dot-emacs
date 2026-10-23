# Fix references: the nixpkgs PR or issue whose fix makes a workaround obsolete
# (see "Fix reference" in GLOSSARY.md and scripts/check-fixes.sh).

# Report which fix references have landed in the pinned nixpkgs (needs network; GITHUB_TOKEN optional)
check-fixes:
    nix run .#check-fixes
