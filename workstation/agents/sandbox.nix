{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.sandbox;
  inherit (cfg) runtimeDir;

  # Claude Code's built-in sandbox, configured as the user-scope baseline every
  # session starts with. See docs/adr/0004-agent-sandbox-policy.md.
  #
  # Linux has no per-path Unix socket allowlist (`allowUnixSockets` is
  # macOS-only), and the Nix daemon and the signing agent are both sockets, so
  # every socket is allowed and the ones that act with the user's authority are
  # hidden by path instead. Hidden paths go in `credentials.files` rather than
  # `filesystem.denyRead`: a credential deny is the one entry no project scope
  # can remove.
  deny = path: {
    inherit path;
    mode = "deny";
  };

  # The probe runs every check against the values this module renders, so a new
  # credential path or socket gets a probe row without anyone writing one.
  probe = pkgs.writeShellApplication {
    name = "agent-sandbox-probe";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.jq
      pkgs.nix
      pkgs.openssh
      pkgs.socat
      pkgs.systemd
      pkgs.util-linux
    ];
    # SC2088: the `~/` paths are literal settings values, expanded by `expand`.
    # SC2016: the single-quoted `sh -c` scripts take their values as arguments.
    excludeShellChecks = [
      "SC2088"
      "SC2016"
    ];
    text = ''
      credential_paths=(${lib.escapeShellArgs cfg.credentialPaths})
      hidden_sockets=(${lib.escapeShellArgs cfg.hiddenSockets})
      denied_env=(${lib.escapeShellArgs cfg.deniedEnvVars})
      signing=${lib.boolToString cfg.signing.enable}
      signing_key=${
        lib.escapeShellArg (if cfg.signing.publicKey == null then "" else cfg.signing.publicKey)
      }

      json=false
      [ "''${1:-}" = "--json" ] && json=true

      expand() {
        case "$1" in
          "~/"*) printf '%s/%s' "$HOME" "''${1#\~/}" ;;
          *) printf '%s' "$1" ;;
        esac
      }

      # Outside the sandbox the write probes below would touch real files, and
      # every "blocked" row would report a leak that says nothing about the
      # sandbox. $HOME is not writable inside it, so a successful write here
      # means the probe is running unconfined.
      marker="$HOME/.agent-sandbox-probe"
      if (: >"$marker") 2>/dev/null; then
        rm -f "$marker"
        echo "agent-sandbox-probe: not running inside the Claude Code sandbox; ask the agent to run it" >&2
        exit 2
      fi

      rows=()
      failed=0
      # record ID KIND EXPECT RESULT PROBE [DETAIL]
      record() {
        rows+=("$(jq -cn --arg id "$1" --arg kind "$2" --arg expect "$3" \
          --arg result "$4" --arg probe "$5" --arg detail "''${6:-}" \
          '{id: $id, kind: $kind, expect: $expect, result: $result, probe: $probe, detail: $detail}')")
        [ "$4" = "ok" ] || [ "$2" = "info" ] || failed=1
      }

      # Never prints what it reads: a successful read is reported as a leak by
      # path only.
      readable() {
        local p=$1 f
        if [ -f "$p" ]; then
          [ -n "$(head -c1 "$p" 2>/dev/null)" ]
          return
        fi
        [ -d "$p" ] || return 1
        while IFS= read -r -d "" f; do
          [ -n "$(head -c1 "$f" 2>/dev/null)" ] && return 0
        # -L: sops-nix secrets are symlinks into the runtime tmpfs.
        done < <(find -L "$p" -type f -readable -print0 2>/dev/null)
        return 1
      }

      connects() {
        timeout 3 socat -u OPEN:/dev/null "UNIX-CONNECT:$1" >/dev/null 2>&1
      }

      n=0
      for entry in "''${credential_paths[@]}"; do
        n=$((n + 1))
        p=$(expand "$entry")
        if readable "$p"; then
          record "$(printf 'B%02d' "$n")" blocked fail "LEAK: $p" "read $entry"
        else
          record "$(printf 'B%02d' "$n")" blocked fail ok "read $entry"
        fi
      done

      n=0
      for entry in "''${hidden_sockets[@]}"; do
        n=$((n + 1))
        reached=""
        if [ -S "$entry" ]; then
          connects "$entry" && reached=$entry
        elif [ -d "$entry" ]; then
          while IFS= read -r -d "" s; do
            if connects "$s"; then
              reached=$s
              break
            fi
          done < <(find -L "$entry" -type s -print0 2>/dev/null)
        fi
        if [ -n "$reached" ]; then
          record "$(printf 'S%02d' "$n")" blocked fail "LEAK: $reached" "connect $entry"
        else
          record "$(printf 'S%02d' "$n")" blocked fail ok "connect $entry"
        fi
      done

      n=0
      for name in "''${denied_env[@]}"; do
        n=$((n + 1))
        if [ -n "''${!name+x}" ]; then
          record "$(printf 'E%02d' "$n")" blocked fail "LEAK: \$$name is set" "env $name"
        else
          record "$(printf 'E%02d' "$n")" blocked fail ok "env $name"
        fi
      done

      # Write probes create a file only where none existed and remove it again.
      try_create() {
        local p=$1
        [ -e "$p" ] && { (: >>"$p") 2>/dev/null; return; }
        if (: >"$p") 2>/dev/null; then
          rm -f "$p"
          return 0
        fi
        return 1
      }

      if try_create "$HOME/.claude/agent-sandbox-probe"; then
        record W01 blocked fail "LEAK: wrote ~/.claude" "write ~/.claude"
      else
        record W01 blocked fail ok "write ~/.claude"
      fi
      if [ -d .claude ] && try_create .claude/settings.local.json; then
        record W02 blocked fail "LEAK: wrote .claude/settings.local.json" "write .claude/settings.local.json"
      else
        record W02 blocked fail ok "write .claude/settings.local.json"
      fi
      if [ -d .git/hooks ] && try_create .git/hooks/agent-sandbox-probe; then
        record W03 blocked fail "LEAK: wrote .git/hooks" "write .git/hooks"
      else
        record W03 blocked fail ok "write .git/hooks"
      fi

      if curl -sS -o /dev/null --max-time 5 https://example.com 2>/dev/null; then
        record N01 blocked fail "LEAK: reached example.com" "https://example.com"
      else
        record N01 blocked fail ok "https://example.com"
      fi

      if [ "$signing" = true ]; then
        if timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
          record P01 blocked fail "LEAK: authenticated to github.com" "ssh git@github.com"
        else
          record P01 blocked fail ok "ssh git@github.com"
        fi
      fi

      check() {
        local id=$1 desc=$2
        shift 2
        local out
        if out=$("$@" 2>&1); then
          record "$id" allowed succeed ok "$desc"
        else
          record "$id" allowed succeed FAIL "$desc" "$(tail -n1 <<<"$out")"
        fi
      }

      check A01 "nix-shell -p hello --run hello" nix-shell -p hello --run hello
      check A02 "nix build --no-link nixpkgs#hello" nix build --no-link nixpkgs#hello

      if [ "$signing" = true ]; then
        want=$(ssh-keygen -lf - <<<"$signing_key" | cut -d' ' -f2)
        have=$(ssh-add -l 2>/dev/null | cut -d' ' -f2 || true)
        if [ "$have" = "$want" ]; then
          record A03 allowed succeed ok "signing agent holds only the agent key"
        else
          record A03 allowed succeed FAIL "signing agent holds only the agent key" "expected $want, agent has: ''${have:-nothing}"
        fi
        keyfile=$(mktemp)
        printf '%s\n' "$signing_key" >"$keyfile"
        check A04 "ssh-keygen -Y sign with the agent key" \
          sh -c 'echo probe | ssh-keygen -Y sign -n git -f "$1" >/dev/null' _ "$keyfile"
        rm -f "$keyfile"
      fi

      # The process cap uses `timeout` inside the sandbox (systemd-run cannot
      # reach the user manager from here), so check that the allowance is
      # enforced: a 1 s allowance on a 5 s sleep must be cut off with 124.
      check A05 "process cap: sandbox branch and timeout enforce the allowance" \
        sh -c '[ "''${SANDBOX_RUNTIME:-}" = 1 ] || exit 1; timeout --kill-after=1 1 sleep 5; [ $? -eq 124 ]'
      check A06 "journalctl and systemctl status" \
        sh -c 'journalctl -n1 -q >/dev/null && systemctl status --no-pager -n0 nix-daemon >/dev/null'
      check A07 "https://cache.nixos.org" curl -sS -o /dev/null --max-time 10 https://cache.nixos.org/nix-cache-info

      if [ -c /dev/kvm ]; then
        record I01 info info yes "/dev/kvm present"
      else
        record I01 info info no "/dev/kvm present"
      fi

      if [ "$json" = true ]; then
        printf '%s\n' "''${rows[@]}" | jq -s .
      else
        printf '%s\n' "''${rows[@]}" | jq -rs \
          '(["ID","KIND","EXPECT","RESULT","PROBE"] | @tsv),
           (.[] | [.id, .kind, .expect, .result, (.probe + (if .detail != "" then " (" + .detail + ")" else "" end))] | @tsv)' |
          column -t -s $'\t'
      fi
      exit "$failed"
    '';
  };
