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
  # "default" is the shared host key, identical on every machine and installed
  # from sops/bootstrap/host-key.yaml. The hardware entries are escape hatches.
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
  # Never auto-generate. There is a single shared host key, installed by
  # `just bootstrap-host-key`; a freshly generated key would be a recipient of
  # nothing and would fail at decryption time instead of at setup time.
  sops.age.generateKey = false;
  sops.age.sshKeyPaths = [ ];
  sops.defaultSopsFile = ../sops/home/secrets.yaml;

  sops.secrets = {
    # Main SSH private key. Left at the default path
    # (${config.xdg.configHome}/sops-nix/secrets/ssh/main, a symlink into the
    # per-user runtime tmpfs) and the default mode 0400, which already passes
    # OpenSSH's strict permission check. Do not point `path` into ~/.ssh: that
    # only adds a symlink chain that dangles until sops-nix.service has run.
    "ssh/main" = { };
    "ssh/old" = { };
    "ssh/trashcan" = { };

    "authinfo/openai" = { };
    "authinfo/anthropic" = { };
    "authinfo/openrouter" = { };
    "authinfo/azure" = { };
    "authinfo/github" = { };
    "authinfo/gitlab" = { };
    "authinfo/codeberg" = { };
    "authinfo/imap_knowit" = { };
    "authinfo/github_pat" = { };
    "authinfo/kagi" = { };
  };

  sops.templates."nix-github-token" = {
    path = "${homeDir}/.config/nix/github-token.conf";
    mode = "0600";
    content = ''
      access-tokens = github.com=${config.sops.placeholder."authinfo/github_pat"}
    '';
  };

  sops.templates.authinfo = {
    path = "${homeDir}/.authinfo";
    mode = "0600";
    content = ''
      machine api.openai.com password ${config.sops.placeholder."authinfo/openai"}
      machine api.anthropic.com password ${config.sops.placeholder."authinfo/anthropic"}
      machine openrouter.ai password ${config.sops.placeholder."authinfo/openrouter"}
      machine ai.azure.com password ${config.sops.placeholder."authinfo/azure"}
      machine api.github.com login ohaukeboe^forge password ${config.sops.placeholder."authinfo/github"}
      machine gitlab.com/api/v4 login ohaukeboe^forge password ${
        config.sops.placeholder."authinfo/gitlab"
      }
      machine codeberg.org/api/v1 login ohaukeboe^forge password ${
        config.sops.placeholder."authinfo/codeberg"
      }
      machine localhost port 1026 login oskar.haukeboe@knowit.no/ password "${
        config.sops.placeholder."authinfo/imap_knowit"
      }"
      machine githubpat password ${config.sops.placeholder."authinfo/github_pat"}
      machine kagi.com password ${config.sops.placeholder."authinfo/kagi"}
    '';
  };
}
