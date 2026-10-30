# Tabula Rasa: план и прогон. Один список шагов (Get-PbRunPlan) — и экран плана, и экран прогона в окне,
# и вывод в консоль (setup.ps1 -Console).
#
# Шаг: @{ Key; Phase (1–7); PhaseName; Kind; Name; Ref; State = wait|run|done|skip|error; Detail; Note; Irreversible }.
# Invoke-PbRun выполняет шаги по порядку. Из окна — в фоновом runspace с общим $Sync: State/Detail шагов,
# $Sync.SkipCurrent (снять текущий), $Sync.StopAfter (остановить после текущего), вопросы — $Sync.Ask / $Sync.Answer
# вместо Read-Host. Без $Sync — как раньше, в консоли.

$script:PbPhases = [ordered]@{
    1 = 'Точка восстановления'; 2 = 'Настройки Windows'; 3 = 'Программы'; 4 = 'Настройки программ'
    5 = 'Файлы'; 6 = 'Среда'; 7 = 'Имя компьютера'
}

function New-PbStep ([int]$Phase, [string]$Kind, [string]$Key, [string]$Name, $Ref) {
    return [hashtable]::Synchronized(@{ Key = $Key; Phase = $Phase; PhaseName = $script:PbPhases[$Phase]; Kind = $Kind; Name = $Name; Ref = $Ref
        State = 'wait'; Detail = ''; Note = ''; Irreversible = $false })
}

# $Sel — выбор окна (Apps, Configs, Tweaks, Files, FileTitles, Name, Upgrades); $Status — статусы окна (необязательно):
# @{ Apps = @{ id = @{ Kind } }; Tweaks = @{ id = 'applied' } } — только для пометок «будет пропущено»
function Get-PbRunPlan ($Sel, $Apps, $Tweaks, $Status) {
    $plan = New-Object System.Collections.ArrayList
    $pre = @($Tweaks | Where-Object { $_.Phase -ne 'post' -and $Sel.Tweaks -contains $_.Id })
    $post = @($Tweaks | Where-Object { $_.Phase -eq 'post' -and $Sel.Tweaks -contains $_.Id })
    $apps = @($Apps | Where-Object { $Sel.Apps -contains $_.Id })
    $cfg = @($Apps | Where-Object { $_.Config -and $_.Config.Import -and $Sel.Configs -contains $_.Id })
    $any = $pre.Count + $post.Count + $apps.Count + $cfg.Count + @($Sel.Files).Count + [int][bool]$Sel.Name
    if (-not $any) { return , $plan }

    [void]$plan.Add((New-PbStep 1 'restore' 'restore' 'Создать точку восстановления' $null))
    foreach ($t in $pre) {
        $s = New-PbStep 2 'tweak' "tweak:$($t.Id)" $t.Name $t.Id
        $s.Irreversible = [bool]$t.Irreversible
        if ($s.Irreversible) { $s.Note = 'необратимо: отменяется только точкой восстановления' }
        elseif ($Status -and $Status.Tweaks -and $Status.Tweaks[$t.Id] -eq 'applied') { $s.Note = 'уже применено: значения будут записаны повторно' }
        [void]$plan.Add($s)
    }
    foreach ($a in $apps) {
        $s = New-PbStep 3 'app' "app:$($a.Id)" $a.Name $a.Id
        $st = if ($Status -and $Status.Apps) { $Status.Apps[$a.Id] } else { $null }
        if ($st -and $st.Kind -eq 'update' -and @($Sel.Upgrades) -contains $a.Id) { $s.Note = "обновление: $($st.Text -replace '^обновление: ', '')" }
        elseif ($st -and $st.Kind -in 'installed', 'update') { $s.Note = 'уже установлено: будет пропущено' }
        elseif ($a.Source -eq 'web') { $s.Note = 'с официального сайта, с проверкой подписи' }
        if ($a.Interactive) { $s.Note = (@($s.Note, 'откроется мастер установки') | Where-Object { $_ }) -join '; ' }
        [void]$plan.Add($s)
    }
    foreach ($a in $cfg) {
        $s = New-PbStep 4 'config' "config:$($a.Id)" "$($a.Name): с моими настройками" $a.Id
        if (-not (Find-PbConfig $a.Config.File)) { $s.Note = 'сохранённых настроек нет: будет пропущено' }
        [void]$plan.Add($s)
    }
    if (@($Sel.Files).Count) {
        $titles = if ($Sel.FileTitles) { @($Sel.FileTitles) } else { @($Sel.Files) }
        $s = New-PbStep 5 'files' 'files' "Загрузить файлы: $($titles.Count)" $null
        $s.Note = ($titles -join ', ')
        [void]$plan.Add($s)
    }
    foreach ($t in $post) { [void]$plan.Add((New-PbStep 6 'tweak' "tweak:$($t.Id)" $t.Name $t.Id)) }
    if ($Sel.Name -and $Sel.Name -ne $env:COMPUTERNAME) {
        $s = New-PbStep 7 'rename' 'rename' "Имя компьютера: $env:COMPUTERNAME → $($Sel.Name)" $Sel.Name
        $s.Note = 'вступит в силу после перезагрузки'
        [void]$plan.Add($s)
    }
    return , $plan
}

