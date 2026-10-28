# Who can read a Linux secret store, and is plaintext `~/.authinfo` worse?

Research report. Question: who on a Linux system can read secrets from the
Secret Service (gnome-keyring, KeePassXC, oo7), gpg-agent, the kernel keyring,
systemd-creds and age/sops? Is any of them meaningfully better than a
plaintext `~/.authinfo` on a fully encrypted disk, without having to type a
password all the time?

Checked on 2026-10-28 on `dig-laptop` (NixOS `26.11.20261020.02c087f`,
kernel `7.2.11-zen1`, COSMIC, Emacs 31.1) against the repo at `160eaf4` and
the primary sources listed at the end. No secret file, keyring, socket or
`/run/secrets` entry was read for this report.

## TL;DR

- **On Linux, any process running as your user can read every secret in an
  unlocked Secret Service collection.** It needs only the session D-Bus. The
  spec defines no per-application access control. GNOME's own security notes
  say that isolating apps inside one session would be "security theater"
  until the desktop itself is hardened. macOS Keychain has per-item app ACLs.
  Linux has none, apart from Flatpak's per-app Secret portal.
- **The same holds for gpg-agent, the kernel user keyring, sops-nix outputs and
  the age key.** Each is open to any same-UID process for as long as it is
  unlocked or cached. Only a hardware token with a touch policy (YubiKey)
  puts a *human* in the loop on each use.
- **This repo already makes `~/.authinfo` a sops-nix template**
  (`workstation/sops.nix:120-142`), not a hand-kept plaintext file. The real
  master secret is the shared host age key, handed to your user as
  `/run/secrets/host-age-key` (owner = you, mode 0400,
  `modules/sops/default.nix:65-72`). Any process of yours can read that key,
  and it decrypts *every* secret in `sops/`, the SSH keys included. Moving
  `.authinfo` entries into a keyring would not change the overall risk.
- **What actually matters for your threat model:** FDE covers a powered-off
  or hibernated laptop, which ADR 0001 keeps on LUKS. FDE does nothing
  against code already running as you: malware, a compromised npm or Emacs
  package, or an AI agent. You already handle agents the right way: the
  sandbox hides `~/.authinfo`, the keyring and the bus. **One likely gap:**
  the sandbox deny list does not name `/run/secrets` or
  `$XDG_RUNTIME_DIR/secrets.d` (unverified, see §6).
- **Recommendation:** keep the current design for low- and medium-value API
  keys. Close the `/run/secrets` sandbox gap. Move only the few high-value
  credentials, such as GitHub PATs with write scope, to something that asks
  for a YubiKey touch. Moving `.authinfo` into gnome-keyring adds work and
  buys almost nothing.

## 1. What is in use on this machine (repo facts)

- **gnome-keyring** is on, with gcr-ssh-agent turned off
  (`modules/cosmic-de/default.nix:298-304`). The NixOS module sets
  `security.pam.services.login.enableGnomeKeyring = true` and wraps the daemon
  with `cap_ipc_lock`
  (nixpkgs `nixos/modules/services/desktops/gnome/gnome-keyring.nix:38-45`).
  It holds Proton Pass CLI's database key through
  `PROTON_PASS_LINUX_KEYRING = "dbus"` (`modules/cosmic-de/default.nix:315-322`).
- **PAM auto-unlock is wired up.** `/etc/pam.d/greetd` includes `login`, and
  `/etc/pam.d/login` has `pam_gnome_keyring.so` in the auth, password and
  session (`auto_start`) stacks. **But** `pam_fprintd.so` is `auth sufficient`
  *before* it (`/etc/pam.d/login:5-7`, from `services.fprintd.enable` in
  `common/system/system.nix:140`). A fingerprint login never hands PAM a
  password, so the login keyring stays locked and asks for its password at
  first use. This is what upstream's PAM module implies: it unlocks with
  "the user's password" (gnome-keyring `pam/gkr-pam-module.c`).
- **`~/.authinfo`** is rendered at activation by `sops.templates.authinfo`
  with mode 0600 (`workstation/sops.nix:120-142`). Its values come from
  `sops/home/secrets.yaml`. The sops-nix Home Manager module defaults its
  secrets mount to `%r/secrets.d`, which is `$XDG_RUNTIME_DIR`, a tmpfs
  (sops-nix `modules/home-manager/sops.nix:193-195`). Because `path` is set,
  `~/.authinfo` is *likely* a symlink into that tmpfs, so the plaintext would
  live in RAM, not on disk. *Not verified on the host, because the sandbox
  denies reading the path.*
