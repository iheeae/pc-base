# Tabula Rasa: сохранения галочек и «Мои данные».
#
# «Мои данные» — клон своего приватного репозитория <логин>/tabula-rasa-private в $script:PB.DataRoot (C:\tabula-rasa-private).
# Подключены (есть DataRoot\.git) — сохранения лежат в DataRoot\saves и каждое изменение коммитится и отправляется;
# нет сети — коммит остаётся локальным, отправится при следующем запуске. Не подключены — сохранения лежат
# в %LOCALAPPDATA%\tabula-rasa\saves, после подключения их можно перенести.
#
# Сохранение — только галочки: Apps, Tweaks, Configs (у кого выбрано «с моими настройками»), Files, FilesAsk
# плюс Name, Created, Machine, Version. Настройки программ живут отдельно, в DataRoot\configs.

$script:PbSaveVersion = 1
$script:PbDataRepoName = 'tabula-rasa-private'

function Get-PbLocalSaveDir { Join-Path $env:LOCALAPPDATA 'tabula-rasa\saves' }
function Test-PbDataConnected { Test-Path (Join-Path $script:PB.DataRoot '.git') }
function Get-PbSaveDir {
    if (Test-PbDataConnected) { return (Join-Path $script:PB.DataRoot 'saves') }
    return (Get-PbLocalSaveDir)
}

# git в своих данных: возвращает @{ Code; Out }, вывод — строками (stderr тоже)
function Invoke-PbGit {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = @(& git -C $script:PB.DataRoot @args 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $prev }
    return @{ Code = $LASTEXITCODE; Out = $out }
}

# ---------- файлы сохранений ----------

function ConvertTo-SaveFileName ([string]$Name) {
    $n = ($Name -replace '[\\/:*?"<>|\x00-\x1F]', '_').Trim(' .')
    if (-not $n) { $n = 'Сохранение' }
    return "$n.json"
}

# читает и новый формат, и старые наборы без Name/Created/Machine
function Read-SaveFile ([string]$Path) {
    $j = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $created = $null
    if ($j.Created) { try { $created = [datetime]::Parse($j.Created, [Globalization.CultureInfo]::InvariantCulture) } catch { } }
    if (-not $created) { $created = (Get-Item $Path).LastWriteTime }
    return @{
        Apps     = @($j.Apps | Where-Object { $_ })
        Configs  = @($j.Configs | Where-Object { $_ })
        Tweaks   = @($j.Tweaks | Where-Object { $_ })
        Files    = @($j.Files | Where-Object { $_ })
        FilesAsk = [bool]$j.FilesAsk
        Name     = $(if ($j.Name) { [string]$j.Name } else { [IO.Path]::GetFileNameWithoutExtension($Path) })
        Created  = $created
        Machine  = [string]$j.Machine
    }
}

function Write-SaveFile ([string]$Path, [hashtable]$Sel, [string]$Name, $Created, [string]$Machine) {
    if (-not $Created) { $Created = Get-Date }
    if (-not $Machine) { $Machine = $env:COMPUTERNAME }
    $json = [ordered]@{
        Version = $script:PbSaveVersion; Name = $Name
        Created = ([datetime]$Created).ToString('s', [Globalization.CultureInfo]::InvariantCulture); Machine = $Machine
        Apps = @($Sel.Apps); Configs = @($Sel.Configs); Tweaks = @($Sel.Tweaks)
        Files = @($Sel.Files); FilesAsk = [bool]$Sel.FilesAsk
    } | ConvertTo-Json -Depth 5
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

# список сохранений: сначала свежие. Store — 'data' (Мои данные) или 'local'
function Get-PbSaves ([switch]$LocalOnly) {
    $dirs = @()
    if (-not $LocalOnly -and (Test-PbDataConnected)) { $dirs += @{ Dir = (Join-Path $script:PB.DataRoot 'saves'); Store = 'data' } }
    else { $dirs += @{ Dir = (Get-PbLocalSaveDir); Store = 'local' } }
    $out = foreach ($d in $dirs) {
        if (-not (Test-Path $d.Dir)) { continue }
        foreach ($f in (Get-ChildItem $d.Dir -Filter *.json -File)) {
            try { $s = Read-SaveFile $f.FullName } catch { continue }
            [pscustomobject]@{ Name = $s.Name; Path = $f.FullName; Created = $s.Created; Machine = $s.Machine; Store = $d.Store }
        }
    }
    return @($out | Sort-Object Created -Descending)
}

# -Selection: путь → Мои данные → локальные; по имени сохранения или имени файла
function Find-PbSave ([string]$NameOrPath) {
    if (Test-Path $NameOrPath -PathType Leaf) { return (Resolve-Path $NameOrPath).Path }
    $key = $NameOrPath -replace '\.json$', ''
    foreach ($dir in @((Join-Path $script:PB.DataRoot 'saves'), (Get-PbLocalSaveDir))) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($f in (Get-ChildItem $dir -Filter *.json -File)) {
            if ($f.BaseName -eq $key) { return $f.FullName }
            try { if ((Read-SaveFile $f.FullName).Name -eq $key) { return $f.FullName } } catch { }
        }
    }
    return $null
}

