#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define text coloring for clear readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

skip() {
    echo -e "${CYAN}[SKIP]${NC} $1"
}

# Make locally installed tools visible so detection works in a fresh shell
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.dotnet:$PATH"

have_command() {
    command -v "$1" >/dev/null 2>&1
}

APT_UPDATED=false

apt_update_once() {
    if [ "$APT_UPDATED" = false ]; then
        log "Updating apt package lists..."
        sudo apt-get update -y
        APT_UPDATED=true
    fi
}

# Installs only the packages that are not already present
ensure_packages() {
    if [ "$OS" == "arch" ]; then
        sudo pacman -S --needed --noconfirm "$@"
        return
    fi

    local missing=()
    local pkg
    for pkg in "$@"; do
        # dpkg -s exits 0 for packages removed but not purged ("rc" state), so
        # check the status field itself.
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        skip "Already installed: $*"
        return
    fi

    apt_update_once
    sudo apt-get install -y "${missing[@]}"
}

# 0. Option parsing and environment detection
INSTALL_GUI=""

usage() {
    cat <<'USAGE'
Usage: bash install-required.sh [options]

Options:
  --no-gui   Skip GUI applications (Ghostty, Zen Browser, Zed, Discord).
  --gui      Install GUI applications even when WSL is detected.
  -h/--help  Show this message.

With neither flag, GUI apps are installed everywhere except WSL, where they
are skipped automatically.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-gui) INSTALL_GUI=false ;;
        --gui) INSTALL_GUI=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

IS_WSL=false
if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || [ -n "$WSL_DISTRO_NAME" ]; then
    IS_WSL=true
fi

if [ -z "$INSTALL_GUI" ]; then
    if [ "$IS_WSL" = true ]; then
        INSTALL_GUI=false
    else
        INSTALL_GUI=true
    fi
fi

if [ "$IS_WSL" = true ]; then
    log "Detected WSL."
fi
if [ "$INSTALL_GUI" = false ]; then
    log "GUI applications will be skipped (Ghostty, Zen Browser, Zed, Discord)."
fi

# 1. Safe OS Type Detection
if [ -f /etc/arch-release ]; then
    OS="arch"
    log "Detected Arch-based system."
elif [ -f /etc/debian_version ] || grep -qi "debian\|ubuntu" /etc/os-release 2>/dev/null; then
    OS="debian"
    log "Detected Debian/Ubuntu-based system."
else
    echo "Error: Unsupported distribution. This script only supports Debian- and Arch-based platforms."
    exit 1
fi

# 2. Core Prerequisites
# git, unzip and gzip are Neovim dependencies: plugins are cloned and release
# archives unpacked during install. ripgrep and fd back Telescope's live_grep
# and file finder.
log "Checking core prerequisites..."
if [ "$OS" == "arch" ]; then
    ensure_packages curl git tar sed fzf unzip gzip wget jq gnupg ca-certificates ripgrep fd
else
    ensure_packages curl git tar sed fzf unzip gzip wget jq gnupg ca-certificates ripgrep fd-find
    # Debian ships the fd binary as fdfind; Telescope and muscle memory both want fd.
    if ! have_command fd && have_command fdfind; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log "Linked fdfind to ~/.local/bin/fd."
    fi
fi

# 3. Development Essentials Setup
# Neovim needs a C compiler and make: treesitter parsers are compiled with cc,
# and both telescope-fzf-native and LuaSnip's jsregexp build with make on install.
log "Checking build essentials..."
if [ "$OS" == "arch" ]; then
    ensure_packages base-devel
else
    ensure_packages build-essential
fi

