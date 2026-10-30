# pc-base: общие функции. Подключается из setup.ps1 и undo.ps1 через dot-source.
# Совместимо с Windows PowerShell 5.1 (на чистой системе другого нет).

$script:PB = [ordered]@{
    Root                 = $null                  # движок (клон публичной репы), задаёт setup.ps1
    DataRoot             = 'C:\pc-base-private'   # свои данные (клон приватной репы), setup.ps1 -DataRoot
    LogDir               = Join-Path $env:ProgramData 'pc-base\logs'
    Stamp                = (Get-Date -Format 'yyyy-MM-dd_HHmmss')
    Changes              = New-Object System.Collections.ArrayList
    Results              = New-Object System.Collections.ArrayList
    Manual               = New-Object System.Collections.ArrayList
    NeedExplorerRestart  = $false
    NeedReboot           = $false
    Os                   = $null
    IsDomain             = $false
    IsLaptop             = $false
    InstallersDir        = $null
    InstallersAsked      = $false
    DriveInstalledNow    = $false
}

# свой конфиг программы: сначала DataRoot\configs\..., потом встроенный Root\configs\...; нет нигде — $null
function Find-PbConfig ([string]$Rel) {
    foreach ($base in @($script:PB.DataRoot, $script:PB.Root)) {
        if (-not $base) { continue }
        $p = Join-Path $base (Join-Path 'configs' $Rel)
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ---------- вывод ----------

function Write-Step  ([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok    ([string]$Text) { Write-Host "    [OK]   $Text" -ForegroundColor Green }
function Write-Skip  ([string]$Text) { Write-Host "    [--]   $Text" -ForegroundColor DarkGray }
function Write-Warn2 ([string]$Text) { Write-Host "    [!]    $Text" -ForegroundColor Yellow }
function Write-Fail  ([string]$Text) { Write-Host "    [FAIL] $Text" -ForegroundColor Red }

function Add-Result ([string]$What, [string]$Status, [string]$Details = '') {
    [void]$script:PB.Results.Add([pscustomobject]@{ 'Что' = $What; 'Статус' = $Status; 'Детали' = $Details })
}

function Add-Manual ([string]$Text) {
    if ($Text -and -not $script:PB.Manual.Contains($Text)) { [void]$script:PB.Manual.Add($Text) }
}

# ---------- окружение ----------

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EnvInfo {
    $build = [Environment]::OSVersion.Version.Build
    $script:PB.Os = if ($build -ge 22000) { '11' } else { '10' }
    try { $script:PB.IsDomain = [bool](Get-CimInstance Win32_ComputerSystem).PartOfDomain } catch { }
    try { $script:PB.IsLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop) } catch { }
}

# HKCU-твики пишутся в куст того, кто запустил скрипт. Если повышение шло через
# другую учётку (LAPS, доменный админ), настройки уедут не тому пользователю.
function Test-SameUserAsDesktop {
    try {
        $p = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
        if (-not $p) { return $true }
        $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner
        return ($o.User -eq $env:USERNAME)
    } catch { return $true }
}

function Update-SessionPath {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $wa = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $env:Path = (@($m, $u, $wa) | Where-Object { $_ }) -join ';'
}

function Add-MachinePath ([string]$Dir) {
    $cur = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = $cur -split ';' | Where-Object { $_ }
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'Machine')
        [void]$script:PB.Changes.Add([ordered]@{ Kind = 'MachinePath'; Dir = $Dir })
    }
    Update-SessionPath
}

# ---------- реестр, службы, задачи (всё пишется в журнал изменений для undo.ps1) ----------

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')][string]$Type = 'DWord'
    )
    $keyCreated = $false
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null; $keyCreated = $true }
    $oldExists = $false; $oldValue = $null; $oldKind = $null
    try {
        $key = Get-Item -Path $Path
        if ($key.GetValueNames() -contains $Name) {
            $oldExists = $true
            $oldValue = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            $oldKind = $key.GetValueKind($Name).ToString()
        }
    } catch { }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    [void]$script:PB.Changes.Add([ordered]@{
        Kind = 'Reg'; Path = $Path; Name = $Name; New = $Value; Type = $Type
        OldExists = $oldExists; Old = $oldValue; OldKind = $oldKind; KeyCreated = $keyCreated
    })
}

