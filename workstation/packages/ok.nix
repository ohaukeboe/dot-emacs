{
  buildGoModule,
  fzf,
  installShellFiles,
  lib,
  makeWrapper,
  nvSources,
  yq-go,
}:

buildGoModule {
  pname = "ok";
  version = lib.removePrefix "v" nvSources.ok.version;
  src = nvSources.ok.src;

  # Not tracked by nvfetcher: bump by hand whenever go.mod/go.sum change.
  vendorHash = "sha256-OJM9WO129g/Onk6E0BkHHohpkfqDsvyq7WiIefBKxDU=";

  subPackages = [ "." ];
  ldflags = [
    "-s"
    "-w"
    "-X main.version=${lib.removePrefix "v" nvSources.ok.version}"
  ];

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  # Same runtime deps and completions as the upstream Homebrew formula.
  postInstall = ''
    installShellCompletion --cmd ok \
      --bash <($out/bin/ok completion bash) \
      --fish <($out/bin/ok completion fish) \
      --zsh <($out/bin/ok completion zsh)
    wrapProgram $out/bin/ok \
      --prefix PATH : ${
        lib.makeBinPath [
          fzf
          yq-go
        ]
      }
  '';

  meta = {
    description = "Oslo kommune infrastructure toolbox";
    homepage = "https://github.com/oslokommune/ok";
    mainProgram = "ok";
  };
}