# 4. tree-sitter CLI (Neovim dependency)
# nvim-treesitter shells out to the tree-sitter CLI to build any parser it cannot
# fetch prebuilt, and :checkhealth flags it as missing otherwise. Only recent
# Debian/Ubuntu releases carry a tree-sitter-cli package, so fall back to the
# upstream release binary.
install_tree_sitter_binary() {
    local asset tmpdir
    case "$(uname -m)" in
        x86_64) asset="tree-sitter-linux-x64.gz" ;;
        aarch64|arm64) asset="tree-sitter-linux-arm64.gz" ;;
        *) warn "No tree-sitter release build for $(uname -m). Skipping."; return 1 ;;
    esac

    tmpdir="$(mktemp -d)"
    if ! curl -fsSL -o "$tmpdir/$asset" \
        "https://github.com/tree-sitter/tree-sitter/releases/latest/download/$asset"; then
        rm -rf "$tmpdir"
        warn "Could not download $asset."
        return 1
    fi

    if ! gunzip -f "$tmpdir/$asset"; then
        rm -rf "$tmpdir"
        warn "Downloaded tree-sitter archive was not readable."
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    install -m 755 "$tmpdir/${asset%.gz}" "$HOME/.local/bin/tree-sitter"
    rm -rf "$tmpdir"
}

if have_command tree-sitter; then
    skip "tree-sitter CLI is already installed at $(command -v tree-sitter)."
elif [ "$OS" == "arch" ]; then
    log "Installing the tree-sitter CLI via pacman..."
    ensure_packages tree-sitter-cli
    success "tree-sitter CLI installed via pacman."
else
    log "Installing the tree-sitter CLI..."
    apt_update_once
    if sudo apt-get install -y tree-sitter-cli 2>/dev/null; then
        success "tree-sitter CLI installed via apt."
    else
        log "tree-sitter-cli is not in apt on this release. Downloading the latest GitHub release binary..."
        # Best effort: the function warns for itself, and set -e would take the
        # whole script down with it otherwise.
        if install_tree_sitter_binary; then
            success "tree-sitter CLI installed to ~/.local/bin."
        else
            warn "tree-sitter CLI not installed; nvim-treesitter cannot build parsers from source."
        fi
    fi
fi

# 5. Editors and clipboard support
# Neovim's "+ / "* registers need a clipboard bridge. On Linux that is
# xclip/wl-clipboard; on WSL it is win32yank, which talks to the Windows clipboard
# and works whether or not WSLg is available.
install_win32yank() {
    local tmpdir
    if [ "$(uname -m)" != "x86_64" ]; then
        warn "win32yank ships x64 builds only; skipping on $(uname -m)."
        return 1
    fi

    tmpdir="$(mktemp -d)"
    if ! curl -fsSL -o "$tmpdir/win32yank.zip" \
        "https://github.com/equalsraf/win32yank/releases/latest/download/win32yank-x64.zip"; then
        rm -rf "$tmpdir"
        warn "Could not download win32yank."
        return 1
    fi

    if ! unzip -qo "$tmpdir/win32yank.zip" win32yank.exe -d "$tmpdir"; then
        rm -rf "$tmpdir"
        warn "Could not unpack win32yank."
        return 1
    fi

    mkdir -p "$HOME/.local/bin"
    install -m 755 "$tmpdir/win32yank.exe" "$HOME/.local/bin/win32yank.exe"
    rm -rf "$tmpdir"
}

if [ "$IS_WSL" = true ]; then
    if have_command win32yank.exe; then
        skip "win32yank is already installed at $(command -v win32yank.exe)."
    else
        log "Installing win32yank for Windows clipboard integration..."
        if install_win32yank; then
            success "win32yank installed to ~/.local/bin."
        else
            warn "Neovim's + register will not reach the Windows clipboard until win32yank is installed."
        fi
    fi
else
    log "Checking clipboard tooling..."
    ensure_packages xclip wl-clipboard
fi

# The nvim config in NVIM_CONFIG_REPO uses vim.pack, which needs Neovim 0.12+.
# Debian and Ubuntu ship far older builds, so use the official release tarball there.
NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=12

