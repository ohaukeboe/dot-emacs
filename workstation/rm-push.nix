# Send to reMarkable: Firefox extension that pushes PDFs, web pages and
# documents to the reMarkable cloud. https://github.com/ohaukeboe/rm-push
{
  inputs,
  pkgs,
  ...
}:
let
  rm-push = pkgs.callPackage ./packages/rm-push.nix { src = inputs.rm-push; };
in
{
  # The extension is unsigned. Zen builds without MOZ_REQUIRE_SIGNING, so
  # the pref below is enough to let it install.
  programs.zen-browser.policies = {
    Preferences."xpinstall.signatures.required" = {
      Value = false;
      Status = "locked";
    };
    ExtensionSettings.${rm-push.extensionId} = {
      installation_mode = "force_installed";
      install_url = "file://${rm-push}/share/rm-push/rm-push.xpi";
    };
  };
}
