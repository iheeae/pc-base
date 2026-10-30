# Tabula Rasa: откат изменений реестра, служб, задач и PATH по журналу setup.ps1.
# Снесённые UWP-приложения и установленные программы не возвращаются — для этого есть точка восстановления.
#
#   powershell -ExecutionPolicy Bypass -File undo.ps1                  # последний журнал
#   powershell -ExecutionPolicy Bypass -File undo.ps1 -File <json>     # конкретный

param([string]$File)

$ErrorActionPreference = 'Continue'
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($File) { $a += @('-File', "`"$File`"") }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $a
    return
}

. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\run.ps1')

# последний журнал — и в новой папке, и в старой (pc-base), пока она существует; то же окно «Откат изменений»
if (-not $File) { $File = @(Get-PbChangeLogs | ForEach-Object { $_.Path }) | Select-Object -First 1 }
if (-not $File -or -not (Test-Path $File)) { Write-Fail 'Журнал изменений не найден'; Read-Host '  Enter — закрыть' | Out-Null; return }

$count = @(Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }).Count
Write-Step "Откат по журналу $File (записей: $count)"
if ((Read-Host '  Выполнить откат? [y/N]') -notmatch '^[yYнН]') { return }
foreach ($r in (Invoke-PbUndo $File)) { if ($r.Ok) { Write-Ok $r.Text } else { Write-Fail $r.Text } }
Write-Host ''
Write-Host '  Готово. Проводник и панель задач применят изменения после повторного входа или перезагрузки.' -ForegroundColor Green
Write-Host "  $script:PbUndoLimits" -ForegroundColor Yellow
Read-Host '  Enter — закрыть' | Out-Null
