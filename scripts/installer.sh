#!/usr/bin/env bash
# The installer entrypoint: from a booted NixOS installer to an installed
# machine in one command, without cloning anything by hand first.
#
#   nix run github:ohaukeboe/dot-emacs#install -- [options]
#
#     --ref <branch>      branch to clone (default: main)
#     --hostname <name>   machine to install; asked for when omitted
#     --disk <device>     disk for a machine not yet registered; asked for
#     --mount             keep the existing partitioning (retry a failed install)
#     --no-tailnet        do not offer to join the tailnet
#     --dry-run           print what would run, change nothing
#
# Packaged by flake.nix as the `install` app, which puts git, just and vim on
# PATH. It only sequences the existing steps — `just bootstrap`,
# `just new-machine`, `just tailnet-up`, `just install-machine` — each of which
# still works on its own; docs/new-machine.md describes them. Re-running it
# resumes: every stage skips what an earlier run already did.
#
# Firmware preparation (docs/new-machine.md, step 1) cannot be done from here.
set -euo pipefail

REPO=https://github.com/ohaukeboe/dot-emacs
CHECKOUT=/root/dot-emacs

# Kept for the sudo re-exec below; the loop consumes "$@".
args=("$@")
ref=main hostname='' disk='' mode=format tailnet=ask dry_run=false

usage() {
  sed -n '/^#   nix run/,/^#     --dry-run/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-1}"
}

while (($#)); do
  case $1 in
  --ref) ref=${2:?--ref needs a branch} && shift ;;
  --hostname) hostname=${2:?--hostname needs a name} && shift ;;
  --disk) disk=${2:?--disk needs a device} && shift ;;
  --mount) mode=mount ;;
  --no-tailnet) tailnet=no ;;
  --dry-run) dry_run=true ;;
  -h | --help) usage 0 ;;
  *)
    echo "error: unknown option '$1'" >&2
    usage
    ;;
  esac
  shift
done

die() {
  echo "error: $*" >&2
  exit 1
}

stage() { printf '\n==> %s\n' "$*"; }

# Everything that changes state goes through here, so --dry-run covers it.
run() {
  if $dry_run; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

ask_yes() { # $1 prompt, $2 default (y|n)
  local answer
  read -rp "$1 " answer
  answer=${answer:-$2}
  [[ $answer == [yY]* ]]
}

# The installer logs in as `nixos`, and disko, nixos-install and the host key
# paths all need root. PATH is passed on explicitly: it carries the tools this
# app added, and sudo is free to reset it.
if [[ $EUID -ne 0 ]] && ! $dry_run; then
  exec sudo env "PATH=$PATH" "NIX_CONFIG=${NIX_CONFIG:-}" "$0" "${args[@]}"
fi

# The scripts below call `nix` against the flake. Recent installer images
# enable flakes already; older ones do not, and this costs nothing when they do.
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes"

########################################
stage "Repository"
########################################

# HTTPS, not SSH: the SSH key lives in sops, which is not readable yet.
# An existing checkout is reused as it is. It may hold an edited machines.nix
# from an earlier run, which a pull or a fresh clone would throw away.
if [[ -d $CHECKOUT/.git ]]; then
  echo "reusing $CHECKOUT (on $(git -C "$CHECKOUT" branch --show-current))"
else
  run git clone --branch "$ref" "$REPO" "$CHECKOUT"
fi

if [[ -d $CHECKOUT ]]; then
  cd "$CHECKOUT"
else
  # Dry run with no checkout: look at an empty directory rather than wherever
  # this was started from, so every stage reports a fresh machine.
  echo "[dry-run] no checkout yet; the stages below assume a fresh one"
  cd "$(mktemp -d)"
fi

registered() { # $1 hostname
  [[ -f machines/machines.nix ]] && grep -qE "^[[:space:]]*$1 = \{" machines/machines.nix
}

########################################
stage "Bootstrap (shared host key, private files)"
########################################

# git-agecrypt leaves private/** as ciphertext until bootstrap has run, and the
# flake cannot evaluate before then. Plaintext JSON there means it is done.
if [[ -f /var/lib/sops-nix/keys.txt ]] && [[ $(head -c1 private/hosts.json 2>/dev/null) == '{' ]]; then
  echo "already done"
else
  run just bootstrap
fi

########################################
stage "Machine"
########################################

if [[ -z $hostname ]]; then
  if [[ -f machines/machines.nix ]]; then
    echo "Registered machines with a disko layout (reinstallable):"
    for d in machines/*/disk.nix; do
      [[ -e $d ]] && echo "  $(basename "$(dirname "$d")")"
    done
  fi
  read -rp "Hostname to install (existing, or a new one to register): " hostname
fi
[[ $hostname =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
  die "'$hostname' is not a valid hostname (lowercase letters, digits, dashes)"

if registered "$hostname"; then
  # install-machine would refuse too, but only after evaluating the flake.
  [[ -f machines/$hostname/disk.nix ]] ||
    die "$hostname is registered but has no disko layout (machines/$hostname/disk.nix).
It predates disko and must be installed by hand — see docs/new-machine.md."
  echo "$hostname is registered; installing it to the disk in machines/$hostname/disk.nix"
  [[ -z $disk ]] || echo "note: --disk is ignored for a registered machine"
else
  if [[ -z $disk ]]; then
    echo
    lsblk -d -o NAME,SIZE,MODEL,TYPE
    echo
    read -rp "Disk for $hostname (the whole disk, e.g. nvme0n1): " disk
  fi
  [[ $disk == /dev/* ]] || disk=/dev/$disk
  run just new-machine "$hostname" "$disk"
fi

########################################
stage "Machine options"
########################################

# vim, not $EDITOR: the installer image sets that to nano.
if $dry_run; then
  echo "[dry-run] would offer: vim machines/machines.nix, then nix fmt and an evaluation of .#$hostname"
elif ask_yes "Edit machines/machines.nix (modules, nixos-hardware, enableSecureBoot) first? [y/N]" n; then
  while true; do
    vim machines/machines.nix
    nix fmt
    # The flake only sees git-tracked files.
    git add machines/machines.nix "machines/$hostname"
    echo "Evaluating .#$hostname ..."
    if nix eval --raw ".#nixosConfigurations.\"$hostname\".config.system.build.toplevel.drvPath" >/dev/null; then
      break
    fi
    ask_yes "$hostname does not evaluate. Edit again? [Y/n]" y || die "aborted; re-run to continue"
  done
fi

########################################
stage "Tailnet"
########################################

# The private attic cache answers on the tailnet only; without it the install
# builds everything the cache would have served.
if [[ $tailnet == no ]]; then
  echo "skipped (--no-tailnet)"
elif ! $dry_run && ./scripts/tailnet-up.sh --quiet >/dev/null 2>&1; then
  echo "already joined"
elif $dry_run || ask_yes "Join the tailnet to use the private binary cache? [Y/n]" y; then
  run just tailnet-up
fi

########################################
stage "Install"
########################################

# A disk that already carries this layout most likely comes from an install
# that failed partway. Offer to keep it rather than repartition.
if [[ $mode == format ]] && ! $dry_run &&
  lsblk -nro PARTLABEL 2>/dev/null | grep -qx disk-main-luks &&
  ask_yes "A disk already has this layout (an earlier, failed install?). Keep it and only mount? [y/N]" n; then
  mode=mount
fi

run just install-machine "$hostname" "$mode"
