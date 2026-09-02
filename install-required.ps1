#Requires -Version 7.0

# Windows counterpart of install-required.sh.
#
# The two scripts are kept in the same order, with the same numbered sections, so
# they can be read side by side. Where a Linux tool has no Windows build the step
# prints [UNSUPPORTED] with the reason and the substitute; where Windows already
# provides the thing it prints [NO-OP]. Both are collected into a summary at the end.

[CmdletBinding()]
param(
    [switch]$NoGui,
    [switch]$Gui,
    [switch]$DryRun,
    [switch]$Help
)

# Roughly `set -e`.
$ErrorActionPreference = 'Stop'

# PowerShell 7.4+ turns a non-zero native exit code into a terminating error while
# $ErrorActionPreference is Stop. This script checks $LASTEXITCODE itself - winget
# uses non-zero codes for ordinary "no package found" answers - so opt out.
$PSNativeCommandUseErrorActionPreference = $false

# Define text coloring for clear readability
function Write-Log     { param([string]$Message) Write-Host '[INFO] '    -ForegroundColor Blue   -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host '[SUCCESS] ' -ForegroundColor Green  -NoNewline; Write-Host $Message }
function Write-Warn    { param([string]$Message) Write-Host '[WARNING] ' -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Skip    { param([string]$Message) Write-Host '[SKIP] '    -ForegroundColor Cyan   -NoNewline; Write-Host $Message }

# Everything flagged here is replayed as a summary when the script finishes, which
# is the whole point of the Windows port: nothing is silently dropped.
$script:Flagged = [System.Collections.Generic.List[object]]::new()

function Write-Unsupported {
    param([string]$Name, [string]$Reason, [string]$Substitute)
    $script:Flagged.Add([pscustomobject]@{ Kind = 'UNSUPPORTED'; Name = $Name; Reason = $Reason; Substitute = $Substitute })
    Write-Host '[UNSUPPORTED] ' -ForegroundColor Red -NoNewline
    Write-Host "$Name - $Reason"
    if ($Substitute) { Write-Host "              -> $Substitute" -ForegroundColor DarkGray }
}

function Write-NoOp {
    param([string]$Name, [string]$Reason)
    $script:Flagged.Add([pscustomobject]@{ Kind = 'NO-OP'; Name = $Name; Reason = $Reason; Substitute = $null })
    Write-Host '[NO-OP] ' -ForegroundColor DarkGray -NoNewline
    Write-Host "$Name - $Reason" -ForegroundColor DarkGray
}

# Application only: Windows PowerShell aliases curl and wget to Invoke-WebRequest,
# and a stale alias would make these checks lie about a missing binary.
function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Get-CommandPath {
    param([Parameter(Mandatory)][string]$Name)
    (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}

# Counterpart of the PATH export in install-required.sh: persist it for new shells
# and patch the current process so later detection in this same run sees it.
function Add-UserPath {
    param([Parameter(Mandatory)][string]$Directory)

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($current) { $entries = @($current -split ';' | Where-Object { $_ -ne '' }) }

    if ($entries -notcontains $Directory) {
        if ($DryRun) {
            Write-Log "[dry-run] would add $Directory to the user PATH."
        } else {
            [Environment]::SetEnvironmentVariable('Path', ((@($entries) + $Directory) -join ';'), 'User')
            Write-Log "Added $Directory to the user PATH."
        }
    }

    if (($env:Path -split ';') -notcontains $Directory) {
        $env:Path = "$Directory;$env:Path"
    }
}

function Test-WingetPackage {
    param([Parameter(Mandatory)][string]$Id)
    $null = winget list --id $Id --exact --disable-interactivity --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Installs only what is not already present, the equivalent of ensure_packages.
function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [string]$Command,
        [string[]]$ExtraArgs = @()
    )

    if ($Command -and (Test-Command $Command)) {
        Write-Skip "$Name is already installed at $(Get-CommandPath $Command)."
        return
    }
    if (Test-WingetPackage -Id $Id) {
        Write-Skip "$Name is already installed (winget package $Id)."
        return
    }
    if ($DryRun) {
        $extra = if ($ExtraArgs.Count -gt 0) { ' ' + ($ExtraArgs -join ' ') } else { '' }
        Write-Log "[dry-run] winget install --id $Id$extra"
        return
    }

    Write-Log "Installing $Name ($Id)..."
    $wingetArgs = @(
        'install', '--id', $Id, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    ) + $ExtraArgs

    & winget @wingetArgs | Out-Host
    $code = $LASTEXITCODE

    # winget returns non-zero for "already at the latest version" and after installers
    # that ask for a reboot. Re-reading the package list is more reliable than trying
    # to keep a table of its error codes current.
    if ($code -eq 0 -or (Test-WingetPackage -Id $Id)) {
        Write-Success "$Name installed."
    } else {
        Write-Warn "$Name did not install cleanly (winget exit code $code)."
    }
}

# 0. Option parsing and environment detection
function Show-Usage {
    Write-Host @'
Usage: pwsh -File install-required.ps1 [options]

Options:
  -NoGui    Skip GUI applications (Zen Browser, Zed, Discord, Nerd Font).
  -Gui      Install GUI applications (the default on a desktop).
  -DryRun   Print every step without installing anything. Useful because the
            Visual Studio Build Tools step is a multi-GB download.
  -Help     Show this message.

Applications with no Windows build are reported as [UNSUPPORTED] together with
their substitute, and things Windows already provides as [NO-OP]. Both are
summarised when the script finishes.
'@
}

if ($Help) { Show-Usage; exit 0 }

if ($Gui -and $NoGui) {
    Write-Warn 'Pass either -Gui or -NoGui, not both.'
    exit 1
}

# There is no WSL case to detect here - this script *is* the Windows side - so GUI
# applications are on unless you turn them off for a Server or headless box.
$InstallGui = -not $NoGui
if (-not $InstallGui) {
    Write-Log 'GUI applications will be skipped (Zen Browser, Zed, Discord, Nerd Font).'
}
if ($DryRun) {
    Write-Log 'Dry run: nothing will actually be installed.'
}

# 1. Safe environment detection (replaces the Debian/Arch detection)
if (-not (Test-Command 'winget')) {
    Write-Warn 'winget was not found. Install "App Installer" from the Microsoft Store, or get it'
    Write-Warn 'from https://github.com/microsoft/winget-cli/releases, then re-run this script.'
    exit 1
}
Write-Log "Detected Windows $([Environment]::OSVersion.Version), winget $((& winget --version) -join '')."

# Everything below installs into the user profile. Running elevated would put rustup,
# fnm, the dotnet tools and the Neovim config into the administrator's profile
# instead - the same reason bootstrap.sh refuses to run as root. This is a warning
# rather than a refusal because the Build Tools and font steps do want UAC.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Warn 'Running elevated. rustup, fnm, the dotnet tools and the Neovim config will land in'
    Write-Warn "the administrator profile ($HOME), not your normal one. Prefer running this"
    Write-Warn 'unelevated and letting the individual installers prompt for UAC.'
}