function Get-FreeSavePath ([string]$Dir, [string]$Name, [string]$Except) {
    $base = [IO.Path]::GetFileNameWithoutExtension((ConvertTo-SaveFileName $Name))
    $p = Join-Path $Dir "$base.json"; $i = 2
    while ((Test-Path $p) -and $p -ne $Except) { $p = Join-Path $Dir "$base ($i).json"; $i++ }
    return $p
}

# коммит изменений в saves\ своих данных; отправка — отдельно (Push-PbData), чтобы окно не ждало сеть
function Save-PbDataCommit ([string]$Message) {
    [void](Invoke-PbGit add -A -- saves)
    $r = Invoke-PbGit commit -q -m $Message
    if ($r.Code -ne 0 -and ($r.Out -join "`n") -notmatch 'nothing (added )?to commit|no changes added to commit') {
        throw "git commit: $($r.Out -join ' ')"
    }
}

# сохранить текущее: одноимённое перезаписывается (это «обновить сохранение»). Возвращает путь
function Save-PbSave ([string]$Name, [hashtable]$Sel) {
    $dir = Get-PbSaveDir
    $p = Join-Path $dir (ConvertTo-SaveFileName $Name)
    Write-SaveFile $p $Sel $Name
    if (Test-PbDataConnected) { Save-PbDataCommit "Сохранение: $Name" }
    return $p
}

function Rename-PbSave ([string]$Path, [string]$NewName) {
    $s = Read-SaveFile $Path
    $dir = Split-Path $Path
    $np = Get-FreeSavePath $dir $NewName $Path
    Write-SaveFile $np $s $NewName $s.Created $s.Machine
    if ($np -ne $Path) { Remove-Item $Path -Force }
    # локальный файл git не видит: коммит выйдет пустым и пропустится
    if (Test-PbDataConnected) { Save-PbDataCommit "Сохранение переименовано: $($s.Name) → $NewName" }
    return $np
}

function Remove-PbSave ([string]$Path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    try { $name = (Read-SaveFile $Path).Name } catch { }
    Remove-Item $Path -Force
    if (Test-PbDataConnected) { Save-PbDataCommit "Удалено сохранение: $name" }
}

# локальные сохранения → Мои данные одним коммитом. Совпало имя — рядом с номером, ничего не теряется
function Move-PbLocalSaves {
    $local = @(Get-PbSaves -LocalOnly)
    if (-not $local.Count -or -not (Test-PbDataConnected)) { return 0 }
    $dir = Join-Path $script:PB.DataRoot 'saves'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($s in $local) {
        $np = Get-FreeSavePath $dir $s.Name
        Move-Item $s.Path $np
    }
    Save-PbDataCommit "Перенос локальных сохранений с $($env:COMPUTERNAME): $($local.Count)"
    return $local.Count
}

# ---------- состояние и отправка ----------

