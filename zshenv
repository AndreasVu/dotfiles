# Sourced by every zsh invocation, interactive or not. Keep it small and
# never let a missing file here break non-interactive shells.

# .zshrc is interactive-only, so without this a nested `zsh -c` re-prepends the
# entries below on every level and PATH grows a duplicate each time.
typeset -U path PATH

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Put the default Node on PATH without sourcing nvm.sh, which costs ~250ms per
# shell and only ever runs in interactive shells. Resolving the alias chain by
# hand is a few builtin file reads. .zshrc lazy-loads the nvm function itself.
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR
if [[ -d "$NVM_DIR/versions/node" ]]; then
  _nvm_v=""
  if [[ -r "$NVM_DIR/alias/default" ]]; then
    _nvm_v="$(<"$NVM_DIR/alias/default")"
    _nvm_hops=0
    while [[ -r "$NVM_DIR/alias/$_nvm_v" && $_nvm_hops -lt 5 ]]; do
      _nvm_v="$(<"$NVM_DIR/alias/$_nvm_v")"
      (( _nvm_hops++ ))
    done
  fi
  if [[ ! -d "$NVM_DIR/versions/node/$_nvm_v/bin" ]]; then
    () {
      setopt localoptions numericglobsort
      _nvm_dirs=("$NVM_DIR"/versions/node/*(/N))
    }
    _nvm_v="${_nvm_dirs[-1]:t}"
  fi
  [[ -d "$NVM_DIR/versions/node/$_nvm_v/bin" ]] && path=("$NVM_DIR/versions/node/$_nvm_v/bin" $path)
  unset _nvm_v _nvm_hops _nvm_dirs
fi