# Make locally installed tools visible so detection works in a fresh shell
$LocalBin = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Path $LocalBin -Force | Out-Null
Add-UserPath $LocalBin

# 2. Core Prerequisites
# git, unzip and gzip are Neovim dependencies: plugins are cloned and release
# archives unpacked during install. ripgrep and fd back Telescope's live_grep
# and file finder.
Write-Log 'Checking core prerequisites...'

foreach ($builtin in @('curl', 'tar')) {
    if (Test-Command $builtin) {
        Write-Skip "$builtin ships with Windows ($(Get-CommandPath $builtin))."
    } else {
        Write-Warn "$builtin is expected to ship with Windows 10 1803+ but is not on PATH."
    }
}

Install-WingetPackage -Id 'Git.Git'                 -Name 'git'     -Command 'git'
Install-WingetPackage -Id 'junegunn.fzf'            -Name 'fzf'     -Command 'fzf'
Install-WingetPackage -Id 'jqlang.jq'               -Name 'jq'      -Command 'jq'
Install-WingetPackage -Id 'BurntSushi.ripgrep.MSVC' -Name 'ripgrep' -Command 'rg'
Install-WingetPackage -Id 'sharkdp.fd'              -Name 'fd'      -Command 'fd'
Install-WingetPackage -Id 'GnuPG.GnuPG'             -Name 'gnupg'   -Command 'gpg'
Install-WingetPackage -Id 'JernejSimoncic.Wget'     -Name 'wget'    -Command 'wget'
Install-WingetPackage -Id '7zip.7zip'               -Name '7-Zip'   -Command '7z'

