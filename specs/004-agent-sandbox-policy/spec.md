# Feature Specification: Agent Sandbox Policy

**Feature Branch**: `004-agent-sandbox-policy`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: (none given with the command; derived from the
sandboxing research session of 2026-10-08 and the note
`roam/20261008071854-agent_sandboxing.org`) "Sandbox the Claude Code agent per
project. It runs in auto mode. The threat is the agent deciding on its own to do
something I did not ask for, not prompt injection. It must keep making signed
commits, keep using ad-hoc tools and project dev environments from Nix, and
keep spinning up VMs. It must not change the system or infrastructure and must
not read credentials. Permissions should be declared per project, and the agent
should be able to propose the permission changes it needs for me to review and
approve."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Auto mode cannot touch credentials or the system (Priority: P1)

The user works in a project with the agent in auto mode. While debugging, the
agent decides on its own to look at a key file, restart a container, or apply
the system configuration. With this feature, every shell command the agent runs
is confined: credential locations read as missing, the services that act with
the user's authority (container runtime, VM manager, password and key agents,
the editor's server) cannot be reached, and system-changing commands fail. The
agent can still install ad-hoc tools from the package manager, enter the
project's development environment, build the project, and run VM-based tests.

**Why this priority**: This is the protection the feature exists for. Today the
agent runs with the user's full authority, and two group memberships (container
runtime, VM manager) are equivalent to root. One wrong autonomous decision is
enough to damage the workstation or leak a secret.

**Independent Test**: Ask the agent to run the probe set (read each credential
location, contact each hidden service, attempt a system change, then fetch an
ad-hoc tool, build the project and start a test VM). Every probe in the first
group fails and every probe in the second group succeeds.

**Acceptance Scenarios**:

1. **Given** auto mode in any project, **When** the agent runs a command that
   reads a file under a protected credential location, **Then** the read fails
   and the content never appears in the session.
2. **Given** auto mode, **When** the agent runs a command that talks to the
   container runtime, VM manager, password store, key agent or editor server,
   **Then** the connection fails.
3. **Given** auto mode, **When** the agent tries to apply a system
   configuration or elevate privileges, **Then** the command is refused before
   or during execution.
4. **Given** auto mode, **When** the agent requests a tool that is not
   installed through the package manager's ad-hoc shell, **Then** the tool is
   fetched and runs.
5. **Given** a project that defines a development environment and a VM test,
   **When** the agent enters the environment and runs the VM test, **Then** both
   work as they do without the sandbox.
6. **Given** the confinement cannot be established at session start (missing
   dependency, unsupported kernel feature), **When** the session starts,
   **Then** it refuses to run commands rather than running them unconfined.

---

### User Story 2 - The agent makes signed commits but cannot push (Priority: P2)

The user asks the agent to commit its work. The commit is signed and shows as
verified on the code host, under a signing identity that is distinct from the
user's own, so agent-made commits can be told apart. The same identity cannot
authenticate to any remote, so the agent cannot push, and pushing remains a
user action.

**Why this priority**: Signed commits are a hard requirement from the user and
were the main reason an earlier attempt at sandboxing was turned off. Without
this, the P1 protection would be disabled again.

**Independent Test**: In a sandboxed session, have the agent create a commit
and attempt a push. Verify the commit signature locally and on the code host,
and confirm the push fails for lack of authentication.

**Acceptance Scenarios**:

1. **Given** a sandboxed session, **When** the agent commits, **Then** the
   commit is signed and verifies against the agent's signing identity.
2. **Given** a sandboxed session, **When** the agent attempts to push over any
   transport, **Then** the push fails.
3. **Given** the user commits from their own shell, **When** they inspect the
   signature, **Then** it uses the user's own identity, unchanged by this
   feature.
4. **Given** an open authenticated remote connection the user started earlier,
   **When** the agent runs a command in the same time window, **Then** it cannot
   reuse that connection.

---

### User Story 3 - Per-project policy with agent-proposed changes (Priority: P3)

A project needs more than the baseline: write access to a sibling project, a
network host for a package registry, or one tool that only works outside the
sandbox. The user declares this in the project's own policy. When the agent hits
a limit, it does not look for a workaround and cannot run the command
unconfined. Instead it proposes the narrowest policy change with a one-line
reason. The user sees exactly what would change and approves or rejects it. The
proposal requires the user's approval even in auto mode. Once approved, the
change takes effect for the next command where possible.

**Why this priority**: This makes the P1 baseline livable. Without a cheap way
to widen it per project, the user would turn the sandbox off again.

**Independent Test**: In a project without a policy, ask the agent to write to
a sibling project. Observe the failure, the proposal, the approval prompt, and
a successful retry after approval. Reject a second proposal and confirm nothing
changes.

