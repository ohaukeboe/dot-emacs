{
  buildNpmPackage,
  lib,
  src,
}:

buildNpmPackage {
  pname = "zotra-server";
  version = "0-unstable";
  inherit src;

  # translation-server's src/http.js requires whatwg-encoding without declaring
  # it, and the jsdom zotra's lockfile resolves no longer pulls it in, so the
  # server crashes at startup. Declare it here; the vendored lockfile is
  # upstream's plus that one package. Regenerate it whenever upstream's
  # package-lock.json changes:
  #   npm install --package-lock-only --ignore-scripts whatwg-encoding@^3.1.1
  postPatch = ''
    substituteInPlace package.json --replace-fail \
      '"dependencies": {' '"dependencies": { "whatwg-encoding": "^3.1.1",'
    cp ${./zotra-server-lock.json} package-lock.json
  '';

  # Bump together with zotra-server-lock.json.
  npmDepsHash = "sha256-d/RvG6ryatQTaq4M/yt3T48Ua5q4lAxfAa6+YkP8c1w=";

  makeCacheWritable = true;
  dontNpmBuild = true;

  meta = {
    description = "Zotero translation server wrapper that also fetches attachments";
    homepage = "https://github.com/mpedramfar/zotra-server";
    license = lib.licenses.agpl3Only;
    mainProgram = "zotra";
  };
}
