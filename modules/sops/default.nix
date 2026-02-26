{
  config,
  lib,
  pkgs,
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

      # sops.defaultSopsFile = ../../sops/system/secrets.yaml;
      sops.age.sshKeyPaths = [ ];
      sops.age.keyFile = ageKeyFiles.${config.sops.ageKey};
      sops.age.plugins = [
        pkgs.age-plugin-yubikey
        pkgs.age-plugin-tpm
      ];

      # This is the actual specification of the secrets.
      # sops.secrets.example_key = { };
    };
}
