{
  lib,
  python312,
  expiringSkipTests,
  src,
}:

# Upstream kagisearch/kagimcp built from source.
#
# Test overrides for fastmcp's transitive test dep chain in the pinned nixpkgs
# revision; each warns once nixpkgs ships a new version (see
# lib/expiring-override.nix).
let
  pyproject = lib.importTOML "${src}/pyproject.toml";

  # Upstream pins pydantic~=2.12.5 (<2.13); nixpkgs ships 2.13.x. API-compatible.
  pydanticPin = "pydantic~=2.12.5";

  pythonOverridden = python312.override {
    packageOverrides = pyfinal: pyprev: {
      cfn-lint = expiringSkipTests pyprev.cfn-lint {
        brokenAt = "1.43.3";
        reason = "via py-key-value-aio → aiobotocore → types-aiobotocore-dynamodb: failing integration tests";
      };
      inquirer = expiringSkipTests pyprev.inquirer {
        brokenAt = "3.4.1";
        reason = "via py-key-value-aio → aioboto3 → chalice: flaky pexpect TIMEOUTs in acceptance tests";
      };
      inline-snapshot = expiringSkipTests pyprev.inline-snapshot {
        brokenAt = "0.34.2";
        reason = "via http-snapshot → openai/mocket: test_docs.py black-formatting assertions fail";
      };
      cyclopts = expiringSkipTests pyprev.cyclopts {
        brokenAt = "4.25.3";
        reason = "via fastmcp: flaky pexpect TIMEOUT in test_behavior[zsh-literal-positional]";
      };
      anyio = expiringSkipTests pyprev.anyio {
        brokenAt = "4.14.2";
        reason = "via fastmcp: test_tls_connectable fails with \"server_hostname can only be specified in client mode\" on Python 3.12";
      };
    };
  };
in
pythonOverridden.pkgs.buildPythonApplication {
  pname = "kagimcp";
  inherit (pyproject.project) version;
  pyproject = true;
  inherit src;
  build-system = with pythonOverridden.pkgs; [ hatchling ];
  nativeBuildInputs = [ pythonOverridden.pkgs.pythonRelaxDepsHook ];
  pythonRelaxDeps =
    lib.warnIfNot (builtins.elem pydanticPin pyproject.project.dependencies)
      "expiring override: kagimcp no longer pins ${pydanticPin}. Try removing pythonRelaxDeps."
      [ "pydantic" ];
  dependencies = with pythonOverridden.pkgs; [
    fastmcp
    pydantic
    urllib3
    python-dateutil
    typing-extensions
  ];
  doCheck = false;
}
