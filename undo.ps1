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

# последний журнал — и в новой папке, и в старой (pc-base), пока она существует
if (-not $File) {
    $File = @($script:PB.LogDir, (Join-Path $script:PbLegacy.Program 'logs')) |
            Where-Object { Test-Path $_ } |
            ForEach-Object { Get-ChildItem $_ -Filter 'changes_*.json' -ErrorAction SilentlyContinue } |
            Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $File -or -not (Test-Path $File)) { Write-Fail 'Журнал изменений не найден'; Read-Host '  Enter — закрыть' | Out-Null; return }

$changes = @(Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json)
Write-Step "Откат по журналу $File (записей: $($changes.Count))"
if ((Read-Host '  Выполнить откат? [y/N]') -notmatch '^[yYнН]') { return }

[array]::Reverse($changes)
foreach ($c in $changes) {
    try {
        switch ($c.Kind) {
            'Reg' {
                if ($c.OldExists) {
                    $kind = if ($c.OldKind) { $c.OldKind } else { $c.Type }
                    $val = $c.Old
                    if ($kind -eq 'MultiString') { $val = [string[]]@($val) }
                    if ($kind -eq 'Binary') { $val = [byte[]]@($val) }
                    New-ItemProperty -Path $c.Path -Name $c.Name -Value $val -PropertyType $kind -Force -ErrorAction Stop | Out-Null
                } elseif (Test-Path $c.Path) {
                    Remove-ItemProperty -Path $c.Path -Name $c.Name -ErrorAction SilentlyContinue
                }
                if ($c.KeyCreated -and (Test-Path $c.Path)) {
                    $k = Get-Item $c.Path
                    if ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item $c.Path -Force }
                }
                Write-Ok "$($c.Path)\$($c.Name)"
            }
            'RegKey' {
                if ($c.KeyCreated -and (Test-Path $c.Path)) { Remove-Item $c.Path -Recurse -Force; Write-Ok "ключ $($c.Path) удалён" }
            }
            'Service' {
                $map = @{ 'Auto' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }
                $st = $map[[string]$c.Old]
                if ($st) { Set-Service -Name $c.Name -StartupType $st -ErrorAction Stop; Write-Ok "служба $($c.Name) → $st" }
            }
            'Task' {
                if ($c.WasEnabled) { Enable-ScheduledTask -TaskPath $c.TaskPath -TaskName $c.TaskName -ErrorAction Stop | Out-Null; Write-Ok "задача $($c.TaskName) включена" }
            }
            'Hibernate' {
                if ($c.WasEnabled) { & powercfg.exe /hibernate on; Write-Ok 'гибернация и быстрый запуск снова включены' }
            }
            'PowerScheme' {
                if ($c.Old) { & powercfg.exe /setactive $c.Old; Write-Ok "схема питания $($c.Old) снова активна" }
            }
            'MachinePath' {
                $cur = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ -and $_ -ne $c.Dir }
                [Environment]::SetEnvironmentVariable('Path', ($cur -join ';'), 'Machine')
                Write-Ok "PATH: удалён $($c.Dir)"
            }
        }
    } catch { Write-Fail "$($c.Kind) $($c.Path)$($c.Name): $($_.Exception.Message)" }
}
Write-Host ''
Write-Host '  Готово. Проводник и панель задач применят изменения после повторного входа или перезагрузки.' -ForegroundColor Green
Write-Host '  Не отменяются через undo.ps1: удалённые встроенные приложения и OneDrive, установленные программы,' -ForegroundColor Yellow
Write-Host '  обновления winget upgrade --all, применённые настройки программ в файлах. Для них — точка восстановления' -ForegroundColor Yellow
Write-Host '  «tabula-rasa <дата>» (Панель управления → Восстановление) или удаление программ вручную.' -ForegroundColor Yellow
Read-Host '  Enter — закрыть' | Out-Null
