# The Quickshell rail and popups: the built config, its checks and its service.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.modules.mango;

  inherit (import ./common.nix { inherit config lib pkgs; })
    palette
    sessionTarget
    terminal
    bindToSession
    powerMenu
    lockScreen
    layout
    ;

  mango = config.programs.mango.package;

  # The rail and its popups (specs/012-mango-rail-bar, specs/013-mango-islands-shell,
  # specs/014-quickshell-rail).
  # Config.qml is the only file with placeholders; the rest is copied as is.
  hm = config.home-manager.users.${config.user.username};
  # Phone card and page (Phone.qml) through KDE Connect's own QML module.
  kdeconnect = hm.services.kdeconnect.enable;
  kdeconnectQml = "${hm.services.kdeconnect.package}/lib/qt-6/qml";
  # The rail's Bluetooth pairing agent; Rail.qml runs it and answers its prompts.
  btAgent = pkgs.writers.writePython3 "mango-bt-agent" {
    libraries = with pkgs.python3Packages; [
      dbus-python
      pygobject3
    ];
  } (builtins.readFile ./bt-agent.py);
  # Job progress from KDE programs as notifications, not KIO's own window.
  jobView = pkgs.writers.writePython3 "mango-job-view" {
    libraries = with pkgs.python3Packages; [
      dbus-python
      pygobject3
    ];
  } (builtins.readFile ./job-view.py);
  quickshellConfig = pkgs.replaceVars ./quickshell/Config.qml (
    palette
    // {
      inherit terminal;
      systemctl = "${config.systemd.package}/bin/systemctl";
      systemdRun = "${config.systemd.package}/bin/systemd-run";
      # "Open Claude" in the usage popup; hidden when Claude Code is off.
      claude = optionalString hm.programs.claude-code.enable (
        getExe hm.programs.claude-code.finalPackage
      );
      mmsg = getExe' mango "mmsg";
      mangoLayout = getExe layout;
      btAgent = "${btAgent}";
      nmcli = getExe' config.networking.networkmanager.package "nmcli";
      pwMetadata = getExe' config.services.pipewire.package "pw-metadata";
      brightnessctl = getExe pkgs.brightnessctl;
      cliphist = getExe pkgs.cliphist;
      # The one package from outside nixpkgs (specs/016 FR-025, an exception
      # to specs/010-mango-wm-session FR-009).
      passBackend = getExe inputs.cosmic-pass.packages.${pkgs.stdenv.hostPlatform.system}.default;
      passClearSecs = toString cfg.pass.clipboardClearSeconds;
      powerMenu = getExe powerMenu;
      lock = getExe lockScreen;
      kdeconnect = lib.boolToString kdeconnect;
    }
  );
  quickshellDir = pkgs.runCommand "mango-quickshell" { } ''
    mkdir $out
    cp ${./quickshell}/*.qml $out/
    install -m644 ${quickshellConfig} $out/Config.qml
    ${optionalString (!kdeconnect) "rm $out/Phone.qml $out/PhoneIcon.qml"}
  '';

  # The login screen (quickshell/greeter.qml) gets the user and the sessions
  # from the environment: every installed Wayland session as { id, name, command },
  # the default session first. shortcut: Exec is split on spaces with its field
  # codes dropped, so a quoted argument breaks; parse it properly if one appears.
  # greetd leaves the greeter's and the session's output on the console,
  # where it shows at logout and reboot; this sends it to the journal instead.
  toJournal = "${config.systemd.package}/bin/systemd-cat -t";
  displayManager = config.services.displayManager;
  greeterSessions =
    pkgs.runCommand "mango-greeter-sessions.json" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        for f in ${displayManager.sessionData.desktops}/share/wayland-sessions/*.desktop; do
          jq -n \
            --arg id "$(basename "$f" .desktop)" \
            --arg name "$(sed -n 's/^Name=//p' "$f" | head -1)" \
            --arg exec "$(sed -n 's/^Exec=//p' "$f" | head -1)" \
            '{ id: $id, name: $name, command: ("${toJournal} \($id) \($exec)" | split(" ") | map(select(. != "" and (startswith("%") | not)))) }'
        done | jq -s --arg default ${escapeShellArg (toString displayManager.sessionData.autologinSession)} \
          'sort_by(.id != $default)' > $out
      '';
  # The greeter user has no home, so Quickshell's cache and state go here.
  greeterState = "/var/cache/mango-greeter";
  greeter = pkgs.writeShellScript "mango-greeter" ''
    export MANGO_GREETER_USER=${escapeShellArg config.user.username}
    MANGO_GREETER_SESSIONS=$(< ${greeterSessions})
    export MANGO_GREETER_SESSIONS
    export XDG_CACHE_HOME=${greeterState}/cache XDG_STATE_HOME=${greeterState}/state
    # The session's cursor (default.nix); cage would fall back to its own.
    export XCURSOR_THEME=Adwaita XCURSOR_SIZE=24
    # cage offers no server-side decorations, so Qt would draw its own title
    # bar and frame around the window.
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec ${getExe pkgs.quickshell} -p ${quickshellDir}/greeter.qml
  '';

  # Fails the build on any qmllint warning in the popups. Two categories are
  # off: Quickshell's PanelWindow is registered uncreatable and BluetoothAdapter
  # is not exposed to qmllint, though both work at runtime. Quickshell
  # registers the config's own types at runtime; qmllint needs a qmldir.
  qmlCheck = pkgs.runCommand "mango-qml-check" { } ''
    cp -r ${quickshellDir} qml
    chmod -R u+w qml
    cd qml
    for f in [A-Z]*.qml; do
      if grep -q '^pragma Singleton' "$f"; then
        echo "singleton ''${f%.qml} 1.0 $f"
      else
        echo "''${f%.qml} 1.0 $f"
      fi
    done > qmldir
    if ! ${pkgs.qt6.qtdeclarative}/bin/qmllint \
        -I ${pkgs.quickshell}/lib/qt-6/qml \
        -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
        ${optionalString kdeconnect "-I ${kdeconnectQml}"} \
        --max-warnings 0 \
        --unresolved-type disable \
        --uncreatable-type disable \
        "$PWD"/*.qml; then
      echo "modules/mango/quickshell: qmllint failed; fix the QML" >&2
      exit 1
    fi
    touch $out
  '';

  # qmllint misses errors that only show when Quickshell loads the config
  # (a reserved property name once stopped the whole shell). This loads the
  # built config against the running Wayland session for a few seconds, with
  # its own runtime dir, and fails on any error that names a QML file.
  #   just qs-check
  qsCheck = pkgs.writeShellApplication {
    name = "mango-qs-check";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
    ];
    text = ''
      : "''${WAYLAND_DISPLAY:?run this inside a Wayland session}"
      runtime=$(mktemp -d)
      trap 'rm -rf "$runtime"' EXIT
      socket=$WAYLAND_DISPLAY
      [[ $socket == /* ]] || socket="''${XDG_RUNTIME_DIR:?}/$socket"
      log=$(
        WAYLAND_DISPLAY=$socket XDG_RUNTIME_DIR=$runtime \
          ${optionalString kdeconnect "QML_IMPORT_PATH=${kdeconnectQml}"} \
          timeout 6 ${getExe pkgs.quickshell} -p ${quickshellDir}/shell.qml 2>&1 |
          sed 's/\x1b\[[0-9;]*m//g'
      ) || true
      problems=$(grep -E '^ *(WARN|ERROR)' <<<"$log" |
        grep -E '@[A-Za-z]+\.qml|mango-quickshell/[A-Za-z]+\.qml' || true)
      if [[ -n $problems ]] || ! grep -q 'Configuration Loaded' <<<"$log"; then
        echo "$log" >&2
        echo "mango-qs-check: the Quickshell config failed to load cleanly" >&2
        exit 1
      fi
      echo "mango-qs-check: config loaded without QML errors"
    '';
  };
in
{
  config = mkIf cfg.enable {
    system.build.mangoQsCheck = qsCheck;
    system.extraDependencies = [ qmlCheck ];

    # Quickshell draws a plain window, so cage runs it full screen, on the
    # last output only (-m last) so a dock does not split it across screens.
    # cage has no layer shell, which is why greeter.qml is a plain window.
    services.greetd = mkIf cfg.greeter.enable {
      enable = true;
      settings.default_session.command = "${toJournal} mango-greeter ${pkgs.dbus}/bin/dbus-run-session ${getExe pkgs.cage} -s -m last -- ${greeter}";
    };
    systemd.tmpfiles.settings."10-mango-greeter" = mkIf cfg.greeter.enable {
      ${greeterState}.d = {
        user = "greeter";
        group = "greeter";
        mode = "0750";
      };
    };
    # The greeter's icons; the session gets this font from Home Manager.
    fonts.packages = mkIf cfg.greeter.enable [ pkgs.nerd-fonts.symbols-only ];

    # The rail's brightnessctl writes /sys/class/backlight/*/brightness; its
    # udev rule makes that group-video writable.
    services.udev.packages = [ pkgs.brightnessctl ];
    users.users.${config.user.username}.extraGroups = [ "video" ];

    home-manager.users.${config.user.username} = {
      # COSMIC starts kdeconnectd from XDG autostart; Mango runs no autostart.
      # Quick controls show the phone instead of the tray indicator.
      services.kdeconnect = {
        enable = true;
        indicator = false;
      };
      systemd.user.services.kdeconnect = bindToSession;
      # Only in this session: Plasma owns org.kde.JobViewServer and org.kde.kuiserver itself.
      systemd.user.services.mango-job-view = {
        Unit = {
          Description = "KDE job progress as notifications";
          PartOf = [ sessionTarget ];
          After = [ sessionTarget ];
        };
        Service = {
          ExecStart = "${jobView}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ sessionTarget ];
      };

      programs.quickshell = {
        enable = true;
        configs.mango = quickshellDir;
        activeConfig = "mango";
        systemd = {
          enable = true;
          target = sessionTarget;
        };
      };
      # The config is a store symlink, so Quickshell's file watcher misses a
      # rebuild; a changed unit makes home-manager restart the service instead.
      systemd.user.services.quickshell.Unit.X-Restart-Triggers = [ "${quickshellDir}" ];
      systemd.user.services.quickshell.Service.Environment = mkIf kdeconnect [
        "QML_IMPORT_PATH=${kdeconnectQml}"
      ];
    };
  };
}
