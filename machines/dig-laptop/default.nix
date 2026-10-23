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
  # appear on input bump. Only here: the repo sits behind the org's SAML SSO,
  # so other machines' GitHub tokens get a 403 when fetching it.
  home-manager.users.${config.user.username}.agents.extraSkillPaths = [
    (pkgs.symlinkJoin {
      name = "punkt-skills";
      paths = [ "${inputs.punkt-skills}/skills" ];
    })
  ];
}
