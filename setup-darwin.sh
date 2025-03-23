#!/bin/sh

curl -L https://nixos.org/nix/install | sh
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
#nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix run home-manager -- switch --flake .#oskar-darwin --impure

DIR="$(readlink -f "$(dirname "$0")")"
mkdir -p ~/.config/nix

ln -sf $DIR/nix.conf ~/.config/nix/nix.conf
ln -sf $DIR ~/.config/home-manager

# Setup cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install
echo "trusted-users = root oskar" | sudo tee -a /etc/nix/nix.conf && sudo pkill nix-daemon
cachix use nix-community

home-manager switch --flake .#oskar-darwin --impure
