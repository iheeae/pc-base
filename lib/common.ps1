# Tabula Rasa: общие функции. Подключается из setup.ps1 и undo.ps1 через dot-source.
# Совместимо с Windows PowerShell 5.1 (на чистой системе другого нет).

$script:PB = [ordered]@{
    Root                 = $null                  # движок (клон публичного репозитория), задаёт setup.ps1
    DataRoot             = 'C:\tabula-rasa-private'   # Мои данные (клон приватного репозитория), setup.ps1 -DataRoot
    LogDir               = Join-Path $env:ProgramData 'tabula-rasa\logs'
    Stamp                = (Get-Date -Format 'yyyy-MM-dd_HHmmss')
    Changes              = New-Object System.Collections.ArrayList
    Results              = New-Object System.Collections.ArrayList
    Manual               = New-Object System.Collections.ArrayList
    NeedExplorerRestart  = $false
    NeedReboot           = $false
    Os                   = $null
    IsDomain             = $false
    IsLaptop             = $false
    WindowShownSec       = $null      # от запуска процесса до окна (замер — gui.ps1, запись в журнал — setup.ps1)
}

# ---------- переезд pc-base → Tabula Rasa ----------
# Старые места до переименования. Папки переезжают на новые (Move-PbLegacyDir), ничего не удаляется.
$script:PbLegacy = [ordered]@{
    Root     = 'C:\pc-base'
    DataRoot = 'C:\pc-base-private'
    Local    = Join-Path $env:LOCALAPPDATA 'pc-base'
    Program  = Join-Path $env:ProgramData 'pc-base'
}

# 'moved' — переехала; 'both' — есть и старая, и новая (не трогаем); 'none' — старой нет;
# 'busy' — занята дольше $WaitSec (открыт Проводник, терминал): работать со старой
function Move-PbLegacyDir ([string]$Old, [string]$New, [int]$WaitSec = 60) {
    if (-not (Test-Path $Old)) { return 'none' }
    if (Test-Path $New) { return 'both' }
    $deadline = (Get-Date).AddSeconds($WaitSec); $said = $false
    while ($true) {
        try { Move-Item $Old $New -ErrorAction Stop; return 'moved' }
        catch {
            if ((Get-Date) -gt $deadline) { return 'busy' }
            if (-not $said) { Write-Warn2 "папка $Old используется другой программой (Проводник, терминал?); ожидание до $WaitSec с"; $said = $true }
            Start-Sleep -Seconds 2
        }
    }
}

# origin клона со старым именем репозитория → новое, не полагаясь на редирект GitHub
function Update-PbOrigin ([string]$Dir) {
    if (-not (Test-Path (Join-Path $Dir '.git'))) { return }
    $u = & git -C $Dir remote get-url origin 2>$null
    if (-not $u) { return }
    $n = $u -replace '/pc-base-private(\.git)?/?$', '/tabula-rasa-private.git' -replace '/pc-base(\.git)?/?$', '/tabula-rasa.git'
    if ($n -ne $u) { & git -C $Dir remote set-url origin $n 2>$null }
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

# PATH заново из системы и пользователя (после установок) плюс папки Git и GitHub CLI, если их ещё нет в PATH
function Update-SessionPath {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $wa = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    $env:Path = (@($m, $u, $wa) | Where-Object { $_ }) -join ';'
    foreach ($p in "$env:ProgramFiles\Git\cmd", "$env:ProgramFiles\GitHub CLI") {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path += ";$p" }
    }
}

# ---------- реестр, службы, задачи (всё пишется в журнал изменений для undo.ps1) ----------

# запись в журнал изменений и сразу на диск: если прогон оборвётся (закрыли окно, сбой питания), undo.ps1 всё равно
# откатит уже сделанное. Записей — сотни, перезапись файла целиком на каждую не заметна
function Add-PbChange ($Change) {
    [void]$script:PB.Changes.Add($Change)
    try { [void](Save-Changes) } catch { }
}

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
    Add-PbChange ([ordered]@{
        Kind = 'Reg'; Path = $Path; Name = $Name; New = $Value; Type = $Type
        OldExists = $oldExists; Old = $oldValue; OldKind = $oldKind; KeyCreated = $keyCreated
    })
}

# Значение по умолчанию у ключа, например для классического контекстного меню.
function Set-RegDefault ([string]$Path, [string]$Value) {
    $existed = Test-Path $Path
    if (-not $existed) { New-Item -Path $Path -Force | Out-Null }
    Set-Item -Path $Path -Value $Value -Force
    Add-PbChange ([ordered]@{ Kind = 'RegKey'; Path = $Path; KeyCreated = (-not $existed) })
}

function Set-SvcStart ([string]$Name, [ValidateSet('Disabled', 'Manual', 'Automatic')][string]$Start) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    $old = (Get-CimInstance Win32_Service -Filter "Name='$Name'").StartMode
    if ($Start -eq 'Disabled' -and $svc.Status -eq 'Running') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Name -StartupType $Start -ErrorAction Stop
    Add-PbChange ([ordered]@{ Kind = 'Service'; Name = $Name; Old = $old; New = $Start })
}

