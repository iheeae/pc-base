# Tabula Rasa: загрузка файлов в раздел «Файлы» — релиз files в репозитории «Моих данных» (<логин>/tabula-rasa-private).
# Имя ассета — ASCII (другие символы GitHub искажает), исходное имя файла — в подписи (label): её показывает окно.
# Релиз files создаётся, если его нет. Папка загружается одним архивом .zip. Ограничение GitHub — меньше 2 ГБ на файл.
#
#   powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\upload-files.ps1 <файл или папка> [...]
#   powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\upload-files.ps1 -FromDrive
#
# -FromDrive   перенос папки pc-base-exe с подключённого Google Drive («Мой диск\pc-base-exe»; другая папка — -DriveDir).
#              Google Drive только читается: файлы на нём не удаляются, не переименовываются и не изменяются.
# -Replace     файл с тем же именем уже есть в релизе и отличается — заменить (без ключа такой файл пропускается).
# -Repo        <владелец>/<репозиторий>; по умолчанию — репозиторий «Моих данных» (-DataRoot, C:\tabula-rasa-private).
# -DryRun      только показать, что будет загружено.
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Path,
    [switch]$FromDrive,
    [string]$DriveDir,
    [string]$Repo,
    [string]$DataRoot = 'C:\tabula-rasa-private',
    [switch]$Replace,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'lib\common.ps1'); . (Join-Path $root 'lib\data.ps1'); . (Join-Path $root 'lib\files.ps1')
$script:PB.Root = $root; $script:PB.DataRoot = $DataRoot
$skipNames = '^(desktop\.ini|thumbs\.db|\..*|~\$.*)$'

# ---------- GitHub ----------
Update-PbPath
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Fail 'GitHub CLI (gh) не найден. Подключите «Мои данные» в окне Tabula Rasa: GitHub CLI будет установлен.'; exit 1
}
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) { Write-Fail 'Вход в GitHub CLI не выполнен. Подключите «Мои данные» в окне Tabula Rasa или выполните gh auth login.'; exit 1 }
if (-not $Repo) { $Repo = Get-PbDataRepo }
if (-not $Repo) {
    $login = (& gh api user --jq .login 2>$null | Select-Object -First 1)
    if (-not $login) { Write-Fail 'Не удалось получить имя пользователя GitHub (gh api user).'; exit 1 }
    $Repo = "$login/$script:PbDataRepoName"
    Write-Warn2 "«Мои данные» на этом компьютере не подключены ($DataRoot); используется репозиторий $Repo"
}

# ---------- что загружать ----------
$src = New-Object System.Collections.ArrayList
function Add-Source ($Item) {
    if ($Item.Name -match $skipNames) { return }
    [void]$src.Add([pscustomobject]@{
        Path = $Item.FullName; IsDir = [bool]$Item.PSIsContainer
        Title = $(if ($Item.PSIsContainer) { "$($Item.Name).zip" } else { $Item.Name })
        Size = $(if ($Item.PSIsContainer) { $null } else { [int64]$Item.Length })
    })
}
if ($FromDrive) {
    if (-not $DriveDir) {
        foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            foreach ($top in 'Мой диск', 'My Drive') {
                $p = Join-Path $d.Root (Join-Path $top 'pc-base-exe')
                if (Test-Path $p) { $DriveDir = $p; break }
            }
            if ($DriveDir) { break }
        }
    }
    if (-not $DriveDir -or -not (Test-Path $DriveDir -PathType Container)) {
        Write-Fail 'Папка pc-base-exe на Google Drive не найдена. Запустите Google Drive, войдите в учётную запись и дождитесь появления диска либо укажите папку: -DriveDir <путь>.'
        exit 1
    }
    Write-Host "Источник: $DriveDir (только чтение)" -ForegroundColor Gray
    Get-ChildItem -LiteralPath $DriveDir -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Add-Source $_ }
}
foreach ($p in @($Path | Where-Object { $_ })) {
    $it = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $it) { Write-Fail "не найдено: $p"; continue }
    Add-Source $it
}
if (-not $src.Count) {
    Write-Host 'Нечего загружать. Укажите файлы или папки либо -FromDrive.' -ForegroundColor Yellow
    Write-Host '  powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\upload-files.ps1 <файл или папка> [...]' -ForegroundColor Gray
    exit 1
}

