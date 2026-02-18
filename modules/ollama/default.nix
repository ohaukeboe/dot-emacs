{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.ollama;
in
{
  options.modules.ollama = {
    enable = mkEnableOption "Ollama";

    loadModels = mkOption {
      type = with types; listOf str;
      default = [
        "llama3.2:3b"
        "llama3.1:8b"
        "gemma3:4b"
      ];
      description = "List of Ollama models to preload.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.ollama-vulkan;
      description = "Override the default Ollama package.";
    };
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      loadModels = cfg.loadModels;
      package = cfg.package;
    };
  };
}