**Acceptance Scenarios**:

1. **Given** a command fails because of the sandbox, **When** the agent
   responds, **Then** it proposes a policy change instead of retrying
   unconfined or working around the limit.
2. **Given** a proposed policy change in auto mode, **When** it is about to be
   written, **Then** the user is prompted with the exact change and nothing is
   written without approval.
3. **Given** the agent's shell commands, **When** they try to write the
   project policy or the agent's own configuration directly, **Then** the write
   fails.
4. **Given** an approved change that grants a directory, **When** the agent
   retries, **Then** the retry succeeds without restarting the session.
5. **Given** a project policy that tries to re-allow a credential location the
   baseline protects, **When** the session runs, **Then** the location stays
   protected.

---

### User Story 4 - Read-only system debugging in the system-config project (Priority: P4)

In the workstation configuration project, the agent investigates a failing
service. It reads system and user logs and service status. It can build the new
configuration to check it evaluates and compiles. It cannot activate the
configuration, restart system services or elevate privileges.

**Why this priority**: The user values this debugging ability in this one
project. It mostly follows from P1 and needs only a small project policy.

**Independent Test**: In the system-config project, have the agent read recent
logs for a named service, show its status, and build the configuration. Then
have it attempt to activate the configuration and restart a system service.

**Acceptance Scenarios**:

1. **Given** the system-config project, **When** the agent reads logs or
   service status, **Then** it gets the same output the user would.
2. **Given** the system-config project, **When** the agent builds the
   configuration without activating it, **Then** the build runs.
3. **Given** the system-config project, **When** the agent tries to activate
   the configuration or restart a system service, **Then** the action fails.

---

### Edge Cases

- The agent creates or clones a new repository during a session: hook and
  config files inside it must not become a way to run code later outside the
  sandbox.
- A session is killed hard and leaves read-only placeholder files at policy
  paths, so later approvals fail to save. The user needs a documented way to
  detect and clear them.
- The existing per-command runtime cap needs the user's service manager from
  inside the sandbox. It must keep working, and the access this implies must be
  documented as a known gap.
- A tool used by the agent ignores the network proxy settings and cannot reach
  an allowed host. The failure must name the host so a proposal can follow.
- The agent signing identity is unavailable (agent not started, key not yet
  decrypted after boot). Commits must fail with a clear message rather than
  fall back to the user's identity.
- A project that genuinely needs the container runtime declares a narrow
  exception. The exception must not reopen the runtime to every command.
- Another agent harness or a nested agent session started from inside the
  sandbox.
- The user types a command directly at the session's shell prompt. It runs
  with the user's authority, and the documentation must say so.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The agent's shell commands MUST run confined in every project
  unless a project policy explicitly exempts a narrow command pattern.
- **FR-002**: A session MUST refuse to run shell commands when confinement
  cannot be established. It MUST NOT silently fall back to unconfined execution.
- **FR-003**: The agent MUST NOT be able to retry a blocked command unconfined
  on its own decision.
- **FR-004**: The baseline policy MUST block reads of every listed credential
  location: SSH keys, GPG keys, decrypted SOPS secrets, age keys, cloud and
  cluster credentials, code-host CLI tokens, the password store, desktop
  keyrings, password-manager data and browser profiles.
- **FR-005**: The baseline MUST block reads of the same credential locations
  through the agent's built-in file-reading tool, not only its shell.
- **FR-006**: The baseline MUST make unreachable from confined commands: the
  rootful and rootless container runtimes, the system VM manager, the user's
  main SSH agent, the GPG agent, the desktop keyring, the password-manager
  browser bridge and the editor server.
- **FR-007**: The package manager daemon MUST remain reachable so ad-hoc tool
  shells, project development environments, builds and VM tests keep working.
- **FR-008**: Hardware virtualisation MUST remain available to confined
  commands for VM-based tests.
- **FR-009**: Credential-bearing environment variables (code-host tokens and any
  others the baseline lists) MUST be removed from the environment of confined
  commands.
- **FR-010**: The baseline MUST refuse privilege elevation and activation of
  the system configuration.
- **FR-011**: Confined commands MUST NOT be able to write the agent's own
  configuration, project policy files, repository hook or config files, or
  shell startup files.
