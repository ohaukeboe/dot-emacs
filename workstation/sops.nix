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
    # Scoped to projects scaffolded by nix-init, deliberately not the shared
    # host key: a project repo should never carry the key that provisions
    # machines (docs/adr/0002-project-scoped-age-key.md). Not a `sops.ageKey`
    # choice -- it is a recipient of nothing under sops/, only of the secrets
    # files scaffolded projects commit. Rendered below, not bootstrapped.
    projects = "${ageKeyDir}/projects.txt";
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
      # Drives the sops CLI for projects scaffolded by nix-init. Global for
      # the same reason devenv is: a devenv project resolves secretspec while
      # direnv is still entering the environment, so it cannot come from the
      # environment it is about to enter.
      #
      # devenv ships its own bin/secretspec (0.19.1 in devenv 2.2.2), which
      # collides with this one in buildEnv. hiPrio settles it in favour of the
      # standalone package, which is newer and is not silently re-pinned every
      # time devenv is updated.
      (lib.hiPrio secretspec)
    ]
    ++ lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) [ age-plugin-tpm ];

  # mkDefault so a NixOS host can point this at the copy modules/sops hands
  # over as a secret, sparing every machine an age key in the home directory.
  sops.age.keyFile = mkDefault ageKeyFiles.${config.sops.ageKey};
  # Never auto-generate. There is a single shared host key, installed by
  # `just bootstrap-host-key`; a freshly generated key would be a recipient of
  # nothing and would fail at decryption time instead of at setup time.
  sops.age.generateKey = false;
  sops.age.sshKeyPaths = [ ];
  # The sops CLI looks for ~/.config/sops/age/keys.txt unless told otherwise.
  # On a NixOS host that file does not exist (see modules/sops), so point the
  # CLI at whatever sops-nix itself decrypts with. The shared host key is a
  # recipient of everything under sops/, so one identity is enough.
  home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;
  # A second identity source, for the projects key. sops unions everything it
  # finds across SOPS_AGE_KEY_FILE, SOPS_AGE_KEY_CMD and the default keys.txt,
  # so this hands a scaffolded project its own key without the variable above
  # losing the host key that decrypts this repository -- and it reaches devenv,
  # which resolves secretspec while direnv is still entering the directory and
  # so cannot be given the identity by a justfile. A command that fails is not
  # fatal to sops, so this stays inert until activation renders the file.
  home.sessionVariables.SOPS_AGE_KEY_CMD = "cat ${ageKeyFiles.projects}";
  sops.defaultSopsFile = ../sops/home/secrets.yaml;

  sops.secrets = {
    # The projects age identity. `path` puts it where a scaffolded project's
    # secrets.justfile points SOPS_AGE_KEY_FILE, so a fresh clone on any
    # machine decrypts with no manual key installation. Unlike ssh/main this
    # wants a stable well-known path: the projects that reference it live
    # outside this repository and cannot be told where sops-nix happened to
    # put it.
    "age/projects" = {
      path = ageKeyFiles.projects;
    };
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
    "authinfo/context7" = { };
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
      machine context7.com password ${config.sops.placeholder."authinfo/context7"}
    '';
  };
}
