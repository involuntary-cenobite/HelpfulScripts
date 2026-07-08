# bootstrap.sh

System setup script for either **Fedora** or **Ubuntu/Debian** distros

Run on a fresh machine and it installs tools, sets up Zsh with Oh My Zsh, configures a custom prompt, and verifies everything at the end.

## Usage

```bash
 ./bootstrap.sh
```

Requires `sudo` for package installation and system changes. Safe to re-run — every installer checks whether the tool already exists and skips it if so.

## What it does

### 1. Prerequisites

Installs `curl`, `git`, and `unzip` via the system package manager before anything else runs.

### 2. Shell setup

| Step | What happens |
|------|-------------|
| Install Zsh | Installed via `apt`/`dnf` if not already present |
| Set as default | Runs `usermod --shell` to make Zsh the login shell |
| Oh My Zsh | Installed non-interactively (`RUNZSH=no CHSH=no`) |
| Plugins | Clones `zsh-autosuggestions` and `zsh-syntax-highlighting` into `$ZSH_CUSTOM/plugins` |
| `.zshrc` | Appends a `shell` block (PATH, `.aliases` source) and a `prompt` block and won't duplicate on subsequent runs, guarded by `# BEGIN bootstrap:` markers |

### 3. Package manager packages

Installed via `apt-get` or `dnf` in a single batch call:

- `ripgrep`
- `fzf`
- `htop`
- `jq`
- `tree`

### 4. Custom installers

Each runs only if the binary is not already on `PATH`.

| Tool | Install method |
|------|---------------|
| `bat` | Package manager; creates `~/.local/bin/bat → batcat` symlink on Debian |
| `fd` | Package manager (`fd-find` on Debian); creates `~/.local/bin/fd → fdfind` symlink |
| `btop` | Package manager with GitHub binary fallback for older Debian/Ubuntu |
| `eza` | Package manager; adds the [gierens apt repo](https://github.com/eza-community/eza) on Debian |
| `terraform` | HashiCorp apt/dnf repo |
| `minikube` | Binary download from `storage.googleapis.com` |
| `docker` | Official Docker apt/dnf repo; adds user to `docker` group; enables service via systemd |
| `kubectl` | Binary download pinned to the current stable release from `dl.k8s.io` |
| `k9s` | GitHub release binary (latest tag) |
| `lazygit` | GitHub release binary (latest tag) |
| `lazydocker` | GitHub release binary (latest tag) |

### 5. Fonts

Downloads the latest **CaskaydiaCove Nerd Font Mono** from the [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) releases and installs it to `~/.local/share/fonts`, then runs `fc-cache`.

### 6. Verification

After `main` returns, `verify_bootstrap` runs a suite of checks (commands, directories, `.zshrc` markers, fonts) and prints a pass/fail summary.

## Customisation

All user-facing configuration is at the top of the script.

**Add a standard package** — append to `PACKAGES`:

```bash
PACKAGES=(
    ripgrep
    fzf
    my-new-package           # same name on both distros
    "apt-name:dnf-name"      # different name per distro
)
```

**Add a custom installer** — write a function following the template in the `Custom Installers` section, then register it in `CUSTOM_INSTALLERS`:

```bash
CUSTOM_INSTALLERS=(
    ...
    install_mytool
)

install_mytool() {
    begin_install mytool || return 0
    case "$DISTRO" in
        debian) pkg_install mytool ;;
        fedora) pkg_install mytool ;;
    esac
}
```

**Remove a tool** — delete (or comment out) its entry from `CUSTOM_INSTALLERS` or `PACKAGES`.

## Helper functions

| Function | Purpose |
|----------|---------|
| `begin_install <binary>` | Skips with an info message if the binary already exists; returns 1 to skip |
| `github_install <binary> <url>` | Downloads a `.tar.gz`, extracts a single binary, installs to `/usr/local/bin` |
| `github_latest_tag <owner/repo> [strip-v]` | Returns the latest GitHub release tag; optionally strips the leading `v` |
| `install_binary <name> <url>` | Downloads a single binary directly and installs to `/usr/local/bin` |
| `add_apt_repo <name> <key-url> <repo-line>` | Adds a signed apt repo; no-op if the `.list` file already exists |
| `pkg_install <...>` | Delegates to `apt-get install -y` or `dnf install -y` |

## Supported distros

Detected via `/etc/os-release`. Supported `ID` values: `ubuntu`, `debian`, `linuxmint`, `pop`, `fedora`. Derivatives with `ID_LIKE` containing `ubuntu`, `debian`, `fedora`, `rhel`, or `centos` are also handled.
