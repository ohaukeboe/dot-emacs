# Worktree include list: give every new linked worktree the local-only files
# listed in the main worktree's .worktreeinclude (CLAUDE.md, .envrc, ...).
# Claude Code reads the same file for its own worktrees.
#
# Listed paths must be ignored (e.g. in .git/info/exclude), or the links show
# as untracked and `git worktree remove` refuses. Exclude a linked directory
# without a trailing slash: `docs/agents/` matches directories only, not the
# symlink that replaces it.
{ pkgs, ... }:
let
  worktreeInclude = pkgs.writeShellApplication {
    name = "git-worktree-include";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      # post-checkout args: <prev HEAD> <new HEAD> <branch flag>. The previous
      # HEAD is all zeros only on a fresh checkout.
      [[ ''${1:-} =~ ^0+$ ]] || exit 0

      # Only linked worktrees: a clone or the main worktree has nothing to
      # take from.
      git_dir=$(git rev-parse --path-format=absolute --git-dir)
      common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
      [ "$git_dir" != "$common_dir" ] || exit 0

      main=$(dirname "$common_dir")
      list="$main/.worktreeinclude"
      [ -f "$list" ] || exit 0

      warn() { echo "worktree-include: $*" >&2; }

      # The hook's exit status becomes that of `git worktree add`, so every
      # failure below only warns.
      while IFS= read -r p || [ -n "$p" ]; do
        p=''${p%/}
        [[ -z $p || $p == \#* ]] && continue
        if [[ $p == *[\*\?\[]* ]]; then
          warn "skipping glob '$p': only literal paths are supported"
          continue
        fi
        if [ ! -e "$main/$p" ]; then
          warn "skipping '$p': not in $main"
          continue
        fi
        # Never overwrite: the branch may track the path itself.
        [ -e "$p" ] || [ -L "$p" ] && continue
        mkdir -p "$(dirname "$p")" || { warn "cannot create parent of '$p'"; continue; }
        case $p in
          # Each worktree keeps its own approvals.
          .claude/*) cp -r "$main/$p" "$p" || warn "cannot copy '$p'" ;;
          *) ln -s "$main/$p" "$p" || warn "cannot link '$p'" ;;
        esac
      done <"$list"
      exit 0
    '';
  };
in
{
  # A config-defined hook rather than core.hooksPath: a repository's own
  # core.hooksPath (beads, lefthook) overrides a global one, while
  # config-defined hooks run alongside the repository's hooks.
  programs.git.settings.hook.worktree-include = {
    event = "post-checkout";
    command = "${worktreeInclude}/bin/git-worktree-include";
  };
}
