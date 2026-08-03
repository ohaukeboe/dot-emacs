{
  python312,
  src,
}:

# Upstream kagisearch/kagimcp built from source.
#
# Test overrides for fastmcp's transitive test dep chain in the pinned nixpkgs revision:
#   - cfn-lint (via py-key-value-aio → aiobotocore → types-aiobotocore-dynamodb): failing integration tests.
#   - inquirer (via py-key-value-aio → aioboto3 → chalice): flaky pexpect TIMEOUTs in acceptance tests.
#   - inline-snapshot (via http-snapshot → openai/mocket): test_docs.py black-formatting assertions fail.
#   - cyclopts (via fastmcp): flaky pexpect TIMEOUT in test_behavior[zsh-literal-positional].
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
      inline-snapshot = pyprev.inline-snapshot.overridePythonAttrs (_: {
        doCheck = false;
      });
      cyclopts = pyprev.cyclopts.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };
in
pythonOverridden.pkgs.buildPythonApplication {
  pname = "kagimcp";
  version = "1.0.2";
  pyproject = true;
  inherit src;
  build-system = with pythonOverridden.pkgs; [ hatchling ];
  nativeBuildInputs = [ pythonOverridden.pkgs.pythonRelaxDepsHook ];
  # Upstream pins pydantic~=2.12.5 (<2.13); nixpkgs ships 2.13.x. API-compatible.
  pythonRelaxDeps = [ "pydantic" ];
  dependencies = with pythonOverridden.pkgs; [
    fastmcp
    pydantic
    urllib3
    python-dateutil
    typing-extensions
  ];
  doCheck = false;
}
