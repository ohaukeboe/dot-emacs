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
      # "default" is the shared host key, identical on every machine and
      # installed from sops/bootstrap/host-key.yaml by `just bootstrap-host-key`.
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

      # Hand the shared host key to the user, so Home Manager does not need a
      # copy of it in the home directory. The bootstrap file lists that same key
      # as a recipient of itself (see .sops.yaml), so the system key installed
      # at ${ageKeyFiles.default} can decrypt it.
      #
      # Only meaningful for the shared key: the yubikey/tpm settings decrypt
      # with the hardware key directly and have nothing to hand over.
      #
      # Left at the default /run/secrets/<name> path on purpose.
      # sops-install-secrets creates missing parent directories as root, so
      # aiming this at ~/.config/sops/age/ would leave a root-owned ~/.config
      # for Home Manager to fight over.
      sops.secrets = mkIf (config.sops.ageKey == "default") {
        host-age-key = {
          sopsFile = ../../sops/bootstrap/host-key.yaml;
          key = "host_age_key";
          owner = config.user.username;
          mode = "0400";
        };
      };

      # Point Home Manager at it under the same condition. This has to be
      # driven from here rather than from workstation/sops.nix: `sops.ageKey`
      # exists separately in each module tree, so the Home Manager side cannot
      # see that this machine decrypts with the shared key. When it does not,
      # Home Manager keeps its own default of ~/.config/sops/age/keys.txt.
      home-manager.users.${config.user.username}.sops.age.keyFile = mkIf (
        config.sops.ageKey == "default"
      ) config.sops.secrets.host-age-key.path;

      # This is the actual specification of the secrets.
      # sops.secrets.example_key = { };
    };
}
