# Unit tests for lib/expiring-override.nix, run by `nix flake check`.
#
# Pure evaluation on stand-in packages: the assertions run while the check is
# evaluated, and the derivation only records that they passed.  They test
# `resolve`, which carries the expiry decision and message without emitting the
# warning, so a passing check prints nothing.
{
  lib,
  runCommand,
}:

let
  inherit (import ../lib/expiring-override.nix { inherit lib; }) resolve expiringSkipTests;

  pkg =
    {
      version ? "1.2.0",
      broken ? false,
    }:
    {
      pname = "demo";
      inherit version;
      meta = { inherit broken; };
      overrideAttrs = f: pkg { inherit version broken; } // { overridden = f { }; };
    };

  markOverridden = p: p // { overridden = true; };

  run = args: resolve ({ reason = "test"; } // args) markOverridden;

  failures = lib.runTests {
    testFixedInNotReached = {
      expr =
        let
          r = run {
            pkg = pkg { };
            fixedIn = "1.3.0";
          };
        in
        [
          r.expired
          (r.result.overridden or false)
        ];
      expected = [
        false
        true
      ];
    };

    testFixedInReachedDropsOverride = {
      expr =
        let
          r = run {
            pkg = pkg { version = "1.3.0"; };
            fixedIn = "1.3.0";
          };
        in
        [
          r.expired
          (r.result.overridden or false)
          r.message
        ];
      expected = [
        true
        false
        "expiring override: demo 1.3.0 reached fixedIn 1.3.0, override dropped (test). Remove it."
      ];
    };

    testBrokenAtSameVersion = {
      expr =
        (run {
          pkg = pkg { };
          brokenAt = "1.2.0";
        }).expired;
      expected = false;
    };

    testBrokenAtNewVersionKeepsOverride = {
      expr =
        let
          r = run {
            pkg = pkg { version = "1.2.1"; };
            brokenAt = "1.2.0";
          };
        in
        [
          r.expired
          (r.result.overridden or false)
          r.message
        ];
      expected = [
        true
        true
        "expiring override: demo 1.2.0 -> 1.2.1 (test). Try removing it, or bump brokenAt."
      ];
    };

    testWhileMarkedBrokenStillBroken = {
      expr =
        let
          r = run {
            pkg = pkg { broken = true; };
            whileMarkedBroken = true;
          };
        in
        [
          r.expired
          (r.result.overridden or false)
        ];
      expected = [
        false
        true
      ];
    };

    testWhileMarkedBrokenFixedDropsOverride = {
      expr =
        let
          r = run {
            pkg = pkg { };
            whileMarkedBroken = true;
          };
        in
        [
          r.expired
          (r.result.overridden or false)
        ];
      expected = [
        true
        false
      ];
    };

    testNoConditionThrows = {
      expr = (builtins.tryEval (run { pkg = pkg { }; }).expired).success;
      expected = false;
    };

    testTwoConditionsThrow = {
      expr =
        (builtins.tryEval
          (run {
            pkg = pkg { };
            fixedIn = "1.3.0";
            brokenAt = "1.2.0";
          }).expired
        ).success;
      expected = false;
    };

    testFixedByAloneNeverExpires = {
      expr =
        let
          r = run {
            pkg = pkg { version = "9.9.9"; };
            fixedBy = "NixOS/nixpkgs#572466";
          };
        in
        [
          r.expired
          (r.result.overridden or false)
          r.message
        ];
      expected = [
        false
        true
        null
      ];
    };

    testFixedByWithBrokenAtNamesFixInWarning = {
      expr =
        let
          r = run {
            pkg = pkg { version = "1.2.1"; };
            brokenAt = "1.2.0";
            fixedBy = "NixOS/nixpkgs#572466";
          };
        in
        [
          r.expired
          (r.result.overridden or false)
          r.message
        ];
      expected = [
        true
        true
        "expiring override: demo 1.2.0 -> 1.2.1 (test). Try removing it, or bump brokenAt. Fix tracked in NixOS/nixpkgs#572466 (just check-fixes)."
      ];
    };

    testTwoConditionsWithFixedByThrow = {
      expr =
        (builtins.tryEval
          (run {
            pkg = pkg { };
            fixedIn = "1.3.0";
            brokenAt = "1.2.0";
            fixedBy = "NixOS/nixpkgs#572466";
          }).expired
        ).success;
      expected = false;
    };

    testMalformedFixedByThrows = {
      expr =
        map
          (
            ref:
            (builtins.tryEval
              (run {
                pkg = pkg { };
                fixedBy = ref;
              }).expired
            ).success
          )
          [
            "nixpkgs#572466"
            "NixOS/nixpkgs572466"
            "NixOS/nixpkgs#"
            "NixOS/nixpkgs#57a"
            "https://github.com/NixOS/nixpkgs/pull/572466"
          ];
      expected = [
        false
        false
        false
        false
        false
      ];
    };

    # Not expired, so no warning; falls back to overrideAttrs for a package
    # without overridePythonAttrs.
    testSkipTestsDisablesChecks = {
      expr =
        (expiringSkipTests (pkg { }) {
          brokenAt = "1.2.0";
          reason = "test";
          skipImportsCheck = true;
        }).overridden;
      expected = {
        doCheck = false;
        pythonImportsCheck = [ ];
      };
    };
  };
in
assert lib.assertMsg (
  failures == [ ]
) "expiring-override tests failed: ${builtins.toJSON failures}";
runCommand "expiring-override-tests" { } "touch $out"
