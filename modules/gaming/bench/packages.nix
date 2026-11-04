# The game-bench scripts as packages. Called from ./default.nix with the
# module's options, and from tests/game-bench.nix with fixtures.
{
  lib,
  writeShellApplication,
  writers,
  writeText,
  fetchurl,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  procps,
  util-linux,
  systemd,
  gamemode,
  scx,
  steam-run,
  power-profiles-daemon,
  mesa,
  mangohud,
  nix,
  # { variants; workloads; } from modules.gaming.benchmark
  benchConfig,
  # Derivation rebuilt as background load; null in tests.
  loadPackage ? null,
  # The Steam launcher (programs.steam.package); null in tests.
  steam ? null,
}:

let
  script = name: builtins.readFile ../../../scripts/game-bench/${name};
  # The helpers both bash halves share, ahead of the script itself.
  withCommon = name: script "common.sh" + "\n" + script name;

  configFile = writeText "game-bench.json" (builtins.toJSON benchConfig);

  # factoriobench.com "flame_Sla 10k" (Factorio 1.0, no mods); the file name
  # is its SHA-256. specs/008-game-performance-tuning/research.md R6.
  factorioSave = fetchurl {
    url = "https://assets.factoriobench.com/maps/4c5f65003d84370f16d6950f639be1d6f92984f24c0240de6335d3e161705504.zip";
    sha256 = "4c5f65003d84370f16d6950f639be1d6f92984f24c0240de6335d3e161705504";
  };

  game-bench-priv = writeShellApplication {
    name = "game-bench-priv";
    runtimeInputs = [
      coreutils
      gnused
      systemd
    ];
    runtimeEnv.GAME_BENCH_SCX = "${scx.full}/bin";
    text = withCommon "game-bench-priv.sh";
  };

  game-bench-wrap = writeShellApplication {
    name = "game-bench-wrap";
    runtimeInputs = [
      coreutils
      util-linux
      gamemode
    ];
    text = script "game-bench-wrap.sh";
  };

  game-bench-summary = writers.writePython3Bin "game-bench-summary" { } (script "summary.py");

  game-bench = writeShellApplication {
    name = "game-bench";
    runtimeInputs = [
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      jq
      procps
      util-linux
      systemd
      gamemode
      steam-run
      power-profiles-daemon
      nix
    ];
    runtimeEnv = {
      GAME_BENCH_CONFIG = "${configFile}";
      # Absolute store path: the sudo rule allows exactly this file. sudo
      # itself comes from the setuid wrapper on PATH, not the store.
      GAME_BENCH_PRIV = lib.getExe game-bench-priv;
      GAME_BENCH_SUMMARY = lib.getExe game-bench-summary;
      GAME_BENCH_STEAM = if steam == null then "steam" else lib.getExe steam;
      GAME_BENCH_FACTORIO_SAVE = "${factorioSave}";
      GAME_BENCH_LOAD_DRV = if loadPackage == null then "" else loadPackage.drvPath;
      GAME_BENCH_VERSIONS = "${writeText "game-bench-versions.json" (
        builtins.toJSON {
          mesa = mesa.version;
          mangohud = mangohud.version;
          scx = scx.full.version;
        }
      )}";
    };
    # jq programs reference jq variables ($v, $w) inside single quotes.
    excludeShellChecks = [ "SC2016" ];
    text = withCommon "game-bench.sh";
  };
in
{
  inherit
    game-bench
    game-bench-priv
    game-bench-wrap
    game-bench-summary
    ;
}
