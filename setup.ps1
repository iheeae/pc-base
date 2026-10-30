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

[CmdletBinding()]
param(
    [string]$Selection,
    [switch]$NoPull,
    [switch]$DryRun,
    [string]$DataRoot
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
    if ($DataRoot) { $argList += @('-DataRoot', "`"$DataRoot`"") }
    if ($isAdmin) { Start-Process powershell.exe -ArgumentList $argList }
    else { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList }
    return
}

$Host.UI.RawUI.WindowTitle = 'Tabula Rasa'
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'lib\gui.ps1')
. (Join-Path $PSScriptRoot 'lib\configs.ps1')
$script:PB.Root = $PSScriptRoot
if ($DataRoot) { $script:PB.DataRoot = $DataRoot }
$EngineRepo = 'iheeae/tabula-rasa'
$startNotices = @()

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
    # ---------- свежая версия базы ----------
    if (-not $NoPull -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $top = & git -C $PSScriptRoot rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            Write-Step 'Обновление Tabula Rasa'
            & git -C $top pull --ff-only
            if ($LASTEXITCODE -ne 0) { Write-Warn2 'git pull не выполнен, используется текущая версия' }
        }
    }
    # Мои данные: подтянуть с GitHub и отправить то, что не ушло в прошлый раз
    if (-not $NoPull -and (Test-PbDataConnected)) {
        Write-Step "Мои данные ($($script:PB.DataRoot)): синхронизация с GitHub"
        if (-not (Push-PbData)) { Write-Warn2 "нет связи с GitHub; неотправленные изменения ($((Get-PbDataState).Pending)) будут отправлены при следующем запуске" }
    }

    # ---------- каталог ----------
    $Apps = (Import-PowerShellDataFile (Join-Path $PSScriptRoot 'catalog\apps.psd1')).Apps
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
    # файлы pc-base-exe показываем в окне, только если Диск уже виден; иначе — выбор во время прогона
    $driveDir = Find-InstallersDir
    $driveItems = if ($driveDir) { @(Get-DriveItems $driveDir) } else { $null }
    $sel = Show-SelectionDialog -Apps $Apps -Tweaks $Tweaks -DriveItems $driveItems -Initial $initial -Notices $startNotices -DryRun $true -IsDomain $script:PB.IsDomain
    if (-not $sel) { Write-Host '  Отменено.'; return }
    $DryRun = $sel.DryRun
    $newName = $sel.Name

    $selApps = @($Apps | Where-Object { $sel.Apps -contains $_.Id })
    $selCfg = @($Apps | Where-Object { $_.ConfigFn -and $sel.Configs -contains $_.Id })
    $preTw = @($Tweaks | Where-Object { $_.Phase -ne 'post' -and $sel.Tweaks -contains $_.Id })
    $postTw = @($Tweaks | Where-Object { $_.Phase -eq 'post' -and $sel.Tweaks -contains $_.Id })

    if ($DryRun) {
        Write-Step 'Будет сделано'
        $preTw | ForEach-Object { Write-Host "    твик:      $($_.Name)$(if ($_.Irreversible) { '   [необратимо]' })" }
        $selApps | ForEach-Object { Write-Host "    программа: $($_.Name) [$($_.Source)]" }
        $selCfg | ForEach-Object { Write-Host "    настройки: $($_.Name) — $($_.ConfigName)" }
        $sel.Files | ForEach-Object { Write-Host "    с Диска:   $_" }
        if ($sel.FilesAsk -and -not $sel.Files.Count) { Write-Host '    с Диска:   выбор во время прогона' }
        $postTw | ForEach-Object { Write-Host "    после:     $($_.Name)" }
        if ($newName) { Write-Host "    имя:       $newName" }
        Write-Host ''
        Write-Host '  Показан только план, изменения не вносились. Чтобы применить их, выберите внизу окна режим «Применить».' -ForegroundColor Yellow
        return
    }

    # ---------- точка восстановления ----------
    Write-Step 'Точка восстановления'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description "tabula-rasa $($script:PB.Stamp)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok 'создана'
    } catch { Write-Warn2 "не создана: $($_.Exception.Message)" }

    # ---------- 2. настройки ----------
    if ($preTw) { Write-Step 'Настройки Windows'; foreach ($t in $preTw) { Invoke-Tweak $t } }

    # ---------- 3. программы ----------
    if ($selApps) {
        Write-Step 'Программы'
        if (-not (Initialize-Winget)) { Write-Fail 'Без winget программы из каталога установить невозможно' }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            & winget source update --name winget 2>$null | Out-Null
        }
        foreach ($a in $selApps) {
            if ($a.Source -eq 'winget' -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Add-Result $a.Name 'ОШИБКА' 'нет winget'; continue
            }
            Install-App $a
        }
        Update-SessionPath
    }

    # ---------- 3а. настройки программ ----------
    if ($selCfg) {
        Write-Step 'Настройки программ'
        foreach ($a in $selCfg) {
            Write-Host "  - $($a.Name): $($a.ConfigName)" -ForegroundColor White
            try { & $a.ConfigFn } catch { Write-Fail $_.Exception.Message; Add-Result "$($a.Name): $($a.ConfigName)" 'ОШИБКА' $_.Exception.Message }
        }
    }

    # ---------- 3б. файлы с Диска ----------
    if ($sel.Files.Count -or $sel.FilesAsk) {
        Write-Step 'Файлы с Диска (pc-base-exe)'
        Copy-ExeToDesktop -Names $sel.Files -Ask:($sel.FilesAsk -and -not $sel.Files.Count)
    }

    # ---------- 4. среда ----------
    if ($postTw) {
        Write-Step 'Среда'
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { [void](Initialize-Winget) }
        foreach ($t in $postTw) { Invoke-Tweak $t }
    }

    if ($script:PB.DriveInstalledNow) {
        if ((Read-Host '  Google Drive устанавливался только для pc-base-exe. Удалить его с этого компьютера? [y/N]') -match '^[yYнН]') {
            & winget uninstall --id Google.GoogleDrive -e --silent --disable-interactivity
            Write-Ok 'Google Drive удалён'
        }
    }

    # ---------- 5. имя ПК ----------
    if ($newName -and $newName -ne $env:COMPUTERNAME) {
        try { Rename-Computer -NewName $newName -Force -ErrorAction Stop; $script:PB.NeedReboot = $true; Add-Result "Имя компьютера → $newName" 'применено' }
        catch { Add-Result "Имя компьютера → $newName" 'ОШИБКА' $_.Exception.Message }
    }

    if ($script:PB.NeedExplorerRestart) { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
}
finally {
    $changesFile = $null
    if ($script:PB.Changes.Count) { $changesFile = Save-Changes }

    if ($script:PB.Results.Count) {
        Write-Step 'Итог'
        $script:PB.Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
        $fails = @($script:PB.Results | Where-Object { $_.'Статус' -eq 'ОШИБКА' })
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
