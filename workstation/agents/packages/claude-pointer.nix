{
  buildNpmPackage,
  makeWrapper,
  nodejs_24,
  src,
  writeText,
  zip,
}:

let
  version = "0.1.0";
in
buildNpmPackage (finalAttrs: {
  pname = "claude-pointer";
  inherit version src;
  nodejs = nodejs_24;
  npmDepsHash = "sha256-K6h1qWKc9/CQHnTlEuoEivKsr57JQ8eQtyIS/WZRZ08=";

  nativeBuildInputs = [
    makeWrapper
    zip
  ];

  # `npm run build` bundles helper/dist/cli.js (with all runtime deps) and
  # extension/dist; nothing from node_modules is needed at runtime.
  installPhase = ''
    runHook preInstall

    install -Dm755 helper/dist/cli.js $out/lib/claude-pointer/cli.js
    makeWrapper ${nodejs_24}/bin/node $out/bin/claude-pointer \
      --add-flags $out/lib/claude-pointer/cli.js

    # Stands in for the wrapper `claude-pointer install` writes to ~/.local/share.
    makeWrapper ${nodejs_24}/bin/node $out/libexec/claude-pointer/native-host \
      --add-flags "$out/lib/claude-pointer/cli.js native-host"

    mkdir -p $out/lib/mozilla/native-messaging-hosts
    substitute ${finalAttrs.passthru.nativeHostManifest} \
      $out/lib/mozilla/native-messaging-hosts/claude_pointer.json \
      --subst-var out

    mkdir -p $out/share/claude-pointer
    substitute ${finalAttrs.passthru.mcpConfig} $out/share/claude-pointer/mcp.json \
      --subst-var out
    (cd extension/dist && zip -qr -X $out/share/claude-pointer/claude-pointer.xpi .)

    runHook postInstall
  '';

  passthru = {
    extensionId = "claude-pointer@ohaukeboe";
    # Same content as `claude-pointer install` writes; see helper/src/install.ts.
    nativeHostManifest = writeText "claude_pointer.json" (
      builtins.toJSON {
        name = "claude_pointer";
        description = "Claude Pointer bridge to Claude Code sessions";
        path = "@out@/libexec/claude-pointer/native-host";
        type = "stdio";
        allowed_extensions = [ finalAttrs.passthru.extensionId ];
      }
    );
    mcpConfig = writeText "mcp.json" (
      builtins.toJSON {
        mcpServers.claude-pointer = {
          command = "@out@/bin/claude-pointer";
          args = [ "channel" ];
        };
      }
    );
  };

  meta.mainProgram = "claude-pointer";
})
