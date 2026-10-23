# Default recipe to display help information
default:
    @just --list

# Update flake inputs and nvfetcher sources, then report which fix references have landed
update: && update-sources check-fixes
    #!/usr/bin/env bash
    set -euo pipefail
    # punkt-skills is only fetchable from dig-laptop (org SAML SSO), so other
    # hosts keep its locked rev and update everything else.
    if [ "$(hostname)" = dig-laptop ]; then
      nix flake update
    else
      jq -r '.nodes.root.inputs | keys[] | select(. != "punkt-skills")' flake.lock \
        | xargs nix flake update
    fi

import 'just/bootstrap.just'
import 'just/emacs.just'
import 'just/machine.just'
import 'just/sops.just'
import 'just/nvfetcher.just'
import 'just/agecrypt.just'
import 'just/fixes.just'
