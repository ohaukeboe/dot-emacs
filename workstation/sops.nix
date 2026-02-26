{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  homeDir = config.home.homeDirectory;
  ageKeyDir = "${homeDir}/.config/sops/age";
  ageKeyFiles = {
    default = "${ageKeyDir}/keys.txt";
    tpm = "${ageKeyDir}/tpm-identity.txt";
    yubikey-wallet = "${ageKeyDir}/yubikey-wallet.txt";
    yubikey-home = "${ageKeyDir}/yubikey-home.txt";
  };
in
{
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  home.packages =
    with pkgs;
    [
      sops
      age
      age-plugin-yubikey
    ]
    ++ lib.optionals (!pkgs.stdenv.isDarwin) [ age-plugin-tpm ];

  sops.age.keyFile = ageKeyFiles.${config.sops.ageKey};
  # Only auto-generate a key for the "default" case (user-managed age key).
  # YubiKey and TPM keys are hardware-backed and must be provisioned externally.
  sops.age.generateKey = config.sops.ageKey == "default";
  sops.age.sshKeyPaths = [ ];
  sops.defaultSopsFile = ../sops/home/secrets.yaml;
}
