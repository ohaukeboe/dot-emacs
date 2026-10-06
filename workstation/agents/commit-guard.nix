{ lib, pkgs, ... }:
let
  # The `git commit` ask rule stops at a permission prompt, and the user reviews
  # the staged diff at that prompt. The guard denies a commit that stages in the
  # same call (`git add ... && git commit`, `-a`, pathspecs), so what was
  # reviewed is exactly what gets committed. See commit-guard.py.
  commitGuard = pkgs.writers.writePython3Bin "agent-commit-guard" {
    flakeIgnore = [
      # Conflicts with the formatter (ruff), which owns layout.
      "E203"
      "E501"
      "W503"
    ];
  } (builtins.readFile ./commit-guard.py);
in
{
  agents.tools.commit-guard = {
    # Its own PreToolUse hook rather than an agents.bashRewriters stage: it
    # never returns updatedInput, so it cannot race the rewriter chain, and a
    # deny from any hook wins over the chain's ask. It also reads the command
    # as the agent wrote it, before rtk or the process cap rewrite it.
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = lib.getExe commitGuard;
          }
        ];
      }
    ];
  };
}
