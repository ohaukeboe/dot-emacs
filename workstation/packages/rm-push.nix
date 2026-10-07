{
  bun,
  lib,
  src,
  stdenvNoCC,
  zip,
}:

let
  # bun has no nixpkgs fetcher; vendor node_modules as a fixed-output derivation.
  # Bump outputHash whenever bun.lock changes.
  node_modules = stdenvNoCC.mkDerivation {
    pname = "rm-push-node_modules";
    version = "0.1.0";
    inherit src;

    nativeBuildInputs = [ bun ];
    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      bun install --frozen-lockfile --production --ignore-scripts --no-progress
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -R node_modules $out
      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-QmeBvzWy4bDfkrCRd9JNnBJzEvcHOGzwR98TErOAikE=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rm-push";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    bun
    zip
  ];

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    cp -R ${node_modules} node_modules
    chmod -R u+w node_modules
    bun build.ts
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/rm-push
    (cd dist && zip -qr -X $out/share/rm-push/rm-push.xpi .)
    runHook postInstall
  '';

  passthru = {
    inherit node_modules;
    extensionId = "rm-push@ohaukeboe";
  };
})
