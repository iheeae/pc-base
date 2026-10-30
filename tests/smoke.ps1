# Tabula Rasa: «дымовая» проверка окна на настоящей Windows (CI): окно открывается с полным каталогом, ждёт фоновую
# проверку статусов (реестр, winget), проходит по разделам, показывает план и закрывается само.
#   powershell -ExecutionPolicy Bypass -STA -File tests\smoke.ps1
# Ошибки окна (lib\gui.ps1, Write-PbUiError) пишутся в logs\ui-error_*.txt — их наличие и есть провал проверки.
# Мои данные не подключаются: DataRoot — пустая временная папка.

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot
$env:TR_SMOKE = '1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tabula-rasa-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
. (Join-Path $root 'lib\splash.ps1'); . (Join-Path $root 'lib\common.ps1'); . (Join-Path $root 'lib\gui.ps1'); . (Join-Path $root 'lib\configs.ps1')
$script:PB.Root = $root; $script:PB.DataRoot = Join-Path $tmp 'data'; $script:PB.LogDir = Join-Path $tmp 'logs'
New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
$Apps = (Import-PowerShellDataFile (Join-Path $root 'catalog\apps.psd1')).Apps
. (Join-Path $root 'catalog\tweaks.ps1')
Get-EnvInfo
$Tweaks = @($Tweaks | Where-Object { $_.Os -contains $script:PB.Os })
$Apps = @($Apps | Where-Object { -not $_.Os -or $_.Os -contains $script:PB.Os })

$fail = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
# сторож: раз в 5 с — что на экране; через 300 с закрыть все окна (модальные тоже), чтобы проверка не висела
Add-Type -AssemblyName PresentationFramework, WindowsBase
$watch = New-Object Windows.Threading.DispatcherTimer
$watch.Interval = [TimeSpan]::FromSeconds(5)
$watch.add_Tick({
    $wins = @(); try { $wins = @([Windows.Application]::Current.Windows | ForEach-Object { "$($_.GetType().Name) «$($_.Title)» visible=$($_.IsVisible)" }) } catch { }
    Write-Host ("  [{0,3} с] окон: {1}: {2}" -f [int]$sw.Elapsed.TotalSeconds, $wins.Count, ($wins -join '; '))
    if ($sw.Elapsed.TotalSeconds -gt 300) {
        $script:SmokeTimeout = $true
        $watch.Stop()
        foreach ($w in @([Windows.Application]::Current.Windows)) { try { $w.Close() } catch { } }
    }
})
$watch.Start()
try {
    $r = Show-SelectionDialog -Apps $Apps -Tweaks $Tweaks -Notices @('Проверка окна') -DryRun $true -IsDomain $false -RunInWindow $true
    Write-Host "Окно закрылось через $([int]$sw.Elapsed.TotalSeconds) с"
} catch {
    $fail += "окно упало: $($_.Exception.Message) $($_.ScriptStackTrace)"
}
$watch.Stop()
if ($script:SmokeTimeout) { $fail += 'окно не закрылось само за 300 с (см. строки сторожа выше: какие окна были открыты)' }
foreach ($f in @(Get-ChildItem $script:PB.LogDir -Filter 'ui-error_*.txt' -ErrorAction SilentlyContinue)) {
    $fail += "ошибка в окне: " + (Get-Content $f.FullName -Raw -Encoding UTF8)
}
$own = @($Error | Where-Object { $_.InvocationInfo -and $_.InvocationInfo.ScriptName -match '[\\/](lib|catalog)[\\/]' } |
    ForEach-Object { "$($_.Exception.Message) @ $(Split-Path $_.InvocationInfo.ScriptName -Leaf):$($_.InvocationInfo.ScriptLineNumber)" } | Select-Object -Unique)
if ($own.Count) { Write-Host "Ошибки в журнале PowerShell ($($own.Count)):"; $own | ForEach-Object { Write-Host "  $_" } }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($fail.Count) {
    $fail | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red; if ($env:GITHUB_ACTIONS) { Write-Host ("::error title=tests/smoke.ps1::" + ($_ -replace '%', '%25' -replace '\r?\n', '%0A')) } }
    exit 1
}
if ($own.Count -and $env:GITHUB_ACTIONS) { Write-Host ("::warning title=tests/smoke.ps1::" + (($own | Select-Object -First 10) -join '%0A')) }
Write-Host 'Окно открылось, отработало и закрылось без ошибок' -ForegroundColor Green
exit 0
