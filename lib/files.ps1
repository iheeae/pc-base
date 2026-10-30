# Tabula Rasa: раздел «Файлы» — файлы из релиза files в репозитории «Моих данных» (<логин>/tabula-rasa-private).
#
# Хранилище — один «живой» релиз с тегом files, файлы — его ассеты. GitHub портит не-ASCII имена ассетов, поэтому
# имя ассета ASCII (ConvertTo-PbAssetName), а исходное имя файла — в подписи (label); окно показывает подпись.
# После загрузки файл сверяется с sha256 из поля digest ассета. Ничего не устанавливается: файлы кладутся
# в «Рабочий стол\tabula-rasa-files», запускаются вручную. Загрузка в релиз — tools\upload-files.ps1.
#
# Нужен вход в GitHub CLI (его выполняет подключение «Моих данных», lib\data.ps1; там же Invoke-PbGh). Список и загрузка — через REST
# (gh api, gh release download); строки JSON идут в base64, чтобы не зависеть от кодовой страницы консоли.

$script:PbFilesTag = 'files'
$script:PbAssetMax = 2GB   # GitHub: каждый ассет — меньше 2 ГиБ

function Get-PbFilesDir {
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk) { $desk = Join-Path $HOME 'Desktop' }
    return (Join-Path $desk 'tabula-rasa-files')
}

# id релиза files или $null, если его нет; ошибки сети и доступа — исключением
function Get-PbFilesRelease ([string]$Repo) {
    $r = Invoke-PbGh api "repos/$Repo/releases/tags/$($script:PbFilesTag)" --jq .id
    if ($r.Code -eq 0) { return [int64]($r.Out | Select-Object -First 1) }
    if (($r.Out -join ' ') -match 'HTTP 404') { return $null }
    throw (Get-PbGhError $r.Out 'Не удалось получить релиз files.')
}

# @{ Repo; ReleaseId; Files }: ReleaseId $null — релиза нет. Файл: Id, Name (ASCII), Label, Title (что показывать),
# Size, Sha256 (пусто, если GitHub не посчитал digest), Updated
function Get-PbFiles ([string]$Repo) {
    $rel = Get-PbFilesRelease $Repo
    $files = @()
    if ($rel) {
        $r = Invoke-PbGh api --paginate "repos/$Repo/releases/$rel/assets?per_page=100" --jq '.[] | tojson | @base64'
        if ($r.Code -ne 0) { throw (Get-PbGhError $r.Out 'Не удалось получить список файлов.') }
        $files = foreach ($line in $r.Out) {
            if ($line -notmatch '^[A-Za-z0-9+/=]+$') { continue }
            $a = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line)) | ConvertFrom-Json
            if ($a.state -and $a.state -ne 'uploaded') { continue }   # незавершённая загрузка
            $sha = if ([string]$a.digest -match '^sha256:([0-9a-fA-F]{64})$') { $Matches[1].ToLower() } else { '' }
            $upd = $null
            try { $upd = [datetime]::Parse([string]$a.updated_at, [Globalization.CultureInfo]::InvariantCulture) } catch { }
            [pscustomobject]@{
                Id = [int64]$a.id; Name = [string]$a.name; Label = [string]$a.label
                Title = $(if ([string]$a.label) { [string]$a.label } else { [string]$a.name })
                Size = [int64]$a.size; Sha256 = $sha; Updated = $upd
            }
        }
    }
    return @{ Repo = $Repo; ReleaseId = $rel; Files = @($files | Sort-Object Title) }
}

# ---------- имена ----------

$script:PbTranslit = @{
    'а' = 'a'; 'б' = 'b'; 'в' = 'v'; 'г' = 'g'; 'д' = 'd'; 'е' = 'e'; 'ё' = 'e'; 'ж' = 'zh'; 'з' = 'z'; 'и' = 'i'; 'й' = 'y'
    'к' = 'k'; 'л' = 'l'; 'м' = 'm'; 'н' = 'n'; 'о' = 'o'; 'п' = 'p'; 'р' = 'r'; 'с' = 's'; 'т' = 't'; 'у' = 'u'; 'ф' = 'f'
    'х' = 'kh'; 'ц' = 'ts'; 'ч' = 'ch'; 'ш' = 'sh'; 'щ' = 'shch'; 'ъ' = ''; 'ы' = 'y'; 'ь' = ''; 'э' = 'e'; 'ю' = 'yu'; 'я' = 'ya'
    'є' = 'ye'; 'і' = 'i'; 'ї' = 'yi'; 'ґ' = 'g'
}

