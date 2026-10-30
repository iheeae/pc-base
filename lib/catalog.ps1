# Tabula Rasa: собственный каталог программ — catalog\apps.psd1 в «Моих данных», сверх встроенного.
#
# Формат тот же, что у встроенного каталога, но только декларативно: Source = 'winget' и поля описания, без web-источников,
# без Override, Config и скриптблоков. Каждая запись проверяется при загрузке (Test-PbUserApp), ошибочные пропускаются
# с сообщением. Запись в файл — Write-PbUserCatalog, коммит — lib\data.ps1 (Save-PbDataCommit).
#
# Поиск для «Добавить программу» — winget search произвольным текстом (по имени, id и moniker) плюс winget search --tag
# по словам запроса; результаты объединяются без дублей и сортируются: точное совпадение имени → начало имени → остальное.
# Таблица winget разбирается по позициям колонок из строки заголовка (сами заголовки локализованы).

$script:PbUserAppKeys = @('Id', 'Name', 'Desc', 'Category', 'Source', 'WingetId', 'Scope', 'Interactive', 'Note', 'Manual', 'OpenSource', 'License')
$script:PbUserCategory = 'Мой каталог'

function Get-PbUserCatalogPath { Join-Path (Join-Path $script:PB.DataRoot 'catalog') 'apps.psd1' }

