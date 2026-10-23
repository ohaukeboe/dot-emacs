# Workaround overrides that say when they may be obsolete (see "Package
# overrides" in GLOSSARY.md). Each takes at most one expiry condition, checked
# against the pinned nixpkgs at evaluation time, and at least one unless it
# has a fix reference:
#
#   fixedIn = "X";            the fix release is known. Once nixpkgs reaches it,
#                             the override is dropped and a warning says so.
#   brokenAt = "X";           the version seen broken. Once nixpkgs ships any
#                             other version, a warning asks for a re-check; the
#                             override keeps applying until then.
#   whileMarkedBroken = true; once nixpkgs drops meta.broken, the override is
#                             dropped and a warning says so.
#
#   fixedBy, a string "owner/repo#N" (not spelled out as an assignment here,
#   so `just check-fixes` does not report this example): the fix reference,
#   the nixpkgs PR (preferred) or issue whose change obsoletes the override.
#   Not judged at evaluation time (`just check-fixes` does that); alone, the
#   override always applies. Expiry warnings name it.
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
    else if given == [ ] && args ? fixedBy then
      null
    else
      throw "expiringOverride: give at most one of ${lib.concatStringsSep ", " conditionKinds}, and at least one unless fixedBy is set (got: [ ${toString given} ])";

  # A fix reference: owner/repo#N. The one definition of its syntax:
  # flake.nix injects it into scripts/check-fixes.sh, so `just check-fixes`
  # parses exactly what is accepted here. POSIX ERE, usable by both.
  fixReferencePattern = "[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+";

  checkFixedBy =
    args:
    if !(args ? fixedBy) || builtins.match fixReferencePattern args.fixedBy != null then
      args
    else
      throw "expiringOverride: fixedBy must look like owner/repo#N (got: ${args.fixedBy})";

  # Everything but the warning itself, so tests can inspect it without one.
  resolve =
    {
      pkg,
      reason,
      ...
    }@args:
    override:
    let
      kind = conditionOf (checkFixedBy args);
      name = lib.getName pkg;
      expired =
        kind != null
        && {
          fixedIn = lib.versionAtLeast pkg.version args.fixedIn;
          brokenAt = pkg.version != args.brokenAt;
          whileMarkedBroken = !(pkg.meta.broken or false);
        }
        .${kind};
      # null when there is no expiry condition (fixedBy alone): never warned.
      message =
        if kind == null then
          null
        else
          {
            fixedIn = "expiring override: ${name} ${pkg.version} reached fixedIn ${args.fixedIn}, override dropped (${reason}). Remove it.";
            brokenAt = "expiring override: ${name} ${args.brokenAt} -> ${pkg.version} (${reason}). Try removing it, or bump brokenAt.";
            whileMarkedBroken = "expiring override: ${name} is no longer marked broken, override dropped (${reason}). Remove it.";
          }
          .${kind}
          + lib.optionalString (args ? fixedBy) " Fix tracked in ${args.fixedBy} (just check-fixes).";
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
  inherit
    fixReferencePattern
    resolve
    expiringOverride
    expiringSkipTests
    ;
}
