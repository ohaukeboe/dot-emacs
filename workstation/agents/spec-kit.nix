{ pkgs, ... }:
{
  # Spec-driven development (github/spec-kit). Its workflow commands are not
  # global skills: they are templates that `specify init --ai claude` renders
  # into a project, together with the `.specify/` scripts they call. So only
  # the CLI is installed here; run `specify init` per project.
  agents.tools.specKit.packages = [ pkgs.spec-kit ];
}