# Connected, User (логин GitHub), Pending — сколько коммитов не отправлено
function Get-PbDataState {
    $st = @{ Connected = (Test-PbDataConnected); User = $null; Pending = 0; Repo = $null }
    if (-not $st.Connected) { return $st }
    $st.User = ((Invoke-PbGit config user.name).Out | Select-Object -First 1)
    $url = ((Invoke-PbGit remote get-url origin).Out | Select-Object -First 1)
    if ($url -match 'github\.com[/:]([^/]+/[^/]+?)(\.git)?/?$') { $st.Repo = $Matches[1] }
    $r = Invoke-PbGit rev-list --count '@{u}..HEAD'
    if ($r.Code -eq 0) { $st.Pending = [int]($r.Out | Select-Object -First 1) }
    return $st
}

# git pull --rebase + push; нет сети — коммиты остаются и уйдут в следующий раз. Возвращает $true, если всё отправлено
function Push-PbData {
    if (-not (Test-PbDataConnected)) { return $true }
    # клон мог остаться на другой ветке (проверка PR и т.п.) — тогда сохранения уходили бы не туда.
    # Без незакоммиченных изменений возвращаемся на основную ветку репозитория; с ними — не трогаем.
    $def = 'master'
    $r = Invoke-PbGit symbolic-ref --short refs/remotes/origin/HEAD
    if ($r.Code -eq 0 -and "$($r.Out | Select-Object -First 1)" -match '^origin/(.+)$') { $def = $Matches[1] }
    $cur = "$((Invoke-PbGit symbolic-ref --short -q HEAD).Out | Select-Object -First 1)"
    if ($cur -ne $def -and -not (Invoke-PbGit status --porcelain).Out) { [void](Invoke-PbGit checkout -q $def) }
    [void](Invoke-PbGit pull -q --rebase)
    $r = Invoke-PbGit push -q
    return $r.Code -eq 0
}

# ---------- подключение ----------

function Update-PbPath {
    $env:Path = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')) -join ';'
    foreach ($p in "$env:ProgramFiles\Git\cmd", "$env:ProgramFiles\GitHub CLI") {
        if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path += ";$p" }
    }
}

