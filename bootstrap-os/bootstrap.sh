#!/usr/bin/env bash
# Bootstrap script — Fedora & Ubuntu/Debian

set -euo pipefail

# --- CONFIGURATION — edit this section to customise the bootstrap ---

# Packages installed directly via the system package manager (apt/dnf).
#   Simple entry:  "package"            same name on both distros
#   Split entry:   "apt-name:dnf-name"  different name per distro
#
# For packages needing a custom repo or post-install steps, add a
# function to the "Custom Installers" section and list it below.
PACKAGES=(
    ripgrep
    fzf
    htop
    jq
    tree
)

# Custom installer functions — defined in the "Custom Installers" section.
# Add/remove entries here to control what runs.
CUSTOM_INSTALLERS=(
    install_bat        # needs a batcat→bat symlink on Ubuntu/Debian
    install_fd         # needs a fdfind→fd symlink on Ubuntu/Debian
    install_btop       # not in apt repos pre-22.04; falls back to GitHub binary
    install_eza        # needs a custom apt repo on Ubuntu/Debian
    install_terraform  # needs the HashiCorp repo
    install_minikube   # binary download; not in standard repos
    install_docker      # needs the Docker repo + docker group membership
    install_kubectl     # binary download; versioned repo URLs make apt/dnf awkward
    install_k9s         # binary download from GitHub releases
    install_lazygit     # binary download from GitHub releases
    install_lazydocker  # binary download from GitHub releases
    install_archey      # .deb/.rpm from GitHub releases
)

# --- Helpers ---

info() { printf '\033[0;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

# Print skip/installing message; returns 1 (skip) if the binary already exists.
begin_install() {
    command_exists "$1" && { info "$1 already installed, skipping."; return 1; }
    info "Installing $1..."
    return 0
}

# --- Distro detection ---

detect_distro() {
    [ -f /etc/os-release ] || die "/etc/os-release not found — cannot detect distro"
    # shellcheck source=/dev/null
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian|linuxmint|pop) echo "debian" ;;
        fedora)                       echo "fedora" ;;
        *)
            case "${ID_LIKE:-}" in
                *ubuntu*|*debian*)        echo "debian" ;;
                *fedora*|*rhel*|*centos*) echo "fedora" ;;
                *) die "Unsupported distro: ${ID:-unknown}" ;;
            esac
            ;;
    esac
}

DISTRO=$(detect_distro)
info "Detected distro family: $DISTRO"

# --- Package manager ---

pkg_update() {
    case "$DISTRO" in
        debian) sudo apt-get update -qq ;;
        fedora) sudo dnf check-update -q || true ;;  # exits 100 when updates exist
    esac
}

pkg_install() {
    case "$DISTRO" in
        debian) sudo apt-get install -y "$@" ;;
        fedora) sudo dnf install -y "$@" ;;
    esac
}

# Extract a single binary from a tar.gz URL and install it to /usr/local/bin.
github_install() {
    local binary="$1" url="$2" tmpdir
    tmpdir=$(mktemp -d)
    curl -fsSL "$url" -o "$tmpdir/archive.tar.gz"
    tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir" "$binary"
    sudo install "$tmpdir/$binary" "/usr/local/bin/$binary"
    rm -rf "$tmpdir"
}

# Fetch the latest release tag for a GitHub repo. Pass "strip-v" to drop a leading "v".
github_latest_tag() {
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ "${2:-}" == "strip-v" ]] && tag="${tag#v}"
    echo "$tag"
}

# Download a single binary from a URL and install it to /usr/local/bin.
install_binary() {
    local name="$1" url="$2" tmpfile
    tmpfile=$(mktemp)
    curl -fsSL "$url" -o "$tmpfile"
    sudo install "$tmpfile" "/usr/local/bin/$name"
    rm -f "$tmpfile"
}

# Add an apt repo with a GPG key. No-op if the list file already exists.
add_apt_repo() {
    local name="$1" key_url="$2" repo_line="$3"
    local list_file="/etc/apt/sources.list.d/${name}.list"
    [ -f "$list_file" ] && return 0
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "/etc/apt/keyrings/${name}.gpg"
    echo "$repo_line" | sudo tee "$list_file" > /dev/null
    sudo chmod 644 "/etc/apt/keyrings/${name}.gpg" "$list_file"
    sudo apt-get update -qq
}

# --- Core setup ---

