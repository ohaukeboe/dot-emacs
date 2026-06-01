{ buildNpmPackage, fetchurl }:

buildNpmPackage {
  pname = "chrome-devtools-mcp";
  version = "1.0.1";
  src = fetchurl {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-1.0.1.tgz";
    hash = "sha256-8CyjSlq3caR9BbfmKJsAfSjVcMsNdwIlTeRctEaDra8=";
  };
  sourceRoot = "package";
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-v6ZX9uqsEtYwiDRLa95SieDu+5fzuZcJEHeNhoCmNSo=";
  npmFlags = [
    "--omit=dev"
    "--ignore-scripts"
  ];
  dontNpmBuild = true;
  preInstall = "mkdir -p node_modules";
  postPatch = "cp ${../chrome-devtools-mcp-lock.json} package-lock.json";
}
