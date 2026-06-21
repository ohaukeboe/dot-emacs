{
  python312,
  src,
}:

# Upstream kagisearch/kagimcp built from source.
#
# Test overrides for fastmcp's transitive test dep chain in the pinned nixpkgs revision:
#   - cfn-lint (via py-key-value-aio → aiobotocore → types-aiobotocore-dynamodb): failing integration tests.
#   - inquirer (via py-key-value-aio → aioboto3 → chalice): flaky pexpect TIMEOUTs in acceptance tests.
# Remove when nixpkgs ships fixes.
let
  pythonOverridden = python312.override {
    packageOverrides = pyfinal: pyprev: {
      cfn-lint = pyprev.cfn-lint.overridePythonAttrs (_: {
        doCheck = false;
      });
      inquirer = pyprev.inquirer.overridePythonAttrs (_: {
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
