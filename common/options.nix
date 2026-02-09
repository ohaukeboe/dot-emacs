{ lib, ... }:

with lib;

{
  options = {
    user = {
      username = mkOption {
        type = types.str;
        default = "oskar";
        description = "Primary username for the system";
        example = "alice";
      };

      # Example of additional options you can add later:
      # email = mkOption {
      #   type = types.str;
      #   default = "";
      #   description = "User's email address";
      # };
      #
      # fullName = mkOption {
      #   type = types.str;
      #   default = "";
      #   description = "User's full name";
      # };
    };

    # You can add other common configuration sections here:
    # system = {
    #   ...
    # };
    #
    # network = {
    #   ...
    # };
  };
}