Write-NoOp 'ca-certificates' 'Windows manages its own certificate store.'
Write-NoOp 'unzip / gzip' 'Expand-Archive and the bundled tar.exe unpack everything this script downloads.'
Write-NoOp 'sed' 'not needed by a PowerShell script; Git for Windows ships one in usr\bin anyway.'
Write-NoOp 'fdfind -> fd shim' 'a Debian packaging quirk; the winget fd package installs fd.exe directly.'

# 3. Development Essentials Setup
# Neovim needs a C compiler: treesitter parsers are compiled with cc. On Windows the
# same toolchain is what rustup's default stable-msvc target links against, so one
# Build Tools install covers both.
function Get-CppToolchain {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $found = & $vswhere -products '*' -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $found) { return ($found | Select-Object -First 1) }
    }
    return $null
}

Write-Log 'Checking build essentials...'
$vcPath = Get-CppToolchain
if ($vcPath) {
    Write-Skip "Visual C++ build tools are already installed at $vcPath."
} elseif (Test-Command 'cl') {
    Write-Skip "cl.exe is already on PATH at $(Get-CommandPath 'cl')."
} else {
    Write-Log 'Installing Visual Studio 2022 Build Tools with the C++ workload (large, multi-GB download)...'
    Install-WingetPackage -Id 'Microsoft.VisualStudio.2022.BuildTools' -Name 'VS 2022 Build Tools' -ExtraArgs @(
        '--override', '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )
}

# 4. tree-sitter CLI (Neovim dependency)
# nvim-treesitter shells out to the tree-sitter CLI to build any parser it cannot
# fetch prebuilt, and :checkhealth flags it as missing otherwise. There is no winget
# package, so take the latest upstream release binary. The .zip asset is used rather
# than the .gz the Linux script takes, because Expand-Archive handles zip natively.
function Install-TreeSitterBinary {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        'x86'   { 'x86' }
        default { $null }
    }
    if (-not $arch) {
        Write-Warn "No tree-sitter release build for $env:PROCESSOR_ARCHITECTURE. Skipping."
        return $false
    }

    $asset  = "tree-sitter-cli-windows-$arch.zip"
    $url    = "https://github.com/tree-sitter/tree-sitter/releases/latest/download/$asset"
    $tmpdir = Join-Path ([IO.Path]::GetTempPath()) ('tree-sitter-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpdir -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmpdir $asset)
        Expand-Archive -Path (Join-Path $tmpdir $asset) -DestinationPath $tmpdir -Force

        $exe = Get-ChildItem -Path $tmpdir -Filter 'tree-sitter*.exe' -Recurse | Select-Object -First 1
        if (-not $exe) {
            Write-Warn 'The downloaded tree-sitter archive contained no executable.'
            return $false
        }

        Move-Item -Path $exe.FullName -Destination (Join-Path $LocalBin 'tree-sitter.exe') -Force
        return $true
    } catch {
        Write-Warn "Could not install tree-sitter: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -Path $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Command 'tree-sitter') {
    Write-Skip "tree-sitter CLI is already installed at $(Get-CommandPath 'tree-sitter')."
} elseif ($DryRun) {
    Write-Log '[dry-run] would download the latest tree-sitter CLI release into ~\.local\bin.'
} else {
    Write-Log 'Installing the latest tree-sitter CLI from the GitHub releases page...'
    # Best effort: the function warns for itself, and an unhandled throw would take
    # the whole script down with it otherwise.
    if (Install-TreeSitterBinary) {
        Write-Success "tree-sitter CLI installed to $LocalBin."
    } else {
        Write-Warn 'tree-sitter CLI not installed; nvim-treesitter cannot build parsers from source.'
    }
}

# 5. Editors and clipboard support
Write-NoOp 'xclip / wl-clipboard / win32yank' 'Neovim on Windows talks to the Win32 clipboard directly, so the + and * registers work with no bridge.'

# The nvim config in $NvimConfigRepo uses vim.pack, which needs Neovim 0.12+. Unlike
# Debian, winget carries a current build, so there is no release-tarball fallback
# here - but the version is still checked in case that ever regresses.
$NvimMinMajor = 0
$NvimMinMinor = 12

# The full string as Neovim reports it, including any -dev suffix.
function Get-NvimVersionText {
    if (-not (Test-Command 'nvim')) { return $null }
    $line = (& nvim --version 2>$null | Select-Object -First 1)
    if ($line -match 'NVIM v(\S+)') { return $Matches[1] }
    return $null
}

function Test-NvimIsNewEnough {
    $text = Get-NvimVersionText
    if (-not ($text -match '^(\d+)\.(\d+)')) { return $false }
    return ([version]::new([int]$Matches[1], [int]$Matches[2]) -ge [version]::new($NvimMinMajor, $NvimMinMinor))
}

if (Test-NvimIsNewEnough) {
    Write-Skip "Neovim $(Get-NvimVersionText) is already installed at $(Get-CommandPath 'nvim')."
} else {
    Install-WingetPackage -Id 'Neovim.Neovim' -Name 'Neovim'
    if ((-not $DryRun) -and (-not (Test-NvimIsNewEnough))) {
        Write-Warn "Neovim install did not produce a $NvimMinMajor.$NvimMinMinor+ build. Your nvim config may not load."
    }
}

# 6. Shell Setup
# zsh has no native Windows build, so the whole Oh My Zsh stack is replaced by the
# closest PowerShell equivalents. Like the Linux script, nothing here writes to the
# shell config itself - the snippet to paste is printed at the end instead.
Write-Log 'Checking shell tooling...'
Write-Unsupported 'zsh' 'no native Windows build; it exists only under WSL, MSYS2 or Cygwin.' 'PowerShell 7, with the equivalents below'
Write-Unsupported 'Oh My Zsh' 'a zsh framework, so it cannot run without zsh.' 'oh-my-posh, for prompt themes'
Write-Unsupported 'zsh-autosuggestions' 'a zsh plugin.' 'PSReadLine -PredictionSource HistoryAndPlugin'
Write-Unsupported 'zsh-syntax-highlighting' 'a zsh plugin.' 'PSReadLine syntax colouring, which is built in'
Write-Unsupported 'zsh-completions' 'a zsh plugin.' 'PSReadLine menu completion plus per-tool argument completers'
Write-Unsupported 'chsh' 'Windows has no login shell to change.' 'set PowerShell 7 as the default profile in Windows Terminal'

Install-WingetPackage -Id 'JanDeDobbeleer.OhMyPosh' -Name 'oh-my-posh' -Command 'oh-my-posh'

# PSReadLine ships with PowerShell, but predictive suggestions need 2.2+.
$psrl = Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ($psrl -and $psrl.Version -ge [version]'2.2.0') {
    Write-Skip "PSReadLine $($psrl.Version) already supports predictive suggestions."
} elseif ($DryRun) {
    Write-Log '[dry-run] would install PSReadLine 2.2+ for the current user.'
} else {
    Write-Log 'Installing a PSReadLine new enough for predictive suggestions...'
    try {
        Install-Module PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        Write-Success 'PSReadLine installed for the current user.'
    } catch {
        Write-Warn "Could not install PSReadLine: $($_.Exception.Message)"
    }
}

# 7. Terminal Deployment
Write-Unsupported 'Ghostty' 'macOS and Linux only. A Windows GUI is on the roadmap but unreleased, and the Windows ports on GitHub are unaffiliated with the project.' 'Windows Terminal or WezTerm, or run Ghostty inside WSL. ghostty/config.ghostty stays in this repo for your Linux machines.'

# 8. Git Tooling
# No dynamic fallback needed here: unlike apt, winget carries a current lazygit.
Install-WingetPackage -Id 'JesseDuffield.lazygit' -Name 'Lazygit' -Command 'lazygit'

# 9. Browser Setup (Zen Browser)
if (-not $InstallGui) {
    Write-Skip 'Zen Browser (GUI application).'
} else {
    Install-WingetPackage -Id 'Zen-Team.Zen-Browser' -Name 'Zen Browser'
}

# 10. Editor Setup (Zed Editor)
# Zed supports Windows officially, and has since its 1.0 stable release, so this is
# a plain winget install rather than the shell installer the Linux script pipes.
if (-not $InstallGui) {
    Write-Skip 'Zed (GUI application).'
} else {
    Install-WingetPackage -Id 'ZedIndustries.Zed' -Name 'Zed'
}

# 11. Language Runtime (.NET SDK 10.0 Setup)
# winget routes to the official Microsoft package, so the dotnet-install.sh dance
# the Linux script needs on Debian does not apply.
Install-WingetPackage -Id 'Microsoft.DotNet.SDK.10' -Name '.NET SDK 10' -Command 'dotnet'

# 12. Rust toolchain
if (Test-Command 'rustup') {
    Write-Skip "Rust is already installed at $(Get-CommandPath 'rustup')."
} else {
    Install-WingetPackage -Id 'Rustlang.Rustup' -Name 'Rust (rustup)' -Command 'rustup'
    # stable-msvc links against the Build Tools installed in step 3; the GNU toolchain
    # would need a separate MinGW.
    if ((Test-Command 'rustup') -and (-not $DryRun)) {
        & rustup default stable-msvc | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'Rust default toolchain set to stable-msvc.'
        } else {
            Write-Warn 'Could not set the default Rust toolchain. Run: rustup default stable-msvc'
        }
    }
}