# ошибка записи или $null. $Known — уже занятые id (встроенный каталог и предыдущие записи)
function Test-PbUserApp ($A, $Known) {
    if ($A -isnot [hashtable]) { return 'запись не является таблицей @{ … }' }
    $extra = @($A.Keys | Where-Object { $script:PbUserAppKeys -notcontains $_ })
    if ($extra.Count) { return "недопустимые поля: $($extra -join ', ')" }
    foreach ($k in $A.Keys) {
        $v = $A[$k]
        if ($k -in 'Interactive', 'OpenSource') { if ($v -isnot [bool]) { return "поле $k должно быть `$true или `$false" } }
        elseif ($v -isnot [string]) { return "поле $k должно быть строкой" }
    }
    if ($A.Id -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { return "Id «$($A.Id)»: допустимы строчные латинские буквы, цифры и . _ -" }
    if ($Known -contains $A.Id) { return "Id «$($A.Id)» уже есть в каталоге" }
    if (-not $A.Name) { return 'не указано поле Name' }
    if ($A.Source -and $A.Source -ne 'winget') { return "Source = '$($A.Source)': в собственном каталоге допустим только winget" }
    if ($A.WingetId -notmatch '^[A-Za-z0-9][\w.+-]{0,127}$') { return "WingetId «$($A.WingetId)» недопустим" }
    if ($A.Scope -and $A.Scope -notin 'machine', 'user') { return "Scope = '$($A.Scope)': допустимо machine или user" }
    return $null
}

# @{ Apps = проверенные записи (Mine = $true); Errors = строки «запись N: …» }. Нет файла — пусто
function Read-PbUserCatalog ($BuiltinIds) {
    $out = @{ Apps = @(); Errors = @() }
    $p = Get-PbUserCatalogPath
    if (-not (Test-Path -LiteralPath $p)) { return $out }
    try { $d = Import-PowerShellDataFile -LiteralPath $p -ErrorAction Stop }
    catch { $out.Errors += "файл catalog\apps.psd1 не читается: $($_.Exception.Message)"; return $out }
    $known = @($BuiltinIds)
    $i = 0
    foreach ($a in @($d.Apps)) {
        $i++
        $err = Test-PbUserApp $a $known
        if ($err) { $out.Errors += "запись $i$(if ($a -is [hashtable] -and $a.Name) { " ($($a.Name))" }): $err"; continue }
        $x = @{}
        foreach ($k in $a.Keys) { $x[$k] = $a[$k] }
        $x.Source = 'winget'
        if (-not $x.Category) { $x.Category = $script:PbUserCategory }
        if (-not $x.Desc) { $x.Desc = '' }
        $x.Mine = $true
        $known += $x.Id
        $out.Apps += $x
    }
    return $out
}

function ConvertTo-PbPsd1String ([string]$S) { "'" + ($S -replace "'", "''") + "'" }

# весь файл заново: заголовок + записи по одной на строку, поля в порядке $script:PbUserAppKeys
function Write-PbUserCatalog ($Apps) {
    $p = Get-PbUserCatalogPath
    $head = @((Get-PbEmptyCatalog) -split "`r?`n" | Where-Object { $_ -match '^#' })
    $rows = foreach ($a in @($Apps)) {
        $f = foreach ($k in $script:PbUserAppKeys) {
            if (-not $a.ContainsKey($k) -or $null -eq $a[$k] -or ($a[$k] -is [string] -and -not $a[$k] -and $k -ne 'Desc')) { continue }
            $v = if ($a[$k] -is [bool]) { if ($a[$k]) { '$true' } else { '$false' } } else { ConvertTo-PbPsd1String ([string]$a[$k]) }
            "$k = $v"
        }
        '        @{ ' + ($f -join '; ') + ' }'
    }
    $text = (@($head) + '@{' + '    Apps = @(' + @($rows) + '    )' + '}') -join "`n"
    New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
    [IO.File]::WriteAllText($p, $text + "`n", (New-Object Text.UTF8Encoding $true))
}

# id для новой записи: my.<winget-id в нижнем регистре>, при совпадении — с номером
function New-PbUserAppId ([string]$WingetId, $Known) {
    $base = 'my.' + ($WingetId.ToLower() -replace '\+', 'p' -replace '[^a-z0-9._-]', '-' -replace '-{2,}', '-').Trim('-')
    if ($base.Length -gt 60) { $base = $base.Substring(0, 60) }
    $id = $base; $n = 2
    while (@($Known) -contains $id) { $id = "$base-$n"; $n++ }
    return $id
}

# добавить или удалить запись: файл + коммит (Save-PbDataCommit — проверка «только чтение» там же). Отправка — отдельно
function Add-PbUserApp ([hashtable]$Entry, $BuiltinIds) {
    Assert-PbDataWritable
    $cur = Read-PbUserCatalog $BuiltinIds
    $err = Test-PbUserApp $Entry (@($BuiltinIds) + @($cur.Apps | ForEach-Object { $_.Id }))
    if ($err) { throw "Запись не добавлена: $err." }
    Write-PbUserCatalog (@($cur.Apps) + $Entry)
    Save-PbDataCommit "Мой каталог: добавлено $($Entry.Name)" @('catalog')
}

function Remove-PbUserApp ([string]$Id, $BuiltinIds) {
    Assert-PbDataWritable
    $cur = Read-PbUserCatalog $BuiltinIds
    $gone = @($cur.Apps | Where-Object { $_.Id -eq $Id })
    if (-not $gone.Count) { throw "В собственном каталоге нет записи $Id." }
    Write-PbUserCatalog @($cur.Apps | Where-Object { $_.Id -ne $Id })
    Save-PbDataCommit "Мой каталог: удалено $($gone[0].Name)" @('catalog')
}

# ---------- winget search ----------

# таблица winget → @{ Name; Id; Version }. Колонки — по позициям начала слов в строке над линией из дефисов.
# Строки со спиннером (…\r) обрезаются до последнего \r; усечённые id («…») отбрасываются
function ConvertFrom-PbWingetTable ([string[]]$Lines) {
    $clean = @($Lines | ForEach-Object { $l = [string]$_; $i = $l.LastIndexOf("`r"); if ($i -ge 0) { $l.Substring($i + 1) } else { $l } })
    $dash = -1
    for ($i = 1; $i -lt $clean.Count; $i++) { if ($clean[$i] -match '^-{8,}\s*$') { $dash = $i; break } }
    if ($dash -lt 1) { return @() }
    $head = $clean[$dash - 1]
    $starts = @()
    for ($i = 0; $i -lt $head.Length; $i++) {
        if ($head[$i] -ne ' ' -and ($i -eq 0 -or $head[$i - 1] -eq ' ')) { $starts += $i }
    }
    if ($starts.Count -lt 3) { return @() }
    $rows = for ($r = $dash + 1; $r -lt $clean.Count; $r++) {
        $l = $clean[$r]
        if (-not $l.Trim()) { break }
        $cols = for ($c = 0; $c -lt 3; $c++) {
            $a = $starts[$c]; $b = $starts[$c + 1]
            if ($a -ge $l.Length) { ''; continue }
            if ($b -gt $l.Length) { $b = $l.Length }
            $l.Substring($a, $b - $a).Trim()
        }
        $name = $cols[0]; $id = $cols[1]; $ver = $cols[2]
        if (-not $id -or $id -match '…' -or $id -notmatch '^[\w.+-]+$') { continue }
        [pscustomobject]@{ Name = $name; Id = $id; Version = $ver }
    }
    return @($rows)
}

# winget с выводом в UTF-8 (иначе позиции колонок съезжают) и ограничением 2 мин: зависший winget не держит поиск
function Invoke-PbWinget {
    $r = Invoke-PbWingetTimed @($args) 2 ('search_' + ($args -join '_'))
    if ($r.TimedOut) { throw 'winget не ответил за 2 минуты.' }
    return @($r.Out)
}

# объединить, убрать дубли по id, отсортировать: точное имя → начало имени → остальное (внутри — порядок winget)
function Merge-PbWingetResults ([string]$Query, $Lists) {
    $q = $Query.Trim()
    $seen = @{}; $all = @(); $n = 0
    foreach ($l in $Lists) {
        foreach ($r in @($l)) {
            $k = $r.Id.ToLower()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $rank = if ($r.Name -ieq $q) { 0 } elseif ($r.Name.StartsWith($q, [StringComparison]::OrdinalIgnoreCase)) { 1 } else { 2 }
            $all += [pscustomobject]@{ Name = $r.Name; Id = $r.Id; Version = $r.Version; Rank = $rank; Order = $n }
            $n++
        }
    }
    return @($all | Sort-Object Rank, Order)
}

function Search-PbWinget ([string]$Query, [int]$Max = 50) {
    $q = $Query.Trim()
    if (-not $q) { return @() }
    $common = @('--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    $lists = @(, (ConvertFrom-PbWingetTable (Invoke-PbWinget search --query $q @common)))
    foreach ($w in @($q -split '\s+' | Where-Object { $_ -match '^[\w+.-]{2,}$' } | Select-Object -First 3)) {
        $lists += , (ConvertFrom-PbWingetTable (Invoke-PbWinget search --tag $w @common))
    }
    return @(Merge-PbWingetResults $q $lists | Select-Object -First $Max)
}

# winget show: Publisher, Description, Homepage, License (ключи на английском и русском)
function ConvertFrom-PbWingetShow ([string[]]$Lines) {
    $map = @{ 'Publisher' = 'Publisher'; 'Издатель' = 'Publisher'; 'Description' = 'Description'; 'Описание' = 'Description'
              'Homepage' = 'Homepage'; 'Домашняя страница' = 'Homepage'; 'License' = 'License'; 'Лицензия' = 'License' }
    $out = @{ Publisher = ''; Description = ''; Homepage = ''; License = '' }
    $cur = $null
    foreach ($raw in $Lines) {
        $l = [string]$raw; $i = $l.LastIndexOf("`r"); if ($i -ge 0) { $l = $l.Substring($i + 1) }
        if ($l -match '^([^\s:][^:]*):\s*(.*)$') {
            $cur = $map[$Matches[1].Trim()]
            if ($cur) { $out[$cur] = $Matches[2].Trim() }
            continue
        }
        # продолжение многострочного значения (описание) — с отступом
        if ($cur -and $l -match '^\s+\S') { $out[$cur] = ($out[$cur] + ' ' + $l.Trim()).Trim() } else { $cur = $null }
    }
    return $out
}

function Get-PbWingetShow ([string]$Id) {
    ConvertFrom-PbWingetShow (Invoke-PbWinget show --id $Id -e --source winget --accept-source-agreements --disable-interactivity)
}