# ---------- релиз files ----------
Write-Host "Репозиторий: $Repo, релиз files$(if ($DryRun) { ' — ПРОВЕРКА, ничего не загружается' })" -ForegroundColor Cyan
try { $list = Get-PbFiles $Repo } catch { Write-Fail $_.Exception.Message; exit 1 }
if (-not $list.ReleaseId) {
    if ($DryRun) { Write-Host '  Релиза files нет: он будет создан.' -ForegroundColor Gray }
    else {
        $r = Invoke-PbGh api -X POST "repos/$Repo/releases" -f "tag_name=$($script:PbFilesTag)" -f 'name=Файлы' -f make_latest=false `
            -f 'body=Файлы для раздела «Файлы» в Tabula Rasa. Добавляются инструментом tools\upload-files.ps1: имя ассета — ASCII, исходное имя файла — в подписи (label).' --jq .id
        if ($r.Code -ne 0) { Write-Fail (Get-PbGhError $r.Out 'Не удалось создать релиз files (в пустом репозитории релиз создать нельзя: нужен хотя бы один коммит).'); exit 1 }
        Write-Ok 'релиз files создан'
    }
}
$used = @{}
foreach ($f in $list.Files) { $used[$f.Name] = $f }

# ---------- загрузка ----------
$res = New-Object System.Collections.ArrayList
function Add-Row ($S, [string]$Name, [string]$Status, [string]$Sha) {
    [void]$res.Add([pscustomobject]@{ 'Файл' = $S.Title; 'Имя в релизе' = $Name; 'Результат' = $Status; Sha = $Sha })
}
$i = 0
foreach ($s in $src) {
    $i++
    Write-Host ''
    Write-Host "[$i/$($src.Count)] $($s.Title)" -ForegroundColor White
    # тот же файл (та же подпись) — то же имя ассета; иначе — свободное имя
    $ex = @($list.Files | Where-Object { $_.Title -eq $s.Title }) | Select-Object -First 1
    if ($ex) { $name = $ex.Name }
    else {
        $base = ConvertTo-PbAssetName $s.Title
        $name = $base; $n = 2
        while ($used.ContainsKey($name)) {
            $name = if ($base -match '^(.+?)(\.[A-Za-z0-9]{1,8})$') { "$($Matches[1])-$n$($Matches[2])" } else { "$base-$n" }
            $n++
        }
    }
    $used[$name] = $true
    if ($s.Size -ge $script:PbAssetMax) { Write-Fail "$(Format-PbSize $s.Size): GitHub принимает файлы размером меньше 2 ГБ. Файл не загружен."; Add-Row $s $name 'ОШИБКА: больше 2 ГБ'; continue }
    if ($DryRun) {
        $what = if ($ex) { "уже есть в релизе как ${name}: будет сверен$(if ($Replace) { ' и заменён, если отличается' })" } else { "будет загружен как $name" }
        Write-Host "    $what$(if ($s.IsDir) { ' (папка — архивом .zip)' })" -ForegroundColor Gray
        Add-Row $s $name 'план'
        continue
    }

    $tmp = Join-Path $env:TEMP "tabula-rasa\upload\$i"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $staged = Join-Path $tmp $name
    try {
        # копия под ASCII-именем: из имени файла gh берёт имя ассета. Исходный файл только читается
        if ($s.IsDir) {
            Write-Host '    упаковка папки в .zip…' -ForegroundColor Gray
            Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::CreateFromDirectory($s.Path, $staged, [IO.Compression.CompressionLevel]::Optimal, $true)
        } else {
            $linked = $false
            try { New-Item -ItemType HardLink -Path $staged -Target $s.Path -ErrorAction Stop | Out-Null; $linked = $true } catch { }
            if (-not $linked) {
                Write-Host "    чтение файла ($(Format-PbSize $s.Size))…" -ForegroundColor Gray
                Copy-Item -LiteralPath $s.Path -Destination $staged -Force -ErrorAction Stop
            }
        }
        $size = (Get-Item -LiteralPath $staged).Length
        if ($size -ge $script:PbAssetMax) { throw "$(Format-PbSize $size) после упаковки: GitHub принимает файлы размером меньше 2 ГБ." }
        $sha = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLower()

        $clobber = @()
        if ($ex) {
            $same = if ($ex.Sha256) { $ex.Sha256 -eq $sha } else { $ex.Size -eq $size }
            if ($same) { Write-Skip 'уже загружен, совпадает'; Add-Row $s $name 'уже загружен'; continue }
            if (-not $Replace) { Write-Warn2 'в релизе другая версия этого файла; чтобы заменить её, запустите с ключом -Replace'; Add-Row $s $name 'пропущено: отличается'; continue }
            $clobber = @('--clobber')
        }
        & gh release upload $script:PbFilesTag "$staged#$($s.Title)" -R $Repo @clobber
        if ($LASTEXITCODE -ne 0) { throw "gh release upload вернул $LASTEXITCODE." }
        Add-Row $s $name $(if ($ex) { 'заменён' } else { 'загружен' }) $sha
    } catch {
        Write-Fail $_.Exception.Message; Add-Row $s $name "ОШИБКА: $($_.Exception.Message)"
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- сверка: digest загруженного = sha256 исходного ----------
$sent = @($res | Where-Object { $_.Sha })
if ($sent.Count) {
    try {
        $after = (Get-PbFiles $Repo).Files
        foreach ($r in $sent) {
            $a = @($after | Where-Object { $_.Name -eq $r.'Имя в релизе' }) | Select-Object -First 1
            if (-not $a) { $r.'Результат' = 'ОШИБКА: нет в релизе после загрузки' }
            elseif (-not $a.Sha256) { $r.'Результат' += ', digest не указан' }
            elseif ($a.Sha256 -ne $r.Sha) { $r.'Результат' = 'ОШИБКА: SHA-256 не совпадает' }
            else { $r.'Результат' += ', SHA-256 совпадает' }
        }
    } catch { Write-Warn2 "сверка не выполнена: $($_.Exception.Message)" }
}

Write-Host ''
$res | Select-Object 'Файл', 'Имя в релизе', 'Результат' | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$fails = @($res | Where-Object { $_.'Результат' -like 'ОШИБКА*' }).Count
if ($FromDrive) { Write-Host 'Файлы на Google Drive не изменялись и не удалялись.' -ForegroundColor Gray }
if ($fails) { Write-Host "Ошибок: $fails" -ForegroundColor Red; exit 1 }
Write-Host "Готово. Файлы доступны в окне Tabula Rasa, раздел «Файлы»: https://github.com/$Repo/releases/tag/$($script:PbFilesTag)" -ForegroundColor Green
