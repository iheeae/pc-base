# Tabula Rasa: сохранения галочек и «Мои данные».
#
# «Мои данные» — клон своего приватного репозитория <логин>/tabula-rasa-private в $script:PB.DataRoot (C:\tabula-rasa-private).
# Подключены (есть DataRoot\.git) — сохранения лежат в DataRoot\saves и каждое изменение коммитится и отправляется;
# нет сети — коммит остаётся локальным, отправится при следующем запуске. Не подключены — сохранения лежат
# в %LOCALAPPDATA%\tabula-rasa\saves, после подключения их можно перенести.
#
# Разметка репозитория — манифест tabula-rasa.json (format, created, engine), README, saves\, configs\, catalog\,
# .gitignore от секретов (Install-PbDataLayout). Манифест новее движка — только чтение. Репозиторий стал публичным —
# отправка не выполняется (Test-PbDataPrivate перед каждым push).
#
# Сохранение — только галочки: Apps, Tweaks, Configs (у кого выбрано «с моими настройками»), Files (имена ассетов
# релиза files, lib\files.ps1) плюс Name, Created, Machine, Version. Настройки программ живут отдельно, в DataRoot\configs.

$script:PbSaveVersion = 1
$script:PbDataRepoName = 'tabula-rasa-private'
$script:PbLayoutFormat = 1          # версия разметки репозитория данных; больше — новее движка, только чтение
$script:PbManifest = 'tabula-rasa.json'

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

# gh: возвращает @{ Code; Out }, stderr — строками вместе с выводом
function Invoke-PbGh {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = @(& gh @args 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $prev }
    return @{ Code = $LASTEXITCODE; Out = $out }
}

# понятный текст ошибки gh: нет сети, нет входа, нет доступа
function Get-PbGhError ([string[]]$Out, [string]$What) {
    $t = (@($Out) | Where-Object { $_ }) -join ' '
    if ($t -match 'dial tcp|timeout|no such host|connection|socket|network') { return "Нет связи с GitHub. $t" }
    if ($t -match 'auth login|not logged|HTTP 401|authentication') { return "Вход в GitHub CLI не выполнен: подключите «Мои данные» заново. $t" }
    if ($t -match 'HTTP 403') { return "Нет доступа к репозиторию. $t" }
    return "$What $t".Trim()
}

# ---------- файлы сохранений ----------

function ConvertTo-SaveFileName ([string]$Name) {
    $n = ($Name -replace '[\\/:*?"<>|\x00-\x1F]', '_').Trim(' .')
    if (-not $n) { $n = 'Сохранение' }
    return "$n.json"
}

# читает и новый формат, и старые наборы без Name/Created/Machine; FilesAsk старых сохранений не нужен и пропускается
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
        Files = @($Sel.Files)
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

# коммит изменений своих данных ($Paths — внутри DataRoot); отправка — отдельно (Push-PbData), чтобы окно не ждало сеть
function Save-PbDataCommit ([string]$Message, [string[]]$Paths = @('saves')) {
    Assert-PbDataWritable
    [void](Invoke-PbGit add -A -- @Paths)
    $r = Invoke-PbGit commit -q -m $Message
    if ($r.Code -ne 0 -and ($r.Out -join "`n") -notmatch 'nothing (added )?to commit|no changes added to commit') {
        throw "git commit: $($r.Out -join ' ')"
    }
}

# сохранить текущее: одноимённое перезаписывается (это «обновить сохранение»). Возвращает путь
function Save-PbSave ([string]$Name, [hashtable]$Sel) {
    if (Test-PbDataConnected) { Assert-PbDataWritable }
    $dir = Get-PbSaveDir
    $p = Join-Path $dir (ConvertTo-SaveFileName $Name)
    Write-SaveFile $p $Sel $Name
    if (Test-PbDataConnected) { Save-PbDataCommit "Профиль: $Name" }
    return $p
}

function Rename-PbSave ([string]$Path, [string]$NewName) {
    if (Test-PbDataConnected) { Assert-PbDataWritable }
    $s = Read-SaveFile $Path
    $dir = Split-Path $Path
    $np = Get-FreeSavePath $dir $NewName $Path
    Write-SaveFile $np $s $NewName $s.Created $s.Machine
    if ($np -ne $Path) { Remove-Item $Path -Force }
    # локальный файл git не видит: коммит выйдет пустым и пропустится
    if (Test-PbDataConnected) { Save-PbDataCommit "Профиль переименован: $($s.Name) → $NewName" }
    return $np
}

function Remove-PbSave ([string]$Path) {
    if (Test-PbDataConnected) { Assert-PbDataWritable }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    try { $name = (Read-SaveFile $Path).Name } catch { }
    Remove-Item $Path -Force
    if (Test-PbDataConnected) { Save-PbDataCommit "Удалён профиль: $name" }
}