nvim_is_new_enough() {
    local version major minor
    have_command nvim || return 1
    version=$(nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v([0-9]+\.[0-9]+).*/\1/')
    major=${version%%.*}
    minor=${version##*.}
    case "$major$minor" in
        *[!0-9]*|"") return 1 ;;
    esac
    [ "$major" -gt "$NVIM_MIN_MAJOR" ] && return 0
    [ "$major" -eq "$NVIM_MIN_MAJOR" ] && [ "$minor" -ge "$NVIM_MIN_MINOR" ]
}

install_neovim_tarball() {
    local arch asset tmpdir dest
    case "$(uname -m)" in
        x86_64) arch="linux-x86_64" ;;
        aarch64|arm64) arch="linux-arm64" ;;
        *) warn "No official Neovim tarball for $(uname -m). Install Neovim 0.12+ manually."; return 1 ;;
    esac

    asset="nvim-${arch}.tar.gz"
    dest="$HOME/.local/share/nvim-release"
    tmpdir="$(mktemp -d)"

    if ! curl -fsSL -o "$tmpdir/$asset" "https://github.com/neovim/neovim/releases/latest/download/$asset"; then
        rm -rf "$tmpdir"
        warn "Could not download $asset from the Neovim releases page."
        return 1
    fi

    tar -xzf "$tmpdir/$asset" -C "$tmpdir"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    mv "$tmpdir/nvim-${arch}" "$dest"
    rm -rf "$tmpdir"

    mkdir -p "$HOME/.local/bin"
    ln -sfn "$dest/bin/nvim" "$HOME/.local/bin/nvim"
    hash -r 2>/dev/null || true
}

if nvim_is_new_enough; then
    skip "Neovim $(nvim --version | head -1 | awk '{print $2}') is already installed at $(command -v nvim)."
elif [ "$OS" == "arch" ]; then
    log "Installing Neovim via pacman..."
    ensure_packages neovim
    if nvim_is_new_enough; then
        success "Neovim $(nvim --version | head -1 | awk '{print $2}') installed."
    else
        warn "pacman's Neovim is older than ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR}; vim.pack in your config needs a newer build."
    fi
else
    log "Installing Neovim from the official release tarball (apt's build is too old for vim.pack)..."
    if install_neovim_tarball && nvim_is_new_enough; then
        success "Neovim $(nvim --version | head -1 | awk '{print $2}') installed to ~/.local/share/nvim-release."
    else
        warn "Neovim install did not produce a ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR}+ build. Your nvim config may not load."
    fi
fi

# 6. Shell Setup (Zsh & Oh My Zsh)
log "Checking Zsh..."
ensure_packages zsh

if [ -d "$HOME/.oh-my-zsh" ]; then
    warn "Existing Oh My Zsh installation found. Removing $HOME/.oh-my-zsh for a clean install."
    rm -rf "$HOME/.oh-my-zsh"
fi

log "Installing Oh My Zsh..."
# --keep-zshrc leaves an existing .zshrc alone, including when it is a symlink into your dotfiles
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
success "Oh My Zsh installed."

log "Installing custom Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

install_plugin() {
    local repo="$1"
    local name="$2"
    local dest="$ZSH_CUSTOM/plugins/$name"

    if [ -d "$dest" ]; then
        skip "$name is already present."
        return
    fi

    if git clone --depth=1 "$repo" "$dest"; then
        success "$name installed."
    else
        warn "Failed to clone $name from $repo."
    fi
}

install_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
install_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting
install_plugin https://github.com/zsh-users/zsh-completions zsh-completions

ZSH_PATH="$(command -v zsh)"
if [ "$SHELL" = "$ZSH_PATH" ]; then
    skip "Login shell is already $ZSH_PATH."
else
    log "Setting $ZSH_PATH as the login shell for $USER..."
    if sudo chsh -s "$ZSH_PATH" "$USER"; then
        success "Login shell changed. Log out and back in for it to take effect."
    else
        warn "Could not change the login shell. Run: chsh -s $ZSH_PATH"
    fi
fi

# 7. Terminal Deployment (Ghostty)
if [ "$INSTALL_GUI" = false ]; then
    skip "Ghostty (GUI application)."
