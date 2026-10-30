# Tabula Rasa: развёртывание и обслуживание компьютеров. Профилей нет — одно окно со всем каталогом.
#
# Запуск (права администратора запрашиваются автоматически):
#   powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\setup.ps1
# Обычно запускается из bootstrap.ps1; вручную — для повторного прогона.
#
# Две папки: движок — здесь (C:\tabula-rasa, клон публичного репозитория), Мои данные — C:\tabula-rasa-private
# (клон своего приватного репозитория: сохранения, настройки программ). Подключаются из окна; без них работает всё,
# кроме «с моими настройками», а сохранения пишутся локально.
#
# Ключи:
#   -Selection <имя|путь>   открыть окно с сохранением: путь к .json, имя из Моих данных или локальных сохранений
#   -NoPull                 не подтягивать свежую версию из git
#   -DryRun                 открыть окно в режиме «только показать план» (он и так по умолчанию)
#   -DataRoot <папка>       где лежат свои данные, если не в C:\tabula-rasa-private
#   -Console                план и прогон — в консоли, как раньше (для отладки); по умолчанию — в окне, консоль скрыта

[CmdletBinding()]
param(
    [string]$Selection,
    [switch]$NoPull,
    [switch]$DryRun,
    [string]$DataRoot,
    [switch]$Console
)

$ErrorActionPreference = 'Continue'   # Stop ломает нативные команды в PS 5.1; где надо — -ErrorAction Stop явно
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- права админа и STA (окно на WPF работает только в STA-потоке) ----------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSta = [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'
if (-not $isAdmin -or -not $isSta) {
    $argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Selection) { $argList += @('-Selection', "`"$Selection`"") }
    if ($NoPull) { $argList += '-NoPull' }
    if ($DryRun) { $argList += '-DryRun' }
    if ($Console) { $argList += '-Console' }
    if ($DataRoot) { $argList += @('-DataRoot', "`"$DataRoot`"") }
    if ($isAdmin) { Start-Process powershell.exe -ArgumentList $argList }
    else { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList }
    return
}

$Host.UI.RawUI.WindowTitle = 'Tabula Rasa'

# ---------- самая свежая версия: до загрузки lib\*.ps1 ----------
# Клон движка всегда приводится к origin/master — другая ветка, отставание или локальные правки не повод запускать
# старую версию. Ничего не теряется: правки уходят в git stash, свои коммиты master — в ветку backup/master-<дата>.
# Если версия изменилась, этот же setup.ps1 перезапускается, чтобы окно работало уже на новом коде.
# Повторный запуск помечается переменной TR_ENGINE_SYNCED, чтобы не проверять второй раз.
$preNotices = @()
if ($env:TR_ENGINE_NOTICE) { $preNotices += @($env:TR_ENGINE_NOTICE -split "`n" | Where-Object { $_ }) }
$env:TR_ENGINE_NOTICE = $null
$engineSynced = $env:TR_ENGINE_SYNCED -eq '1'
$env:TR_ENGINE_SYNCED = $null
if (-not $NoPull -and -not $engineSynced -and (Get-Command git -ErrorAction SilentlyContinue) -and
    (Test-Path (Join-Path $PSScriptRoot '.git'))) {
    function Invoke-EngineGit { & git -C $PSScriptRoot @args 2>$null }
    $engineOrigin = Invoke-EngineGit remote get-url origin
    # только свой клон (в том числе старый адрес до переименования); чужой разбирает блок «старый клон» ниже
    if ($engineOrigin -match 'github\.com[/:]iheeae/(tabula-rasa|pc-base)(\.git)?/?$') {
        Write-Host '  Проверка обновлений Tabula Rasa...' -ForegroundColor Gray
        $before = Invoke-EngineGit rev-parse HEAD
        Invoke-EngineGit fetch --quiet origin master | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $preNotices += 'Нет связи с GitHub: обновления не проверены, запущена текущая версия Tabula Rasa.'
        } else {
            $target = Invoke-EngineGit rev-parse origin/master
            $branch = Invoke-EngineGit symbolic-ref --short -q HEAD
            if ($before -ne $target -or $branch -ne 'master') {
                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                if (Invoke-EngineGit status --porcelain) {
                    Invoke-EngineGit stash push --include-untracked -m "tabula-rasa: локальные изменения перед обновлением $stamp" | Out-Null
                    $preNotices += "Локальные изменения в $PSScriptRoot перед обновлением сохранены в git stash ($stamp)."
                }
                Invoke-EngineGit merge-base --is-ancestor master origin/master
                if ($LASTEXITCODE -eq 1) {   # у локальной master есть коммиты, которых нет на GitHub
                    Invoke-EngineGit branch -f "backup/master-$stamp" master | Out-Null
                    $preNotices += "Локальные коммиты ветки master сохранены в ветке backup/master-$stamp."
                }
                Invoke-EngineGit checkout -q -B master origin/master | Out-Null
                Invoke-EngineGit branch -q --set-upstream-to=origin/master master | Out-Null
                $after = Invoke-EngineGit rev-parse HEAD
                if ($after -ne $target) {
                    $preNotices += "Не удалось обновить Tabula Rasa в $($PSScriptRoot): запущена текущая версия."
                } elseif ($after -ne $before) {
                    Write-Host "  Tabula Rasa обновлён: $($before.Substring(0, 7)) -> $($after.Substring(0, 7)). Перезапуск..." -ForegroundColor Green
                    $env:TR_ENGINE_SYNCED = '1'
                    $env:TR_ENGINE_NOTICE = ($preNotices -join "`n")
                    $relaunch = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
                    if ($Selection) { $relaunch += @('-Selection', $Selection) }
                    if ($DryRun) { $relaunch += '-DryRun' }
                    if ($Console) { $relaunch += '-Console' }
                    if ($DataRoot) { $relaunch += @('-DataRoot', $DataRoot) }
                    & powershell.exe @relaunch
                    exit $LASTEXITCODE
                }
            }
        }
    }
}

. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\gui.ps1')
. (Join-Path $PSScriptRoot 'lib\configs.ps1')
$script:PB.Root = $PSScriptRoot
if ($DataRoot) { $script:PB.DataRoot = $DataRoot }
$EngineRepo = 'iheeae/tabula-rasa'
$startNotices = @($preNotices)
$windowMode = $false

# загрузчик в отдельном окне: переносит или заново клонирует папку движка. Сами выходим сразу, чтобы не держать её
function Start-PbBootstrap {
    $boot = "[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://raw.githubusercontent.com/$EngineRepo/master/bootstrap.ps1 | iex"
    Start-Process powershell.exe -WorkingDirectory $env:SystemRoot -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $boot)
    Set-Location $env:SystemRoot
}