# 13. Node
# nvm-sh is a POSIX shell script and cannot run under PowerShell. fnm is used rather
# than nvm-windows because it is per-user, needs no elevation to switch versions, and
# keeps the --lts flag the Linux script relies on.
Write-Unsupported 'nvm (nvm-sh)' 'a POSIX shell script; it cannot run under PowerShell.' 'fnm - per-user, no elevation to switch versions, and it keeps --lts'

Install-WingetPackage -Id 'Schniz.fnm' -Name 'fnm' -Command 'fnm'

if ((Test-Command 'fnm') -and (-not $DryRun)) {
    $aliases = & fnm list 2>$null
    if ($LASTEXITCODE -eq 0 -and (($aliases -join "`n") -match 'default')) {
        Write-Skip 'A default Node version is already aliased.'
    } else {
        Write-Log 'Installing the latest Node LTS...'
        & fnm install --lts | Out-Host
        if ($LASTEXITCODE -eq 0) {
            & fnm default lts-latest | Out-Host
            Write-Success 'Latest Node LTS installed and set as the default.'
        } else {
            Write-Warn "Could not install Node. Run 'fnm install --lts' by hand."
        }
    }
}

# 14. Nerd Font (JetBrains Mono)
# Only useful where something renders it, so it follows the GUI flag.
function Test-NerdFontInstalled {
    $dirs = @(
        (Join-Path $env:WINDIR 'Fonts'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
    )
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) { continue }
        $hit = Get-ChildItem -Path $dir -Filter 'JetBrainsMono*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Nerd|NF' } | Select-Object -First 1
        if ($hit) { return $true }
    }
    return $false
}

