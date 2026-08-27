#!/usr/bin/env bash

# Writes the git identity files that gitconfig includes. Both live in $HOME,
# outside this repo, so no email address is ever tracked here.
#
#   ~/.gitconfig-identity  default identity
#   ~/.gitconfig-work      identity for repos under ~/work/
#
# Safe to re-run: existing files are left alone unless --force is passed.

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[GIT]${NC} $1"
}

success() {
    echo -e "${GREEN}[GIT]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[GIT]${NC} $1"
}

skip() {
    echo -e "${CYAN}[SKIP]${NC} $1"
}

FORCE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=true ;;
        -h|--help)
            echo "Usage: bash setup-git-identity.sh [--force]"
            echo "  --force  Overwrite existing identity files."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

IDENTITY_FILE="$HOME/.gitconfig-identity"
WORK_FILE="$HOME/.gitconfig-work"

if [ "$FORCE" = false ] && [ -f "$IDENTITY_FILE" ] && [ -f "$WORK_FILE" ] \
    && [ ! -L "$IDENTITY_FILE" ] && [ ! -L "$WORK_FILE" ]; then
    skip "Git identity already configured. Re-run with --force to change it."
    exit 0
fi

if [ ! -t 0 ]; then
    warn "Not running interactively; skipping the git identity prompt."
    warn "Run 'bash setup-git-identity.sh' by hand, or git will not know who you are."
    exit 0
fi

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local answer
    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        read -r -p "$prompt: " answer
        echo "$answer"
    fi
}

write_identity() {
    local file="$1"
    local name="$2"
    local email="$3"
    # An older version of this repo symlinked these paths into the dotfiles
    # checkout. Writing through such a link would put the email back into a
    # tracked file, so replace the link with a real file.
    if [ -L "$file" ]; then
        warn "$file is a symlink into $(dirname "$(readlink -f "$file")"); replacing it with a real file."
        rm -f "$file"
    fi
    umask 077
    cat > "$file" <<EOF
[user]
	name = $name
	email = $email
EOF
}

log "Setting up your git identity. These files stay out of the dotfiles repo."

EXISTING_NAME="$(git config --file "$IDENTITY_FILE" user.name 2>/dev/null || true)"
EXISTING_EMAIL="$(git config --file "$IDENTITY_FILE" user.email 2>/dev/null || true)"

GIT_NAME="$(prompt_with_default "Your name" "$EXISTING_NAME")"
GIT_EMAIL="$(prompt_with_default "Default git email" "$EXISTING_EMAIL")"

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    warn "Name and email are both required. Nothing written."
    exit 1
fi

write_identity "$IDENTITY_FILE" "$GIT_NAME" "$GIT_EMAIL"
success "Wrote $IDENTITY_FILE"

EXISTING_WORK_NAME="$(git config --file "$WORK_FILE" user.name 2>/dev/null || true)"
EXISTING_WORK_EMAIL="$(git config --file "$WORK_FILE" user.email 2>/dev/null || true)"

echo
if [ -n "$EXISTING_WORK_EMAIL" ] && [ "$EXISTING_WORK_EMAIL" != "$GIT_EMAIL" ]; then
    log "Repos under ~/work/ use a separate identity. Enter - to drop it and reuse the default."
else
    log "Repos under ~/work/ can use a separate identity. Leave it blank to reuse the default."
fi
WORK_EMAIL="$(prompt_with_default "Work git email" "$EXISTING_WORK_EMAIL")"
[ "$WORK_EMAIL" = "-" ] && WORK_EMAIL=""

if [ -z "$WORK_EMAIL" ]; then
    write_identity "$WORK_FILE" "$GIT_NAME" "$GIT_EMAIL"
    log "No separate work email; ~/work/ will use the default identity."
else
    WORK_NAME="$(prompt_with_default "Work name" "${EXISTING_WORK_NAME:-$GIT_NAME}")"
    write_identity "$WORK_FILE" "${WORK_NAME:-$GIT_NAME}" "$WORK_EMAIL"
fi
success "Wrote $WORK_FILE"

echo
success "Git identity configured."
log "Default:  $(git config --file "$IDENTITY_FILE" user.name) <$(git config --file "$IDENTITY_FILE" user.email)>"
log "Work:     $(git config --file "$WORK_FILE" user.name) <$(git config --file "$WORK_FILE" user.email)>"
