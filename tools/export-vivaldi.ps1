# Снимает настройки Vivaldi с этого компьютера: обёртка над Export-VivaldiConfig (lib\configs.ps1) для консоли.
# То же самое делает вкладка «Снятие настроек» в окне Tabula Rasa: там же просмотр изменений, коммит и отправка.
#
#   powershell -ExecutionPolicy Bypass -File export-vivaldi.ps1 [-Out <папка configs>] [-DataRoot <Мои данные>]
# По умолчанию пишет в configs\vivaldi\prefs.json «Моих данных» (C:\tabula-rasa-private), если они есть на этом компьютере,
# иначе — в configs рядом с собой. В папку движка не пишет: это клон публичного репозитория. Коммит — вручную.
param([string]$Out, [string]$DataRoot = 'C:\tabula-rasa-private')

$root = Split-Path $PSScriptRoot
. (Join-Path $root 'lib\common.ps1'); . (Join-Path $root 'lib\configs.ps1')
if (-not $Out) { $Out = if (Test-Path (Join-Path $DataRoot 'configs')) { Join-Path $DataRoot 'configs' } else { Join-Path $PSScriptRoot 'configs' } }
try { $r = Export-VivaldiConfig $Out } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$file = Join-Path $Out $r.Files[0]
Write-Host "Готово: $file ($([math]::Round((Get-Item $file).Length / 1KB)) КБ)" -ForegroundColor Green
if ($r.Removed.Count) { Write-Host "Исключено как конфиденциальное, ключей: $($r.Removed.Count)" -ForegroundColor Yellow; $r.Removed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray } }
