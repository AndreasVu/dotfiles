#Requires -Version 7.0

# Windows counterpart of setup-git-identity.sh. Writes the git identity files that
# gitconfig includes. Both live in $HOME, outside this repo, so no email address is
# ever tracked here.
#
#   ~/.gitconfig-identity  default identity
#   ~/.gitconfig-work      identity for repos under ~/work/
#
# git on Windows expands ~ to %USERPROFILE%, so the include paths in gitconfig need
# no change. Safe to re-run: existing files are left alone unless -Force is passed.

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Write-Log     { param([string]$Message) Write-Host '[GIT] '  -ForegroundColor Blue   -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host '[GIT] '  -ForegroundColor Green  -NoNewline; Write-Host $Message }
function Write-Warn    { param([string]$Message) Write-Host '[GIT] '  -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Skip    { param([string]$Message) Write-Host '[SKIP] ' -ForegroundColor Cyan   -NoNewline; Write-Host $Message }

if ($Help) {
    Write-Host 'Usage: pwsh -File setup-git-identity.ps1 [-Force]'
    Write-Host '  -Force  Overwrite existing identity files.'
    exit 0
}

$IdentityFile = Join-Path $HOME '.gitconfig-identity'
$WorkFile     = Join-Path $HOME '.gitconfig-work'

function Test-IsSymlink {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    return ((Get-Item $Path -Force).LinkType -eq 'SymbolicLink')
}

if ((-not $Force) -and (Test-Path $IdentityFile) -and (Test-Path $WorkFile) -and
    (-not (Test-IsSymlink $IdentityFile)) -and (-not (Test-IsSymlink $WorkFile))) {
    Write-Skip 'Git identity already configured. Re-run with -Force to change it.'
    exit 0
}

# Unattended runs must not hang on a prompt. IsInputRedirected is the real
# equivalent of the shell's [ ! -t 0 ]; UserInteractive alone stays true even when
# stdin is a pipe or a closed handle, which is exactly the case that would hang.
if ([Console]::IsInputRedirected -or (-not [Environment]::UserInteractive)) {
    Write-Warn 'Not running interactively; skipping the git identity prompt.'
    Write-Warn 'Run setup-git-identity.ps1 by hand, or git will not know who you are.'
    exit 0
}

if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    Write-Warn 'git is not on PATH. Run install-required.ps1 first.'
    exit 1
}

function Read-WithDefault {
    param([string]$Prompt, [string]$Default)
    if ($Default) {
        $answer = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        return $answer.Trim()
    }
    return (Read-Host $Prompt).Trim()
}

function Get-ConfigValue {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return '' }
    $value = & git config --file $File $Key 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return ($value | Select-Object -First 1)
}

function Write-Identity {
    param([string]$File, [string]$Name, [string]$Email)

    # An older version of this repo symlinked these paths into the dotfiles
    # checkout. Writing through such a link would put the email back into a
    # tracked file, so replace the link with a real file.
    if (Test-IsSymlink $File) {
        Write-Warn "$File is a symlink; replacing it with a real file."
        Remove-Item $File -Force
    }

    # No umask equivalent on Windows. These sit directly in %USERPROFILE%, which is
    # already restricted to this account and SYSTEM by its inherited ACL.
    # utf8NoBOM matters: a BOM in a git config file is not parsed away.
    $content = "[user]`n`tname = $Name`n`temail = $Email`n"
    Set-Content -Path $File -Value $content -Encoding utf8NoBOM -NoNewline
}

Write-Log 'Setting up your git identity. These files stay out of the dotfiles repo.'

$existingName  = Get-ConfigValue $IdentityFile 'user.name'
$existingEmail = Get-ConfigValue $IdentityFile 'user.email'

$gitName  = Read-WithDefault 'Your name' $existingName
$gitEmail = Read-WithDefault 'Default git email' $existingEmail

if ([string]::IsNullOrWhiteSpace($gitName) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
    Write-Warn 'Name and email are both required. Nothing written.'
    exit 1
}

Write-Identity -File $IdentityFile -Name $gitName -Email $gitEmail
Write-Success "Wrote $IdentityFile"

$existingWorkName  = Get-ConfigValue $WorkFile 'user.name'
$existingWorkEmail = Get-ConfigValue $WorkFile 'user.email'

Write-Host ''
if ($existingWorkEmail -and ($existingWorkEmail -ne $gitEmail)) {
    Write-Log 'Repos under ~/work/ use a separate identity. Enter - to drop it and reuse the default.'
} else {
    Write-Log 'Repos under ~/work/ can use a separate identity. Leave it blank to reuse the default.'
}
$workEmail = Read-WithDefault 'Work git email' $existingWorkEmail
if ($workEmail -eq '-') { $workEmail = '' }

if ([string]::IsNullOrWhiteSpace($workEmail)) {
    Write-Identity -File $WorkFile -Name $gitName -Email $gitEmail
    Write-Log 'No separate work email; ~/work/ will use the default identity.'
} else {
    $defaultWorkName = if ($existingWorkName) { $existingWorkName } else { $gitName }
    $workName = Read-WithDefault 'Work name' $defaultWorkName
    if ([string]::IsNullOrWhiteSpace($workName)) { $workName = $gitName }
    Write-Identity -File $WorkFile -Name $workName -Email $workEmail
}
Write-Success "Wrote $WorkFile"

Write-Host ''
Write-Success 'Git identity configured.'
Write-Log "Default:  $(Get-ConfigValue $IdentityFile 'user.name') <$(Get-ConfigValue $IdentityFile 'user.email')>"
Write-Log "Work:     $(Get-ConfigValue $WorkFile 'user.name') <$(Get-ConfigValue $WorkFile 'user.email')>"
