{
  fetchzip,
  lib,
  stdenvNoCC,
}:

# Oslo kommune's typeface, from https://designmanual.oslo.kommune.no/oslologo-oslo-sans.
# Installs both the CFF OTF family (Oslo Sans) and the Office TTF family
# (Oslo Sans Office), which Word/PowerPoint documents from the kommune reference.
let
  version = "1.3";
  base = "https://designmanual-web-oslo-kommune-no.s3.dualstack.eu-central-1.amazonaws.com/Filer";
  otf = fetchzip {
    name = "oslo-sans-otf";
    url = "${base}/Oslo-Sans-${version}-CFF-OTF.zip";
    hash = "sha256-JIafn6k3OQ6NYmV9G1dyGniCHa+XXt/rWu1MtAz41tA=";
    stripRoot = false;
  };
  office = fetchzip {
    name = "oslo-sans-office-ttf";
    url = "${base}/Oslo-Sans-Office-${version}-TTF.zip";
    hash = "sha256-VXFH6jQoZAIJPd/aq2CFbvNVZR2se7sW+es1bpDwSP0=";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation {
  pname = "oslo-sans";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 -t $out/share/fonts/opentype "${otf}/Oslo Sans ${version} (CFF OTF)"/*.otf
    install -Dm444 -t $out/share/fonts/truetype "${office}/Oslo Sans Office ${version} (TTF)"/*.ttf
    runHook postInstall
  '';

  meta = {
    description = "Oslo Sans, the typeface of Oslo kommune";
    homepage = "https://designmanual.oslo.kommune.no/oslologo-oslo-sans";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