# Подключить Мои данные. Идёт в фоне; о ходе пишет в $Sync: Step (текст), Code и Url (вход в GitHub), Error.
# Шаги: gh (поставить через winget) → вход в браузере → <логин>/tabula-rasa-private (создать приватной, если нет) →
# клон в DataRoot (или pull, если уже есть) → имя и noreply-почта для коммитов.
function Connect-PbData ($Sync) {
    function Step ([string]$T) { $Sync.Step = $T }
    Update-PbPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git не установлен. Запустите Tabula Rasa через загрузчик: он устанавливает Git.' }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Step 'Установка GitHub CLI…'
        & winget install --id GitHub.cli -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        Update-PbPath
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Не удалось установить GitHub CLI через winget.' }
    }

    Step 'Проверка входа в GitHub…'
    $auth = @(& gh auth status --hostname github.com 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -and ($auth -join "`n") -match 'Failed to log in') {
        # учётка есть, но проверить не вышло: нет сети или токен отозван — новый вход тут не поможет
        $why = @(& gh api user 2>&1 | ForEach-Object { "$_" }) -join ' '
        if ($why -match 'dial tcp|timeout|no such host|connection|socket') { throw "Нет связи с GitHub: $why" }
        throw "Сохранённый вход в GitHub недействителен. Выполните gh auth logout и подключитесь снова. $why"
    }
    if ($LASTEXITCODE -ne 0) {
        Step 'Ожидание входа в GitHub в браузере…'
        $psi = New-Object Diagnostics.ProcessStartInfo 'gh', 'auth login --hostname github.com --git-protocol https --web --skip-ssh-key'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardInput = $true
        $p = [Diagnostics.Process]::Start($psi)
        $Sync.Pid = $p.Id
        $p.StandardInput.Close()
        $tail = @()
        while ($null -ne ($line = $p.StandardError.ReadLine())) {
            if ($line -match 'code[^A-Z0-9]*\(?([A-Z0-9]{4}-[A-Z0-9]{4})\)?') { $Sync.Code = $Matches[1] }
            elseif ($line -match '(https://\S+/login/device)') { $Sync.Url = $Matches[1] }
            elseif ($line.Trim()) { $tail = @($tail + $line.Trim()) | Select-Object -Last 3 }
        }
        $p.WaitForExit()
        $Sync.Code = $null; $Sync.Pid = $null
        if ($p.ExitCode -ne 0) { throw ("Вход в GitHub не завершён. " + ($tail -join ' ')).Trim() }
    }
    & gh auth setup-git --hostname github.com 2>$null | Out-Null

    $login = (& gh api user --jq .login 2>$null | Select-Object -First 1)
    $id = (& gh api user --jq .id 2>$null | Select-Object -First 1)
    if (-not $login) { throw 'Не удалось получить имя пользователя GitHub (gh api user).' }
    $repo = "$login/$($script:PbDataRepoName)"

    if (Test-Path (Join-Path $script:PB.DataRoot '.git')) {
        Step "Обновление $($script:PB.DataRoot)…"
        [void](Invoke-PbGit pull -q --rebase)
    } else {
        if ((Test-Path $script:PB.DataRoot) -and @(Get-ChildItem $script:PB.DataRoot -Force).Count) {
            throw "Папка $($script:PB.DataRoot) уже существует и не является клоном репозитория. Переименуйте или удалите её."
        }
        & gh repo view $repo --json name *> $null
        if ($LASTEXITCODE -ne 0) {
            Step "Создание приватного репозитория $repo…"
            & gh repo create $repo --private --add-readme --description 'Мои данные для Tabula Rasa' *> $null
            if ($LASTEXITCODE -ne 0) { throw "Не удалось создать репозиторий $repo." }
        }
        Step "Клонирование $repo…"
        & git clone -q "https://github.com/$repo.git" $script:PB.DataRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Не удалось клонировать $repo." }
    }
    [void](Invoke-PbGit config user.name $login)
    [void](Invoke-PbGit config user.email "$id+$login@users.noreply.github.com")
    [void](Invoke-PbGit config core.quotepath false)
    Step 'Готово'
    return $login
}

# ---------- отключение ----------

# что удалит «Отключить и удалить с этого компьютера» — для подтверждения
function Get-PbEraseList {
    $l = @()
    if (Test-Path $script:PB.DataRoot) { $l += "папка $($script:PB.DataRoot) со всем содержимым" }
    if (Get-Command gh -ErrorAction SilentlyContinue) { $l += 'вход в GitHub CLI (gh auth logout)' }
    $l += 'сохранённый пароль/токен git для github.com (Диспетчер учётных данных)'
    $l += 'настройку git «брать токен из gh» для github.com'
    return $l
}

# после обслуживания чужого компьютера: личные данные и вход удаляются. Возвращает список того, что не удалось
function Disconnect-PbData {
    $fail = @()
    Update-PbPath
    if (Test-Path $script:PB.DataRoot) {
        try {
            Get-ChildItem $script:PB.DataRoot -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }   # объекты git — только чтение
            Remove-Item $script:PB.DataRoot -Recurse -Force -ErrorAction Stop
        } catch { $fail += "папка $($script:PB.DataRoot): $($_.Exception.Message)" }
    }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $users = @(& gh auth status --hostname github.com 2>&1 | ForEach-Object { "$_" } |
            Where-Object { $_ -match 'account (\S+)' } | ForEach-Object { if ($_ -match 'account (\S+)') { $Matches[1] } })
        foreach ($u in $users) { & gh auth logout --hostname github.com --user $u *> $null }
        & gh auth status --hostname github.com *> $null
        if ($LASTEXITCODE -eq 0) { $fail += 'вход gh в github.com сохранился' }
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        foreach ($h in 'github.com', 'gist.github.com') {
            & git config --global --unset-all "credential.https://$h.helper" 2>$null
        }
        "protocol=https`nhost=github.com`n`n" | & git credential reject 2>$null
    }
    & cmdkey.exe /delete:git:https://github.com *> $null
    return $fail
}
