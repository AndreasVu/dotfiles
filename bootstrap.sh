#!/usr/bin/env bash

# Single entrypoint for a fresh machine: installs the tools, then links the dotfiles.
#   bash bootstrap.sh

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[BOOTSTRAP]${NC} $1"
}

success() {
    echo -e "${GREEN}[BOOTSTRAP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[BOOTSTRAP]${NC} $1"
}

fail() {
    echo -e "${RED}[BOOTSTRAP]${NC} $1" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: bash bootstrap.sh [options]

Runs install-required.sh (packages, shell, runtimes), then ./install (dotbot
symlinks), then setup-git-identity.sh (prompts for your git name and email).
All three are safe to re-run.

Options:
  --tools-only   Run install-required.sh only, skip linking and git identity.
  --link-only    Run ./install only, skip the tool installation.
  --skip-git     Do not prompt for the git identity.
  --no-gui       Skip GUI applications (Ghostty, Zen Browser, Zed, Discord).
  --gui          Install GUI applications even when WSL is detected.
  -h, --help     Show this message.

GUI applications are installed everywhere except WSL, which is detected
automatically. Use --gui or --no-gui to decide explicitly.
USAGE
}

RUN_TOOLS=true
RUN_LINK=true
RUN_GIT=true
TOOL_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --tools-only) RUN_LINK=false; RUN_GIT=false ;;
        --link-only) RUN_TOOLS=false ;;
        --skip-git) RUN_GIT=false ;;
        --no-gui|--gui) TOOL_ARGS+=("$1") ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "Unknown option: $1" ;;
    esac
    shift
done

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${BASEDIR}"

# Everything here installs into $HOME. Running under sudo would put oh-my-zsh,
# rustup, nvm and the symlinks in /root instead.
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this as root or with sudo. Run it as your normal user; the script calls sudo where it needs to."
fi

if [ "$RUN_TOOLS" = true ]; then
    [ -f "${BASEDIR}/install-required.sh" ] || fail "install-required.sh not found in ${BASEDIR}."
    log "Step 1/3 - installing tools and runtimes..."
    bash "${BASEDIR}/install-required.sh" "${TOOL_ARGS[@]}"
    success "Tools installed."
else
    warn "Skipping tool installation (--link-only)."
fi

if [ "$RUN_LINK" = true ]; then
    [ -f "${BASEDIR}/install" ] || fail "install not found in ${BASEDIR}."
    log "Step 2/3 - linking dotfiles with dotbot..."
    bash "${BASEDIR}/install"
    success "Dotfiles linked."
else
    warn "Skipping dotbot link step (--tools-only)."
fi

# The git identity lives in ~/.gitconfig-identity and ~/.gitconfig-work, which are
# never tracked in this repo, so a public dotfiles repo exposes no email address.
if [ "$RUN_GIT" = true ]; then
    if [ -f "${BASEDIR}/setup-git-identity.sh" ]; then
        log "Step 3/3 - git identity..."
        bash "${BASEDIR}/setup-git-identity.sh"
    else
        warn "setup-git-identity.sh not found; skipping the git identity step."
    fi
else
    warn "Skipping the git identity prompt."
fi

success "Bootstrap complete."
if [ "$RUN_LINK" = true ]; then
    log "Start a new shell to pick everything up:  exec zsh"
    log "If the login shell was just changed, log out and back in for it to stick."
fi
