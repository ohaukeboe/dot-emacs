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

  # Not tracked by nvfetcher; `just fix-hashes` (run by `just update`) bumps it.
  vendorHash = "sha256-4uDCCLgoLcGttsVpIPZPtM8r5xRtmTXs+5qVSiF3KKM=";

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
