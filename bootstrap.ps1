# pc-base bootstrap -- public loader. No secrets, no personal data.
# ASCII only on purpose: it is fetched with irm and run with iex in Windows PowerShell 5.1.
#
# On a clean Windows, open PowerShell AS ADMINISTRATOR and run:
#   irm iheeae.github.io/pc-base | iex
# Old Windows 10 without TLS 1.2 by default:
#   [Net.ServicePointManager]::SecurityProtocol='Tls12'; irm iheeae.github.io/pc-base | iex
# Same file straight from the repo:
#   irm https://raw.githubusercontent.com/iheeae/pc-base/master/bootstrap.ps1 | iex
#
# What it does (no GitHub login needed):
#   1. makes sure winget works
#   2. installs Git
#   3. clones the public repo iheeae/pc-base into C:\pc-base; an old copy there (another origin,
#      or no common history with origin/master) is moved to C:\pc-base.old_<date>, nothing is deleted
#   4. starts C:\pc-base\setup.ps1 (selection window)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo   = 'iheeae/pc-base'
$Branch = 'master'
$Dest   = 'C:\pc-base'

function Say ($t, $c = 'Cyan') { Write-Host "==> $t" -ForegroundColor $c }
function Refresh-Path {
    $env:Path = @([Environment]::GetEnvironmentVariable('Path', 'Machine'),
                  [Environment]::GetEnvironmentVariable('Path', 'User'),
                  (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')) -join ';'
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Say 'Run PowerShell as Administrator and paste the command again.' 'Red'
    return
}

# ---------- 1. winget ----------
Refresh-Path
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Say 'winget not found, registering App Installer'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    Refresh-Path
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Say 'Installing winget via Microsoft.WinGet.Client module'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -AllowClobber
    Import-Module Microsoft.WinGet.Client -Force
    Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    Refresh-Path
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Say 'winget is still missing. Update "App Installer" from Microsoft Store and run again.' 'Red'
    return
}

# ---------- 2. git ----------
$null = winget list --id Git.Git -e --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) {
    Say 'Installing Git'
    winget install --id Git.Git -e --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}
Refresh-Path
$gitCmd = "$env:ProgramFiles\Git\cmd"
if ((Test-Path $gitCmd) -and ($env:Path -notlike "*$gitCmd*")) { $env:Path += ";$gitCmd" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Say 'git did not install, see the output above.' 'Red'
    return
}
git config --global core.quotepath false
git config --global --add safe.directory ($Dest -replace '\\', '/')

# ---------- 3. clone ----------
# The public repo started with a clean history: an old C:\pc-base (another origin, or the same URL
# without a common ancestor with origin/master) cannot be pulled. Move it aside, never delete.
function Test-OurClone ([string]$Dir) {
    if (-not (Test-Path (Join-Path $Dir '.git'))) { return $false }
    $origin = git -C $Dir remote get-url origin 2>$null
    if ($origin -notmatch ('github\.com[/:]' + [regex]::Escape($Repo) + '(\.git)?/?$')) { return $false }
    git -C $Dir fetch --quiet origin 2>$null
    if ($LASTEXITCODE -ne 0) { return $true }   # offline: nothing to judge by, keep it
    $null = git -C $Dir merge-base HEAD "origin/$Branch" 2>$null
    return ($LASTEXITCODE -eq 0)
}
if ((Test-Path $Dest) -and -not (Test-OurClone $Dest)) {
    $old = "$Dest.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Say "$Dest is an old copy of pc-base or something else -- moving it to $old" 'Yellow'
    Set-Location $env:SystemRoot
    $moved = $false
    for ($i = 0; $i -lt 30 -and -not $moved; $i++) {
        try { Move-Item $Dest $old -ErrorAction Stop; $moved = $true }
        catch {
            if ($i -eq 0) { Say 'The folder is busy (an old pc-base window?), waiting up to 60 s' 'Yellow' }
            Start-Sleep -Seconds 2
        }
    }
    if (-not $moved) { Say "Could not move $Dest. Close windows and editors that use it and run again." 'Red'; return }
}
if (Test-Path (Join-Path $Dest '.git')) {
    Say "Updating $Dest"
    git -C $Dest pull --ff-only
} else {
    Say "Cloning $Repo into $Dest"
    git clone --branch $Branch "https://github.com/$Repo.git" $Dest
    if ($LASTEXITCODE -ne 0) { Say 'Clone failed' 'Red'; return }
}

# ---------- 4. setup ----------
$setup = Join-Path $Dest 'setup.ps1'
if (-not (Test-Path $setup)) { Say "setup.ps1 not found in $Dest" 'Red'; return }
Say "Starting $setup" 'Green'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup -NoPull