elif have_command ghostty; then
    skip "Ghostty is already installed at $(command -v ghostty)."
else
    log "Installing Ghostty..."
    if [ "$OS" == "arch" ]; then
        ensure_packages ghostty
        success "Ghostty installed via pacman."
    else
        # Run using recommended native string execution to prevent subshell asset errors
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
        success "Ghostty installed via mkasberg community build script."
    fi
fi

# 8. Git Tooling (Lazygit with Dynamic Fallback)
# Everything here is best effort: lazygit is a convenience, so a download failure
# warns and moves on rather than killing the rest of the bootstrap. Work happens
# in a temp dir so a failed run never litters the dotfiles repo.
install_lazygit_binary() {
    local arch lazygit_arch version tmpdir
    arch="$(uname -m)"
    case "$arch" in
        x86_64) lazygit_arch="linux_x86_64" ;;
        aarch64|arm64) lazygit_arch="linux_arm64" ;;
        *) warn "No lazygit release build for $arch. Skipping."; return 1 ;;
    esac

    version=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" 2>/dev/null \
        | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$version" ]; then
        warn "Could not read the latest lazygit version (GitHub API rate limit?). Skipping."
        return 1
    fi

    tmpdir="$(mktemp -d)"
    if ! curl -fsSL -o "$tmpdir/lazygit.tar.gz" \
        "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_${lazygit_arch}.tar.gz"; then
        rm -rf "$tmpdir"
        warn "Could not download lazygit ${version}. Skipping."
        return 1
    fi

    if ! tar -xf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit; then
        rm -rf "$tmpdir"
        warn "Downloaded lazygit archive was not readable. Skipping."
        return 1
    fi

    sudo install "$tmpdir/lazygit" -D -t /usr/local/bin/
    rm -rf "$tmpdir"
    success "Lazygit ${version} installed to /usr/local/bin/."
}

if have_command lazygit; then
    skip "Lazygit is already installed at $(command -v lazygit)."
else
    log "Installing Lazygit..."
    if [ "$OS" == "arch" ]; then
        ensure_packages lazygit
        success "Lazygit installed via pacman."
    else
        # Graceful fallback wrapper for Debian systems lacking native package access
        apt_update_once
        if sudo apt-get install -y lazygit 2>/dev/null; then
            success "Lazygit installed via apt."
        else
            log "Lazygit not available in native apt repositories. Downloading latest GitHub release binary..."
            # Best effort: the function warns for itself, and set -e would take
            # the whole script down with it otherwise.
            install_lazygit_binary || true
        fi
    fi
fi

# 9. Browser Setup (Zen Browser)
if [ "$INSTALL_GUI" = false ]; then
    skip "Zen Browser (GUI application)."
elif have_command zen || have_command zen-browser || [ -d "$HOME/.tarball-installations/zen" ]; then
    skip "Zen Browser is already installed."
else
    log "Installing Zen Browser..."
    ZEN_INSTALLER="$(mktemp)"
    if curl -fsSL -o "$ZEN_INSTALLER" https://updates.zen-browser.app/install.sh && bash "$ZEN_INSTALLER"; then
        success "Zen Browser installed successfully."
    else
        warn "Zen Browser installer failed. Check your environment compatibility."
    fi
    rm -f "$ZEN_INSTALLER"
fi

# 10. Editor Setup (Zed Editor)
if [ "$INSTALL_GUI" = false ]; then
    skip "Zed (GUI application)."
elif have_command zed; then
    skip "Zed is already installed at $(command -v zed)."
else
    log "Installing Zed Editor..."
    if curl -fsSL https://zed.dev/install.sh | sh; then
        success "Zed installed safely to local bin space."
    else
        warn "Zed installation script encountered an issue."
    fi
fi

# 11. Language Runtime (.NET SDK 10.0 Setup)
if have_command dotnet; then
    skip ".NET SDK is already installed at $(command -v dotnet)."