# Значение по умолчанию у ключа, например для классического контекстного меню.
function Set-RegDefault ([string]$Path, [string]$Value) {
    $existed = Test-Path $Path
    if (-not $existed) { New-Item -Path $Path -Force | Out-Null }
    Set-Item -Path $Path -Value $Value -Force
    [void]$script:PB.Changes.Add([ordered]@{ Kind = 'RegKey'; Path = $Path; KeyCreated = (-not $existed) })
}

function Set-SvcStart ([string]$Name, [ValidateSet('Disabled', 'Manual', 'Automatic')][string]$Start) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    $old = (Get-CimInstance Win32_Service -Filter "Name='$Name'").StartMode
    if ($Start -eq 'Disabled' -and $svc.Status -eq 'Running') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Name -StartupType $Start -ErrorAction Stop
    [void]$script:PB.Changes.Add([ordered]@{ Kind = 'Service'; Name = $Name; Old = $old; New = $Start })
}

function Disable-Task ([string]$TaskPath, [string]$TaskName) {
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return }
    $wasEnabled = $t.State -ne 'Disabled'
    if ($wasEnabled) { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null }
    [void]$script:PB.Changes.Add([ordered]@{ Kind = 'Task'; TaskPath = $TaskPath; TaskName = $TaskName; WasEnabled = $wasEnabled })
}

# Снос UWP у всех пользователей и из образа (чтобы не вернулись у новых профилей). Не откатывается.
function Remove-Appx ([string[]]$Names) {
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($n in $Names) {
        $pk = Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue
        foreach ($p in $pk) {
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
            catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { Write-Warn2 "$n : $($_.Exception.Message)" } }
        }
        foreach ($p in ($prov | Where-Object { $_.DisplayName -eq $n })) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null } catch { }
        }
        if ($pk) { Write-Ok "снесено: $n" }
    }
}

function Save-Changes {
    if (-not (Test-Path $script:PB.LogDir)) { New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null }
    $f = Join-Path $script:PB.LogDir "changes_$($script:PB.Stamp).json"
    ConvertTo-Json -InputObject @($script:PB.Changes) -Depth 6 | Set-Content -Path $f -Encoding UTF8
    return $f
}

# ---------- winget ----------

function Initialize-Winget {
    Update-SessionPath
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

    Write-Warn2 'winget не найден, пробую зарегистрировать App Installer'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    Update-SessionPath
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

    Write-Warn2 'Ставлю winget через модуль Microsoft.WinGet.Client'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -AllowClobber
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    } catch { Write-Fail "winget не поставился: $($_.Exception.Message)"; return $false }
    Update-SessionPath
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Test-WingetInstalled ([string]$Id) {
    $null = & winget list --id $Id -e --accept-source-agreements --disable-interactivity 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Install-WingetApp ($App) {
    if (Test-WingetInstalled $App.WingetId) { Write-Skip "$($App.Name): уже стоит"; Add-Result $App.Name 'уже стоит'; return }
    $a = @('install', '--id', $App.WingetId, '-e', '--source', 'winget',
           '--accept-package-agreements', '--accept-source-agreements')
    if ($App.Interactive) { $a += '--interactive' } else { $a += @('--silent', '--disable-interactivity') }
    if ($App.Scope)    { $a += @('--scope', $App.Scope) }
    if ($App.Override) { $a += @('--override', $App.Override) }
    Write-Host "    ставлю $($App.Name) ($($App.WingetId))..." -ForegroundColor Gray
    & winget @a
    $code = $LASTEXITCODE
    # 0x8A15002B — обновление не требуется, 0x8A150061 — уже установлен; 3010/1641 — нужна перезагрузка
    if ($code -in 3010, 1641) { $script:PB.NeedReboot = $true }
    if ($code -in 0, 3010, 1641, -1978335189, -1978335135 -or (Test-WingetInstalled $App.WingetId)) {
        Write-Ok $App.Name; Add-Result $App.Name 'поставлено'
    } else {
        Write-Fail "$($App.Name): winget вернул $code"; Add-Result $App.Name 'ОШИБКА' "winget exit $code"
    }
}

# ---------- установка с официального сайта (Source = 'web') ----------
# Страница загрузки → самая свежая версия по FileRegex → скачать → проверить цифровую подпись → запустить.

function Test-UninstallEntry ([string]$Like) {
    if (-not $Like) { return $false }
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    return [bool](Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Like } | Select-Object -First 1)
}

