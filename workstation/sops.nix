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

  sops.secrets = {
    "authinfo/openai" = { };
    "authinfo/anthropic" = { };
    "authinfo/openrouter" = { };
    "authinfo/azure" = { };
    "authinfo/github" = { };
    "authinfo/gitlab" = { };
    "authinfo/github_uio" = { };
    "authinfo/codeberg" = { };
    "authinfo/imap_uio" = { };
    "authinfo/imap_knowit" = { };
    "authinfo/context7" = { };
    "authinfo/github_pat" = { };
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
      machine api.github.uio.no login oskah^forge password ${
        config.sops.placeholder."authinfo/github_uio"
      }
      machine codeberg.org/api/v1 login ohaukeboe^forge password ${
        config.sops.placeholder."authinfo/codeberg"
      }
      machine localhost port 1026 login oskah@uio.no/ password ${
        config.sops.placeholder."authinfo/imap_uio"
      }
      machine localhost port 1026 login oskar.haukeboe@knowit.no/ password "${
        config.sops.placeholder."authinfo/imap_knowit"
      }"
      machine context7.com password ${config.sops.placeholder."authinfo/context7"}
      machine githubpat password ${config.sops.placeholder."authinfo/github_pat"}
    '';
  };
}