# локальные сохранения → Мои данные одним коммитом. Совпало имя — рядом с номером, ничего не теряется
function Move-PbLocalSaves {
    $local = @(Get-PbSaves -LocalOnly)
    if (-not $local.Count -or -not (Test-PbDataConnected)) { return 0 }
    Assert-PbDataWritable
    $dir = Join-Path $script:PB.DataRoot 'saves'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($s in $local) {
        $np = Get-FreeSavePath $dir $s.Name
        Move-Item $s.Path $np
    }
    Save-PbDataCommit "Перенос локальных профилей с $($env:COMPUTERNAME): $($local.Count)"
    return $local.Count
}

# ---------- состояние и отправка ----------

# <владелец>/<репозиторий> «Моих данных» из origin; не подключены или origin не на GitHub — $null
function Get-PbDataRepo {
    if (-not (Test-PbDataConnected)) { return $null }
    $url = ((Invoke-PbGit remote get-url origin).Out | Select-Object -First 1)
    if ($url -match 'github\.com[/:]([^/]+/[^/]+?)(\.git)?/?$') { return $Matches[1] }
    return $null
}

# Connected, User (логин GitHub), Repo, Pending — сколько коммитов не отправлено
function Get-PbDataState {
    $st = @{ Connected = (Test-PbDataConnected); User = $null; Pending = 0; Repo = $null }
    if (-not $st.Connected) { return $st }
    $st.User = ((Invoke-PbGit config user.name).Out | Select-Object -First 1)
    $st.Repo = Get-PbDataRepo
    $r = Invoke-PbGit rev-list --count '@{u}..HEAD'
    if ($r.Code -eq 0) { $st.Pending = [int]($r.Out | Select-Object -First 1) }
    return $st
}

# 'private' | 'public' | 'unknown' (нет сети, нет gh). Публичный репозиторий данных опасен: в настройках программ
# бывают личные данные
function Test-PbDataPrivate ([string]$Repo) {
    if (-not $Repo) { $Repo = Get-PbDataRepo }
    if (-not $Repo -or -not (Get-Command gh -ErrorAction SilentlyContinue)) { return 'unknown' }
    $r = Invoke-PbGh api "repos/$Repo" --jq .private
    if ($r.Code -ne 0) { return 'unknown' }
    switch (($r.Out | Select-Object -First 1)) { 'true' { return 'private' } 'false' { return 'public' } }
    return 'unknown'
}

# git pull --rebase + push. 'ok' — всё отправлено; 'offline' — нет сети (коммиты уйдут в следующий раз);
# 'public' — репозиторий стал публичным, отправка не выполнялась
function Push-PbData {
    if (-not (Test-PbDataConnected)) { return 'ok' }
    Update-PbPath
    # клон мог остаться на другой ветке (проверка PR и т.п.) — тогда сохранения уходили бы не туда.
    # Без незакоммиченных изменений возвращаемся на основную ветку репозитория; с ними — не трогаем.
    $def = 'master'
    $r = Invoke-PbGit symbolic-ref --short refs/remotes/origin/HEAD
    if ($r.Code -eq 0 -and "$($r.Out | Select-Object -First 1)" -match '^origin/(.+)$') { $def = $Matches[1] }
    $cur = "$((Invoke-PbGit symbolic-ref --short -q HEAD).Out | Select-Object -First 1)"
    if ($cur -ne $def -and -not (Invoke-PbGit status --porcelain).Out) { [void](Invoke-PbGit checkout -q $def) }
    [void](Invoke-PbGit pull -q --rebase)
    $vis = Test-PbDataPrivate
    if ($vis -eq 'public') { return 'public' }
    if ($vis -ne 'private') { return 'offline' }
    $r = Invoke-PbGit push -q -u origin HEAD
    if ($r.Code -eq 0) { return 'ok' }
    return 'offline'
}

function Get-PbPublicWarning ([string]$Repo) {
    "Репозиторий $Repo стал публичным, поэтому изменения не отправляются в GitHub: в настройках программ бывают личные данные. Сделайте репозиторий приватным (Settings → General → Change visibility). Изменения сохранены на этом компьютере."
}

# последний коммит, затронувший путь в «Моих данных»: @{ Date; Machine } (компьютер — из «… (PC-01)» в конце сообщения) или $null
function Get-PbDataLastChange ([string]$Rel) {
    if (-not (Test-PbDataConnected)) { return $null }
    $r = Invoke-PbGit log -1 --format=%cI%x09%s -- ($Rel -replace '\\', '/')
    $l = $r.Out | Select-Object -First 1
    if ($r.Code -ne 0 -or $l -notmatch '^(\S+)\t(.*)$') { return $null }
    $d = $null
    try { $d = [datetime]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) } catch { }
    $m = if ($Matches[2] -match '\(([^()]+)\)\s*$') { $Matches[1] } else { '' }
    return @{ Date = $d; Machine = $m }
}

