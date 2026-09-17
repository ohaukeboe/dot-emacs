{ ... }:

{
  imports = [
    ./cosmic-de/module.nix
    ./gaming/module.nix
    ./no-rgb
    ./sshd
    ./silent-boot
    ./secure-boot
    ./ollama
    ./sleep-then-hibernate
    ./sops
    ./attic
  ];
}
