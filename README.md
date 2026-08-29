# dotfiles

Managed with [dotbot](https://github.com/anishathalye/dotbot). Targets Debian/Ubuntu and Arch.

## Bootstrap on a fresh machine

```sh
sudo apt-get update && sudo apt-get install -y git   # or: sudo pacman -S git
git clone --recurse-submodules https://github.com/AndreasVu/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash bootstrap.sh
exec zsh
```

`bootstrap.sh` runs `install-required.sh` (packages, shell, runtimes), then
`./install` (dotbot symlinks), then `setup-git-identity.sh` (prompts for your
git name and email). The order matters because `zshrc` sources Oh My Zsh; if a
step aborts, the following ones do not run.

Run it as your normal user, never with `sudo` — everything installs into `$HOME`
and the script calls `sudo` itself where it needs to. It refuses to start as root.

| Flag | Effect |
| --- | --- |
| *(none)* | Install tools, then link dotfiles |
| `--tools-only` | Run `install-required.sh` only |
| `--link-only` | Run `./install` only |
| `--skip-git` | Skip the git identity prompt |
| `--no-gui` | Skip GUI apps (Ghostty, Zen Browser, Zed, Discord) |
| `--gui` | Install GUI apps even on WSL |
| `-h`, `--help` | Usage |

The two halves can still be run directly (`bash install-required.sh`, `./install`)
if you prefer.

## Re-running

Everything is safe to re-run. `install-required.sh` detects what is already
present and prints `[SKIP]`; on Debian it does not even hit `apt-get update`
when nothing is missing.

Two deliberate exceptions:

- **Oh My Zsh is always removed and reinstalled clean.** Anything you put in
  `~/.oh-my-zsh/custom/` is destroyed on every run — keep it in this repo instead.
  This step needs network, and a failed download leaves you with no `~/.oh-my-zsh`
  until you re-run.
- The script ensures tools are *present*, not *current*. It will not upgrade an
  already-installed lazygit, Zed, .NET, Node or zoxide.

## What gets installed

| Step | Tools |
| --- | --- |
| Prerequisites | curl, git, tar, sed, fzf, unzip, gzip, wget, jq, gnupg, ca-certificates, ripgrep, fd |
| Build | build-essential / base-devel (gcc + make) |
| Treesitter | tree-sitter CLI (apt/pacman, else the upstream release binary) |
| Editors | Neovim 0.12+, clipboard bridge (xclip + wl-clipboard, or win32yank on WSL) |
| Shell | zsh, Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, `chsh` to zsh |
| Terminal | Ghostty *(GUI)* |
| Git | lazygit |
| Browser | Zen Browser *(GUI)* |
| Editor | Zed *(GUI)* |
| Runtimes | .NET SDK 10.0, Rust (rustup), Node (nvm, latest LTS) |
| Neovim config | clone of [AndreasVu/nvim](https://github.com/AndreasVu/nvim) into `~/.config/nvim` |
| Fonts | JetBrainsMono Nerd Font, Noto Color Emoji *(GUI)* |
| Navigation | zoxide |
| Chat | Discord *(GUI)* |
| .NET tools | lazydotnet |

## What gets linked

| Target | Source |
| --- | --- |
| `~/.zshrc`, `~/.zshenv`, `~/.profile`, `~/.bash_logout` | `zshrc`, `zshenv`, `profile`, `bash_logout` |
| `~/.gitconfig`, `~/.gitignore_global` | `gitconfig`, `gitignore_global` |
| `~/.ideavimrc` | `ideavimrc` |
| `~/.config/ghostty/*` | `ghostty/*` |
| `~/.config/zed/*` | `zed/*` |

Links use `force: true`, so dotbot replaces the regular `~/.profile` and
`~/.bash_logout` that Debian ships in `/etc/skel`.

## Git identity

| File | Applies to |
| --- | --- |
| `~/.gitconfig-identity` | everything by default |
| `~/.gitconfig-work` | repos under `~/work/`, via `includeIf` |

`bootstrap.sh` prompts for both and writes them. To change them later:

```sh
bash setup-git-identity.sh --force
```

Re-running without `--force` leaves existing files alone, and the script skips
itself entirely when stdin is not a terminal, so unattended runs do not hang.

`user.useConfigOnly = true` is set deliberately: if those files are missing, git
refuses to commit rather than silently inventing an address from your username
and hostname. The error tells you to run the script.

## Notes

- Neither install script writes to the dotfiles-managed `~/.zshrc`. rustup runs
  with `--no-modify-path` and nvm with `PROFILE=/dev/null` so their installers
  do not append snippets into the symlinked file.
- .NET installed via `dotnet-install.sh` lands in `~/.dotnet`, which is not on
  PATH by default. `zshrc` sets `DOTNET_ROOT` and adds it.

## WSL

WSL is detected from `/proc/version` and `$WSL_DISTRO_NAME`, and GUI applications
are skipped there automatically — Ghostty, Zen Browser, Zed and Discord all want
a desktop you probably run on the Windows side instead. Everything else installs
normally.

`--no-gui` forces the same behaviour anywhere (headless servers, containers), and
`--gui` overrides the detection if you do run a desktop under WSLg.

Clipboard differs too: on WSL the script installs
[win32yank](https://github.com/equalsraf/win32yank) to `~/.local/bin` so Neovim's
`+` register reaches the Windows clipboard, instead of xclip/wl-clipboard. That
works with or without WSLg.

The dotfiles themselves are linked either way. The Ghostty and Zed configs are
harmless on a machine without those apps, and stay in place for when you sync the
same repo to a desktop.

## Shell startup

`.zshrc` deliberately does **not** source `nvm.sh`. Doing so costs ~250-450ms on
every single shell, which was around 85% of total startup time. Instead:

- `.zshenv` resolves the default Node version by following nvm's alias chain
  (`default` -> `lts/*` -> `lts/<name>` -> `v22.x`) with a few builtin file reads
  and puts that version's `bin` on `PATH`. Falls back to the newest installed
  version, and does nothing at all when nvm is absent.
- `.zshrc` defines `nvm` as a stub function that sources `nvm.sh` on first call
  and then replaces itself. `nvm use`, `nvm install` and friends work as normal;
  you just pay for them only when you use them.

`.profile` carries a POSIX version of the same resolver, because desktop sessions
read `.profile` but never `.zshenv` — without it, anything launched from a GUI
(Zed, a desktop nvim) has no `node`, and Copilot and several Mason servers fail
silently.

## Neovim

`~/.config/nvim` is **not** managed by dotbot. `install-required.sh` clones
[AndreasVu/nvim](https://github.com/AndreasVu/nvim) there as an independent
repo, so commit and push nvim changes from that directory as normal. Re-runs
leave an existing checkout untouched; a non-git `~/.config/nvim` is moved aside
to `~/.config/nvim.bak.<timestamp>` rather than deleted.

That config uses `vim.pack`, which requires **Neovim 0.12+**. Debian and Ubuntu
ship much older builds, so on Debian the script installs the official release
tarball to `~/.local/share/nvim-release` and symlinks `~/.local/bin/nvim`;
Arch uses pacman. The version is checked either way, and you get a warning
rather than a silent too-old Neovim.

Plugins install on the first `nvim` launch. Most come from GitHub; `leap.nvim`
is fetched from codeberg.org, so that host needs to be reachable too.

JetBrainsMono Nerd Font is installed alongside the GUI apps and set as Ghostty's
`font-family`. The nvim config ships with `vim.g.have_nerd_font = false`; flip it
to `true` in that repo to get the icons.
- `ghostty/auto/theme.ghostty` is included optionally via `config-file = ?auto/theme.ghostty`.
  It is symlinked into this repo, so anything writing it will show up as a git change.