if (-not $InstallGui) {
    Write-Skip 'JetBrainsMono Nerd Font (GUI application).'
} elseif (Test-NerdFontInstalled) {
    Write-Skip 'JetBrainsMono Nerd Font is already installed.'
} else {
    Install-WingetPackage -Id 'DEVCOM.JetBrainsMonoNerdFont' -Name 'JetBrainsMono Nerd Font'
}

Write-NoOp 'Noto Color Emoji' 'Windows ships Segoe UI Emoji, so emoji render without an extra font.'

# 15. Neovim configuration
# Neovim reads its config from %LOCALAPPDATA%\nvim on Windows, not ~/.config/nvim.
$NvimConfigRepo = 'https://github.com/AndreasVu/nvim.git'
$NvimConfigDir  = Join-Path $env:LOCALAPPDATA 'nvim'

if (Test-Path (Join-Path $NvimConfigDir '.git')) {
    Write-Skip "Neovim config already cloned at $NvimConfigDir."
} else {
    if (Test-Path $NvimConfigDir) {
        $backup = "$NvimConfigDir.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warn "$NvimConfigDir exists but is not a git checkout. Moving it to $backup."
        if (-not $DryRun) { Move-Item -Path $NvimConfigDir -Destination $backup }
    }

    if ($DryRun) {
        Write-Log "[dry-run] would clone $NvimConfigRepo into $NvimConfigDir."
    } else {
        Write-Log "Cloning Neovim config from $NvimConfigRepo..."
        & git clone $NvimConfigRepo $NvimConfigDir | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Neovim config cloned to $NvimConfigDir."
            Write-Log 'Plugins install on the first nvim launch via vim.pack.'
        } else {
            Write-Warn "Could not clone the Neovim config. Clone it manually into $NvimConfigDir."
        }
    }
}

