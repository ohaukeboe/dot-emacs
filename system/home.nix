{ pkgs, ... }:

{
  home.file.".local/share/applications/1password-silent.desktop".text = ''
    [Desktop Entry]
    Name=1Password
    GenericName=Password Manager
    Exec=${pkgs._1password-gui}/bin/1password --silent
    Icon=1password
    Terminal=false
    Type=Application
    Categories=Office;
    StartupNotify=false
    NoDisplay=true
  '';

  xdg = {
    autostart.enable = true;
    autostart.entries = [
      "/home/oskar/.local/share/applications/1password-silent.desktop"
    ];
  };
}