# ---------- переезд pc-base → Tabula Rasa ----------
# Запуск из старой C:\pc-base: свою папку не переместить, поэтому переносит загрузчик. Новая уже есть — запускается она.
# С -NoPull (так запускает загрузчик) не переезжаем: загрузчик уже пробовал, папка занята — работаем из старой.
$newRoot = 'C:\tabula-rasa'
if ($PSScriptRoot -eq $script:PbLegacy.Root -and -not $NoPull) {
    if (Test-Path (Join-Path $newRoot 'setup.ps1')) {
        Write-Host "  Tabula Rasa установлен в $newRoot, запуск оттуда." -ForegroundColor Yellow
        $fwd = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$newRoot\setup.ps1`"")
        if ($Selection) { $fwd += @('-Selection', "`"$Selection`"") }
        if ($DataRoot) { $fwd += @('-DataRoot', "`"$DataRoot`"") }
        Start-Process powershell.exe -WorkingDirectory $env:SystemRoot -ArgumentList $fwd
    } else {
        Write-Host "  pc-base теперь называется Tabula Rasa. Загрузчик перенесёт $PSScriptRoot в $newRoot." -ForegroundColor Yellow
        Start-PbBootstrap
    }
    return
}
if ($PSScriptRoot -eq $script:PbLegacy.Root) {
    $startNotices += "Tabula Rasa запущен из старой папки $($PSScriptRoot): её не удалось переименовать. Закройте окна, которые её используют, и запустите Tabula Rasa снова."
}
if (Get-Command git -ErrorAction SilentlyContinue) { Update-PbOrigin $PSScriptRoot }
if ($PSScriptRoot -ne $script:PbLegacy.Root -and (Test-Path $script:PbLegacy.Root)) {
    $startNotices += "Найдена старая папка $($script:PbLegacy.Root). Если всё работает, её можно удалить."
}
# Мои данные, локальные сохранения, журналы и логи
if (-not $DataRoot) {
    switch (Move-PbLegacyDir $script:PbLegacy.DataRoot $script:PB.DataRoot) {
        'both' { $startNotices += "Найдена старая папка $($script:PbLegacy.DataRoot). Мои данные уже в $($script:PB.DataRoot), старую папку можно удалить." }
        'busy' { $script:PB.DataRoot = $script:PbLegacy.DataRoot
                 $startNotices += "Папку $($script:PbLegacy.DataRoot) не удалось переименовать: она используется. Мои данные открыты из неё; перезапустите Tabula Rasa, когда папка освободится." }
    }
}
if (Get-Command git -ErrorAction SilentlyContinue) { Update-PbOrigin $script:PB.DataRoot }
[void](Move-PbLegacyDir $script:PbLegacy.Local (Join-Path $env:LOCALAPPDATA 'tabula-rasa') 10)
switch (Move-PbLegacyDir $script:PbLegacy.Program (Join-Path $env:ProgramData 'tabula-rasa') 10) {
    'busy' { $script:PB.LogDir = Join-Path $script:PbLegacy.Program 'logs' }
}

# ---------- старый клон ----------
# Публичный репозиторий начат с чистой истории. Если эта папка — клон чего-то другого (не тот origin или нет общего
# предка с origin/master), git pull не поможет: загрузчик отодвинет папку в .old_<дата> (ничего не удаляя)
# и склонирует движок заново.
if (-not $NoPull -and (Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $PSScriptRoot '.git'))) {
    $origin = & git -C $PSScriptRoot remote get-url origin 2>$null
    $sameOrigin = $origin -match ('github\.com[/:]' + [regex]::Escape($EngineRepo) + '(\.git)?/?$')
    $related = $false
    if ($sameOrigin) {
        & git -C $PSScriptRoot fetch --quiet origin 2>$null
        if ($LASTEXITCODE -eq 0) {
            & git -C $PSScriptRoot merge-base HEAD origin/master 2>$null | Out-Null
            $related = $LASTEXITCODE -eq 0
        } else { $related = $true }   # нет сети — судить не по чему, работаем с тем, что есть
    }
    if (-not $sameOrigin -or -not $related) {
        Write-Host ''
        Write-Host "  $PSScriptRoot содержит устаревшую копию ($origin)." -ForegroundColor Yellow
        Write-Host '  Загрузчик переместит её в .old_<дата> и установит Tabula Rasa заново.' -ForegroundColor Yellow
        Start-PbBootstrap
        return
    }
}

New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
$transcript = Join-Path $script:PB.LogDir "setup_$($script:PB.Stamp).log"
Start-Transcript -Path $transcript -Force | Out-Null

try {
    # свежая версия движка подтягивается в самом начале, до загрузки lib\*.ps1 (см. «самая свежая версия»)
    # Мои данные: подтянуть с GitHub и отправить то, что не ушло в прошлый раз
    if (-not $NoPull -and (Test-PbDataConnected)) {
        Write-Step "Мои данные ($($script:PB.DataRoot)): синхронизация с GitHub"
        switch (Push-PbData) {
            'offline' { Write-Warn2 "нет связи с GitHub; неотправленные изменения ($((Get-PbDataState).Pending)) будут отправлены при следующем запуске" }
            'public'  { $w = Get-PbPublicWarning (Get-PbDataRepo); Write-Warn2 $w; $startNotices += $w }
        }
    }

    # ---------- каталог ----------
    $Apps = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'catalog\apps.psd1')).Apps
    # собственный каталог из «Моих данных»: только winget, ошибочные записи пропускаются
    $uc = Read-PbUserCatalog @($Apps | ForEach-Object { $_.Id })
    $Apps = @($Apps) + @($uc.Apps)
    if ($uc.Errors.Count) { $startNotices += "Собственный каталог: пропущено записей с ошибками: $($uc.Errors.Count) ($($uc.Errors -join '; '))." }
    . (Join-Path $PSScriptRoot 'catalog\tweaks.ps1')
    Get-EnvInfo
    # всё, что не подходит к этой версии Windows, отсекается сразу — в меню и окне его не видно
    $Tweaks = @($Tweaks | Where-Object { $_.Os -contains $script:PB.Os })
    $Apps = @($Apps | Where-Object { -not $_.Os -or $_.Os -contains $script:PB.Os })
    $osTag = "Windows $($script:PB.Os)"

    Clear-Host
    Write-Host ''
    Write-Host '  Tabula Rasa' -ForegroundColor Cyan
    Write-Host ("  {0} | Windows {1} (сборка {2}) | {3}{4}" -f $env:COMPUTERNAME, $script:PB.Os, [Environment]::OSVersion.Version.Build,
        $(if ($script:PB.IsDomain) { 'в домене' } else { 'не в домене' }), $(if ($script:PB.IsLaptop) { ' | ноутбук' } else { '' })) -ForegroundColor Gray
    $ds = Get-PbDataState
    if ($ds.Connected) { Write-Host "  Мои данные: $($script:PB.DataRoot)$(if ($ds.User) { " ($($ds.User))" })$(if ($ds.Pending) { ", не отправлено: $($ds.Pending)" })" -ForegroundColor Gray }
    else { Write-Host '  Мои данные не подключены (подключение — в окне, слева внизу)' -ForegroundColor Gray }
    if ($DryRun) { Write-Host '  РЕЖИМ ПРОВЕРКИ: ничего не меняется' -ForegroundColor Yellow }
    if (-not (Test-SameUserAsDesktop)) {
        Write-Warn2 "Скрипт запущен от $env:USERNAME, а рабочий стол принадлежит другому пользователю."
        Write-Warn2 'Настройки HKCU (Проводник, панель задач, Terminal) будут применены к профилю администратора.'
        if ((Read-Host '    Продолжить? [y/N]') -notmatch '^[yYнН]') { return }
    }

    # ---------- окно выбора ----------
    $initial = $null
    if ($Selection) {
        $p = Find-PbSave $Selection
        if ($p) { $initial = Read-SaveFile $p } else { Write-Warn2 "Сохранение не найдено: $Selection" }
    }
    # список файлов окно получает само, в фоне: из релиза files «Моих данных»
    $sel = Show-SelectionDialog -Apps $Apps -Tweaks $Tweaks -Initial $initial -Notices $startNotices -DryRun $true -IsDomain $script:PB.IsDomain -RunInWindow (-not $Console)
    if ($script:PB.WindowShownSec) { Write-Host "  Окно открылось через $($script:PB.WindowShownSec) с после запуска." -ForegroundColor DarkGray }
    # план, прогон и итог прошли в окне (lib\gui.ps1 + lib\run.ps1): журнал прогона — logs\run_<дата>.log
    if ($sel -and $sel.RanInWindow) { $windowMode = $true; return }
    if (-not $sel) { Write-Host '  Отменено.'; return }

    # -Console: тот же план и прогон (lib\run.ps1), вывод — в консоль
    $plan = Get-PbRunPlan $sel $Apps $Tweaks $null
    if ($sel.DryRun) {
        Write-PbPlan $plan
        Write-Host ''
        Write-Host '  Показан только план, изменения не вносились. Чтобы применить их, выберите внизу окна режим «Применить».' -ForegroundColor Yellow
        return
    }
    Invoke-PbRun $plan $sel $Apps $Tweaks $null
}
finally {
  if ($windowMode) { Stop-Transcript | Out-Null }
  else {
    $changesFile = $null
    if ($script:PB.Changes.Count) { $changesFile = Save-Changes }

    if ($script:PB.Results.Count) {
        Write-Step 'Итог'
        $script:PB.Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
        $fails = @($script:PB.Results | Where-Object { $_.'Статус' -in 'ОШИБКА', 'ТАЙМАУТ' })
        if ($fails.Count) { Write-Host "  Ошибок: $($fails.Count). Подробности — в журнале выполнения" -ForegroundColor Red }
        else { Write-Host '  Ошибок нет' -ForegroundColor Green }
    }
    if ($script:PB.Manual.Count) {
        Write-Step 'Выполнить вручную'
        $i = 1; foreach ($m in $script:PB.Manual) { Write-Host ("  {0,2}. {1}" -f $i, $m); $i++ }
        $script:PB.Manual | Set-Content -Path (Join-Path $script:PB.LogDir "manual_$($script:PB.Stamp).txt") -Encoding UTF8
    }
    if ($changesFile) { Write-Host ''; Write-Host "  Журнал изменений: $changesFile  (откат: undo.ps1)" -ForegroundColor Gray }
    Write-Host "  Журнал выполнения: $transcript" -ForegroundColor Gray
    Stop-Transcript | Out-Null

    if ($script:PB.NeedReboot) {
        if ((Read-Host '  Нужна перезагрузка. Перезагрузить сейчас? [Y/n]') -notmatch '^[nNтТ]') { Restart-Computer -Force }
    } else {
        Read-Host '  Готово. Enter — закрыть' | Out-Null
    }
  }
}
