# Default recipe to display help information
default:
    @just --list

# Update flake inputs and nvfetcher sources, then report which fix references have landed
update: && update-sources check-fixes
    nix flake update

import 'just/bootstrap.just'
import 'just/emacs.just'
import 'just/machine.just'
import 'just/sops.just'
import 'just/nvfetcher.just'
import 'just/agecrypt.just'
import 'just/fixes.just'
