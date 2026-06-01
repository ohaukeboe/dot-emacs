{
  python312,
  src,
}:

# Upstream kagisearch/kagimcp built from source.
#
# cfn-lint override: fastmcp's transitive test dep chain
# (py-key-value-aio → aiobotocore → types-aiobotocore-dynamodb → cfn-lint)
# has failing integration tests in the pinned nixpkgs revision. Skip
# cfn-lint's own checks so the chain builds. Remove when nixpkgs ships a fix.
let
  pythonOverridden = python312.override {
    packageOverrides = pyfinal: pyprev: {
      cfn-lint = pyprev.cfn-lint.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };
in
pythonOverridden.pkgs.buildPythonApplication {
  pname = "kagimcp";
  version = "1.0.0";
  pyproject = true;
  inherit src;
  build-system = with pythonOverridden.pkgs; [ hatchling ];
  dependencies = with pythonOverridden.pkgs; [
    fastmcp
    pydantic
    urllib3
    python-dateutil
    typing-extensions
  ];
  doCheck = false;
}