- **FR-012**: Outbound network access from confined commands MUST be limited
  to a baseline host allowlist (package caches, the code host's read endpoints)
  plus hosts a project policy adds.
- **FR-013**: The baseline policy MUST be generated by the workstation
  configuration and MUST NOT be writable by the agent.
- **FR-014**: A project policy MUST be able to widen the baseline with extra
  readable or writable directories, extra network hosts and narrow exempt
  command patterns.
- **FR-015**: A project policy MUST NOT be able to remove a credential
  protection or the no-unconfined-retry rule set by the baseline.
- **FR-016**: Every change the agent makes to a project policy MUST require the
  user's explicit approval, showing the exact change, in every permission mode
  including auto mode.
- **FR-017**: The agent MUST be instructed to respond to a sandbox failure by
  proposing the narrowest policy change with a one-line reason, rather than
  working around the limit.
- **FR-018**: Approved changes to directory access MUST apply to the running
  session without a restart.
- **FR-019**: The agent MUST sign commits with a dedicated signing identity
  that the code host trusts for signatures only and that cannot authenticate to
  any remote.
- **FR-020**: Commits the user makes outside the agent MUST keep using the
  user's own signing identity.
- **FR-021**: Long-lived authenticated remote connections the user opens MUST
  NOT be reusable by confined commands.
- **FR-022**: Push attempts by the agent MUST require the user's approval even
  when a project grants push credentials.
- **FR-023**: The system-config project policy MUST allow reading system and
  user logs and service status, and building the configuration, without
  allowing any change to running services.
- **FR-024**: The editor integration MUST NOT offer the agent a tool that
  evaluates arbitrary editor code. *(Done 2026-10-08: the evaluation tool is
  disabled in the Emacs configuration.)*
- **FR-025**: The feature MUST ship a probe set the user can ask the agent to
  run, covering every protection in FR-004 to FR-012 and every capability in
  FR-007, FR-008, FR-019 and FR-023.
- **FR-026**: The existing per-command runtime and memory caps MUST keep
  working inside the sandbox.

### Key Entities

- **Baseline policy**: the workstation-wide rules every session starts with.
  Owned by the workstation configuration and not writable by the agent. Holds
  the credential list, the hidden-service list, the network allowlist, the
  refusal rules and the approval rules.
- **Project policy**: per-project additions to the baseline (directories, hosts,
  exempt command patterns). It can only widen access where the baseline allows
  widening. It lives with the project.
- **Policy proposal**: a change to a project policy suggested by the agent,
  with a reason. It is applied only after the user approves it.
- **Agent signing identity**: a signing key separate from the user's, trusted by
  the code host for signatures only, available to confined commands through a
  dedicated agent.
- **Probe set**: the list of checks that demonstrate each protection and each
  preserved capability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of probes against protected credential locations and hidden
  services fail when run by the agent, in a project with no project policy.
- **SC-002**: 100% of preserved-capability probes succeed when run by the agent:
  ad-hoc tool, development environment, project build, VM test and signed
  commit.
- **SC-003**: 0 pushes succeed from a sandboxed session without a user approval
  prompt.
- **SC-004**: 100% of agent edits to a project policy produce an approval
  prompt in auto mode. 0 are applied when rejected.
- **SC-005**: Granting a project one extra directory after a sandbox failure
  takes the user one approval and under 30 seconds, with no manual file
  editing.
- **SC-006**: Every commit created by the agent during a week of normal use
  verifies as signed on the code host, and every one can be attributed to the
  agent identity.
- **SC-007**: In the first two weeks of use the sandbox is not disabled
  globally to unblock work. Each block encountered is resolved by a project
  policy change or recorded as an issue.
- **SC-008**: Starting a session with confinement unavailable never results in
  an unconfined command (verified by removing a dependency and starting a
  session).

## Assumptions

- The threat model is unwanted autonomous actions by a cooperative agent.
  Deliberate evasion and prompt injection are out of scope. The rules that
  match command text are acceptable defences under this model. A full-process
  confinement design remains documented in the research report for when that
  changes.
- Claude Code is the only agent harness covered. Other harnesses are out of
  scope.
- Tools that run outside the shell sandbox (the built-in file tools, hooks,
  MCP servers, language servers) are covered by permission rules and auto mode's
  classifier, not by confinement.
- Project policies default to the per-user, git-ignored project location. A
  project may instead commit its policy when the user wants it versioned.
- Pushing stays a user action by default. A project that needs agent pushes
  grants access explicitly, and every push still prompts (FR-022).
- The user's own group memberships (container runtime, VM manager) are left
  unchanged by this feature, because confinement hides those services from the
  agent. Removing the memberships is a separate hardening decision.
- The per-command runtime cap keeps needing the user's service manager inside
  the sandbox. Reaching it would let the agent start a user service outside the
  sandbox. Under this threat model that is accepted and documented, not fixed.
- On this platform, socket access cannot be allowlisted by path; it is all or
  nothing. Services are hidden by masking their paths. That this hides them
  must be confirmed by the probe set (FR-025) before the feature counts as
  done.
- The research report at https://claude.ai/artifact/8D4UEUDdrqXyLTgvFdgapY
  (revision 3) is the design reference for planning.