in
{
  options.agents.sandbox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = ''
        Run Claude Code's shell commands in its built-in sandbox, with a baseline
        that hides credentials and the sockets that act for the user, forbids
        unsandboxed retries, and makes every project policy change a prompt.
      '';
    };

    runtimeDir = lib.mkOption {
      type = lib.types.strMatching "^/run/user/[0-9]+$";
      default = "/run/user/1000";
      description = ''
        The user's $XDG_RUNTIME_DIR. Sandbox settings take literal paths, so the
        UID is data here; override it on a machine where the user is not 1000.
      '';
    };

    credentialPaths = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^(~/|/).+");
      default = [
        "~/.ssh"
        "~/.gnupg"
        "~/.aws"
        "~/.kube"
        "~/.config/gh"
        "~/.config/sops"
        # Decrypted sops-nix secrets, ssh/main among them.
        "~/.config/sops-nix"
        "~/.password-store"
        "~/.local/share/keyrings"
        "~/.config/1Password"
        "~/.zen"
        "~/.mozilla"
      ];
      description = ''
        Files and directories the agent must never read. Each one becomes a
        sandbox credential deny for shell commands and a Read() deny rule for
        the file tools, which run outside the sandbox.
      '';
    };

    hiddenSockets = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^/.+");
      default = [
        "/run/docker.sock"
        "${runtimeDir}/docker.sock"
        "${runtimeDir}/podman"
        "/run/libvirt"
        "${runtimeDir}/gnupg"
        "${runtimeDir}/keyring"
        "${runtimeDir}/emacs"
        "${runtimeDir}/1Password-BrowserSupport.sock"
        # The session bus serves the keyring (org.freedesktop.secrets). The
        # process cap reaches the user manager over systemd/private instead.
        "${runtimeDir}/bus"
      ]
      # Hiding the main agent before the signing agent exists would break commit
      # signing, which is what got the sandbox switched off the first time.
      ++ lib.optional cfg.signing.enable "${runtimeDir}/ssh-agent";
      defaultText = lib.literalMD "container, VM, key, keyring, editor and session-bus sockets under `runtimeDir`";
      description = "Unix sockets and socket directories hidden from sandboxed commands.";
    };

    writablePaths = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^(~/|/).+");
      default = [
        # The Nix client keeps its flake registry, fetcher and eval caches
        # here; without it every flake command fails on a read-only $HOME.
        "~/.cache/nix"
      ];
      description = ''
        Paths outside the project that every sandboxed command may write.
        Project-specific ones belong in the project policy instead.
      '';
    };

    deniedEnvVars = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^[A-Z_][A-Z0-9_]*$");
      default = [
        "GH_TOKEN"
        "GITHUB_TOKEN"
      ];
      description = "Environment variables removed before every sandboxed command.";
    };

    allowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cache.nixos.org"
        "channels.nixos.org"
        "github.com"
        "codeload.github.com"
        "api.github.com"
        "objects.githubusercontent.com"
      ];
      description = ''
        Hosts sandboxed commands reach without asking. Flake inputs are fetched
        by the Nix client through the sandbox proxy, so the GitHub fetch hosts
        belong here; builds themselves run in the daemon and are not proxied.
      '';
    };

    deniedCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "sudo"
        "nixos-rebuild switch"
        "nixos-rebuild boot"
        "nixos-rebuild test"
      ];
      description = "Bash command prefixes the agent may never run, rendered as deny rules.";
    };

    signing = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Sign the agent's commits with its own signing-only key, served by a
          separate ssh-agent, and hide the user's main agent. Needs the key in
          sops (see specs/004-agent-sandbox-policy/quickstart.md).
        '';
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$");
        default = null;
        description = "Public half of the agent signing key, registered on GitHub as a Signing Key only.";
      };

      socketName = lib.mkOption {
        type = lib.types.strMatching "^[A-Za-z0-9._-]+$";
        default = "ssh-agent-sign";
        description = "Socket of the signing agent, relative to runtimeDir.";
      };

      secret = lib.mkOption {
        type = lib.types.str;
        default = "ssh/agent-signing";
        description = "sops secret holding the private half of the agent signing key.";
      };
    };
  };

  config = lib.mkMerge [
    # A disabled module still has to say so: Claude Code's own default is off,
    # but stating it keeps a stale user setting from surviving.
    { programs.claude-code.settings.sandbox.enabled = lib.mkDefault false; }

    (lib.mkIf cfg.enable {
      home.packages = [
        pkgs.bubblewrap
        pkgs.socat
        probe
      ];

      programs.claude-code.settings = {
        sandbox = {
          enabled = true;
          # Without this a missing bwrap runs every command unsandboxed.
          failIfUnavailable = true;
          # Widen access through project policy, never one command at a time.
          allowUnsandboxedCommands = false;
          filesystem.allowWrite = cfg.writablePaths;
          network = {
            allowAllUnixSockets = true;
            inherit (cfg) allowedDomains;
          };
          credentials = {
            files = map deny (cfg.credentialPaths ++ cfg.hiddenSockets);
            envVars = map (name: {
              inherit name;
              mode = "deny";
            }) cfg.deniedEnvVars;
          };
        };

        permissions = {
          deny = map (p: "Read(${p}/**)") cfg.credentialPaths ++ map (c: "Bash(${c}:*)") cfg.deniedCommands;
          # Shell commands cannot write these (sandbox protected paths), so the
          # Edit tool is the only route, and an ask rule prompts in every mode.
          # Without it auto mode hands protected-path writes to the classifier.
          ask = [
            "Edit(/.claude/settings.json)"
            "Edit(/.claude/settings.local.json)"
          ];
        };

        env = lib.mkMerge [
          {
            # With the sandbox on, every Bash call failed before running with
            # "Shell '/bin/bash' not found in PATH": shell detection fell back to
            # /bin/bash, which NixOS does not have. Name the shell explicitly.
            CLAUDE_CODE_SHELL = lib.getExe pkgs.bashInteractive;
          }
          (lib.mkIf cfg.signing.enable {
            SSH_AUTH_SOCK = "${runtimeDir}/${cfg.signing.socketName}";
            # Overrides user.signingkey for processes Claude Code starts only; the
            # user's own commits keep the main key. Not GIT_CONFIG_COUNT/KEY_0:
            # the sandbox sets those itself (safe.directory) and would overwrite
            # ours. GIT_CONFIG_PARAMETERS is what `git -c` uses, and applies
            # alongside them.
            GIT_CONFIG_PARAMETERS = "'user.signingkey'='key::${toString cfg.signing.publicKey}'";
          })
        ];
      };

      assertions =
        let
          protected = [
            "/nix/var/nix/daemon-socket"
            "${runtimeDir}/systemd"
            "${runtimeDir}/${cfg.signing.socketName}"
          ];
          overlaps = a: b: a == b || lib.hasPrefix "${a}/" b || lib.hasPrefix "${b}/" a;
          clashes = lib.filter (s: lib.any (overlaps s) protected) cfg.hiddenSockets;
          # programs.ssh.settings entries are DAG nodes; the options sit in `data`.
          star = config.programs.ssh.settings."*" or { };
          controlPath = star.data.ControlPath or star.ControlPath or "";
        in
        [
          {
            assertion = clashes == [ ];
            message = ''
              agents.sandbox.hiddenSockets hides ${lib.concatStringsSep ", " clashes}, which the
              agent needs: the Nix daemon socket (FR-007), the user manager's private socket for
              the process cap (FR-026), or the signing agent (FR-019). Remove the entry in
              workstation/agents/sandbox.nix.
            '';
          }
          {
            assertion = !config.agents.processCap.enable || lib.elem "${runtimeDir}/bus" cfg.hiddenSockets;
            message = ''
              agents.sandbox.hiddenSockets does not hide ${runtimeDir}/bus. The session bus serves
              the keyring (org.freedesktop.secrets), so a sandboxed command could read its secrets.
              The process cap does not need it; restore the entry in workstation/agents/sandbox.nix.
            '';
          }
          {
            assertion =
              !cfg.signing.enable
              || (cfg.signing.publicKey != null && config.sops.secrets ? ${cfg.signing.secret});
            message = ''
              agents.sandbox.signing.enable is set but ${
                if cfg.signing.publicKey == null then
                  "agents.sandbox.signing.publicKey is unset"
                else
                  "sops secret \"${cfg.signing.secret}\" is not declared"
              }. Add the key as described in specs/004-agent-sandbox-policy/quickstart.md and
              declare the secret in workstation/sops.nix.
            '';
          }
          {
            assertion = !cfg.signing.enable || lib.elem "~/.ssh" cfg.credentialPaths;
            message = ''
              agents.sandbox.signing.enable is set but "~/.ssh" is not in
              agents.sandbox.credentialPaths. Open SSH master connections live there
              (ControlPath), and the agent must not reuse them to push (FR-021).
            '';
          }
          {
            assertion = !(lib.hasPrefix "/tmp" controlPath);
            message = ''
              programs.ssh ControlPath is ${controlPath}. Master connections in /tmp can be reused by
              any sandboxed command to reach a remote without the agent (FR-021). Keep it under
              ~/.ssh in workstation/ssh.nix.
            '';
          }
        ];
    })
  ];
}
