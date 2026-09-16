#!/usr/bin/env bash
# Join this machine to the tailnet, from an installed system or from the NixOS
# installer.
#
#   ./scripts/tailnet-up.sh [--quiet]
#
#     --quiet   report the state and exit 1 if not joined, instead of running
#               `tailscale up`, which is interactive
#
# The installer runs no tailscaled: services.tailscale.enable lives in the
# system config, which is what the install is about to build. So this starts a
# temporary one from nixpkgs, the way scripts/bootstrap-host-key.sh starts a
# temporary pcscd. Unlike that one it is deliberately left running when the
# script exits — the install that follows needs the tailnet for the whole of its
# run. It is an installer, so it goes away at the next reboot.
#
# Safe to re-run: an already-joined machine is reported and left alone.
set -euo pipefail

quiet=false
case ${1:-} in
"") ;;
--quiet) quiet=true ;;
*)
  echo "usage: $0 [--quiet]" >&2
  exit 1
  ;;
esac

SOCKET=/run/tailscale/tailscaled.sock
STATE=/var/lib/tailscale/tailscaled.state
LOG=/var/log/tailscaled-temporary.log

as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# The temporary daemon is not on PATH, so the CLI that talks to it has to be the
# one from the same build. An installed system has both already.
TS=$(command -v tailscale || true)

wait_for_socket() { # $1 seconds
  for _ in $(seq "$(($1 * 10))"); do
    [[ -S $SOCKET ]] && return 0
    sleep 0.1
  done
  return 1
}

# The socket of an installed system is readable by the user; the one of the
# temporary daemon below is not. Try without sudo first, so a plain status check
# does not prompt for a password.
ts() {
  "$TS" "$@" 2>/dev/null || as_root "$TS" "$@"
}

joined() {
  [[ -n $TS ]] && [[ -S $SOCKET ]] && ts status >/dev/null 2>&1
}

self_name() {
  ts status --json | grep -m1 '"DNSName"' | cut -d'"' -f4
}

if joined; then
  echo "tailnet: already up as $(self_name)"
  exit 0
fi

if [[ $quiet == true ]]; then
  echo "tailnet: not joined"
  exit 1
fi

# An installed machine has the unit; starting it is enough. The installer has
# neither the unit nor the binary.
if [[ ! -S $SOCKET ]]; then
  if as_root systemctl start tailscaled 2>/dev/null && wait_for_socket 10; then
    echo "Started tailscaled.service."
  else
    echo "No tailscaled here; starting a temporary one for this boot."
    tailscale_pkg=$(nix-build --no-out-link '<nixpkgs>' -A tailscale)
    TS="$tailscale_pkg/bin/tailscale"

    # /dev/net/tun is what makes this a real interface rather than
    # userspace-networking, which only proxies and so would leave `nix` itself
    # unable to reach the tailnet.
    as_root modprobe tun 2>/dev/null || true
    [[ -c /dev/net/tun ]] || {
      echo "error: /dev/net/tun is missing; this kernel cannot run tailscaled" >&2
      exit 1
    }

    as_root mkdir -p "$(dirname "$SOCKET")" "$(dirname "$STATE")"
    # setsid --fork, and the redirection inside the root shell because $LOG is
    # not writable by this user: the daemon has to outlive this script.
    as_root sh -c "setsid --fork '$tailscale_pkg/bin/tailscaled' \
      --state='$STATE' --socket='$SOCKET' >>'$LOG' 2>&1"
    wait_for_socket 30 || {
      echo "error: tailscaled did not come up; see $LOG" >&2
      exit 1
    }
    echo "Temporary tailscaled running (log: $LOG). It ends at the next reboot."
  fi
fi

echo
echo "==> tailscale up (follow the login URL, or scan the QR code, if it prints one)"
# --qr prints the login URL as a QR code too: the installer has no browser, so
# the login usually happens on a phone.
as_root "$TS" up --qr
echo "tailnet: up as $(self_name)"
