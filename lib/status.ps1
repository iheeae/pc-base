# Tabula Rasa: статус программ и твиков для окна — только чтение, в фоновой задаче (окно не ждёт).
#
# Программы — в два шага: сразу по реестру Uninstall (Get-PbUninstallEntries, «установлено · версия»), затем одним
# winget list (ConvertFrom-PbWingetList: версия и «Доступно» — есть обновление). Пока winget не ответил, про программы
# из winget «не установлено» не говорится: в реестре их название бывает другим. Программы с сайта — только по реестру.
# Твики — Get-PbTweakStatus (lib\common.ps1): Apply в режиме проверки, ничего не меняется.

# установленные программы: @{ Name; Version } из HKLM (64 и 32 бит) и HKCU, без системных компонентов
function Get-PbUninstallEntries {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 } |
        ForEach-Object { @{ Name = [string]$_.DisplayName; Version = [string]$_.DisplayVersion; Icon = [string]$_.DisplayIcon } })
}

# запись реестра для программы каталога: по Detect (как у web-установки) или по началу названия
# («Git» находит «Git version 2.47», но не «GitHub CLI»)
function Find-PbUninstallEntry ($App, $Entries) {
    if ($App.Detect) { $hit = @($Entries | Where-Object { $_.Name -like $App.Detect }) }
    else {
        $re = '^' + [regex]::Escape([string]$App.Name) + '(\s|$|[\d(\-])'
        $hit = @($Entries | Where-Object { $_.Name -match $re })
    }
    if ($hit.Count) { return $hit[0] }
    return $null
}

# winget list → @{ <id в нижнем регистре> = @{ Version; Available } }. Колонки по позициям из заголовка
# (ConvertFrom-PbWingetTable): 5 колонок — «Доступно» четвёртая; 4 — четвёртая это «Доступно» или «Источник»
function ConvertFrom-PbWingetList ([string[]]$Lines) {
    $out = @{}
    foreach ($r in (ConvertFrom-PbWingetTable $Lines)) {
        $c = @($r.Cols)
        $avail = ''
        if ($c.Count -ge 5) { $avail = $c[3] }
        elseif ($c.Count -eq 4 -and $c[3] -match '^\d') { $avail = $c[3] }
        $out[$r.Id.ToLower()] = @{ Version = $r.Version; Available = $avail }
    }
    return $out
}

function Get-PbWingetInstalled {
    $r = Invoke-PbWingetTimed @('list', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') 3 'list_all'
    if ($r.TimedOut -or $null -eq $r.Code) { throw 'winget list не ответил за 3 минуты.' }
    return (ConvertFrom-PbWingetList $r.Out)
}

# @{ Kind = installed | update | missing | unknown; Text; Version; Available; Icon (DisplayIcon из реестра) }.
# $Winget = $null — winget ещё не ответил
function Get-PbAppStatus ($App, $Entries, $Winget) {
    $st = Get-PbAppStatusCore $App $Entries $Winget
    $reg = Find-PbUninstallEntry $App $Entries
    if ($reg -and $reg.Icon -and $st.Kind -in 'installed', 'update') { $st.Icon = $reg.Icon }
    return $st
}

function Get-PbAppStatusCore ($App, $Entries, $Winget) {
    $reg = Find-PbUninstallEntry $App $Entries
    $w = $null
    if ($Winget -and $App.WingetId) { $w = $Winget[$App.WingetId.ToLower()] }
    if ($w) {
        if ($w.Available) { return @{ Kind = 'update'; Text = "обновление: $($w.Version) → $($w.Available)"; Version = $w.Version; Available = $w.Available } }
        return @{ Kind = 'installed'; Text = $(if ($w.Version -and $w.Version -ne 'Unknown') { "установлено · $($w.Version)" } else { 'установлено' }); Version = $w.Version }
    }
    if ($reg) { return @{ Kind = 'installed'; Text = $(if ($reg.Version) { "установлено · $($reg.Version)" } else { 'установлено' }); Version = $reg.Version } }
    if ($null -ne $Winget -or $App.Source -eq 'web') { return @{ Kind = 'missing'; Text = 'не установлено' } }
    return @{ Kind = 'unknown'; Text = '' }
}

$script:PbTweakStatusText = @{ applied = 'применено'; partial = 'применено частично'; no = 'не применено'; unknown = '' }

# фоновая задача окна: $Sync.Apps (после реестра, затем после winget), $Sync.Tweaks, $Sync.WingetError, $Sync.Done
function Start-PbStatusScan ($Apps, $Tweaks, $Sync) {
    $entries = @(Get-PbUninstallEntries)
    $first = @{}
    foreach ($a in $Apps) { $first[$a.Id] = Get-PbAppStatus $a $entries $null }
    $Sync.Apps = $first
    $tw = @{}
    foreach ($t in $Tweaks) { $tw[$t.Id] = Get-PbTweakStatus $t }
    $Sync.Tweaks = $tw
    try {
        $wg = Get-PbWingetInstalled
        $full = @{}
        foreach ($a in $Apps) { $full[$a.Id] = Get-PbAppStatus $a $entries $wg }
        $Sync.Apps = $full
    } catch { $Sync.WingetError = $_.Exception.Message }
    $Sync.Done = $true
}
