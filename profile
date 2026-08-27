# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

if [ -d "$HOME/.lmstudio/bin" ] ; then
    PATH="$PATH:$HOME/.lmstudio/bin"
fi

# Same reason as the Node block below: a desktop session reads neither .zshenv
# nor .zshrc, where DOTNET_ROOT is normally set.
if [ -d "$HOME/.dotnet" ]; then
    DOTNET_ROOT="$HOME/.dotnet"
    export DOTNET_ROOT
    PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$PATH"
fi

# Desktop sessions do not read .zshenv, so resolve the default Node here too.
# Without this, anything launched from a GUI (Zed, a desktop nvim) has no node
# and Copilot and several Mason servers fail silently.
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
export NVM_DIR
if [ -d "$NVM_DIR/versions/node" ]; then
    _nvm_v=""
    if [ -r "$NVM_DIR/alias/default" ]; then
        _nvm_v=$(cat "$NVM_DIR/alias/default")
        _nvm_hops=0
        while [ -r "$NVM_DIR/alias/$_nvm_v" ] && [ "$_nvm_hops" -lt 5 ]; do
            _nvm_v=$(cat "$NVM_DIR/alias/$_nvm_v")
            _nvm_hops=$((_nvm_hops + 1))
        done
    fi
    if [ ! -d "$NVM_DIR/versions/node/$_nvm_v/bin" ]; then
        _nvm_v=$(ls -1 "$NVM_DIR/versions/node" 2>/dev/null | sort -V | tail -1)
    fi
    if [ -d "$NVM_DIR/versions/node/$_nvm_v/bin" ]; then
        PATH="$NVM_DIR/versions/node/$_nvm_v/bin:$PATH"
    fi
    unset _nvm_v _nvm_hops
fi

export PATH
