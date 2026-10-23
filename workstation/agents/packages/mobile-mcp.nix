{
  android-tools,
  buildNpmPackage,
  makeWrapper,
  nvSources,
}:

buildNpmPackage {
  pname = "mobile-mcp";
  version = nvSources.mobile-mcp.version;
  src = nvSources.mobile-mcp.src;
  sourceRoot = "package";
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-9+CcsH4sGqbH2cmatEighe0s7jhla5imAyScOf8gmc0=";
  npmFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];
  dontNpmBuild = true;
  preInstall = "mkdir -p node_modules";
  postPatch = "cp ${../mobile-mcp-lock.json} package-lock.json";

  nativeBuildInputs = [ makeWrapper ];
  # Android device control shells out to `adb`; the server resolves it from
  # ANDROID_HOME/platform-tools first, then bare `adb` on PATH.
  postFixup = ''
    wrapProgram $out/bin/mcp-server-mobile \
      --prefix PATH : ${android-tools}/bin
  '';
}