install_prerequisites() {
    info "Installing prerequisites..."
    pkg_install curl git unzip
}

install_zsh() {
    command_exists zsh || pkg_install zsh
    local zsh_path; zsh_path=$(command -v zsh)
    if [ "$SHELL" != "$zsh_path" ]; then
        info "Setting zsh as default shell..."
        sudo usermod --shell "$zsh_path" "$USER"
        info "Default shell changed (takes effect on next login)."
    fi
}

install_ohmyzsh() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh..."
        RUNZSH=no CHSH=no \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    [ -d "$zsh_custom/plugins/zsh-autosuggestions" ] || \
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "$zsh_custom/plugins/zsh-autosuggestions"

    [ -d "$zsh_custom/plugins/zsh-syntax-highlighting" ] || \
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "$zsh_custom/plugins/zsh-syntax-highlighting"

    local zshrc="$HOME/.zshrc"
    if [ -f "$zshrc" ]; then
        if grep -q '^plugins=(' "$zshrc"; then
            # Handle both single-line `plugins=(a b c)` and multi-line `plugins=(\n a\n b\n)` forms
            sed -i -E ':a; /^plugins=\(/ { N; /\)/!ba; s/^plugins=\([^)]*\)/plugins=(git-prompt zsh-autosuggestions zsh-syntax-highlighting)/; }' "$zshrc"
        fi
        if grep -q '^ZSH_THEME=' "$zshrc"; then
            sed -i 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
        fi
    fi
}

configure_prompt() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || { warn "~/.zshrc not found — creating it"; touch "$zshrc"; }
    if grep -q '# BEGIN bootstrap: prompt' "$zshrc"; then info "Prompt already configured, skipping."; return; fi

    info "Configuring prompt..."
    cat >> "$zshrc" << 'ZSHRC_PROMPT'

# BEGIN bootstrap: prompt
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

case "$TERM" in
    xterm-color|*-256color) color_prompt=yes ;;
esac

force_color_prompt=yes
if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

_git_prompt_segment() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  echo "%F{%(#.blue.green)}[%F{reset}git:(%F{red}$branch%F{reset})%F{%(#.blue.green)}]"
}

if [ "$color_prompt" = yes ]; then
    PROMPT=$'%F{%(#.blue.green)}╭──${debian_chroot:+($debian_chroot)──}(%B%F{%(#.red.blue)}%n%(#.💀 . )%m%b%F{%(#.blue.green)})-$(_git_prompt_segment)[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n╰─>%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '
    RPROMPT=$'%(?.. %? %F{red}%B⨯%b%F{reset})%(1j. %j %F{yellow}%B⚙%b%F{reset}.)'
else
    PROMPT='${debian_chroot:+($debian_chroot)}%n@%m:%~%# '
fi
unset color_prompt force_color_prompt

case "$TERM" in
xterm*|rxvt*)
    TERM_TITLE=$'\e]0;${debian_chroot:+($debian_chroot)}%n@%m: %~\a'
    ;;
esac

new_line_before_prompt=yes
precmd() {
    print -Pnr -- "$TERM_TITLE"
    if [ "$new_line_before_prompt" = yes ]; then
        if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
            _NEW_LINE_BEFORE_PROMPT=1
        else
            print ""
        fi
    fi
}
# END bootstrap: prompt
ZSHRC_PROMPT
}

configure_zshrc() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || { warn "~/.zshrc not found — creating it"; touch "$zshrc"; }
    if grep -q '# BEGIN bootstrap: shell' "$zshrc"; then info "Shell config already applied, skipping."; return; fi

    info "Configuring PATH and aliases in ~/.zshrc..."
    cat >> "$zshrc" << 'ZSHRC_SHELL'

# BEGIN bootstrap: shell
typeset -U path
path=(/opt "$HOME/.local/bin" "$HOME/.local/share/flatpak/exports/bin" /snap/bin $path)

[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

(( $+commands[archey] )) && archey
# END bootstrap: shell
ZSHRC_SHELL

    if [ ! -f "$HOME/.aliases" ]; then
        touch "$HOME/.aliases"
        info "Created empty ~/.aliases"
    fi
}

# --- Package list installer ---

