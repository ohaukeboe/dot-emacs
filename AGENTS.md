# NixOS & Home Manager Configuration - Agent Guide

This is a personal NixOS and Home Manager configuration using flakes with literate Emacs config in org-mode.

## Build & Deploy Commands

### Home Manager (Standalone)
```bash
# Apply home-manager configuration (non-NixOS systems)
home-manager switch --flake .#default --impure -b backup

# Apply for specific system
home-manager switch --flake .#oskar@x86_64-linux --impure -b backup
```

### NixOS System
```bash
# Deploy NixOS configuration
sudo nixos-rebuild switch --flake .#<hostname>

# Available hostnames: x13-laptop, work-laptop, desktop
sudo nixos-rebuild switch --flake .#x13-laptop
```

### Testing & Validation
```bash
# Check formatting (treefmt: nixfmt, shfmt, toml-sort)
nix fmt

# Verify formatting without applying
nix flake check

# Build without activating (test before deploying)
nix build .#homeConfigurations.default.activationPackage

# Show all flake outputs
nix flake show
```

## Project Structure

```
.
├── flake.nix              # Main flake entry point
├── lib/                   # Helper functions (mkHomeConfiguration, mkNixosConfiguration)
├── machines/              # Hardware-specific configs (desktop, x13-laptop, work-laptop)
│   └── machines.nix       # Declarative machine definitions
├── common/                # Shared modules
│   ├── caches.nix         # Nix binary cache configuration
│   ├── unfree-predicates.nix  # Allowed unfree packages
│   ├── options.nix        # Custom options (user.username, system.audio.allowedSampleRates)
│   └── system/            # NixOS system defaults
├── modules/               # Optional feature modules
│   ├── gaming/            # Gaming setup (Steam, gamescope, Lutris)
│   ├── cosmic-de/         # COSMIC desktop environment
│   ├── secure-boot/       # Lanzaboote secure boot
│   └── sshd/              # SSH daemon configuration
└── workstation/           # Home Manager user configuration
    ├── home.nix           # Main home-manager config
    ├── emacs/             # Literate Emacs configuration
    │   ├── config.org     # Org-mode literate config (SOURCE OF TRUTH)
    │   └── init.el        # Bootstrap loader
    ├── dotfiles/          # Shell configs (fish, starship, etc.)
    └── ssh.nix            # SSH client configuration
```

## Code Style Guidelines

### Nix Files

#### Formatting
- **Indentation**: 2 spaces (enforced by `nixfmt`)
- **Line length**: Reasonable (nixfmt handles wrapping)
- **Strings**: Use double quotes `"string"` for strings
- **Multi-line strings**: Use `''` for heredocs and shell scripts

#### Function Arguments
```nix
# Multi-line argument set (opening brace on same line)
{
  config,
  lib,
  pkgs,
  ...
}:
```

#### Module Structure
```nix
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.feature-name;
in
{
  options.modules.feature-name = {
    enable = mkEnableOption "Feature description";

    someOption = mkOption {
      type = types.str;
      default = "default-value";
      description = "Clear description of what this does";
      example = "example-value";
    };
  };

  config = mkIf cfg.enable {
    # Implementation here
  };
}
```

#### Imports and Dependencies
- List imports in `imports = [ ... ]` array
- Import paths relative to file location
- Prefer explicit inputs over global references
- Use `inherit` to avoid repetition

#### Naming Conventions
- **Options**: `camelCase` for option names (e.g., `allowedSampleRates`)
- **Modules**: `kebab-case` for module directories (e.g., `cosmic-de/`, `secure-boot/`)
- **Variables**: `camelCase` in let bindings (e.g., `cfg`, `homeManagerNixosModule`)
- **Files**: `kebab-case.nix` (e.g., `unfree-predicates.nix`)

#### Comments
```nix
# Single-line comments for brief explanations

# Multi-line comments for complex logic
# explaining why something is done a certain way
```

#### Shell Scripts in Nix
```nix
pkgs.writeShellScriptBin "script-name" ''
  # Use full package paths for portability
  resolution=$(${pkgs.wlr-randr}/bin/wlr-randr | \
    ${pkgs.gnugrep}/bin/grep 'current)' | \
    ${pkgs.coreutils}/bin/head -1)
''
```

### Emacs Lisp

#### Emacs Package Management
- Packages managed through `emacsWithPackagesFromUsePackage` in Nix
- List packages in `extraEmacsPackages` in `workstation/home.nix`
- Use `use-package` declarations in `config.org`

### Commit Message Convention

Follow Conventional Commits format:

```
<type>[optional scope]: <description>

[optional body]
```

**Types**:
- `feat`: New feature or capability
- `fix`: Bug fix
- `refactor`: Code restructuring without changing behavior
- `chore`: Maintenance (dependency updates, etc.)
- `docs`: Documentation changes
- `build`: Build system or dependency changes
- `perf`: Performance improvements
- `style`: Code style/formatting changes

**Examples**:
```
feat(gaming): Add Steam autostart configuration
fix(audio): Configure PipeWire with 192kHz sample rate
refactor: Restructure machine configurations into directories
chore: Update flake dependencies
docs(emacs): Add custom conventional commit prompt for gptel-magit
build: Update flake dependencies and fix platform references
```

## Error Handling & Best Practices

### When Making Changes

1. **Test before deploying**: Use `nix build` to verify changes compile
2. **Format before committing**: Run `nix fmt`
3. **Check flake validity**: Run `nix flake check`
4. **Use module system**: Create optional modules in `modules/` for features
5. **Avoid hardcoding**: Use `config.user.username` instead of `"oskar"`

### Common Patterns

#### Adding a New Module
1. Create `modules/feature-name/default.nix`
2. Use `mkEnableOption` for the enable option
3. Wrap all config in `mkIf cfg.enable { ... }`
4. Import automatically via `modules/default.nix`

#### Adding a New Machine
1. Create `machines/hostname/` directory
2. Add `default.nix`, `hardware-configuration.nix`, optional `config.nix`
3. Register in `machines/machines.nix`

#### Managing Secrets
- Use git-crypt for `secrets/secrets.json`
- Never commit unencrypted secrets
- Reference via `secrets` parameter passed to configurations

## Tools & Resources

- **Package search**: https://search.nixos.org/packages
- **Home Manager options**: https://home-manager-options.extranix.com/
- **Version history**: https://www.nixhub.io/
- **MCP servers**: https://smithery.ai/

## Notes for Agents

- This repo started as Emacs config (hence name "dot-emacs")
- Primary user configuration in `workstation/home.nix`
- NixOS configs support multi-platform (x86_64-linux, aarch64-linux, aarch64-darwin)
- Always run `nix fmt` before committing Nix files
- When editing Emacs config, edit `config.org`, not generated `.el` files