function Disable-Task ([string]$TaskPath, [string]$TaskName) {
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return }
    $wasEnabled = $t.State -ne 'Disabled'
    if ($wasEnabled) { Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null }
    Add-PbChange ([ordered]@{ Kind = 'Task'; TaskPath = $TaskPath; TaskName = $TaskName; WasEnabled = $wasEnabled })
}

# Удаление UWP у всех пользователей и из образа (чтобы не вернулись у новых профилей). Не откатывается.
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
        if ($pk) { Write-Ok "удалено: $n" }
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

    Write-Warn2 'winget не найден, регистрация App Installer'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    Update-SessionPath
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

    Write-Warn2 'Установка winget через модуль Microsoft.WinGet.Client'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -AllowClobber
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers -Force -Latest | Out-Null
    } catch { Write-Fail "не удалось установить winget: $($_.Exception.Message)"; return $false }
    Update-SessionPath
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# аргумент для командной строки процесса (ProcessStartInfo.Arguments)
function ConvertTo-PbArg ([string]$A) {
    if ($A -and $A -notmatch '[\s"]') { return $A }
    return '"' + ($A -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# процесс и все его потомки (winget → msiexec → установщик); без taskkill — только сам процесс
function Stop-PbProcessTree ([int]$Id) {
    if (Get-Command taskkill.exe -ErrorAction SilentlyContinue) { & taskkill.exe /PID $Id /T /F *> $null; return }
    try { (Get-Process -Id $Id -ErrorAction Stop).Kill() } catch { }
}

# winget (или $Exe) отдельным процессом с ограничением времени. Вывод — в logs\winget_<запуск>_<метка>.log, а не в журнал
# выполнения (прогресс-бары его забивали); в консоли — сколько прошло. По таймауту дерево процессов снимается, прогон
# идёт дальше. @{ Code; TimedOut; Log; Seconds }
function Invoke-PbWingetTimed ([string[]]$WingetArgs, [double]$TimeoutMin = 15, [string]$Label = 'winget', [string]$Exe = 'winget') {
    New-Item -ItemType Directory -Path $script:PB.LogDir -Force | Out-Null
    $safe = $Label -replace '[^\w.-]', '_'; if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60) }
    $log = Join-Path $script:PB.LogDir ("winget_{0}_{1}.log" -f $script:PB.Stamp, $safe)
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = (@($WingetArgs) | ForEach-Object { ConvertTo-PbArg $_ }) -join ' '
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $limit = [int]($TimeoutMin * 60); $timedOut = $false; $said = 0
    while (-not $p.WaitForExit(1000)) {
        $sec = [int]$sw.Elapsed.TotalSeconds
        if ($sec -ge $limit) { $timedOut = $true; Stop-PbProcessTree $p.Id; break }
        if ($sec - $said -ge 15) {
            $said = $sec
            Write-Host ("      … идёт {0}:{1:00}, ограничение {2} мин" -f [int][Math]::Floor($sec / 60), ($sec % 60), $TimeoutMin) -ForegroundColor DarkGray
        }
    }
    [void]$p.WaitForExit(10000)
    $text = "> $Exe $($psi.Arguments)`r`n"
    try { $text += $out.Result + $err.Result } catch { }
    try { [IO.File]::WriteAllText($log, $text, (New-Object Text.UTF8Encoding $false)) } catch { }
    $code = $null
    if (-not $timedOut -and $p.HasExited) { $code = $p.ExitCode }
    return @{ Code = $code; TimedOut = $timedOut; Log = $log; Seconds = [int]$sw.Elapsed.TotalSeconds; Out = @($text -split "`r?`n" | Select-Object -Skip 1) }
}

function Test-WingetInstalled ([string]$Id) {
    $r = Invoke-PbWingetTimed @('list', '--id', $Id, '-e', '--accept-source-agreements', '--disable-interactivity') 2 "list_$Id"
    return ($r.Code -eq 0)
}

# коды winget при установке: @{ Ok; Reboot; Text }
function Get-PbWingetCodeInfo ($Code) {
    switch ($Code) {
        0           { return @{ Ok = $true } }
        3010        { return @{ Ok = $true; Reboot = $true; Text = 'нужна перезагрузка' } }
        1641        { return @{ Ok = $true; Reboot = $true; Text = 'нужна перезагрузка' } }
        -1978335189 { return @{ Ok = $true; Text = 'обновление не требуется' } }                                       # 0x8A15002B
        -1978335135 { return @{ Ok = $true; Text = 'уже установлено' } }                                               # 0x8A150061
        -1978334967 { return @{ Ok = $true; Reboot = $true; Text = 'установка завершится после перезагрузки' } }       # 0x8A150109
        -1978334966 { return @{ Reboot = $true; Text = 'перед установкой нужна перезагрузка' } }                       # 0x8A15010A
        -1978335212 { return @{ Text = 'пакет не найден в источнике winget' } }                                         # 0x8A150014
        -1978334957 { return @{ Text = 'установщик сообщил, что конфигурация системы не поддерживает этот пакет' } }   # 0x8A150113
    }
    return @{ Text = ('winget вернул {0} (0x{1:X8})' -f $Code, ([int64]$Code -band 0xFFFFFFFF)) }
}