# имя ассета: транслит, диакритика снимается, всё кроме A-Z a-z 0-9 . _ - → «_». «Отчёт 2024.pdf» → «Otchet_2024.pdf»
function ConvertTo-PbAssetName ([string]$Name) {
    function Convert-Part ([string]$T) {
        $sb = New-Object Text.StringBuilder
        $ch = $T.ToCharArray()
        for ($i = 0; $i -lt $ch.Count; $i++) {
            $c = $ch[$i]
            $lc = [string][char]::ToLowerInvariant($c)
            if (-not $script:PbTranslit.ContainsKey($lc)) { [void]$sb.Append($c); continue }
            $t = $script:PbTranslit[$lc]
            if ($t -and [char]::IsUpper($c)) {
                # ЩУКА → SHCHUKA, Щука → Shchuka
                $word = ($i + 1 -lt $ch.Count -and [char]::IsUpper($ch[$i + 1])) -or ($i -gt 0 -and [char]::IsUpper($ch[$i - 1]))
                $t = if ($word) { $t.ToUpper() } else { $t.Substring(0, 1).ToUpper() + $t.Substring(1) }
            }
            [void]$sb.Append($t)
        }
        $r = $sb.ToString().Normalize([Text.NormalizationForm]::FormD)
        $r = -join @($r.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
        return ($r -replace '[^A-Za-z0-9._-]', '_' -replace '_{2,}', '_' -replace '_?\._?', '.').Trim('._-')
    }
    $ext = [IO.Path]::GetExtension($Name)
    $base = Convert-Part ($Name.Substring(0, $Name.Length - $ext.Length))
    $e = Convert-Part $ext
    if (-not $base) { $base = 'file' }
    if ($e) { return "$base.$e" }
    return $base
}

# имя файла на этом компьютере: из подписи, без недопустимых в Windows символов
function ConvertTo-PbLocalName ([string]$Title) {
    $n = ($Title -replace '[\\/:*?"<>|\x00-\x1F]', '_').Trim(' .')
    if (-not $n) { $n = 'file' }
    return $n
}

# шаблон gh release download -p — точное совпадение: спецсимволы glob в классы
function ConvertTo-PbGlob ([string]$Name) { $Name -replace '([\[\]*?])', '[$1]' }

# ---------- загрузка на компьютер ----------

# один файл: gh release download во временную папку с прогрессом → сверка sha256 → в $DestDir под именем из подписи.
# Возвращает @{ Path; Verified }; ошибка — исключением (повреждённый файл удаляется)
function Save-PbFile ([string]$Repo, $File, [string]$DestDir) {
    $tmp = Join-Path $env:TEMP "tabula-rasa\files\$($File.Id)"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($tmp))).AvailableFreeSpace
        if ($free -lt $File.Size + 100MB) { throw "Недостаточно места на диске $([IO.Path]::GetPathRoot($tmp)): нужно $(Format-PbSize $File.Size), свободно $(Format-PbSize $free)." }
        $psi = New-Object Diagnostics.ProcessStartInfo 'gh'
        $psi.Arguments = (@('release', 'download', $script:PbFilesTag, '-R', $Repo, '-p', (ConvertTo-PbGlob $File.Name), '-D', $tmp, '--clobber') |
            ForEach-Object { ConvertTo-PbArg $_ }) -join ' '
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true; $psi.RedirectStandardOutput = $true
        $p = [Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync(); $outTask = $p.StandardOutput.ReadToEndAsync()
        $last = -1
        while (-not $p.WaitForExit(500)) {
            $got = [int64](Get-ChildItem $tmp -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $pct = if ($File.Size) { [int][Math]::Min(99, 100 * $got / $File.Size) } else { 0 }
            if ($pct -ne $last) { Write-Host ("`r      {0,3}%  {1} из {2}   " -f $pct, (Format-PbSize $got), (Format-PbSize $File.Size)) -NoNewline; $last = $pct }
        }
        $p.WaitForExit()
        if ($last -ge 0) { Write-Host "`r$(' ' * 48)`r" -NoNewline }
        $got = Join-Path $tmp $File.Name
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $got)) {
            throw (Get-PbGhError @($errTask.Result, $outTask.Result) "Не удалось загрузить файл (код $($p.ExitCode)).")
        }
        $verified = $false
        if ($File.Sha256) {
            $h = (Get-FileHash -LiteralPath $got -Algorithm SHA256).Hash.ToLower()
            if ($h -ne $File.Sha256) { throw "Контрольная сумма SHA-256 не совпадает: файл повреждён при загрузке и удалён. Ожидалось $($File.Sha256), получено $h." }
            $verified = $true
        }
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        $dst = Join-Path $DestDir (ConvertTo-PbLocalName $File.Title)
        Move-Item -LiteralPath $got -Destination $dst -Force
        return @{ Path = $dst; Verified = $verified }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue   # недокачанное и повреждённое не остаётся
    }
}

function Format-PbSize ([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} ГБ' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} МБ' -f ($Bytes / 1MB) }
    if ($Bytes -lt 1KB) { return '{0:N0} Б' -f $Bytes }
    return '{0:N0} КБ' -f ($Bytes / 1KB)
}

# шаг прогона: выбранные файлы (по имени ассета или подписи — так находятся и старые сохранения) → рабочий стол
function Save-PbFiles ([string[]]$Names) {
    $what = 'Файлы → Рабочий стол\tabula-rasa-files'
    $repo = Get-PbDataRepo
    if (-not $repo) { Write-Skip '«Мои данные» не подключены'; Add-Result $what 'пропущено' '«Мои данные» не подключены'; return }
    Update-PbPath
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Fail 'GitHub CLI не найден'; Add-Result $what 'ОШИБКА' 'нет GitHub CLI'; return }
    try { $list = Get-PbFiles $repo }
    catch { Write-Fail $_.Exception.Message; Add-Result $what 'ОШИБКА' $_.Exception.Message; return }
    if (-not $list.ReleaseId) { Write-Warn2 "в $repo нет релиза files"; Add-Result $what 'пропущено' 'нет релиза files'; return }

    $pick = @($list.Files | Where-Object { $Names -contains $_.Name -or $Names -contains $_.Title })
    foreach ($n in $Names) {
        if (-not @($list.Files | Where-Object { $_.Name -eq $n -or $_.Title -eq $n }).Count) { Write-Warn2 "нет в релизе: $n"; Add-Result "Файл: $n" 'пропущено' 'нет в релизе files' }
    }
    if (-not $pick.Count) { return }
    $dst = Get-PbFilesDir
    $total = ($pick | Measure-Object Size -Sum).Sum
    Write-Host "    $repo → ${dst}: файлов $($pick.Count), $(Format-PbSize $total)" -ForegroundColor Gray
    $i = 0; $ok = 0
    foreach ($f in $pick) {
        $i++
        Write-Host "    [$i/$($pick.Count)] $($f.Title) ($(Format-PbSize $f.Size))"
        try {
            $r = Save-PbFile $repo $f $dst
            if ($r.Verified) { Write-Ok "$($f.Title): SHA-256 совпадает"; Add-Result "Файл: $($f.Title)" 'загружено' 'SHA-256 совпадает' }
            else { Write-Warn2 "$($f.Title): у ассета нет контрольной суммы, сверка не выполнена"; Add-Result "Файл: $($f.Title)" 'загружено' 'без сверки: у ассета нет digest' }
            $ok++
        } catch { Write-Fail "$($f.Title): $($_.Exception.Message)"; Add-Result "Файл: $($f.Title)" 'ОШИБКА' $_.Exception.Message }
    }
    if ($ok) { Add-Manual "Установить вручную файлы из $dst" }
}
