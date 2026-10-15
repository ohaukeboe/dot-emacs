{
  buildGoModule,
  lib,
  nvSources,
}:

buildGoModule {
  pname = "boilerplate";
  version = lib.removePrefix "v" nvSources.boilerplate.version;
  src = nvSources.boilerplate.src;

  # Not tracked by nvfetcher: bump by hand whenever go.mod/go.sum change.
  vendorHash = "sha256-fiTsgDhHHysKTJgx1Ze8dTidBZBItu7VaXHXnGTD/+E=";

  subPackages = [ "." ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
    "-X github.com/gruntwork-io/boilerplate/version.Version=${nvSources.boilerplate.version}"
  ];

  meta = {
    description = "Cross-platform code generation tool for project templates";
    homepage = "https://github.com/gruntwork-io/boilerplate";
    mainProgram = "boilerplate";
  };
}