function Install-WebApp ($App) {
    if (Test-UninstallEntry $App.Detect) { Write-Skip "$($App.Name): уже стоит"; Add-Result $App.Name 'уже стоит'; return }
    Write-Host "    ищу свежую версию на $($App.PageUrl)..." -ForegroundColor Gray
    $html = (Invoke-WebRequest -Uri $App.PageUrl -UseBasicParsing -ErrorAction Stop).Content
    $found = @([regex]::Matches($html, $App.FileRegex) | ForEach-Object {
        [pscustomobject]@{ File = $_.Value; Ver = [version]($_.Groups['v'].Value + ('.0' * [math]::Max(0, 2 - ($_.Groups['v'].Value.Split('.').Count - 1)))) }
    } | Sort-Object Ver -Descending)
    if (-not $found) { throw "на странице не нашлось файла по шаблону $($App.FileRegex)" }
    $file = $found[0].File
    $dir = Join-Path $env:TEMP 'pc-base'; New-Item -ItemType Directory $dir -Force | Out-Null
    $dst = Join-Path $dir $file
    Write-Host "    качаю $file..." -ForegroundColor Gray
    Invoke-WebRequest -Uri ($App.BaseUrl + $file) -OutFile $dst -UseBasicParsing -ErrorAction Stop
    $sig = Get-AuthenticodeSignature $dst
    if ($sig.Status -ne 'Valid' -or ($App.Signer -and $sig.SignerCertificate.Subject -notmatch $App.Signer)) {
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
        throw "подпись не прошла проверку ($($sig.Status); $($sig.SignerCertificate.Subject)) — файл удалён, не запускаю"
    }
    Write-Ok "подпись в порядке: $($sig.SignerCertificate.Subject -replace ',.*$', '')"
    if ($App.Interactive) { Write-Host "    откроется установщик $($App.Name) — пройди его руками" -ForegroundColor Yellow }
    $p = Start-Process -FilePath $dst -Wait -PassThru
    if ($p.ExitCode -in 3010, 1641) { $script:PB.NeedReboot = $true }
    if (Test-UninstallEntry $App.Detect) { Write-Ok $App.Name; Add-Result $App.Name 'поставлено' $file }
    else { Write-Fail "$($App.Name): установщик закрылся, а программы нет"; Add-Result $App.Name 'ОШИБКА' "код $($p.ExitCode)" }
}

# ---------- pc-base-exe с Google Drive → рабочий стол ----------
# Ничего не ставится: выбранные файлы из папки pc-base-exe (корень Диска) копируются на рабочий стол,
# дальше ставишь руками. Список читается с Диска при каждом запуске — докинул файл, он сразу виден.

$script:DriveRel = 'pc-base-exe'