install_packages() {
    [ ${#PACKAGES[@]} -eq 0 ] && return
    local list=() pkg
    for pkg in "${PACKAGES[@]}"; do
        if [[ "$pkg" == *:* ]]; then
            [[ "$DISTRO" == "debian" ]] && list+=("${pkg%%:*}") || list+=("${pkg##*:}")
        else
            list+=("$pkg")
        fi
    done
    info "Installing packages: ${list[*]}"
    pkg_install "${list[@]}"
}

# --- Custom Installers ---
# Use this section for tools that need a custom repo, a binary download,
# or post-install steps.  Register each function in CUSTOM_INSTALLERS above.
#
# Template:
#
#   install_mytool() {
#       command_exists mytool && { info "mytool already installed, skipping."; return; }
#       info "Installing mytool..."
#       case "$DISTRO" in
#           debian)
#               add_apt_repo "mytool" \
#                   "https://example.com/key.asc" \
#                   "deb [signed-by=/etc/apt/keyrings/mytool.gpg] https://apt.example.com stable main"
#               pkg_install mytool
#               ;;
#           fedora) pkg_install mytool ;;
#       esac
#   }

install_btop() {
    begin_install btop || return 0
    # Try the package manager first; fall back to the static GitHub binary.
    if ! pkg_install btop 2>/dev/null; then
        warn "btop not in package repos — installing from GitHub releases..."
        local version; version=$(github_latest_tag aristocratos/btop strip-v)
        local tmpdir; tmpdir=$(mktemp -d)
        curl -fsSL \
            "https://github.com/aristocratos/btop/releases/download/v${version}/btop-x86_64-linux-musl.tbz" \
            -o "$tmpdir/btop.tbz"
        tar -xjf "$tmpdir/btop.tbz" -C "$tmpdir"
        sudo make -C "$tmpdir/btop" install PREFIX=/usr/local
        rm -rf "$tmpdir"
    fi
}

install_bat() {
    begin_install bat || return 0
    command_exists batcat || pkg_install bat
    # Ubuntu/Debian ships the binary as 'batcat'; shim it to 'bat'
    if command_exists batcat; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    fi
}

install_fd() {
    begin_install fd || return 0
    case "$DISTRO" in
        debian) pkg_install fd-find
                # Ubuntu/Debian ships the binary as 'fdfind'; shim it to 'fd'
                if command_exists fdfind; then
                    mkdir -p "$HOME/.local/bin"
                    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
                fi ;;
        fedora) pkg_install fd ;;
    esac
}

install_eza() {
    begin_install eza || return 0
    case "$DISTRO" in
        debian)
            pkg_install gpg
            add_apt_repo "gierens" \
                "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" \
                "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main"
            pkg_install eza
            ;;
        fedora) pkg_install eza ;;
    esac
}

install_terraform() {
    begin_install terraform || return 0
    case "$DISTRO" in
        debian)
            pkg_install gpg
            add_apt_repo "hashicorp" \
                "https://apt.releases.hashicorp.com/gpg" \
                "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main"
            pkg_install terraform
            ;;
        fedora)
            if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
                sudo curl -fsSL https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
                    -o /etc/yum.repos.d/hashicorp.repo
            fi
            pkg_install terraform
            ;;
    esac
}

install_minikube() {
    begin_install minikube || return 0
    if ! pkg_install minikube 2>/dev/null; then
        warn "minikube not in package repos — installing binary from Google..."
        install_binary minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
    fi
}

install_docker() {
    begin_install docker || return 0
    case "$DISTRO" in
        debian)
            pkg_install gpg
            local arch codename docker_os
            arch=$(dpkg --print-architecture)
            codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
            # Debian uses its own repo; all derivatives (Ubuntu, Pop!_OS, Mint...) use ubuntu's
            [[ "$(. /etc/os-release && echo "$ID")" == "debian" ]] && docker_os=debian || docker_os=ubuntu
            add_apt_repo "docker" \
                "https://download.docker.com/linux/${docker_os}/gpg" \
                "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${docker_os} ${codename} stable"
            pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora)
            if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
                sudo curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
                    -o /etc/yum.repos.d/docker-ce.repo
            fi
            pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
    esac
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker || warn "Could not enable docker service (systemd may not be running — re-run after enabling systemd)"
}

install_kubectl() {
    begin_install kubectl || return 0
    if ! pkg_install kubectl 2>/dev/null; then
        warn "kubectl not in package repos — installing binary from dl.k8s.io..."
        local version; version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
        install_binary kubectl "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"
    fi
}