# план текстом (setup.ps1 -Console и журнал)
function Write-PbPlan ($Plan) {
    $ph = 0
    foreach ($s in $Plan) {
        if ($s.Phase -ne $ph) { $ph = $s.Phase; Write-Step $s.PhaseName }
        Write-Host "    $($s.Name)$(if ($s.Note) { "   [$($s.Note)]" })" -ForegroundColor $(if ($s.Irreversible) { 'Yellow' } else { 'Gray' })
    }
}

# вопрос «да/нет»: в окне — через $Sync (окно показывает диалог), в консоли — Read-Host
function Request-PbAnswer ([string]$Text, [string[]]$Items) {
    $sync = $script:PB.RunSync
    if (-not $sync) {
        Write-Host "    $Text" -ForegroundColor Yellow
        $Items | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
        return ((Read-Host '    [y/N]') -match '^[yYнН]')
    }
    $sync.Answer = $null
    $sync.Ask = @{ Text = $Text; Items = @($Items) }
    while ($null -eq $sync.Answer) { Start-Sleep -Milliseconds 200 }
    $sync.Ask = $null
    return [bool]$sync.Answer
}

# состояние шага по строкам итога, добавленным за время шага
function Get-PbStepState ($Results) {
    $r = @($Results)
    $bad = @($r | Where-Object { $_.'Статус' -in 'ОШИБКА', 'ТАЙМАУТ' })
    if ($bad.Count) { return @{ State = 'error'; Detail = (@($bad | ForEach-Object { "$($_.'Статус'): $($_.'Детали')" }) -join '; ') } }
    $skip = @($r | Where-Object { $_.'Статус' -eq 'пропущено' })
    if ($skip.Count -and $skip.Count -eq $r.Count) { return @{ State = 'skip'; Detail = (@($skip | ForEach-Object { $_.'Детали' }) -join '; ') } }
    return @{ State = 'done'; Detail = (@($r | ForEach-Object { $_.'Статус' } | Select-Object -Unique) -join ', ') }
}

