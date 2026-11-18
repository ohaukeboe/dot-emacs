# Token counter for the Mango rail's usage popup. Contract:
# specs/013-mango-islands-shell/contracts/usage-record.md. Tested by
# tests/agent-usage.nix.
{ writers }:

writers.writePython3Bin "agent-usage-tokens" {
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./agent-usage-tokens.py)