install_k9s() {
    begin_install k9s || return 0
    if ! pkg_install k9s 2>/dev/null; then
        warn "k9s not in package repos — installing from GitHub releases..."
        local version; version=$(github_latest_tag derailed/k9s)
        github_install k9s \
            "https://github.com/derailed/k9s/releases/download/${version}/k9s_Linux_amd64.tar.gz"
    fi
}

install_lazygit() {
    begin_install lazygit || return 0
    if ! pkg_install lazygit 2>/dev/null; then
        warn "lazygit not in package repos — installing from GitHub releases..."
        local version; version=$(github_latest_tag jesseduffield/lazygit strip-v)
        github_install lazygit \
            "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_x86_64.tar.gz"
    fi
}

install_lazydocker() {
    begin_install lazydocker || return 0
    if ! pkg_install lazydocker 2>/dev/null; then
        warn "lazydocker not in package repos — installing from GitHub releases..."
        local version; version=$(github_latest_tag jesseduffield/lazydocker strip-v)
        github_install lazydocker \
            "https://github.com/jesseduffield/lazydocker/releases/download/v${version}/lazydocker_${version}_Linux_x86_64.tar.gz"
    fi
}

install_archey() {
    begin_install archey || return 0
    local version; version=$(github_latest_tag HorlogeSkynet/archey4 strip-v)
    local tmpdir; tmpdir=$(mktemp -d)
    case "$DISTRO" in
        debian)
            curl -fsSL "https://github.com/HorlogeSkynet/archey4/releases/download/v${version}/archey4_${version}-1_all.deb" \
                -o "$tmpdir/archey.deb"
            sudo apt-get install -y "$tmpdir/archey.deb"
            ;;
        fedora)
            curl -fsSL "https://github.com/HorlogeSkynet/archey4/releases/download/v${version}/archey4-${version}-1.noarch.rpm" \
                -o "$tmpdir/archey.rpm"
            sudo dnf install -y "$tmpdir/archey.rpm"
            ;;
    esac
    rm -rf "$tmpdir"
}

# --- Fonts ---

install_caskaydia_font() {
    command_exists fc-list || pkg_install fontconfig
    if fc-list | grep -qi "CaskaydiaCove"; then
        info "CaskaydiaCove Nerd Font already installed, skipping."
        return 0
    fi

    info "Fetching latest Nerd Fonts release tag..."
    local version; version=$(github_latest_tag ryanoasis/nerd-fonts)
    [ -n "$version" ] || die "Failed to fetch Nerd Fonts release version"

    info "Downloading CascadiaCode.zip (${version})..."
    local tmpdir; tmpdir=$(mktemp -d)

    curl -fsSL \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/CascadiaCode.zip" \
        -o "$tmpdir/CascadiaCode.zip"

    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    # Nerd Fonts v3.x uses "NerdFontMono" suffix; v2.x used "NFM"
    unzip -jo "$tmpdir/CascadiaCode.zip" "*CaskaydiaCoveNerdFontMono*" "*CaskaydiaCoveNFM*" -d "$font_dir" 2>/dev/null || \
    unzip -jo "$tmpdir/CascadiaCode.zip" "*.ttf" -d "$font_dir"
    fc-cache -f "$font_dir"
    rm -rf "$tmpdir"
    info "CaskaydiaCove Nerd Font Mono installed to $font_dir."
}

# --- Main ---