# коммит снятых настроек: «Настройки: Vivaldi, VS Code (PC-01)»
function Save-PbConfigCommit ([string[]]$Names) {
    Save-PbDataCommit "Настройки: $($Names -join ', ') ($env:COMPUTERNAME)" @('configs')
}

# ---------- разметка репозитория данных ----------

function Get-PbEngineVersion {
    if ($script:PB.Root -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $v = & git -C $script:PB.Root describe --tags --always 2>$null | Select-Object -First 1
        if ($v) { return [string]$v }
    }
    return 'dev'
}

# манифест или $null
function Read-PbManifest {
    $p = Join-Path $script:PB.DataRoot $script:PbManifest
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return [pscustomobject]@{ format = -1 } }
}

# 'ok' | 'empty' (новый репозиторий: создать разметку) | 'foreign' (есть чужие файлы, манифеста нет: только добавить
# недостающее) | 'old' (разметка старее движка: миграция) | 'new' (новее движка: только чтение) | 'broken' (манифест не читается)
function Get-PbDataLayout {
    if (-not (Test-PbDataConnected)) { return 'none' }
    $m = Read-PbManifest
    if ($m) {
        $f = 0; [void][int]::TryParse([string]$m.format, [ref]$f)
        if ($f -lt 1) { return 'broken' }
        if ($f -gt $script:PbLayoutFormat) { return 'new' }
        if ($f -lt $script:PbLayoutFormat) { return 'old' }
        return 'ok'
    }
    $files = @((Invoke-PbGit ls-files).Out | Where-Object { $_ })
    $other = @($files | Where-Object { $_ -ne 'README.md' })
    $readme = Join-Path $script:PB.DataRoot 'README.md'
    $short = -not (Test-Path $readme) -or @(Get-Content $readme -Encoding UTF8 | Where-Object { $_.Trim() }).Count -le 2
    if (-not $other.Count -and $short) { return 'empty' }
    return 'foreign'
}

function Test-PbDataReadOnly { (Get-PbDataLayout) -eq 'new' }

function Assert-PbDataWritable {
    if (Test-PbDataReadOnly) {
        throw 'Разметка «Моих данных» создана более новой версией Tabula Rasa. Обновите программу: до обновления изменения в «Моих данных» не сохраняются.'
    }
}

$script:PbGitignore = @('*.key', '*.pem', '*.pfx', '*.p12', '*.ovpn', '*.kdbx', '*.kdb', 'id_rsa*', 'id_ed25519*', '.env',
    'Login Data*', 'Cookies*', 'Web Data*', '*.sqlite', '*.sqlite-wal', '*.sqlite-shm', '*.db', '*.log', '*.bak')