- **Emacs** sets `auth-sources '("~/.authinfo")`
  (`workstation/emacs/config.org:1669`). `gptel-api-key` is evaluated once
  as a string at load time (`config.org:4222-4223`), so the OpenAI key sits
  in Emacs's heap for the whole session whatever the backend.
- **No gpg-agent, `pass` or KeePassXC** is configured. Git signs with SSH
  (`workstation/home.nix:694-695`). `~/.password-store` and `~/.gnupg` are
  in the sandbox deny list only as a precaution
  (`workstation/agents/sandbox.nix:268-282`).
- **The age key chain:** the system decrypts with `/var/lib/sops-nix/keys.txt`,
  which is root-only. It then hands the same shared host key to your user as
  the sops secret `host-age-key`, owner = you, mode `0400`
  (`modules/sops/default.nix:57-72`). Home Manager's sops-nix decrypts with
  that key (`modules/sops/default.nix:79-81`). YubiKey and TPM identities
  are configured as escape hatches (`workstation/sops.nix:16-27`).
- **Yama:** `/proc/sys/kernel/yama/ptrace_scope` is `1` (read live).
- **Hibernation:** `modules.sleep-then-hibernate` is on for two machines
  (`machines/machines.nix:45,61`). The swapfile is on the LUKS volume, so
  the hibernation image is encrypted at rest (ADR 0001, Consequences).
- **Backups:** btrbk on `work-laptop` snapshots only `home/oskar/projects` and
  `home/oskar/knowit` (`machines/work-laptop/config.nix:54-68`), not
  `~/.authinfo`.

## 2. Secret Service (gnome-keyring, KeePassXC, oo7)

**Who can read it:** any client on your session bus. The Secret Service is a
D-Bus API. Nothing in the spec identifies or authorises the calling app:

- The spec has no ACL concept. Its "Notes for Service Implementors" chapter is
  literally `[TODO: complete]`
  ([ch11](https://specifications.freedesktop.org/secret-service/latest/ch11.html)).
- The spec encrypts secrets in transit only "to minimize storage of plain text
  secrets in memory" and to keep them out of swap. It says the encryption
  "is not envisioned to withstand man in the middle attacks, or other active
  attacks"
  ([Transfer of Secrets](https://specifications.freedesktop.org/secret-service/latest/transfer-secrets.html)).
- GNOME's security philosophy protects only against *passive* attackers, who
  "would not have access to your user session". It lists "Application
  signing (for ACLs)" as missing. It calls in-session isolation "security
  theater" without wider desktop hardening
  ([GnomeKeyring/SecurityPhilosophy](https://wiki.gnome.org/Projects/GnomeKeyring/SecurityPhilosophy)).
- Once the `login` collection is unlocked, `secret-tool search --all` from any
  of your processes returns everything. This is why the agent sandbox hides
  `$XDG_RUNTIME_DIR/bus`, and why an assertion keeps it hidden
  (`workstation/agents/sandbox.nix:483-490`).

**Compared with macOS:** Keychain items carry per-application access lists
that are tied to code signatures. Linux desktops have no code-signing
identity to attach such a list to, which is the GNOME page's point. *The
macOS behaviour is general knowledge. No Apple source was fetched for this
report.*

**KeePassXC "Confirm when passwords are retrieved by clients":** this prompt
does help, within limits.

- KeePassXC identifies a client by its *unique D-Bus connection address*. It
  records PID and exe path, but per its own source only "for showing to the
  user". Allow and deny decisions are stored per connection and die with it
  ([`DBusClient.h`](https://github.com/keepassxreboot/keepassxc/blob/develop/src/fdosecrets/dbus/DBusClient.h)).
- So every new process has to be approved again. That makes it a real
  speed bump against silent bulk reads. The cost is a prompt for each
  short-lived `secret-tool` or Emacs restart, unless you choose "remember"
  for that connection's lifetime.
- It does not authenticate the app. The displayed name and path come from
  `/proc` and can be made to look harmless. A same-user attacker can also
  wait for, or trigger, a legitimate request. *Inferred from the header. The
  verification code in `DBusMgr::serviceInfo` was not read.*
- Users report that the prompt covers only the password and not protected
  custom attributes (KeePassXC issues
  [#9335](https://github.com/keepassxreboot/keepassxc/issues/9335) and
  [#13028](https://github.com/keepassxreboot/keepassxc/issues/13028)). These
  are issue reports, not docs.

**Flatpak / portal:** sandboxed apps do not get the host keyring. The Secret
portal gives each app "a per-application secret", which the app uses to
encrypt its own storage. The backend keeps that secret in the user's keyring
under the app ID
([org.freedesktop.portal.Secret](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html)).
This is the only per-app isolation the Linux desktop offers. It protects
against Flatpak apps, not against host processes such as Emacs or a shell.

**oo7** is a Rust Secret Service *provider*: a daemon, a client library, a
portal backend and PAM integration. It implements the same D-Bus API, so it
inherits the same "any client on the bus" model
([linux-credentials/oo7](https://github.com/linux-credentials/oo7)). The
README makes no claim of per-app access control on the host.

## 3. gpg-agent, kernel keyring, systemd-creds, age/sops

| Store                       | Who can use it while unlocked/cached          |
| --------------------------- | --------------------------------------------- |
| gpg-agent (pass, .gpg)      | Anything that can reach your agent socket     |
| Kernel `@u` user keyring    | Your UID, per the key's permission bits       |
| Kernel session keyring      | Processes that possess it (descendants)       |
| systemd-creds `--user`      | Your user context, or root                    |
| systemd-creds (host/TPM)    | Root only (host key) or this machine's TPM    |
| sops-nix output files       | File owner (you): plain files on tmpfs        |
| age key file                | Whoever can read the file (you)               |
| age-plugin-yubikey, touch   | Your UID **plus a physical touch**            |

- **gpg-agent** caches a passphrase for `--default-cache-ttl` (default 600 s),
  capped by `--max-cache-ttl` (default 7200 s)
  ([Agent Options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)).
  The socket lives in your 0700 runtime dir. Any of your processes that
  connect inside the TTL can decrypt with no prompt. *This follows from the
  socket model. The GnuPG manual does not say it in one sentence.* `pass`
  is one gpg file per entry, and it relies on gpg-agent to "stay
  authenticated for several minutes"
  ([passwordstore.org](https://www.passwordstore.org/)). Entry names are
  file names, so they are probably visible in clear. The site implies this
  but does not say it.
- **A smartcard/YubiKey behind gpg-agent or age** changes the model. The key
  never leaves the token. With a touch policy of `on`, `fixed` or `cached`
  (touch then valid for 15 s), every use needs a physical touch
  ([ykman openpgp](https://docs.yubico.com/software/yubikey/tools/ykman/OpenPGP_Commands.html)).
  age-plugin-yubikey supports `--pin-policy` and `--touch-policy` and keeps
  the PIN cache across decryptions
  ([age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)). Malware
  can still ride on a touch you meant for something else, but it cannot
  bulk-exfiltrate without you noticing the blinking key.
- **Kernel keyring:** permissions are possessor, user, group and other.
  Possession comes from the caller's session, process and thread keyrings and
  what they link to. Keys sit in unswappable kernel memory (except large
  `big_key` payloads, which go to encrypted tmpfs)
  ([keyrings(7)](https://man7.org/linux/man-pages/man7/keyrings.7.html)).
  Session keyrings are not shared between a systemd user service and your
  terminal, which is exactly the Proton Pass bug this repo hit
  (`modules/cosmic-de/default.nix:315-322`). The keyring guards against swap
  and disk, not against same-UID code, which can usually reach `@u`. Defaults
  for the `@u` permission bits are not on that page. *Uncertain.*
- **systemd-creds:** host-key credentials need the root-only
  `/var/lib/systemd/credential.secret`. TPM2 credentials decrypt only on this
  machine. `--user` (systemd 256+) credentials "may only be decrypted from the
  specified user's context"
  ([systemd-creds(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-creds.html)).
  That makes it good for *system services* and adds nothing against same-user
  code.
- **age/sops-nix:** the home module writes decrypted secrets to
  `$XDG_RUNTIME_DIR/secrets.d`, with symlinks under `~/.config/sops-nix`.
  System secrets go to `/run/secrets`
  ([sops-nix README](https://github.com/Mic92/sops-nix)). Each file is
  protected only by its Unix owner and mode.

## 4. Threat model: what FDE covers and what it does not

| Threat                                  | Plain `.authinfo`+FDE | Keyring (PAM) |
| --------------------------------------- | --------------------- | ------------- |
| Laptop stolen powered off / hibernated  | Safe                  | Safe          |
| Laptop stolen while suspended, unlocked | Exposed               | Exposed       |
| Malware / bad package running as you    | Exposed               | Exposed       |
| AI agent, unsandboxed                   | Exposed               | Exposed (bus) |
| AI agent in this repo's sandbox         | Hidden                | Hidden        |
| Accidental `cat`, `grep -r ~`, screen   | Exposed               | Mostly safe   |
| Sync or backup tool copying `$HOME`     | Exposed if a file     | Safe (enc.)   |
| Swap / hibernate image                  | On LUKS: safe         | On LUKS: safe |

- **FDE** protects data at rest: powered off, or hibernated, because ADR 0001
  puts the swapfile on LUKS. During suspend-to-RAM the LUKS key is still in
  memory. *General knowledge, not sourced here.*
- **Same-user code** defeats every software store, because it can simply
  *ask* the keyring over D-Bus or gpg-agent over its socket. Yama does not
  change this. Scope 1 (live here) restricts only `PTRACE_MODE_ATTACH`
  operations to descendants
  ([Yama](https://www.kernel.org/doc/html/latest/admin-guide/LSM/Yama.html),
  [ptrace(2)](https://man7.org/linux/man-pages/man2/ptrace.2.html)).
  That covers `/proc/PID/mem` and `process_vm_readv`
  ([proc_pid_mem(5)](https://man7.org/linux/man-pages/man5/proc_pid_mem.5.html),
  [process_vm_readv(2)](https://man7.org/linux/man-pages/man2/process_vm_readv.2.html)).
  So malware cannot scrape Emacs's heap, but it does not need to.
  `/proc/PID/environ` is a READ-mode check that Yama does not touch, so API
  keys passed as environment variables can be read by any of your processes.
  The MCP servers here get keys that way (`workstation/agents/mcp-servers.nix:189-216`).
  Same-user malware can also rewrite your shell rc or Emacs init and wait.
- **Where a store does beat a file:** accidental exposure (grep, a screen
  share, a pasted path), dotfile sync or backup tools, and anything that reads
  files but cannot talk D-Bus. The repo's agent sandbox is the most important
  of these. It uses a filesystem deny list *and* hides the bus, so both
  routes are covered (`workstation/agents/sandbox.nix:268-305`).

## 5. Options that avoid typing passwords

| Option                         | Typing                 | Gains over today             |
| ------------------------------ | ---------------------- | ---------------------------- |
| Keep sops-nix `.authinfo`      | None                   | (baseline)                   |
| gnome-keyring + `secrets:Login` | None if PAM unlocks   | Not a file; still bus-open   |
| KeePassXC Secret Service       | DB unlock per session  | Per-connection confirm       |
| `.authinfo.gpg` / `pass`       | Once per gpg TTL       | Little, unless key on token  |
| `pass`/age on YubiKey, touch   | Touch (and PIN once)   | Human in the loop per use    |
| sops-nix for system services   | None                   | Root-only files, not you     |

- **Emacs backends:** `auth-sources` accepts `"secrets:Login"`, the symbol
  `default`, or `"secrets:session"`, through `secrets.el` over D-Bus.
  `(auth-source-pass-enable)` adds `pass`, and `~/.authinfo.gpg` goes through
  EasyPG. The manual warns that plaintext `~/.authinfo` "exposes all your
  secrets in clear text" (Emacs `auth` manual, nodes "Help for users",
  "Secret Service API", "The Unix password store"; read from the local
  `auth.info.gz` for Emacs 31.1;
  [online](https://www.gnu.org/software/emacs/manual/html_node/auth/)).
- **PAM keyring unlock on this machine:** this works only with a password
  login. With fingerprint login (see §1), the first keyring use prompts. To
  avoid that, either log in with the password or give the login keyring an
  empty password. An empty password stores it unencrypted on disk, which
  under FDE is about the same as today's file. *The empty-password behaviour
  is general knowledge, not checked against gnome-keyring source.*
- **gpg-agent long TTL:** raising `max-cache-ttl` to a day is effectively a
  file again, but on a socket. It is only worth it with a token-backed key.

## 6. Recommendation for this setup

1. **Keep `.authinfo` from sops-nix for most API keys**: OpenAI, Anthropic,
   OpenRouter, Azure, Kagi, Context7, and the IMAP bridge password. On FDE,
   with the agent sandbox, a keyring would add a D-Bus hop and little else.
   These keys are revocable, often budget-capped, and rotatable from one
   sops file.
2. **Close the probable sandbox gap first.** `credentialPaths` and
   `hiddenSockets` deny `~/.config/sops` and `~/.config/sops-nix`, but no
   entry names `/run/secrets` or `/run/user/1000/secrets.d`
   (`workstation/agents/sandbox.nix:268-305`, nothing in `workstation/agents/`
   matches either path). `/run/secrets/host-age-key` is user-readable and
   decrypts everything. If bubblewrap does not follow the denied
   `~/.config/sops-nix` symlinks to their targets, a sandboxed command could
   read the master key and every secret directly. *Unverified: this report
   did not test it, and the classifier refused even listing `/run/secrets`.*
   Running `agent-sandbox-probe` or a targeted `test -r` would settle it.
   Adding `/run/secrets` and `/run/secrets.d` to `credentialPaths`, and
   `${runtimeDir}/secrets.d` to `credentialPaths` or `hiddenSockets`, is the
   cheap fix.
3. **High-value tokens behind a touch.** Candidates are the GitHub, GitLab
   and Codeberg PATs with write scope (`authinfo/github`, `github_pat`, which
   also feeds Nix and the GitHub MCP server) and the SSH keys. Store these
   with `age-plugin-yubikey` (touch `cached`) or a gpg key on the YubiKey for
   `pass` / `.authinfo.gpg`, and put that source *first* in `auth-sources`.
   The cost is one touch per use, up to 15 s apart. The Nix `access-tokens`
   and MCP env-var paths would still need a file, so the practical gain is
   to narrow token *scopes*, not to move them.
4. **Skip gnome-keyring for `.authinfo`.** It is already running for Proton
   Pass, but fingerprint login leaves it locked. When unlocked, it is open to
   every same-user process, which is the same exposure the file has.
5. **Optional hardening that costs nothing:** turn `gptel-api-key` into a
   lambda so the key is fetched per request, not held as a string. This is
   minor, because Emacs's heap is already Yama-protected from other
   processes.

## Sources

Primary:

- freedesktop Secret Service spec:
  [ToC](https://specifications.freedesktop.org/secret-service/latest/),
  [Transfer of Secrets](https://specifications.freedesktop.org/secret-service/latest/transfer-secrets.html),
  [Notes for Implementors](https://specifications.freedesktop.org/secret-service/latest/ch11.html)
- [GNOME Keyring Security Philosophy](https://wiki.gnome.org/Projects/GnomeKeyring/SecurityPhilosophy)
- gnome-keyring
  [`pam/gkr-pam-module.c`](https://github.com/GNOME/gnome-keyring/blob/master/pam/gkr-pam-module.c)
- KeePassXC
  [`src/fdosecrets/dbus/DBusClient.h`](https://github.com/keepassxreboot/keepassxc/blob/develop/src/fdosecrets/dbus/DBusClient.h)
- [xdg-desktop-portal Secret portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html)
- [oo7 README](https://github.com/linux-credentials/oo7)
- [GnuPG Agent Options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- [passwordstore.org](https://www.passwordstore.org/)
- [keyrings(7)](https://man7.org/linux/man-pages/man7/keyrings.7.html),
  [ptrace(2)](https://man7.org/linux/man-pages/man2/ptrace.2.html),
  [proc_pid_mem(5)](https://man7.org/linux/man-pages/man5/proc_pid_mem.5.html),
  [process_vm_readv(2)](https://man7.org/linux/man-pages/man2/process_vm_readv.2.html)
- [Kernel Yama docs](https://www.kernel.org/doc/html/latest/admin-guide/LSM/Yama.html)
- [systemd-creds(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-creds.html)
- [sops-nix README](https://github.com/Mic92/sops-nix); module source
  `modules/home-manager/{sops,templates}.nix` from the locked input
- [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey),
  [ykman OpenPGP](https://docs.yubico.com/software/yubikey/tools/ykman/OpenPGP_Commands.html)
- Emacs `auth` manual (local `auth.info.gz`, Emacs 31.1)
- nixpkgs `nixos/modules/services/desktops/gnome/gnome-keyring.nix`,
  `.../display-managers/cosmic-greeter.nix`; live `/etc/pam.d/{login,greetd}`

Secondary (flagged in the text): KeePassXC GitHub issues #9335 and #13028,
and general knowledge on macOS Keychain ACLs, suspend-to-RAM key retention
and gnome-keyring empty-password storage.