# выполнить план. $Apps / $Tweaks — загруженные в этом же runspace (скриптблоки твиков привязаны к своему runspace)
function Invoke-PbRun ($Plan, $Sel, $Apps, $Tweaks, $Sync) {
    $script:PB.RunSync = $Sync
    $script:PB.Upgrades = @($Sel.Upgrades)
    $byId = @{}; foreach ($a in $Apps) { $byId[$a.Id] = $a }
    $tw = @{}; foreach ($t in $Tweaks) { $tw[$t.Id] = $t }
    $wingetReady = $null
    $phase = 0
    try {
        foreach ($s in $Plan) {
            if ($s.State -ne 'wait') { continue }   # уже снят (нет точки восстановления, остановка)
            if ($Sync -and $Sync.StopAfter) { $s.State = 'skip'; $s.Detail = 'прогон остановлен'; continue }
            if ($s.Phase -ne $phase) { $phase = $s.Phase; Write-Step $s.PhaseName }
            if ($Sync) { $Sync.Current = $s.Key; $Sync.SkipCurrent = $false }
            $s.State = 'run'
            $mark = $script:PB.Results.Count
            try {
                switch ($s.Kind) {
                    'restore' {
                        try {
                            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
                            Checkpoint-Computer -Description "tabula-rasa $($script:PB.Stamp)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                            Write-Ok 'создана'; Add-Result 'Точка восстановления' 'создана'
                        } catch {
                            Write-Warn2 "не создана: $($_.Exception.Message)"
                            Add-Result 'Точка восстановления' 'пропущено' $_.Exception.Message
                            # без точки восстановления необратимое уже ничем не отменить — спросить, а не молча выполнить
                            $irr = @($Plan | Where-Object { $_.Irreversible -and $_.State -eq 'wait' })
                            if ($irr.Count -and -not (Request-PbAnswer 'Точка восстановления не создана. Без неё эти изменения отменить будет невозможно. Выполнить их?' @($irr | ForEach-Object { $_.Name }))) {
                                foreach ($x in $irr) { $x.State = 'skip'; $x.Detail = 'нет точки восстановления'; Add-Result $x.Name 'пропущено' 'нет точки восстановления' }
                            }
                        }
                    }
                    'tweak' { Invoke-Tweak $tw[$s.Ref] }
                    'app' {
                        $a = $byId[$s.Ref]
                        if ($a.Source -eq 'winget') {
                            if ($null -eq $wingetReady) {
                                $wingetReady = Initialize-Winget
                                if ($wingetReady) { [void](Invoke-PbWingetTimed @('source', 'update', '--name', 'winget') 5 'source_update') }
                            }
                            if (-not $wingetReady) { Add-Result $a.Name 'ОШИБКА' 'нет winget'; break }
                        }
                        Install-App $a
                        Update-SessionPath
                    }
                    'config' {
                        $a = $byId[$s.Ref]
                        Write-Host "  - $($a.Name): с моими настройками" -ForegroundColor White
                        & $a.Config.Import
                    }
                    'files' { Save-PbFiles -Names $Sel.Files }
                    'rename' {
                        Rename-Computer -NewName $s.Ref -Force -ErrorAction Stop
                        $script:PB.NeedReboot = $true; Add-Result $s.Name 'применено'
                    }
                }
            } catch { Write-Fail $_.Exception.Message; Add-Result $s.Name 'ОШИБКА' $_.Exception.Message }
            $new = @($script:PB.Results | Select-Object -Skip $mark)
            if ($Sync -and $Sync.SkipCurrent) { $s.State = 'skip'; $s.Detail = 'пропущено вручную' }
            elseif ($new.Count) { $st = Get-PbStepState $new; $s.State = $st.State; $s.Detail = $st.Detail }
            else { $s.State = 'done' }
        }
        if ($script:PB.NeedExplorerRestart) { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
    } finally {
        if ($script:PB.Changes.Count) { [void](Save-Changes) }
        if ($script:PB.Manual.Count) { $script:PB.Manual | Set-Content -Path (Join-Path $script:PB.LogDir "manual_$($script:PB.Stamp).txt") -Encoding UTF8 }
        if ($Sync) { $Sync.NeedReboot = $script:PB.NeedReboot; $Sync.Manual = @($script:PB.Manual); $Sync.Done = $true }
        $script:PB.RunSync = $null
    }
}

# ---------- откат (undo.ps1 и окно «Откат изменений») ----------

# журналы изменений: новые первыми, и в старой папке логов (pc-base). @{ Path; Date; Count }
function Get-PbChangeLogs {
    @(@($script:PB.LogDir, (Join-Path $script:PbLegacy.Program 'logs')) | Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Filter 'changes_*.json' -ErrorAction SilentlyContinue } |
        Sort-Object Name -Descending | ForEach-Object {
            $n = 0; try { $n = @(Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).Count } catch { }
            $d = $_.LastWriteTime
            if ($_.BaseName -match '(\d{4}-\d\d-\d\d)_(\d\d)(\d\d)(\d\d)$') { try { $d = [datetime]::ParseExact("$($Matches[1]) $($Matches[2]):$($Matches[3]):$($Matches[4])", 'yyyy-MM-dd HH:mm:ss', $null) } catch { } }
            @{ Path = $_.FullName; Date = $d; Count = $n }
        })
}

# откат одного журнала в обратном порядке; строки результата — @{ Ok; Text }
function Invoke-PbUndo ([string]$File) {
    $changes = @(Get-Content $File -Raw -Encoding UTF8 | ConvertFrom-Json)
    [array]::Reverse($changes)
    foreach ($c in $changes) {
        try {
            $text = switch ($c.Kind) {
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
                    "$($c.Path)\$($c.Name)"
                }
                'RegKey' { if ($c.KeyCreated -and (Test-Path $c.Path)) { Remove-Item $c.Path -Recurse -Force; "ключ $($c.Path) удалён" } }
                'Service' {
                    $st = @{ 'Auto' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }[[string]$c.Old]
                    if ($st) { Set-Service -Name $c.Name -StartupType $st -ErrorAction Stop; "служба $($c.Name) → $st" }
                }
                'Task' { if ($c.WasEnabled) { Enable-ScheduledTask -TaskPath $c.TaskPath -TaskName $c.TaskName -ErrorAction Stop | Out-Null; "задача $($c.TaskName) включена" } }
                'Hibernate' { if ($c.WasEnabled) { & powercfg.exe /hibernate on; 'гибернация и быстрый запуск снова включены' } }
                'PowerScheme' { if ($c.Old) { & powercfg.exe /setactive $c.Old; "схема питания $($c.Old) снова активна" } }
                'MachinePath' {
                    $cur = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ -and $_ -ne $c.Dir }
                    [Environment]::SetEnvironmentVariable('Path', ($cur -join ';'), 'Machine')
                    "PATH: удалён $($c.Dir)"
                }
            }
            if ($text) { @{ Ok = $true; Text = $text } }
        } catch { @{ Ok = $false; Text = "$($c.Kind) $($c.Path)$($c.Name): $($_.Exception.Message)" } }
    }
}

$script:PbUndoLimits = 'Не отменяются через undo.ps1: удалённые встроенные приложения и OneDrive, установленные программы, обновления winget upgrade --all, применённые настройки программ в файлах. Для них используется точка восстановления «tabula-rasa <дата>» (Панель управления → Восстановление) или удаление программ вручную.'
