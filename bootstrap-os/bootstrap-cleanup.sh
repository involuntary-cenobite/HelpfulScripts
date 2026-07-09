#!/usr/bin/env bash
# Cleanup script — removes everything installed by bootstrap.sh
# Run this to reset the system before re-testing bootstrap from scratch.

set -euo pipefail

info() { printf '\033[0;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2; }

command_exists() { command -v "$1" &>/dev/null; }

# --- Distro detection (mirrors bootstrap.sh) ---

detect_distro() {
    [ -f /etc/os-release ] || { warn "Cannot detect distro"; exit 1; }
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian|linuxmint|pop) echo "debian" ;;
        fedora)                       echo "fedora" ;;
        *)
            case "${ID_LIKE:-}" in
                *ubuntu*|*debian*)        echo "debian" ;;
                *fedora*|*rhel*|*centos*) echo "fedora" ;;
                *) warn "Unsupported distro: ${ID:-unknown}"; exit 1 ;;
            esac
            ;;
    esac
}

DISTRO=$(detect_distro)
info "Detected distro family: $DISTRO"

pkg_remove() {
    case "$DISTRO" in
        debian) sudo apt-get remove -y --autoremove "$@" 2>/dev/null || true ;;
        fedora) sudo dnf remove -y "$@" 2>/dev/null || true ;;
    esac
}

# --- Packages ---

remove_packages() {
    info "Removing packages..."
    case "$DISTRO" in
        debian) pkg_remove ripgrep fzf htop jq tree bat fd-find btop eza terraform archey4 ;;
        fedora) pkg_remove ripgrep fzf htop jq tree bat fd btop eza terraform archey4 ;;
    esac
}

# --- Binaries in /usr/local/bin ---

remove_binaries() {
    info "Removing binaries from /usr/local/bin..."
    for bin in minikube kubectl k9s lazygit lazydocker btop; do
        if [ -f "/usr/local/bin/$bin" ]; then
            sudo rm -f "/usr/local/bin/$bin"
            info "  removed /usr/local/bin/$bin"
        fi
    done
}

# --- Symlinks in ~/.local/bin ---

remove_symlinks() {
    info "Removing symlinks from ~/.local/bin..."
    for link in bat fd; do
        if [ -L "$HOME/.local/bin/$link" ]; then
            rm -f "$HOME/.local/bin/$link"
            info "  removed ~/.local/bin/$link"
        fi
    done
}

# --- Docker ---

remove_docker() {
    info "Removing Docker..."
    case "$DISTRO" in
        debian) pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
        fedora) pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
    esac
    sudo gpasswd -d "$USER" docker 2>/dev/null || true
}

# --- Added repos ---

remove_repos() {
    info "Removing added package repos..."
    case "$DISTRO" in
        debian)
            sudo rm -f /etc/apt/sources.list.d/hashicorp.list
            sudo rm -f /etc/apt/sources.list.d/gierens.list
            sudo rm -f /etc/apt/sources.list.d/docker.list
            sudo rm -f /etc/apt/keyrings/hashicorp.gpg
            sudo rm -f /etc/apt/keyrings/gierens.gpg
            sudo rm -f /etc/apt/keyrings/docker.gpg
            sudo apt-get update -qq
            ;;
        fedora)
            sudo rm -f /etc/yum.repos.d/hashicorp.repo
            sudo rm -f /etc/yum.repos.d/docker-ce.repo
            ;;
    esac
}

# --- Oh My Zsh ---

remove_ohmyzsh() {
    info "Removing Oh My Zsh..."
    if [ -d "$HOME/.oh-my-zsh" ]; then
        rm -rf "$HOME/.oh-my-zsh"
        info "  removed ~/.oh-my-zsh"
    fi
}

# --- zshrc bootstrap blocks ---

remove_zshrc_blocks() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || return 0
    info "Removing bootstrap blocks from ~/.zshrc..."
    # Remove everything between BEGIN/END bootstrap markers (inclusive)
    sed -i '/^# BEGIN bootstrap: shell/,/^# END bootstrap: shell/d' "$zshrc"
    sed -i '/^# BEGIN bootstrap: prompt/,/^# END bootstrap: prompt/d' "$zshrc"
    info "  done"
}

# --- zsh ---

remove_zsh() {
    info "Removing zsh..."
    # Check the configured default shell in /etc/passwd, not $SHELL (which reflects
    # the current session and may already be bash even if zsh is the configured shell).
    local configured; configured=$(getent passwd "$USER" | cut -d: -f7)
    if [[ "$configured" == *zsh* ]]; then
        sudo usermod --shell "$(command -v bash)" "$USER"
        info "  default shell reset to bash"
    fi
    pkg_remove zsh
    rm -f "$HOME/.zshrc" "$HOME/.zsh_history" "$HOME/.zcompdump"* 2>/dev/null || true
}

# --- Fonts ---

remove_fonts() {
    info "Removing CaskaydiaCove fonts..."
    rm -f "$HOME/.local/share/fonts"/CaskaydiaCove*.ttf
    if command_exists fc-cache; then
        fc-cache -f "$HOME/.local/share/fonts"
    fi
    info "  done"
}

# --- Main ---

main() {
    info "Starting cleanup (distro: $DISTRO)..."
    echo

    remove_packages
    remove_binaries
    remove_symlinks
    remove_docker
    remove_repos
    remove_ohmyzsh
    remove_zshrc_blocks
    remove_zsh
    remove_fonts

    echo
    info "Cleanup complete. Start a new shell session then re-run bootstrap.sh."
}

main "$@"