else
    log "Installing latest .NET SDK..."
    if [ "$OS" == "arch" ]; then
        ensure_packages dotnet-sdk
        success "Latest .NET SDK installed via pacman."
    else
        log "Using official Microsoft installation engine to prevent apt repository routing issues..."
        # Installs .NET SDK directly via the decoupled engine platform script
        curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 10.0
        success ".NET SDK 10.0 installed to $HOME/.dotnet."
        log "DOTNET_ROOT and the PATH entry for it are set by the .zshrc in this repo."
    fi
fi

# 12. Rust toolchain
if have_command rustup || [ -x "$HOME/.cargo/bin/rustup" ]; then
    skip "Rust is already installed."
else
    log "Installing Rust via rustup..."
    # --no-modify-path keeps rustup from appending to the dotfiles-managed .zshenv/.profile;
    # both already source ~/.cargo/env when it exists.
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        success "Rust toolchain installed to $HOME/.cargo."
    else
        warn "rustup installation encountered an issue."
    fi
fi

# 13. Node via nvm
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    skip "nvm is already installed at $NVM_DIR."
else
    log "Installing nvm..."
    NVM_VERSION=$(curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"(v[^"]+)".*/\1/')
    NVM_VERSION="${NVM_VERSION:-v0.40.3}"
    # The nvm installer aborts if NVM_DIR is set but missing, and it is exported
    # just above, so create it first.
    mkdir -p "$NVM_DIR"
    # PROFILE=/dev/null stops the installer from appending its snippet to the
    # dotfiles-managed .zshrc; the repo .zshrc already loads nvm itself.
    if PROFILE=/dev/null bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"; then
        success "nvm ${NVM_VERSION} installed."
    else
        warn "nvm installation encountered an issue."
    fi
fi

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    if [ -s "$NVM_DIR/alias/default" ]; then
        skip "A default Node version is already aliased ($(cat "$NVM_DIR/alias/default"))."
    else
        log "Installing the latest Node LTS..."
        if nvm install --lts && nvm alias default 'lts/*'; then
            success "Node $(node --version) set as the default."
        else
            warn "Could not install Node. Run 'nvm install --lts' by hand."
        fi
    fi
fi

# 14. Nerd Font (JetBrains Mono)
# Only useful where something renders it, so it follows the GUI flag. On WSL the
# font belongs on the Windows side, in the terminal you actually run there.
NERD_FONT_DIR="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"

install_nerd_font() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    if ! curl -fsSL -o "$tmpdir/JetBrainsMono.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
        rm -rf "$tmpdir"
        warn "Could not download JetBrainsMono Nerd Font."
        return 1
    fi

    # unzip -d will not create nested parents.
    mkdir -p "$NERD_FONT_DIR"
    # The archive carries every weight and variant; four faces is all a terminal needs.
    if ! unzip -qo "$tmpdir/JetBrainsMono.zip" \
        "JetBrainsMonoNerdFont-Regular.ttf" \
        "JetBrainsMonoNerdFont-Bold.ttf" \
        "JetBrainsMonoNerdFont-Italic.ttf" \
        "JetBrainsMonoNerdFont-BoldItalic.ttf" \
        -d "$NERD_FONT_DIR"; then
        rm -rf "$tmpdir"
        warn "Could not unpack the Nerd Font archive."
        return 1
    fi

    rm -rf "$tmpdir"
    fc-cache -f "$NERD_FONT_DIR" >/dev/null 2>&1 || true
}

if [ "$INSTALL_GUI" = false ]; then
    skip "JetBrainsMono Nerd Font (no GUI; install it on the Windows side for WSL)."
elif [ -f "$NERD_FONT_DIR/JetBrainsMonoNerdFont-Regular.ttf" ]; then
    skip "JetBrainsMono Nerd Font is already installed."