main() {
    info "Starting bootstrap (distro: $DISTRO)..."

    pkg_update
    install_prerequisites
    install_zsh
    install_ohmyzsh
    configure_zshrc
    configure_prompt
    install_packages

    local failed=()
    for fn in "${CUSTOM_INSTALLERS[@]}"; do
        "$fn" || { warn "$fn failed — skipping (see output above for details)"; failed+=("$fn"); }
    done
    [ ${#failed[@]} -gt 0 ] && warn "The following installers failed: ${failed[*]}"

    install_caskaydia_font

    echo
    info "Bootstrap complete!"
    info "Run 'exec zsh' now, or open a new terminal, to apply all shell changes."
    info "(\$SHELL will still show your old shell until you do — this is expected.)"
}

main "$@"

# --- TEMPORARY VERIFICATION — remove after confirming on Fedora + Debian ---

verify_bootstrap() {
    local pass=0 fail=0

    check() {
        local label="$1" result="$2"
        if [[ "$result" == ok* ]]; then
            if [ "$result" = "ok" ]; then
                printf '  \033[0;32m✓\033[0m %s\n' "$label"
            else
                printf '  \033[0;32m✓\033[0m %s  \033[0;33m%s\033[0m\n' "$label" "${result#ok }"
            fi
            (( ++pass )) || true
        else
            printf '  \033[0;31m✗\033[0m %s — %s\n' "$label" "$result"
            (( ++fail )) || true
        fi
    }

    check_cmd() { command_exists "$1" && echo "ok" || echo "not found"; }
    check_file() { [ -e "$1" ] && echo "ok" || echo "missing: $1"; }
    check_dir()  { [ -d "$1" ] && echo "ok" || echo "missing: $1"; }
    check_grep() { grep -q "$2" "$1" 2>/dev/null && echo "ok" || echo "not found in $1"; }
    # Flags "from git" for binaries in /usr/local/bin (github_install/install_binary target),
    # plain "ok" for anything installed by the package manager (typically /usr/bin).
    check_source() {
        local path; path=$(command -v "$1" 2>/dev/null)
        if [ -z "$path" ]; then
            echo "not found"
        elif [[ "$path" == /usr/local/bin/* ]]; then
            echo "ok (from git)"
        else
            echo "ok"
        fi
    }

    echo
    printf '\033[1m=== Bootstrap Verification ===\033[0m\n'

    echo
    printf '\033[1m[Packages]\033[0m\n'
    check "ripgrep (rg)"   "$(check_cmd rg)"
    check "fzf"            "$(check_cmd fzf)"
    check "htop"           "$(check_cmd htop)"
    check "btop"           "$(check_source btop)"
    check "jq"             "$(check_cmd jq)"
    check "tree"           "$(check_cmd tree)"
    check "fd"             "$(command_exists fd || command_exists fdfind || [ -L "$HOME/.local/bin/fd" ] && echo ok || echo 'not found')"

    echo
    printf '\033[1m[Custom installs]\033[0m\n'
    check "bat"            "$(command_exists bat || command_exists batcat || [ -L "$HOME/.local/bin/bat" ] && echo ok || echo 'not found')"
    check "eza"            "$(check_cmd eza)"
    check "terraform"      "$(check_cmd terraform)"
    check "minikube"       "$(check_source minikube)"
    check "docker"         "$(check_cmd docker)"
    check "kubectl"        "$(check_source kubectl)"
    check "k9s"            "$(check_source k9s)"
    check "lazygit"        "$(check_source lazygit)"
    check "lazydocker"     "$(check_source lazydocker)"
    check "archey"         "$(check_cmd archey)"

    echo
    printf '\033[1m[Shell]\033[0m\n'
    check "zsh installed"         "$(check_cmd zsh)"
    check "zsh is default shell"  "$([ "$SHELL" = "$(command -v zsh 2>/dev/null)" ] && echo ok || echo "SHELL=$SHELL (restart terminal to apply)")"
    check "oh-my-zsh dir"         "$(check_dir "$HOME/.oh-my-zsh")"
    check "zsh-autosuggestions"   "$(check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions")"
    check "zsh-syntax-highlight"  "$(check_dir "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting")"
    check ".zshrc shell block"    "$(check_grep "$HOME/.zshrc" '# BEGIN bootstrap: shell')"
    check ".zshrc prompt block"   "$(check_grep "$HOME/.zshrc" '# BEGIN bootstrap: prompt')"

    echo
    printf '\033[1m[Fonts]\033[0m\n'
    check "fontconfig (fc-list)"  "$(check_cmd fc-list)"
    if command_exists fc-list; then
        check "CaskaydiaCove font" "$(ls "$HOME/.local/share/fonts"/CaskaydiaCove*.ttf 2>/dev/null | grep -q . && echo ok || echo 'no .ttf files in ~/.local/share/fonts')"
    else
        check "CaskaydiaCove font" "skipped (fc-list unavailable)"
    fi

    echo
    if [ $fail -eq 0 ]; then
        printf '\033[0;32mAll %d checks passed.\033[0m\n' "$pass"
    else
        printf '\033[0;31m%d check(s) failed, %d passed.\033[0m\n' "$fail" "$pass"
    fi
    echo
    printf '\033[0;33mNote:\033[0m run '\''exec zsh'\'' or open a new terminal to apply all shell changes.\n'
    echo
}

verify_bootstrap
