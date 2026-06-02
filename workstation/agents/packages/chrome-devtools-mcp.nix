{ buildNpmPackage, nvSources }:

buildNpmPackage {
  pname = "chrome-devtools-mcp";
  version = nvSources.chrome-devtools-mcp.version;
  src = nvSources.chrome-devtools-mcp.src;
  sourceRoot = "package";
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-jJMiMqGrLeB5fICYaWwMomwjvRiHA7wPZYXVREnPVQw=";
  npmFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];
  dontNpmBuild = true;
  preInstall = "mkdir -p node_modules";
  postPatch = "cp ${../chrome-devtools-mcp-lock.json} package-lock.json";
}