# 16. zoxide
Install-WingetPackage -Id 'ajeetdsouza.zoxide' -Name 'zoxide' -Command 'zoxide'

# 17. Discord
# Unlike Debian, Windows has a first-party winget package, so no deb download.
if (-not $InstallGui) {
    Write-Skip 'Discord (GUI application).'
} else {
    Install-WingetPackage -Id 'Discord.Discord' -Name 'Discord'
}

# 18. .NET global tools
$DotnetTools = Join-Path $HOME '.dotnet\tools'
Add-UserPath $DotnetTools

if (-not (Test-Command 'dotnet')) {
    Write-Warn 'dotnet is not on PATH. Skipping .NET global tools. Open a new shell and re-run if the SDK was just installed.'
} elseif (Test-Command 'lazydotnet') {
    Write-Skip 'lazydotnet is already installed.'
} elseif ($DryRun) {
    Write-Log '[dry-run] dotnet tool install --global lazydotnet'
} else {
    Write-Log 'Installing lazydotnet...'
    & dotnet tool install --global lazydotnet | Out-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Success 'lazydotnet installed.'
    } else {
        Write-Warn 'lazydotnet installation failed.'
    }
}

# Summary of everything this platform could not do
Write-Host ''
Write-Success 'Script completion reached! Base applications deployment finished cleanly.'

$unsupported = @($script:Flagged | Where-Object { $_.Kind -eq 'UNSUPPORTED' })
$noop        = @($script:Flagged | Where-Object { $_.Kind -eq 'NO-OP' })

# Pad to the widest name in each group, so a long entry does not push its reason
# out of the column and break the alignment for everything else.
function Get-NameColumnWidth {
    param([object[]]$Items)
    return ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
}

if ($unsupported.Count -gt 0) {
    $width = Get-NameColumnWidth $unsupported
    Write-Host ''
    Write-Host 'Not available on Windows' -ForegroundColor Red
    Write-Host ('-' * 76)
    foreach ($item in $unsupported) {
        Write-Host ("  {0,-$width}  {1}" -f $item.Name, $item.Reason)
        if ($item.Substitute) {
            Write-Host ("  {0,-$width}  -> {1}" -f '', $item.Substitute) -ForegroundColor DarkGray
        }
    }
}

if ($noop.Count -gt 0) {
    $width = Get-NameColumnWidth $noop
    Write-Host ''
    Write-Host 'Not needed on Windows' -ForegroundColor DarkGray
    Write-Host ('-' * 76)
    foreach ($item in $noop) {
        Write-Host ("  {0,-$width}  {1}" -f $item.Name, $item.Reason) -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Log 'Next: add this to your PowerShell profile (notepad $PROFILE). Nothing above wrote to it,'
Write-Log 'for the same reason the Linux scripts never touch the dotfiles-managed .zshrc:'
Write-Host @'

    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

    oh-my-posh init pwsh | Invoke-Expression
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

'@ -ForegroundColor DarkGray
Write-Log 'Then start a new PowerShell session to pick up the PATH changes.'
