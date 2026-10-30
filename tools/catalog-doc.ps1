# Tabula Rasa: раздел README «Каталог: программы и настройки» — из catalog\apps.psd1 и catalog\tweaks.ps1.
# Описание в README не правится руками: после изменения каталога запустите
#   powershell -ExecutionPolicy Bypass -File tools\catalog-doc.ps1
# Ключ -Check — только проверить, что README соответствует каталогу (так делает CI); код выхода 1, если нет.

param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$readme = Join-Path $root 'README.md'
$begin = '<!-- catalog:begin (tools/catalog-doc.ps1) -->'
$end = '<!-- catalog:end -->'

function ConvertTo-MdCell ([string]$T) { ($T -replace '\|', '\|' -replace '\r?\n', ' ').Trim() }

$apps = (Import-PowerShellDataFile (Join-Path $root 'catalog\apps.psd1')).Apps
. (Join-Path $root 'catalog\tweaks.ps1')

$md = New-Object Text.StringBuilder
[void]$md.AppendLine($begin)
[void]$md.AppendLine('')
[void]$md.AppendLine("<details><summary><b>Программы ($(@($apps).Count))</b></summary>")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Категория | Программа | Описание | Источник |')
[void]$md.AppendLine('|---|---|---|---|')
foreach ($a in $apps) {
    $src = if ($a.Source -eq 'web') { 'официальный сайт' } else { "winget ``$($a.WingetId)``" }
    $marks = @()
    if ($a.OpenSource) { $marks += 'открытый код' }
    if ($a.Config) { $marks += 'перенос настроек' }
    if ($a.Requires) { $marks += 'требует: ' + (@($a.Requires | ForEach-Object { $r = $_; $n = @(@($apps) + @($Tweaks) | Where-Object { $_.Id -eq $r } | ForEach-Object { $_.Name }); if ($n) { $n[0] } else { $r } }) -join ', ') }
    if ($a.Os) { $marks += "только Windows $(@($a.Os) -join ', ')" }
    if ($a.License) { $marks += "условия: $($a.License)" }
    $desc = ConvertTo-MdCell $a.Desc
    if ($marks.Count) { $desc += " *($(ConvertTo-MdCell ($marks -join '; ')))*" }
    [void]$md.AppendLine("| $(ConvertTo-MdCell $a.Category) | $(ConvertTo-MdCell $a.Name) | $desc | $src |")
}
[void]$md.AppendLine('')
[void]$md.AppendLine('</details>')
[void]$md.AppendLine('')
[void]$md.AppendLine("<details><summary><b>Настройки Windows ($(@($Tweaks).Count))</b></summary>")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Группа | Настройка | Что делает | Windows | Отмена |')
[void]$md.AppendLine('|---|---|---|---|---|')
foreach ($t in $Tweaks) {
    $undo = if ($t.Irreversible) { 'только точкой восстановления' } else { 'откат изменений' }
    $desc = ConvertTo-MdCell $t.Desc
    if ($t.Phase -eq 'post') { $desc += ' *(выполняется после установки программ)*' }
    [void]$md.AppendLine("| $(ConvertTo-MdCell $t.Group) | $(ConvertTo-MdCell $t.Name) | $desc | $(@($t.Os) -join ', ') | $undo |")
}
[void]$md.AppendLine('')
[void]$md.AppendLine('</details>')
[void]$md.AppendLine('')
[void]$md.Append($end)
$section = $md.ToString() -replace "`r`n", "`n"

$text = [IO.File]::ReadAllText($readme, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
$i = $text.IndexOf($begin); $j = $text.IndexOf($end)
if ($i -lt 0 -or $j -lt $i) { Write-Host "В README нет меток $begin … $end" -ForegroundColor Red; exit 1 }
$new = $text.Substring(0, $i) + $section + $text.Substring($j + $end.Length)
if ($Check) {
    if ($new -ne $text) { Write-Host 'README не соответствует каталогу: запустите tools\catalog-doc.ps1 и закоммитьте README.md' -ForegroundColor Red; exit 1 }
    Write-Host 'README соответствует каталогу' -ForegroundColor Green
    exit 0
}
[IO.File]::WriteAllText($readme, $new, (New-Object Text.UTF8Encoding $false))
Write-Host "README обновлён: программ $(@($apps).Count), настроек $(@($Tweaks).Count)" -ForegroundColor Green