else
    log "Installing JetBrainsMono Nerd Font (large download)..."
    ensure_packages fontconfig
    if install_nerd_font; then
        success "JetBrainsMono Nerd Font installed to ~/.local/share/fonts."
    else
        warn "Nerd Font not installed; Ghostty will fall back to its default font."
    fi
fi

# A colour emoji font is separate from the Nerd Font; without one, emoji in
# plugin UIs and commit messages render as tofu boxes.
if [ "$INSTALL_GUI" = false ]; then
    skip "Colour emoji font (no GUI; install it on the Windows side for WSL)."
elif [ "$OS" == "arch" ]; then
    ensure_packages noto-fonts-emoji
else
    ensure_packages fonts-noto-color-emoji
fi

# 15. Neovim configuration
NVIM_CONFIG_REPO="https://github.com/AndreasVu/nvim.git"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

if [ -d "$NVIM_CONFIG_DIR/.git" ]; then
    skip "Neovim config already cloned at $NVIM_CONFIG_DIR."
elif [ -e "$NVIM_CONFIG_DIR" ]; then
    NVIM_BACKUP="${NVIM_CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    warn "$NVIM_CONFIG_DIR exists but is not a git checkout. Moving it to $NVIM_BACKUP."
    mv "$NVIM_CONFIG_DIR" "$NVIM_BACKUP"
fi

if [ ! -d "$NVIM_CONFIG_DIR/.git" ]; then
    log "Cloning Neovim config from $NVIM_CONFIG_REPO..."
    mkdir -p "$(dirname "$NVIM_CONFIG_DIR")"
    if git clone "$NVIM_CONFIG_REPO" "$NVIM_CONFIG_DIR"; then
        success "Neovim config cloned to $NVIM_CONFIG_DIR."
        log "Plugins install on the first nvim launch via vim.pack."
    else
        warn "Could not clone the Neovim config. Clone it manually into $NVIM_CONFIG_DIR."
    fi
fi

# 16. zoxide
if have_command zoxide; then
    skip "zoxide is already installed at $(command -v zoxide)."
else
    log "Installing zoxide..."
    if curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
        success "zoxide installed to local bin space."
    else
        warn "zoxide installation script encountered an issue."
    fi
fi

# 17. Discord
# Debian and Ubuntu have no Discord package, and the official deb is the only
# build Discord ships for them. Arch carries it in extra.
install_discord_deb() {
    local tmpdir
    tmpdir="$(mktemp -d)"

    if ! curl -fsSL -o "$tmpdir/discord.deb" \
        "https://discord.com/api/download?platform=linux&format=deb"; then
        rm -rf "$tmpdir"
        warn "Could not download the Discord deb package."
        return 1
    fi

    # apt-get resolves the deb's dependencies; dpkg -i would leave them broken.
    apt_update_once
    if ! sudo apt-get install -y "$tmpdir/discord.deb"; then
        rm -rf "$tmpdir"
        warn "apt-get could not install the Discord deb package."
        return 1
    fi

    rm -rf "$tmpdir"
}

if [ "$INSTALL_GUI" = false ]; then
    skip "Discord (GUI application)."
elif have_command discord; then
    skip "Discord is already installed at $(command -v discord)."
elif [ "$OS" == "arch" ]; then
    log "Installing Discord via pacman..."
    ensure_packages discord
    success "Discord installed via pacman."
else
    log "Installing Discord from the official deb package..."
    if install_discord_deb; then
        success "Discord installed."
    else
        warn "Discord not installed. Grab the deb from https://discord.com/download by hand."
    fi
fi

# 18. .NET global tools
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"

if ! have_command dotnet; then
    warn "dotnet is not on PATH. Skipping .NET global tools."
elif have_command lazydotnet; then
    skip "lazydotnet is already installed."
else
    log "Installing lazydotnet..."
    if dotnet tool install --global lazydotnet; then
        success "lazydotnet installed."
    else
        warn "lazydotnet installation failed."
    fi
fi

success "Script completion reached! Base applications deployment finished cleanly."
log "Next: run ./install to link the dotfiles, then start a new zsh session."
