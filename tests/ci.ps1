# Tabula Rasa: проверки перед коммитом из CLAUDE.md одним скриптом — локально и в CI (.github/workflows/ci.yml).
#   powershell -ExecutionPolicy Bypass -File tests\ci.ps1        (или pwsh -File tests/ci.ps1)
# Синтаксис, уникальность id, тон текстов, BOM, ASCII в bootstrap.ps1, личное, README соответствует каталогу.
# На Windows ещё: model.cs компилируется, разметка окон и заставки загружается в WPF (окна не показываются).
# Проверки без окна и без сети — отдельно: tests\run.ps1. Нужен git.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
Set-Location $root
$script:Fails = 0
function Report ([string]$Name, [string[]]$Bad) {
    $Bad = @($Bad | Where-Object { $_ })
    if ($Bad.Count) {
        $script:Fails++; Write-Host "FAIL $Name" -ForegroundColor Red; $Bad | Select-Object -First 30 | ForEach-Object { Write-Host "     $_" }
        if ($env:GITHUB_ACTIONS) { Write-Host "::error title=tests/ci.ps1::$Name — $((@($Bad) | Select-Object -First 5) -join '; ')" }
    }
    else { Write-Host "ok   $Name" -ForegroundColor Green }
}
$files = @(& git ls-files)

# синтаксис
$bad = foreach ($f in $files | Where-Object { $_ -match '\.(ps1|psd1)$' }) {
    $e = $null; [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$e)
    if ($e) { "${f}: $($e[0].Message) @ $($e[0].Extent.StartLineNumber)" }
}
Report "синтаксис ($($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))" $bad

# каталог грузится, id уникальны
$a = (Import-PowerShellDataFile (Join-Path $root 'catalog\apps.psd1')).Apps; . (Join-Path $root 'catalog\tweaks.ps1')
Report 'каталог: id уникальны' (@($a.Id) + @($Tweaks.Id) | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name })
Report 'каталог: у winget-программ есть WingetId, у сайта — Signer и HTTPS' (@($a | ForEach-Object {
    if ($_.Source -eq 'winget' -and -not $_.WingetId) { "$($_.Id): нет WingetId" }
    if ($_.Source -eq 'web' -and (-not $_.Signer -or $_.PageUrl -notmatch '^https://' -or $_.BaseUrl -notmatch '^https://')) { "$($_.Id): нет Signer или не HTTPS" }
    if ($_.Source -notin 'winget', 'web') { "$($_.Id): источник $($_.Source)" } }))
Report 'твики: Apply, Os, Phase' (@($Tweaks | ForEach-Object {
    if (-not $_.Apply) { "$($_.Id): нет Apply" }
    if (-not $_.Os -or @($_.Os | Where-Object { $_ -notin '10', '11' }).Count) { "$($_.Id): Os" }
    if ($_.Phase -notin 'pre', 'post') { "$($_.Id): Phase" } }))

# тон текстов программы
$tone = '(?<!\p{L})(ты|твой|твоя|твоё|твои|твоих|твоим|твоей|тебе|тебя|снести|снесёт|сносит|снос|репа|репы|репу|репе|бесплатно)(?!\p{L})'
$bad = foreach ($f in $files | Where-Object { $_ -match '\.(ps1|psd1|xaml|cs)$' -and $_ -ne 'tests/ci.ps1' }) {
    Select-String -Path (Join-Path $root $f) -Pattern $tone | Where-Object { $_.Line -notmatch 'бесплатн\w* (навсегда|до|для|без)' } |
        ForEach-Object { "${f}:$($_.LineNumber): $($_.Line.Trim())" }
}
Report 'тон текстов' $bad

# BOM у .ps1 / .psd1 / .xaml / .cs, кроме bootstrap.ps1; bootstrap.ps1 — только ASCII
$bad = foreach ($f in $files | Where-Object { $_ -match '\.(ps1|psd1|xaml|cs)$' -and $_ -ne 'bootstrap.ps1' }) {
    $b = [IO.File]::ReadAllBytes((Join-Path $root $f))
    if ($b.Count -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) { $f }
}
Report 'UTF-8 с BOM' $bad
$b = [IO.File]::ReadAllBytes((Join-Path $root 'bootstrap.ps1'))
Report 'bootstrap.ps1: только ASCII' $(if (@($b | Where-Object { $_ -gt 0x7F }).Count) { 'есть символы вне ASCII' })

# личное: имя владельца допустимо только в адресах репозитория и Pages
$personal = 'IHEEAE|ilyai|ЛАНИТ|LANIT|ВИСМО|VISMO|Хваев|Khvaev|gmail|isidor|C:\\Users\\[a-z]'
$allowed = 'iheeae(\.github\.io|/tabula-rasa|/pc-base|/\(tabula|\.tabula-rasa)|`iheeae`|кроме iheeae'   # сами правила в CLAUDE.md
$bad = foreach ($f in $files | Where-Object { $_ -ne 'tests/ci.ps1' -and $_ -notmatch '\.(png|jpg|ico)$' }) {
    Select-String -Path (Join-Path $root $f) -Pattern $personal | Where-Object {
        $_.Line -notmatch 'grep -rniE' -and (($_.Line -replace $allowed, '') -match $personal) } |
        ForEach-Object { "${f}:$($_.LineNumber): $($_.Line.Trim())" }
}
Report 'личное' $bad

# README соответствует каталогу
& (Join-Path $root 'tools\catalog-doc.ps1') -Check *> $null
Report 'README: раздел каталога соответствует каталогу' $(if ($LASTEXITCODE -ne 0) { 'запустите tools\catalog-doc.ps1' })

# Windows: model.cs и разметка окон в WPF
if ($env:OS -eq 'Windows_NT') {
    $bad = @()
    try {
        . (Join-Path $root 'lib\common.ps1'); . (Join-Path $root 'lib\gui.ps1'); . (Join-Path $root 'lib\splash.ps1')
        $script:PB.Root = $root
        $theme = Initialize-Ui
        foreach ($x in 'main.xaml', 'dialog.xaml', 'addapp.xaml') {
            try { [void](New-UiWindow $x $theme) } catch { $bad += "${x}: $($_.Exception.InnerException.Message) $($_.Exception.Message)" }
        }
        try { [void][Windows.Markup.XamlReader]::Parse((Get-PbSplashXaml)) } catch { $bad += "заставка: $($_.Exception.Message)" }
    } catch { $bad += "Initialize-Ui: $($_.Exception.Message)" }
    Report 'WPF: model.cs, main/dialog/addapp.xaml, заставка' $bad
}

Write-Host ''
if ($script:Fails) { Write-Host "Не пройдено проверок: $($script:Fails)" -ForegroundColor Red; exit 1 }
Write-Host 'Все проверки пройдены' -ForegroundColor Green
exit 0   # иначе остаётся $LASTEXITCODE последней внешней команды из проверок
