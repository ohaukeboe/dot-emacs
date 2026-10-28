{
  config,
  inputs,
  ...
}:

{
  imports = [
    ./disk.nix
    ./hardware-configuration.nix
  ];

  # oslokommune/claude-marketplace, registered as `dig`. Work plugins, so only
  # on the work machine. No plugin is enabled here: projects enable the ones
  # they need in their own .claude/settings.json.
  home-manager.users.${config.user.username}.programs.claude-code.marketplaces.dig =
    inputs.oslokommune-claude-marketplace;
}
