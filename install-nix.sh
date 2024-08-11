#!/bin/sh

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sudo bash -s -- install --no-confirm
sudo rm -f /etc/systemd/system/nix-daemon.service
sudo rm -f /etc/systemd/system/nix-daemon.socket
sudo cp /nix/var/nix/profiles/default/lib/systemd/system/nix-daemon.service /etc/systemd/system/nix-daemon.service
sudo cp /nix/var/nix/profiles/default/lib/systemd/system/nix-daemon.socket /etc/systemd/system/nix-daemon.socket

source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
#nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix run home-manager -- switch --flake .

DIR="$(readlink -f "$(dirname "$0")")"
mkdir -p ~/.config/nix

ln -sf $DIR/nix.conf ~/.config/nix/nix.conf
ln -sf $DIR ~/.config/home-manager

# Setup cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install
echo "trusted-users = root oskar" | sudo tee -a /etc/nix/nix.conf && sudo pkill nix-daemon
cachix use nix-community

home-manager switch