function Find-InstallersDir {
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($top in @('Мой диск', 'My Drive')) {
            $p = Join-Path $d.Root (Join-Path $top $script:DriveRel)
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Select-FolderDialog ([string]$Title) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Title
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

function Get-InstallersDir {
    if ($script:PB.InstallersAsked) { return $script:PB.InstallersDir }
    $script:PB.InstallersAsked = $true

    $dir = Find-InstallersDir
    while (-not $dir) {
        Write-Host ''
        Write-Host '    Нужна папка ' -NoNewline
        Write-Host $script:DriveRel -ForegroundColor White -NoNewline
        Write-Host ' с Google Drive'
        Write-Host '      [1] Поставить Google Drive, войти в аккаунт и подцепить папку'
        Write-Host '      [2] Указать папку вручную (флешка, сеть)'
        Write-Host '      [3] Пропустить'
        $c = Read-Host '    Выбор'
        switch ($c) {
            '1' {
                if (-not (Test-WingetInstalled 'Google.GoogleDrive')) {
                    & winget install --id Google.GoogleDrive -e --source winget --silent --accept-package-agreements --accept-source-agreements
                    $script:PB.DriveInstalledNow = $true
                }
                $exe = Get-ChildItem "$env:ProgramFiles\Google\Drive File Stream" -Recurse -Filter GoogleDriveFS.exe -ErrorAction SilentlyContinue |
                       Sort-Object FullName -Descending | Select-Object -First 1
                if ($exe) { Start-Process $exe.FullName }
                Write-Host '    Войди в аккаунт в окне Google Drive и подожди, пока появится диск (обычно G:).' -ForegroundColor Yellow
                do {
                    $r = Read-Host '    Enter — проверить, S — сдаться'
                    $dir = Find-InstallersDir
                } until ($dir -or $r -match '^[SsЫы]')
            }
            '2' { $dir = Select-FolderDialog "Папка $($script:DriveRel)" }
            '3' { $script:PB.InstallersDir = $null; return $null }
        }
    }
    Write-Ok "источник: $dir"
    $script:PB.InstallersDir = $dir
    return $dir
}

function Get-DriveItems ([string]$Dir) {
    if (-not $Dir) { return @() }
    return @(Get-ChildItem -Path $Dir -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | Sort-Object Name)
}

# $Names — что копировать; $Ask — показать список с галочками (если в окне Диск ещё не был виден)
function Copy-ExeToDesktop ([string[]]$Names, [switch]$Ask) {
    $what = "$($script:DriveRel) → рабочий стол"
    $dir = Get-InstallersDir
    if (-not $dir) { Write-Skip 'папка не подключена'; Add-Result $what 'пропущено' 'папка не подключена'; return }

    $all = Get-DriveItems $dir
    if (-not $all.Count) { Write-Warn2 "$dir пустая"; Add-Result $what 'пусто'; return }
    if ($Ask) {
        $picked = Show-FilePicker -Items $all -Preselect $Names
        if ($null -eq $picked) { Write-Skip 'выбор отменён'; Add-Result $what 'пропущено' 'отменено'; return }
        $Names = $picked
    }
    $items = @($all | Where-Object { $Names -contains $_.Name })
    $missing = @($Names | Where-Object { $all.Name -notcontains $_ })
    foreach ($m in $missing) { Write-Warn2 "на Диске больше нет: $m" }
    if (-not $items.Count) { Write-Skip 'ничего не выбрано'; Add-Result $what 'пропущено' 'ничего не выбрано'; return }

    $dst = Join-Path ([Environment]::GetFolderPath('Desktop')) $script:DriveRel
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Write-Host "    качаю $($items.Count) шт. в $dst (с Диска тянется по сети, может занять время)..." -ForegroundColor Gray
    foreach ($i in $items) { Copy-Item -Path $i.FullName -Destination $dst -Recurse -Force -ErrorAction Stop; Write-Host "      + $($i.Name)" }
    Write-Ok "$($items.Count) → $dst"
    Add-Result $what 'скопировано' "$($items.Count) шт."
    Add-Manual "Поставить руками из $dst"
}

function Install-App ($App) {
    try {
        switch ($App.Source) {
            'winget' { Install-WingetApp $App }
            'web'    { Install-WebApp $App }
            default  { Write-Warn2 "$($App.Name): неизвестный источник '$($App.Source)'"; Add-Result $App.Name 'пропущено' 'источник?'; return }
        }
        if ($App.Manual) { Add-Manual "$($App.Name): $($App.Manual)" }
    } catch {
        Write-Fail "$($App.Name): $($_.Exception.Message)"; Add-Result $App.Name 'ОШИБКА' $_.Exception.Message
    }
}

function Invoke-Tweak ($Tweak) {
    Write-Host "  - $($Tweak.Name)" -ForegroundColor White
    try {
        & $Tweak.Apply
        Add-Result $Tweak.Name 'применено'
        if ($Tweak.Manual) { Add-Manual "$($Tweak.Name): $($Tweak.Manual)" }
    } catch {
        Write-Fail $_.Exception.Message; Add-Result $Tweak.Name 'ОШИБКА' $_.Exception.Message
    }
}
