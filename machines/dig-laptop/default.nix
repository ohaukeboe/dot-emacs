{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  home-manager.users.${config.user.username}.agents = {
    # oslokommune/punkt-skills — the whole skills/ dir, so skills added upstream
    # appear on input bump. Work skills, so only on the work machine.
    extraSkillPaths = [
      (pkgs.symlinkJoin {
        name = "punkt-skills";
        paths = [ "${inputs.punkt-skills}/skills" ];
      })
    ];

    # Domain skills, entered by slash command only: keep every punkt skill out
    # of the automatic listing. Read from the input so new upstream skills are
    # covered too.
    skillOverrides = lib.mapAttrs (_: _: "user-invocable-only") (
      lib.filterAttrs (_: t: t == "directory") (builtins.readDir "${inputs.punkt-skills}/skills")
    );
  };
}
