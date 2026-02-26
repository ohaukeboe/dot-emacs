#!/usr/bin/env bash
# Helper script to resolve SOPS age identity files
# Usage: source scripts/sops-identity.sh <identity>
# Where identity is: default, tpm, yubikey-chain, yubikey-home, all, or auto
# After sourcing, SOPS_AGE_KEY_FILE will be set

set -euo pipefail

SOPS_AGE_DIR="${SOPS_AGE_DIR:-$HOME/.config/sops/age}"
IDENTITY="${1:-auto}"

# Identity file paths
DEFAULT_KEY="$SOPS_AGE_DIR/keys.txt"
TPM_KEY="$SOPS_AGE_DIR/tpm-identity.txt"
YUBIKEY_WALLET_KEY="$SOPS_AGE_DIR/yubikey-wallet.txt"
YUBIKEY_HOME_KEY="$SOPS_AGE_DIR/yubikey-home.txt"
COMBINED_KEY="$SOPS_AGE_DIR/combined-identities.txt"

combine_identities() {
	local found=0
	: >"$COMBINED_KEY"

	if [[ -f $TPM_KEY ]]; then
		echo "  + TPM identity"
		cat "$TPM_KEY" >>"$COMBINED_KEY"
		echo "" >>"$COMBINED_KEY"
		found=1
	fi

	if [[ -f $YUBIKEY_WALLET_KEY ]]; then
		echo "  + YubiKey (wallet) identity"
		cat "$YUBIKEY_WALLET_KEY" >>"$COMBINED_KEY"
		echo "" >>"$COMBINED_KEY"
		found=1
	fi

	if [[ -f $YUBIKEY_HOME_KEY ]]; then
		echo "  + YubiKey (home) identity"
		cat "$YUBIKEY_HOME_KEY" >>"$COMBINED_KEY"
		echo "" >>"$COMBINED_KEY"
		found=1
	fi

	if [[ -f $DEFAULT_KEY ]]; then
		echo "  + Default age key"
		cat "$DEFAULT_KEY" >>"$COMBINED_KEY"
		echo "" >>"$COMBINED_KEY"
		found=1
	fi

	if [[ $found -eq 0 ]]; then
		rm -f "$COMBINED_KEY"
		return 1
	fi
	return 0
}

resolve_identity() {
	case "$IDENTITY" in
	default)
		echo "Using default age key: $DEFAULT_KEY"
		export SOPS_AGE_KEY_FILE="$DEFAULT_KEY"
		;;
	tpm)
		echo "Using TPM identity: $TPM_KEY"
		export SOPS_AGE_KEY_FILE="$TPM_KEY"
		;;
	yubikey-wallet)
		echo "Using YubiKey (wallet) identity: $YUBIKEY_WALLET_KEY"
		export SOPS_AGE_KEY_FILE="$YUBIKEY_WALLET_KEY"
		;;
	yubikey-home)
		echo "Using YubiKey (home) identity: $YUBIKEY_HOME_KEY"
		export SOPS_AGE_KEY_FILE="$YUBIKEY_HOME_KEY"
		;;
	all)
		echo "Combining all available identities..."
		if combine_identities; then
			export SOPS_AGE_KEY_FILE="$COMBINED_KEY"
			echo "Using combined identities: $COMBINED_KEY"
		else
			echo "Error: No identity files found in $SOPS_AGE_DIR"
			exit 1
		fi
		;;
	auto)
		# Auto-detect: prefer TPM > YubiKey (wallet) > YubiKey (home) > default
		if [[ -f $TPM_KEY ]]; then
			echo "Auto-detected TPM identity: $TPM_KEY"
			export SOPS_AGE_KEY_FILE="$TPM_KEY"
		elif [[ -f $YUBIKEY_WALLET_KEY ]]; then
			echo "Auto-detected YubiKey (wallet) identity: $YUBIKEY_WALLET_KEY"
			export SOPS_AGE_KEY_FILE="$YUBIKEY_WALLET_KEY"
		elif [[ -f $YUBIKEY_HOME_KEY ]]; then
			echo "Auto-detected YubiKey (home) identity: $YUBIKEY_HOME_KEY"
			export SOPS_AGE_KEY_FILE="$YUBIKEY_HOME_KEY"
		elif [[ -f $DEFAULT_KEY ]]; then
			echo "Auto-detected default age key: $DEFAULT_KEY"
			export SOPS_AGE_KEY_FILE="$DEFAULT_KEY"
		else
			echo "Error: No identity files found in $SOPS_AGE_DIR"
			echo "Run one of these commands first:"
			echo "  just sops-init                    (default age key)"
			echo "  just tpm-save-identity            (TPM identity)"
			echo "  just yubikey-save-identity wallet  (YubiKey wallet)"
			echo "  just yubikey-save-identity home   (YubiKey home)"
			exit 1
		fi
		;;
	*)
		echo "Unknown identity: $IDENTITY"
		echo "Usage: $0 [default|tpm|yubikey-wallet|yubikey-home|all|auto]"
		exit 1
		;;
	esac

	if [[ $IDENTITY != "all" && ! -f $SOPS_AGE_KEY_FILE ]]; then
		echo "Error: Identity file not found: $SOPS_AGE_KEY_FILE"
		echo "Run the appropriate setup command first:"
		echo "  default:       just sops-init"
		echo "  tpm:           just tpm-save-identity"
		echo "  yubikey-wallet: just yubikey-save-identity wallet"
		echo "  yubikey-home:  just yubikey-save-identity home"
		exit 1
	fi
}

resolve_identity
