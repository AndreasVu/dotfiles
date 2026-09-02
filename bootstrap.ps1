#Requires -Version 7.0

# Single entrypoint for a fresh Windows machine, the counterpart of bootstrap.sh.
#   pwsh -File bootstrap.ps1
#
# There is no link step: dotbot links zshrc, zshenv, profile, bash_logout and the
# ghostty config, none of which have a Windows target, and Windows symlinks need
# Developer Mode or elevation. Configure git by hand as described in the README.

[CmdletBinding()]
param(
    [switch]$ToolsOnly,
    [switch]$SkipGit,
    [switch]$NoGui,
    [switch]$Gui,
    [switch]$DryRun,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Log     { param([string]$Message) Write-Host '[BOOTSTRAP] ' -ForegroundColor Blue   -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host '[BOOTSTRAP] ' -ForegroundColor Green  -NoNewline; Write-Host $Message }
function Write-Warn    { param([string]$Message) Write-Host '[BOOTSTRAP] ' -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Fail    { param([string]$Message) Write-Host '[BOOTSTRAP] ' -ForegroundColor Red    -NoNewline; Write-Host $Message; exit 1 }

function Show-Usage {
    Write-Host @'
Usage: pwsh -File bootstrap.ps1 [options]

Runs install-required.ps1 (packages, shell tooling, runtimes), then
setup-git-identity.ps1 (prompts for your git name and email). Both are safe to
re-run.

Options:
  -ToolsOnly  Run install-required.ps1 only, skip the git identity prompt.
  -SkipGit    Do not prompt for the git identity.
  -NoGui      Skip GUI applications (Zen Browser, Zed, Discord, Nerd Font).
  -Gui        Install GUI applications (the default on a desktop).
  -DryRun     Print every step without installing anything.
  -Help       Show this message.

The dotbot link step is Linux-only and is not run here. Applications with no
Windows build are reported as [UNSUPPORTED] with their substitute.
'@
}

if ($Help) { Show-Usage; exit 0 }

$BaseDir = $PSScriptRoot
Set-Location $BaseDir

# The Linux script refuses to run as root because oh-my-zsh, rustup, nvm and the
# symlinks would end up in /root. The same reasoning applies to an elevated shell
# here, but some Windows installers genuinely want UAC, so warn instead of refusing.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Write-Warn 'Running elevated. Per-user tools and the git identity will be written to the'
    Write-Warn "administrator profile ($HOME). Prefer an unelevated shell and let the individual"
    Write-Warn 'installers prompt for UAC.'
}

# Step 1 - tools
$installScript = Join-Path $BaseDir 'install-required.ps1'
if (-not (Test-Path $installScript)) { Write-Fail "install-required.ps1 not found in $BaseDir." }

Write-Log 'Step 1/2 - installing tools and runtimes...'
$toolArgs = @{}
if ($NoGui)  { $toolArgs['NoGui']  = $true }
if ($Gui)    { $toolArgs['Gui']    = $true }
if ($DryRun) { $toolArgs['DryRun'] = $true }
# A called .ps1 only updates $LASTEXITCODE when it exits explicitly, so clear it
# first: a stale non-zero code from an earlier command would read as a failure here.
$global:LASTEXITCODE = 0
& $installScript @toolArgs
if ($LASTEXITCODE -ne 0) { Write-Fail "Tool installation failed (exit code $LASTEXITCODE)." }
Write-Success 'Tools installed.'

# Step 2 - git identity
# The identity lives in ~/.gitconfig-identity and ~/.gitconfig-work, which are never
# tracked in this repo, so a public dotfiles repo exposes no email address.
if ($ToolsOnly -or $SkipGit) {
    Write-Warn 'Skipping the git identity prompt.'
} else {
    $gitScript = Join-Path $BaseDir 'setup-git-identity.ps1'
    if (Test-Path $gitScript) {
        Write-Log 'Step 2/2 - git identity...'
        & $gitScript
    } else {
        Write-Warn 'setup-git-identity.ps1 not found; skipping the git identity step.'
    }
}

Write-Success 'Bootstrap complete.'
Write-Log 'The dotfiles themselves are not linked on Windows. To pick up the shared git config:'
Write-Log "  git config --global include.path `"$(Join-Path $BaseDir 'gitconfig')`""
Write-Log 'Start a new PowerShell session to pick up the PATH changes.'
