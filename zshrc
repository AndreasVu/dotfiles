# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME=intheloop

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to install it when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# zsh-syntax-highlighting must stay last.
plugins=(
  dotnet
  docker
  docker-compose
  emoji
  fzf
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "oh-my-zsh is not installed. Run install-required.sh from the dotfiles repo."
fi

alias lg="lazygit"
alias ldn="lazydotnet"
alias code="cd ~/code/"
alias work="cd ~/work/"
alias vi="nvim"
alias vim="nvim"

export EDITOR="nvim"
export VISUAL="$EDITOR"

# .NET installed by dotnet-install.sh lands in ~/.dotnet and is not on PATH by default.
if [ -d "$HOME/.dotnet" ]; then
  export DOTNET_ROOT="$HOME/.dotnet"
  path=("$DOTNET_ROOT" $path)
fi

typeset -U path PATH
path=("$HOME/.dotnet/tools" "$HOME/.local/bin" $path)
[ -d "$HOME/.spicetify" ] && path+=("$HOME/.spicetify")
[ -d "$HOME/.lmstudio/bin" ] && path+=("$HOME/.lmstudio/bin")
export PATH

# .zshenv already put the default Node on PATH. Sourcing nvm.sh costs ~250ms,
# so load it on first use instead of on every shell.
if [ -s "$NVM_DIR/nvm.sh" ]; then
  nvm() {
    unset -f nvm
    source "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
    nvm "$@"
  }
fi

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