function Get-PbDataReadme {
    @'
# Мои данные Tabula Rasa

Приватный репозиторий с личными данными для [Tabula Rasa](https://github.com/iheeae/tabula-rasa).
Репозиторий создан программой и должен оставаться приватным: в настройках программ бывают личные данные.
Если репозиторий станет публичным, Tabula Rasa перестанет отправлять в него изменения.

| Расположение | Содержимое |
|---|---|
| `saves/` | профили — сохранённые наборы отметок окна (JSON) |
| `configs/` | настройки программ, снятые на вкладке «Снятие настроек» |
| `catalog/apps.psd1` | собственный каталог программ сверх встроенного |
| релиз `files` | файлы раздела «Файлы» |
| `tabula-rasa.json` | служебный файл: версия разметки |

Изменения вносятся из окна Tabula Rasa, каждое изменение фиксируется отдельным коммитом. Другие файлы и папки
программа не использует и не изменяет.

## Подключение на другом компьютере
Запустите Tabula Rasa в PowerShell от имени администратора командой `irm iheeae.github.io/tabula-rasa | iex`,
слева внизу выберите «Подключить» и войдите в ту же учётную запись GitHub. Репозиторий будет клонирован
в `C:	abula-rasa-private`.
'@
}

function Get-PbEmptyCatalog {
    @'
# Собственный каталог программ Tabula Rasa: дополняет встроенный. Записи добавляются из окна («Добавить программу»).
# Только winget и поля описания: Id, Name, Desc, Category, Source = 'winget', WingetId, Scope, Interactive, Note, Manual,
# OpenSource, License. Записи с ошибками и другими полями пропускаются.
@{
    Apps = @(
    )
}
'@
}

# что добавит разметка: @{ Rel; Text; Bom; Append } (Append — строки в конец существующего .gitignore).
# $Fresh — новый репозиторий: README программы заменяет README, созданный GitHub
function Get-PbLayoutPlan ([switch]$Fresh) {
    $root = $script:PB.DataRoot
    $plan = @()
    if ($Fresh -or -not (Test-Path (Join-Path $root 'README.md'))) { $plan += @{ Rel = 'README.md'; Text = (Get-PbDataReadme) } }
    foreach ($d in 'saves', 'configs') {
        $dir = Join-Path $root $d
        if (-not (Test-Path $dir) -or -not @(Get-ChildItem $dir -Force).Count) { $plan += @{ Rel = "$d/.gitkeep"; Text = '' } }
    }
    if (-not (Test-Path (Join-Path (Join-Path $root 'catalog') 'apps.psd1'))) { $plan += @{ Rel = 'catalog/apps.psd1'; Text = (Get-PbEmptyCatalog); Bom = $true } }
    $gi = Join-Path $root '.gitignore'
    if (Test-Path $gi) {
        $have = @(Get-Content $gi -Encoding UTF8 | ForEach-Object { $_.Trim() })
        $add = @($script:PbGitignore | Where-Object { $have -notcontains $_ })
        if ($add.Count) { $plan += @{ Rel = '.gitignore'; Append = $add } }
    } else {
        $plan += @{ Rel = '.gitignore'; Text = ((@('# Tabula Rasa: защита от случайной отправки секретов') + $script:PbGitignore) -join "`n") + "`n" }
    }
    return $plan
}

# строки для подтверждения: что будет добавлено
function Format-PbLayoutPlan ($Plan) {
    foreach ($p in $Plan) {
        if ($p.Append) { "$($p.Rel): строки $($p.Append -join ', ')" }
        else { $p.Rel }
    }
    $script:PbManifest
}

# записать план и манифест одним коммитом «Разметка Tabula Rasa». Ничего не удаляет и не перезаписывает,
# кроме README нового репозитория (план с -Fresh)
function Install-PbDataLayout ($Plan) {
    $root = $script:PB.DataRoot
    $paths = @()
    foreach ($p in $Plan) {
        $f = Join-Path $root ($p.Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path $f) -Force | Out-Null
        if ($p.Append) {
            $cur = [IO.File]::ReadAllText($f)
            $sep = if ($cur -and -not $cur.EndsWith("`n")) { "`n" } else { '' }
            [IO.File]::WriteAllText($f, $cur + $sep + "# Tabula Rasa: защита от случайной отправки секретов`n" + ($p.Append -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
        } else {
            [IO.File]::WriteAllText($f, ($p.Text -replace "`r?`n", "`n"), (New-Object Text.UTF8Encoding ([bool]$p.Bom)))
        }
        $paths += $p.Rel
    }
    $m = [ordered]@{ format = $script:PbLayoutFormat; created = (Get-Date).ToString('s', [Globalization.CultureInfo]::InvariantCulture); engine = (Get-PbEngineVersion) }
    [IO.File]::WriteAllText((Join-Path $root $script:PbManifest), ($m | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding $false))
    [void](Invoke-PbGit add -A -- @($paths + $script:PbManifest))
    $r = Invoke-PbGit commit -q -m 'Разметка Tabula Rasa'
    if ($r.Code -ne 0) { throw "git commit: $($r.Out -join ' ')" }
}

# разметка старее движка: миграции по шагам, каждая — своим коммитом. Пока формат один (1), шагов нет
function Update-PbDataLayout {
    $m = Read-PbManifest
    $f = [int]$m.format
    while ($f -lt $script:PbLayoutFormat) {
        switch ($f) {
            # 1 { … перенос файлов в новое место …; $msg = 'Разметка Tabula Rasa: формат 2 (…)' }
            default { throw "Нет миграции разметки с формата $f." }
        }
        $f++
    }
}

# ---------- подключение ----------

function Update-PbPath { Update-SessionPath }   # прежнее имя: так его зовут фоновые задачи окна

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
        # после переименования на GitHub старое имя ведёт редиректом на новое: такой репозиторий — не наш, создаём свой
        $found = Invoke-PbGh repo view $repo --json nameWithOwner --jq .nameWithOwner
        if ($found.Code -ne 0 -or "$($found.Out | Select-Object -First 1)" -ne $repo) {
            Step "Создание приватного репозитория $repo…"
            & gh repo create $repo --private --add-readme --description 'Мои данные для Tabula Rasa' *> $null
            if ($LASTEXITCODE -ne 0) { throw "Не удалось создать репозиторий $repo." }
        }
        Step "Клонирование $repo…"
        & git clone -q "https://github.com/$repo.git" $script:PB.DataRoot 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Не удалось клонировать $repo." }
    }
    if ((Test-PbDataPrivate $repo) -eq 'public') { $Sync.Public = $repo }
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
