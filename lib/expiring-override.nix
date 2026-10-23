# Workaround overrides that say when they may be obsolete (see "Package
# overrides" in CONTEXT.md). Each takes exactly one expiry condition, checked
# against the pinned nixpkgs at evaluation time:
#
#   fixedIn = "X";            the fix release is known. Once nixpkgs reaches it,
#                             the override is dropped and a warning says so.
#   brokenAt = "X";           the version seen broken. Once nixpkgs ships any
#                             other version, a warning asks for a re-check; the
#                             override keeps applying until then.
#   whileMarkedBroken = true; once nixpkgs drops meta.broken, the override is
#                             dropped and a warning says so.
#
#   pkgs.expiringOverride {
#     pkg = pyprev.anyio;
#     brokenAt = "4.14.2";
#     reason = "test_tls_connectable fails on Python 3.12";
#   } (p: p.overridePythonAttrs (_: { doCheck = false; }))
#
#   pkgs.expiringSkipTests pyprev.anyio {
#     brokenAt = "4.14.2";
#     reason = "test_tls_connectable fails on Python 3.12";
#   }
#
# Why: docs/adr/0005-expiring-workaround-overrides.md
{ lib }:

let
  conditionKinds = [
    "fixedIn"
    "brokenAt"
    "whileMarkedBroken"
  ];

  conditionOf =
    args:
    let
      given = builtins.filter (k: args ? ${k}) conditionKinds;
    in
    if builtins.length given == 1 then
      builtins.head given
    else
      throw "expiringOverride: give exactly one of ${lib.concatStringsSep ", " conditionKinds} (got: [ ${toString given} ])";

  # Everything but the warning itself, so tests can inspect it without one.
  resolve =
    {
      pkg,
      reason,
      ...
    }@args:
    override:
    let
      kind = conditionOf args;
      name = lib.getName pkg;
      expired =
        {
          fixedIn = lib.versionAtLeast pkg.version args.fixedIn;
          brokenAt = pkg.version != args.brokenAt;
          whileMarkedBroken = !(pkg.meta.broken or false);
        }
        .${kind};
      message =
        {
          fixedIn = "expiring override: ${name} ${pkg.version} reached fixedIn ${args.fixedIn}, override dropped (${reason}). Remove it.";
          brokenAt = "expiring override: ${name} ${args.brokenAt} -> ${pkg.version} (${reason}). Try removing it, or bump brokenAt.";
          whileMarkedBroken = "expiring override: ${name} is no longer marked broken, override dropped (${reason}). Remove it.";
        }
        .${kind};
    in
    {
      inherit expired message;
      result = if expired && kind != "brokenAt" then pkg else override pkg;
    };

  expiringOverride =
    args: override:
    let
      r = resolve args override;
    in
    lib.warnIf r.expired r.message r.result;

  # The common case: a package whose test suite fails or flakes in nixpkgs.
  expiringSkipTests =
    pkg:
    {
      skipImportsCheck ? false,
      ...
    }@args:
    expiringOverride (removeAttrs args [ "skipImportsCheck" ] // { inherit pkg; }) (
      p:
      (p.overridePythonAttrs or p.overrideAttrs) (
        _: { doCheck = false; } // lib.optionalAttrs skipImportsCheck { pythonImportsCheck = [ ]; }
      )
    );
in
{
  inherit resolve expiringOverride expiringSkipTests;
}
