{
  config,
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  # oslokommune/punkt-skills — the whole skills/ dir, so skills added upstream
  # appear on input bump. Work skills, so only on the work machine.
  home-manager.users.${config.user.username}.agents.extraSkillPaths = [
    (pkgs.symlinkJoin {
      name = "punkt-skills";
      paths = [ "${inputs.punkt-skills}/skills" ];
    })
  ];
}
