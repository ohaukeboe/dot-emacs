{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.modules.sops;
in
{
  options.modules.sops = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable secret management";
    };

    ageKey = mkOption {
      type = types.enum [
        "default"
        "tpm"
        "yubikey-wallet"
        "yubikey-home"
      ];
      default = "tpm";
      description = ''
        Which age identity file to use for SOPS decryption.
        Maps to files under ~/.config/sops/age/:
          default        -> keys.txt
          tpm            -> tpm-identity.txt
          yubikey-wallet -> yubikey-wallet.txt
          yubikey-home   -> yubikey-home.txt
      '';
    };
  };

  config =
    let
      ageKeyDir = "/var/lib/sops-nix";
      ageKeyFiles = {
        default = "${ageKeyDir}/keys.txt";
        tpm = "${ageKeyDir}/tpm-identity.txt";
        yubikey-wallet = "${ageKeyDir}/yubikey-wallet.txt";
        yubikey-home = "${ageKeyDir}/yubikey-home.txt";
      };
    in
    mkIf cfg.enable {
      services.pcscd.enable = true;
      environment.systemPackages = with pkgs; [
        sops
        age-plugin-yubikey
        age-plugin-tpm
      ];

      security.tpm2.enable = true;
      security.tpm2.pkcs11.enable = true;
      security.tpm2.tctiEnvironment.enable = true;
      users.users.${config.user.username}.extraGroups = [ "tss" ];

      sops.defaultSopsFile = ../../sops/example.yaml;
      sops.age.sshKeyPaths = [ ];
      sops.age.keyFile = ageKeyFiles.${cfg.ageKey};
      sops.age.plugins = [
        pkgs.age-plugin-yubikey
        pkgs.age-plugin-tpm
      ];

      # This is the actual specification of the secrets.
      sops.secrets.example_key = { };
    };
}