# TimeoutMin в каталоге — для тяжёлых пакетов; по умолчанию 15 мин, с мастером установки — 60
function Install-WingetApp ($App) {
    if (Test-WingetInstalled $App.WingetId) { Write-Skip "$($App.Name): уже установлено"; Add-Result $App.Name 'уже установлено'; return }
    $a = @('install', '--id', $App.WingetId, '-e', '--source', 'winget',
           '--accept-package-agreements', '--accept-source-agreements')
    if ($App.Interactive) { $a += '--interactive' } else { $a += @('--silent', '--disable-interactivity') }
    if ($App.Scope)    { $a += @('--scope', $App.Scope) }
    if ($App.Override) { $a += @('--override', $App.Override) }
    $limit = if ($App.TimeoutMin) { [double]$App.TimeoutMin } elseif ($App.Interactive) { 60 } else { 15 }
    Write-Host "    установка $($App.Name) ($($App.WingetId)), не дольше $limit мин..." -ForegroundColor Gray
    $r = Invoke-PbWingetTimed $a $limit $App.WingetId
    if ($r.TimedOut) {
        Write-Fail "$($App.Name): установка не завершилась за $limit мин и прервана"
        Add-Result $App.Name 'ТАЙМАУТ' "прервано через $limit мин; журнал winget: $($r.Log)"
        return
    }
    $i = Get-PbWingetCodeInfo $r.Code
    if ($i.Reboot) { $script:PB.NeedReboot = $true }
    if ($i.Ok -or (Test-WingetInstalled $App.WingetId)) {
        Write-Ok "$($App.Name)$(if ($i.Text) { ": $($i.Text)" })"; Add-Result $App.Name 'установлено' ([string]$i.Text)
    } else {
        Write-Fail "$($App.Name): $($i.Text)"; Add-Result $App.Name 'ОШИБКА' "$($i.Text); журнал winget: $($r.Log)"
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
    if (Test-UninstallEntry $App.Detect) { Write-Skip "$($App.Name): уже установлено"; Add-Result $App.Name 'уже установлено'; return }
    foreach ($u in $App.PageUrl, $App.BaseUrl) { if ($u -notmatch '^https://') { throw "адрес $u не HTTPS: загрузка без шифрования не выполняется" } }
    if (-not $App.Signer) { throw 'в каталоге не указан издатель (Signer): без проверки издателя файл с сайта не запускается' }
    Write-Host "    поиск актуальной версии на $($App.PageUrl)..." -ForegroundColor Gray
    $html = (Invoke-WebRequest -Uri $App.PageUrl -UseBasicParsing -ErrorAction Stop).Content
    $found = @([regex]::Matches($html, $App.FileRegex) | ForEach-Object {
        [pscustomobject]@{ File = $_.Value; Ver = [version]($_.Groups['v'].Value + ('.0' * [math]::Max(0, 2 - ($_.Groups['v'].Value.Split('.').Count - 1)))) }
    } | Sort-Object Ver -Descending)
    if (-not $found) { throw "на странице не найден файл по шаблону $($App.FileRegex)" }
    $file = $found[0].File
    $dir = Join-Path $env:TEMP 'tabula-rasa'; New-Item -ItemType Directory $dir -Force | Out-Null
    $dst = Join-Path $dir $file
    Write-Host "    загрузка $file..." -ForegroundColor Gray
    Invoke-WebRequest -Uri ($App.BaseUrl + $file) -OutFile $dst -UseBasicParsing -ErrorAction Stop
    $sig = Get-AuthenticodeSignature $dst
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $App.Signer) {
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
        throw "цифровая подпись не прошла проверку ($($sig.Status); $($sig.SignerCertificate.Subject)). Файл удалён и не запускался"
    }
    Write-Ok "подпись действительна: $($sig.SignerCertificate.Subject -replace ',.*$', '')"
    if ($App.Interactive) { Write-Host "    откроется мастер установки $($App.Name), пройдите его вручную" -ForegroundColor Yellow }
    $p = Start-Process -FilePath $dst -Wait -PassThru
    if ($p.ExitCode -in 3010, 1641) { $script:PB.NeedReboot = $true }
    if (Test-UninstallEntry $App.Detect) { Write-Ok $App.Name; Add-Result $App.Name 'установлено' $file }
    else { Write-Fail "$($App.Name): установщик завершился, но программа не найдена"; Add-Result $App.Name 'ОШИБКА' "код $($p.ExitCode)" }
}

function Install-App ($App) {
    try {
        switch ($App.Source) {
            'winget' { Install-WingetApp $App }
            'web'    { Install-WebApp $App }
            default  { Write-Warn2 "$($App.Name): неизвестный источник '$($App.Source)'"; Add-Result $App.Name 'пропущено' 'неизвестный источник'; return }
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
