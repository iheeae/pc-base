# Профиль PowerShell 7, встроенный в Tabula Rasa. Собственный профиль хранится в configs\pwsh_profile.ps1
# «Моих данных» (C:\tabula-rasa-private) и заменяет этот. Изменения вносятся там: при следующем прогоне setup.ps1
# установленный профиль перезаписывается (предыдущий сохраняется как .bak).

# --- PSReadLine: подсказки из истории, Tab-меню, поиск по истории стрелками ---
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -HistoryNoDuplicates -BellStyle None
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit
}

# --- промпт: путь, ветка git, # для админа ---
$script:PbIsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$script:PbHasGit = [bool](Get-Command git -ErrorAction Ignore)

function prompt {
    $code = $LASTEXITCODE
    $path = $PWD.ProviderPath
    if ($path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) { $path = '~' + $path.Substring($HOME.Length) }

    $branch = $null
    if ($script:PbHasGit) {
        $branch = git branch --show-current 2>$null
        if (-not $branch -and $LASTEXITCODE -eq 0) { $branch = '(detached)' }
    }

    Write-Host $path -NoNewline -ForegroundColor Cyan
    if ($branch) { Write-Host " [$branch]" -NoNewline -ForegroundColor Yellow }
    $global:LASTEXITCODE = $code
    if ($script:PbIsAdmin) { Write-Host ' #' -NoNewline -ForegroundColor Red; return ' ' }
    return ' > '
}

# --- алиасы и мелочи ---
function ll { Get-ChildItem -Force @args }
function which ([string]$Name) { Get-Command $Name -All | ForEach-Object { if ($_.Source) { $_.Source } else { $_.Definition } } }
function touch {
    foreach ($f in $args) {
        if (Test-Path $f) { (Get-Item $f).LastWriteTime = Get-Date } else { New-Item -ItemType File -Path $f | Out-Null }
    }
}
function cdb { Set-Location 'C:\tabula-rasa' }
Set-Alias -Name g -Value git
