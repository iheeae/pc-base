# Tabula Rasa: настройки программ — снятие с этого компьютера в «Мои данные» и применение при установке.
#
# У программы в каталоге поле Config:
#   @{ File = 'vivaldi\prefs.json'; From = @('%LOCALAPPDATA%\…\Preferences'); Export = 'Export-VivaldiConfig';
#      Import = 'Set-VivaldiConfig'; Desc = 'что переносится'; Skip = 'что не переносится' }
#   File   — главный файл внутри configs\ (Мои данные или встроенные, Find-PbConfig): нет — «с моими настройками» недоступно
#   From   — где настройки лежат на компьютере; есть хотя бы один путь — программа видна на вкладке «Снятие настроек»
#   Export — функция снятия: Export-X <папка configs> → @{ Files = относительные пути; Removed = что вырезано как секрет }
#   Import — функция применения (вариант «с моими настройками» при установке)
#
# Снятие идёт во временную папку (Invoke-PbCapture), затем окно показывает изменения относительно «Моих данных»
# (Compare-PbCapture) и после подтверждения копирует их (Copy-PbCapture); коммит и отправка — lib\data.ps1.
# Перед записью — фильтр секретов: ключи вида token / password / secret / auth / cookie / session и длинные base64-строки.
# Пути профиля (раскрытые %LOCALAPPDATA%, %APPDATA%, %USERPROFILE% — с \, \\ и /) в снятом заменяются переменными
# (ConvertTo-PbPortablePath), при применении раскрываются под текущего пользователя (Expand-PbPortablePath):
# иначе на другом компьютере пути битые, а имя пользователя попадает в репозиторий.
#
# Реестр (HKCU\Software\<программа>) снимается в JSON (Export-PbRegKey) и применяется через Set-Reg (Import-PbRegJson),
# поэтому попадает в журнал изменений и откатывается undo.ps1.

# %ПЕРЕМЕННЫЕ% и {MyDocuments} (папку «Документы» бывает перенесена, %USERPROFILE%\Documents тогда неверен)
function Expand-PbPath ([string]$P) {
    $P = $P.Replace('{MyDocuments}', [Environment]::GetFolderPath('MyDocuments'))
    # разделитель — системный: на Windows ничего не меняет, проверки на других системах (tests\run.ps1) идут по-честному
    return [Environment]::ExpandEnvironmentVariables($P).Replace('\', [IO.Path]::DirectorySeparatorChar)
}

# первый существующий путь из Config.From или $null
function Get-PbConfigSource ($Config) {
    foreach ($p in @($Config.From)) { $e = Expand-PbPath $p; if ($e -and (Test-Path -LiteralPath $e)) { return $e } }
    return $null
}

# ---------- фильтр секретов ----------

$script:PbSecretKey = '(?i)(token|passw|secret|auth|cookie|session|credential|api[_-]?key|private[_-]?key|bearer)'
$script:PbSecretValue = '[A-Za-z0-9+/_=-]{40,}'

function Test-PbSecretValue ($V) { $V -is [string] -and $V -match "^$($script:PbSecretValue)$" -and $V -notmatch '^[\\/]|^[A-Za-z]:' }

# JSON (объекты ConvertFrom-Json): ключи из $Deny и строки, похожие на токены, удаляются. $Removed — ArrayList путей
function Remove-PbJsonSecrets ($Obj, [string]$Path, $Removed, [string]$Deny = $script:PbSecretKey) {
    if ($Obj -is [pscustomobject]) {
        foreach ($p in @($Obj.PSObject.Properties)) {
            $full = if ($Path) { "$Path.$($p.Name)" } else { $p.Name }
            if ($p.Name -match $Deny -or (Test-PbSecretValue $p.Value)) { [void]$Removed.Add($full); $Obj.PSObject.Properties.Remove($p.Name); continue }
            if ($p.Value -is [array]) {
                $keep = @($p.Value | Where-Object { -not (Test-PbSecretValue $_) })
                if ($keep.Count -ne @($p.Value).Count) { [void]$Removed.Add("$full[]"); $Obj.($p.Name) = $keep }
            }
            Remove-PbJsonSecrets $p.Value $full $Removed $Deny
        }
    } elseif ($Obj -is [array]) { foreach ($x in $Obj) { Remove-PbJsonSecrets $x $Path $Removed $Deny } }
}

# текст (ini, .gitconfig, профиль, JSON с комментариями): строки «ключ-секрет = …» и строки с токеноподобными значениями
function Remove-PbTextSecrets ([string[]]$Lines, [string]$Label, $Removed) {
    $keyLine = '^\s*["'']?[\w.\- ]*' + $script:PbSecretKey.Substring(4) + '[\w.\- ]*["'']?\s*[:=]'
    $out = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($l in $Lines) {
        $n++
        if ($l -match "(?i)$keyLine" -or $l -match $script:PbSecretValue) { [void]$Removed.Add("${Label}: строка $n"); continue }
        [void]$out.Add($l)
    }
    return @($out)
}

# ---------- пути профиля ----------

# самые длинные — первыми: %LOCALAPPDATA% и %APPDATA% лежат внутри %USERPROFILE%
function Get-PbProfileVars {
    $v = foreach ($n in 'LOCALAPPDATA', 'APPDATA', 'USERPROFILE') {
        $p = [Environment]::GetEnvironmentVariable($n)
        if ($p -and $p.Length -gt 3) { @{ Name = $n; Path = $p.TrimEnd('\', '/') } }
    }
    return @($v | Sort-Object { $_.Path.Length } -Descending)
}

# раскрытый путь профиля (с \, \\ или /) → %APPDATA%\x, %USERPROFILE%/x и т. д. (запись разделителей дальше не меняется)
function ConvertTo-PbPortablePath ([string]$Text) {
    if (-not $Text) { return $Text }
    foreach ($v in Get-PbProfileVars) {
        foreach ($form in @($v.Path.Replace('\', '\\'), $v.Path, $v.Path.Replace('\', '/'))) {
            $Text = [regex]::Replace($Text, [regex]::Escape($form) + '(?=[\\/"''\s;,|]|$)', "%$($v.Name)%", 'IgnoreCase')
        }
    }
    return $Text
}

# %APPDATA% и т. п. → пути этого компьютера: перед / — с прямыми слэшами, в JSON — с \\, иначе — с \
function Expand-PbPortablePath ([string]$Text, [bool]$Json = $false) {
    if (-not $Text) { return $Text }
    foreach ($v in Get-PbProfileVars) {
        $tok = [regex]::Escape("%$($v.Name)%")
        $fwd = $v.Path.Replace('\', '/').Replace('$', '$$')
        $back = $(if ($Json) { $v.Path.Replace('\', '\\') } else { $v.Path }).Replace('$', '$$')
        $Text = [regex]::Replace($Text, "$tok(?=/)", $fwd, 'IgnoreCase')
        $Text = [regex]::Replace($Text, $tok, $back, 'IgnoreCase')
    }
    return $Text
}

# текст с кодировкой файла: UTF-16 (reg и некоторые программы), UTF-8 с BOM или без
function Read-PbTextFile ([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { $enc = New-Object Text.UnicodeEncoding $false, $true }
    elseif ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $enc = New-Object Text.UTF8Encoding $true }
    else { $enc = New-Object Text.UTF8Encoding $false }
    return @{ Text = [IO.File]::ReadAllText($Path, $enc); Encoding = $enc }
}

function Convert-PbTextFile ([string]$Path, [scriptblock]$Fn) {
    $t = Read-PbTextFile $Path
    $new = & $Fn $t.Text
    if ($new -ne $t.Text) { [IO.File]::WriteAllText($Path, $new, $t.Encoding) }
}

# ---------- файлы ----------

function Write-PbText ([string]$Path, [string[]]$Lines, [bool]$Bom = $false) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, (($Lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $Bom))
}

function Test-PbBom ([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

# один файл в $Dir\$Rel: json — разбор и фильтр по ключам (не разобрался — как текст), text — фильтр по строкам.
# $Deny — дополнительные ключи JSON (списки недавних файлов и т. п.), $DropLines — дополнительные строки текста
function Export-PbConfigFile ([string]$Src, [string]$Dir, [string]$Rel, [string]$Kind, $Removed, [string]$Deny, [string]$DropLines) {
    $dst = Join-Path $Dir $Rel
    if ($Kind -eq 'json') {
        $j = $null
        try { $j = Get-Content -LiteralPath $Src -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if ($null -ne $j) {
            $d = if ($Deny) { $script:PbSecretKey.Substring(0, $script:PbSecretKey.Length - 1) + '|' + $Deny + ')' } else { $script:PbSecretKey }
            Remove-PbJsonSecrets $j '' $Removed $d
            New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            [IO.File]::WriteAllText($dst, ($j | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding $false))
            return $Rel
        }
    }
    $raw = @(Get-Content -LiteralPath $Src -Encoding UTF8)
    if ($DropLines) {
        $n = 0
        $raw = @($raw | Where-Object { $n++; if ($_ -match $DropLines) { [void]$Removed.Add("${Rel}: строка $n"); $false } else { $true } })
    }
    $lines = Remove-PbTextSecrets $raw $Rel $Removed
    Write-PbText $dst $lines (Test-PbBom $Src)
    return $Rel
}

# копия .bak рядом и замена файла сохранённым (для Import-функций); пути профиля раскрываются под этот компьютер
function Copy-PbConfigIn ([string]$Src, [string]$Dst) {
    New-Item -ItemType Directory -Path (Split-Path $Dst) -Force | Out-Null
    if (Test-Path -LiteralPath $Dst) { Copy-Item -LiteralPath $Dst "$Dst.tabula-rasa_$($script:PB.Stamp).bak" -Force }
    $t = Read-PbTextFile $Src
    [IO.File]::WriteAllText($Dst, (Expand-PbPortablePath $t.Text ($Dst -match '\.json$')), $t.Encoding)
}

# блоки «Имя [ … ]» с вложенностью (SumatraPDF-settings.txt): удаляются целиком
function Remove-PbTextBlocks ([string[]]$Lines, [string[]]$Names, [string]$Label, $Removed) {
    $out = New-Object System.Collections.ArrayList
    $depth = 0
    foreach ($l in $Lines) {
        if ($depth -gt 0) {
            if ($l -match '\[\s*$') { $depth++ } elseif ($l -match '^\s*\]\s*$') { $depth-- }
            continue
        }
        if ($l -match '^\s*(\w+)\s*\[\s*$' -and $Names -contains $Matches[1]) { [void]$Removed.Add("${Label}: $($Matches[1])"); $depth = 1; continue }
        [void]$out.Add($l)
    }
    return @($out)
}

# сохранённый файл configs\<Rel> или $null с записью в итог; общая часть Import-функций
function Get-PbSavedConfig ([string]$Rel, [string]$What) {
    $src = Find-PbConfig $Rel
    if (-not $src) {
        Write-Warn2 "файл configs\$Rel не найден ни в $($script:PB.DataRoot), ни во встроенных настройках"
        Add-Result $What 'пропущено' "нет файла configs\$Rel"
        Add-Manual "$($What -replace ': мои настройки$', ''): снять настройки на настроенном компьютере (вкладка «Снятие настроек»)"
    }
    return $src
}

function Stop-PbApp ([string[]]$Names, [string]$Title) {
    $p = @(Get-Process -Name $Names -ErrorAction SilentlyContinue)
    if (-not $p.Count) { return }
    Write-Warn2 "$Title запущен и будет закрыт, иначе он перезапишет настройки при выходе"
    $p | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# ---------- Vivaldi ----------
# Только поддерево "vivaldi" из Preferences: интерфейс, панели, вкладки, поведение. Аккаунты, почта, синхронизация,
# токены и пароли исключаются; расширения вне этого поддерева.

$script:PbVivaldiDeny = '(?i)(sync|mail|calendar|account|contact|feed|passw|token|secret|auth|login|oauth|email|cookie|session|credential|private|key$)'

function Export-VivaldiConfig ([string]$Dir) {
    $prefs = Expand-PbPath '%LOCALAPPDATA%\Vivaldi\User Data\Default\Preferences'
    if (-not (Test-Path -LiteralPath $prefs)) { throw "Файл $prefs не найден: Vivaldi на этом компьютере не настраивался." }
    $j = Get-Content -LiteralPath $prefs -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.vivaldi) { throw 'В Preferences нет раздела vivaldi.' }
    $removed = New-Object System.Collections.ArrayList
    $v = $j.vivaldi
    Remove-PbJsonSecrets $v 'vivaldi' $removed $script:PbVivaldiDeny
    $rel = Join-Path 'vivaldi' 'prefs.json'
    $out = Join-Path $Dir $rel
    New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
    [IO.File]::WriteAllText($out, ([pscustomobject]@{ vivaldi = $v } | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding $false))
    return @{ Files = @($rel); Removed = @($removed) }
}

function Merge-JsonObject ($Dst, $Src) {
    foreach ($p in $Src.PSObject.Properties) {
        $d = $Dst.PSObject.Properties[$p.Name]
        if ($d -and $d.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) { Merge-JsonObject $d.Value $p.Value }
        else { $Dst | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

# вливает сохранённое поддерево в Preferences профиля
function Set-VivaldiConfig {
    $what = 'Vivaldi: мои настройки'
    $src = Get-PbSavedConfig 'vivaldi\prefs.json' $what
    if (-not $src) { return }
    Stop-PbApp 'vivaldi' 'Vivaldi'
    $dir = Expand-PbPath '%LOCALAPPDATA%\Vivaldi\User Data\Default'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir 'Preferences'
    $saved = Expand-PbPortablePath (Get-Content $src -Raw -Encoding UTF8) $true | ConvertFrom-Json
    if (Test-Path $file) {
        Copy-Item $file "$file.tabula-rasa_$($script:PB.Stamp).bak" -Force
        $cur = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    } else { $cur = [pscustomobject]@{} }
    Merge-JsonObject $cur $saved
    [IO.File]::WriteAllText($file, ($cur | ConvertTo-Json -Depth 100 -Compress), (New-Object Text.UTF8Encoding $false))
    Write-Ok "Vivaldi: настройки применены ($file)"
    Add-Result $what 'применено'
    Add-Manual 'Vivaldi: при первом запуске проверить применение настроек интерфейса; для закладок и паролей войти в Vivaldi Sync'
}

# ---------- профиль PowerShell 7 ----------
# Применение — Set-PwshProfile (catalog\tweaks.ps1): профиль из «Моих данных» перекрывает встроенный

function Export-PwshConfig ([string]$Dir) {
    $src = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
    if (-not (Test-Path -LiteralPath $src)) { throw "Профиль $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir 'pwsh_profile.ps1' 'text' $removed
    return @{ Files = @($rel); Removed = @($removed) }
}

# ---------- Windows Terminal ----------

function Get-PbTerminalSettings { Expand-PbPath '%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json' }

function Export-TerminalConfig ([string]$Dir) {
    $src = Get-PbTerminalSettings
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    # settings.json допускает комментарии: фильтр по строкам, файл остаётся как есть
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'wt' 'settings.json') 'text' $removed
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-TerminalUserConfig {
    $what = 'Windows Terminal: мои настройки'
    $src = Get-PbSavedConfig 'wt\settings.json' $what
    if (-not $src) { return }
    $dst = Get-PbTerminalSettings
    Copy-PbConfigIn $src $dst
    Write-Ok "Windows Terminal: настройки применены ($dst)"
    Add-Result $what 'применено'
}

# ---------- VS Code ----------

function Get-PbCodeCli {
    foreach ($p in "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd") {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $c = Get-Command code -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Export-VSCodeConfig ([string]$Dir) {
    $user = Expand-PbPath '%APPDATA%\Code\User'
    if (-not (Test-Path -LiteralPath $user)) { throw "Папка $user не найдена: VS Code на этом компьютере не настраивался." }
    $removed = New-Object System.Collections.ArrayList
    $files = @()
    foreach ($n in 'settings.json', 'keybindings.json') {
        $src = Join-Path $user $n
        if (Test-Path -LiteralPath $src) { $files += Export-PbConfigFile $src $Dir (Join-Path 'vscode' $n) 'text' $removed }
    }
    $cli = Get-PbCodeCli
    if ($cli) {
        $ext = @(& $cli --list-extensions 2>$null | Where-Object { $_ -match '^[\w-]+\.[\w.-]+$' } | Sort-Object)
        $rel = Join-Path 'vscode' 'extensions.txt'
        Write-PbText (Join-Path $Dir $rel) $ext
        $files += $rel
    }
    if (-not $files.Count) { throw 'Нет ни settings.json, ни keybindings.json, ни списка расширений.' }
    return @{ Files = $files; Removed = @($removed) }
}

function Set-VSCodeConfig {
    $what = 'VS Code: мои настройки'
    $any = $false
    $user = Expand-PbPath '%APPDATA%\Code\User'
    foreach ($n in 'settings.json', 'keybindings.json') {
        $src = Find-PbConfig "vscode\$n"
        if ($src) { Copy-PbConfigIn $src (Join-Path $user $n); $any = $true }
    }
    $list = Find-PbConfig 'vscode\extensions.txt'
    $failed = @()
    if ($list) {
        $any = $true
        Update-SessionPath
        $cli = Get-PbCodeCli
        if (-not $cli) { Write-Warn2 'VS Code не найден: расширения не установлены'; Add-Manual 'VS Code: установить расширения из configs\vscode\extensions.txt' }
        else {
            foreach ($e in @(Get-Content $list -Encoding UTF8 | Where-Object { $_ -match '^[\w-]+\.[\w.-]+$' })) {
                & $cli --install-extension $e --force 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $failed += $e } else { Write-Host "      + $e" }
            }
        }
    }
    if (-not $any) { [void](Get-PbSavedConfig 'vscode\settings.json' $what); return }
    if ($failed.Count) { Write-Warn2 "не установлены расширения: $($failed -join ', ')"; Add-Result $what 'применено частично' "не установлены: $($failed -join ', ')" }
    else { Write-Ok 'VS Code: настройки и расширения применены'; Add-Result $what 'применено' }
}

# ---------- Notepad++ ----------
# config.xml без истории файлов, поиска, сеансов и панелей проектов (пути к личным файлам), shortcuts.xml, stylers.xml

function Export-NppConfig ([string]$Dir) {
    $base = Expand-PbPath '%APPDATA%\Notepad++'
    if (-not (Test-Path -LiteralPath (Join-Path $base 'config.xml'))) { throw "Файл $base\config.xml не найден." }
    $removed = New-Object System.Collections.ArrayList
    $files = @()
    foreach ($n in 'config.xml', 'shortcuts.xml', 'stylers.xml', 'contextMenu.xml') {
        $src = Join-Path $base $n
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $rel = Join-Path 'npp' $n
        if ($n -eq 'config.xml') {
            $x = New-Object xml
            $x.Load($src)
            foreach ($tag in 'History', 'FindHistory', 'ProjectPanels', 'Session') {
                foreach ($node in @($x.SelectNodes("//$tag"))) { [void]$node.ParentNode.RemoveChild($node); [void]$removed.Add("${rel}: $tag") }
            }
            $tmp = [IO.Path]::GetTempFileName()
            $x.Save($tmp)
            $files += Export-PbConfigFile $tmp $Dir $rel 'text' $removed
            Remove-Item $tmp -Force
        } else { $files += Export-PbConfigFile $src $Dir $rel 'text' $removed }
    }
    return @{ Files = $files; Removed = @($removed) }
}

function Set-NppConfig {
    $what = 'Notepad++: мои настройки'
    if (-not (Get-PbSavedConfig 'npp\config.xml' $what)) { return }
    Stop-PbApp 'notepad++' 'Notepad++'
    $base = Expand-PbPath '%APPDATA%\Notepad++'
    foreach ($n in 'config.xml', 'shortcuts.xml', 'stylers.xml', 'contextMenu.xml') {
        $src = Find-PbConfig "npp\$n"
        if ($src) { Copy-PbConfigIn $src (Join-Path $base $n) }
    }
    Write-Ok "Notepad++: настройки применены ($base)"
    Add-Result $what 'применено'
}

# ---------- Flow Launcher ----------

function Export-FlowConfig ([string]$Dir) {
    $src = Expand-PbPath '%APPDATA%\FlowLauncher\Settings\Settings.json'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'flow' 'Settings.json') 'json' $removed
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-FlowConfig {
    $what = 'Flow Launcher: мои настройки'
    $src = Get-PbSavedConfig 'flow\Settings.json' $what
    if (-not $src) { return }
    Stop-PbApp 'Flow.Launcher' 'Flow Launcher'
    $dst = Expand-PbPath '%APPDATA%\FlowLauncher\Settings\Settings.json'
    Copy-PbConfigIn $src $dst
    Write-Ok "Flow Launcher: настройки применены ($dst)"
    Add-Result $what 'применено'
    Add-Manual 'Flow Launcher: запустить и проверить сочетание клавиш и плагины'
}

# ---------- Everything ----------

function Export-EverythingConfig ([string]$Dir) {
    $src = Expand-PbPath '%APPDATA%\Everything\Everything.ini'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден (переносная версия хранит настройки рядом с программой)." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'everything' 'Everything.ini') 'text' $removed
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-EverythingConfig {
    $what = 'Everything: мои настройки'
    $src = Get-PbSavedConfig 'everything\Everything.ini' $what
    if (-not $src) { return }
    Stop-PbApp 'Everything' 'Everything'
    $dst = Expand-PbPath '%APPDATA%\Everything\Everything.ini'
    Copy-PbConfigIn $src $dst
    Write-Ok "Everything: настройки применены ($dst)"
    Add-Result $what 'применено'
    Add-Manual 'Everything: запустить программу (была закрыта для применения настроек)'
}

# ---------- PowerToys ----------
# settings.json общий и модулей (<модуль>\settings.json); журналы, обновления и кэш не берутся

function Export-PowerToysConfig ([string]$Dir) {
    $base = Expand-PbPath '%LOCALAPPDATA%\Microsoft\PowerToys'
    if (-not (Test-Path -LiteralPath (Join-Path $base 'settings.json'))) { throw "Файл $base\settings.json не найден." }
    $removed = New-Object System.Collections.ArrayList
    $files = @(Export-PbConfigFile (Join-Path $base 'settings.json') $Dir (Join-Path 'powertoys' 'settings.json') 'json' $removed)
    foreach ($d in (Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)log|update|cache|temp' })) {
        $f = Join-Path $d.FullName 'settings.json'
        if (Test-Path -LiteralPath $f) { $files += Export-PbConfigFile $f $Dir (Join-Path (Join-Path 'powertoys' $d.Name) 'settings.json') 'json' $removed }
    }
    return @{ Files = $files; Removed = @($removed) }
}

function Set-PowerToysConfig {
    $what = 'PowerToys: мои настройки'
    $root = Get-PbSavedConfig 'powertoys\settings.json' $what
    if (-not $root) { return }
    Stop-PbApp @('PowerToys', 'PowerToys.Settings') 'PowerToys'
    $srcDir = Split-Path $root
    $base = Expand-PbPath '%LOCALAPPDATA%\Microsoft\PowerToys'
    foreach ($f in (Get-ChildItem -LiteralPath $srcDir -Recurse -File -Filter 'settings.json')) {
        $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\', '/')
        Copy-PbConfigIn $f.FullName (Join-Path $base $rel)
    }
    Write-Ok "PowerToys: настройки применены ($base)"
    Add-Result $what 'применено'
    Add-Manual 'PowerToys: запустить программу (была закрыта для применения настроек)'
}

# ---------- Git ----------
# .gitconfig без разделов [credential…] и http.extraheader (там токены); при применении эти разделы
# на целевом компьютере сохраняются (их пишет gh auth setup-git)

function Split-PbGitConfig ([string[]]$Lines) {
    $keep = New-Object System.Collections.ArrayList; $cred = New-Object System.Collections.ArrayList
    $inCred = $false
    foreach ($l in $Lines) {
        if ($l -match '^\s*\[') { $inCred = $l -match '^\s*\[\s*credential' }
        if ($inCred) { [void]$cred.Add($l) } else { [void]$keep.Add($l) }
    }
    return @{ Keep = @($keep); Cred = @($cred) }
}

function Export-GitConfig ([string]$Dir) {
    $src = Join-Path $env:USERPROFILE '.gitconfig'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $parts = Split-PbGitConfig @(Get-Content -LiteralPath $src -Encoding UTF8)
    if ($parts.Cred.Count) { [void]$removed.Add('git\gitconfig: разделы [credential]') }
    $lines = @($parts.Keep | Where-Object { if ($_ -match '(?i)^\s*extraheader\s*=') { [void]$removed.Add('git\gitconfig: http.extraheader'); $false } else { $true } })
    $rel = Join-Path 'git' 'gitconfig'
    Write-PbText (Join-Path $Dir $rel) (Remove-PbTextSecrets $lines $rel $removed)
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-GitConfig {
    $what = 'Git: мои настройки'
    $src = Get-PbSavedConfig 'git\gitconfig' $what
    if (-not $src) { return }
    $dst = Join-Path $env:USERPROFILE '.gitconfig'
    $cred = @()
    if (Test-Path -LiteralPath $dst) {
        $cred = (Split-PbGitConfig @(Get-Content -LiteralPath $dst -Encoding UTF8)).Cred
        Copy-Item -LiteralPath $dst "$dst.tabula-rasa_$($script:PB.Stamp).bak" -Force
    }
    Write-PbText $dst (@(Get-Content $src -Encoding UTF8 | ForEach-Object { Expand-PbPortablePath $_ }) + @($cred))
    Write-Ok "Git: настройки применены ($dst)$(if ($cred.Count) { ', вход в GitHub на этом компьютере сохранён' })"
    Add-Result $what 'применено'
}

# ---------- реестр HKCU → JSON → Set-Reg ----------
# Формат: { "Values": { "<имя>": { "Kind": "DWord", "Data": 1 } }, "Keys": { "<подраздел>": { … } } }.
# Имена значений и подразделов — ключи JSON, поэтому их проверяет тот же фильтр секретов; длинные двоичные значения
# (base64) он тоже вырезает. $SkipKeys / $SkipValues — regex имён, которые не снимаются (история, недавние файлы)

function ConvertFrom-PbRegKey ($Key, [string]$SkipKeys, [string]$SkipValues, [string]$Path, $Removed) {
    $vals = [ordered]@{}
    foreach ($n in @($Key.GetValueNames() | Sort-Object)) {
        if (-not $n) { continue }   # значение по умолчанию программам не нужно
        if ($SkipValues -and $n -match $SkipValues) { [void]$Removed.Add("$Path\$n"); continue }
        $kind = $Key.GetValueKind($n).ToString()
        if ($kind -notin 'String', 'ExpandString', 'DWord', 'QWord', 'Binary', 'MultiString') { continue }
        $data = $Key.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
        if ($kind -eq 'Binary') { $data = [Convert]::ToBase64String([byte[]]$data) }
        elseif ($kind -eq 'MultiString') { $data = @($data) }
        $vals[$n] = [ordered]@{ Kind = $kind; Data = $data }
    }
    $keys = [ordered]@{}
    foreach ($k in @($Key.GetSubKeyNames() | Sort-Object)) {
        if ($SkipKeys -and $k -match $SkipKeys) { [void]$Removed.Add("$Path\$k\"); continue }
        $sub = $Key.OpenSubKey($k)
        if ($sub) { try { $keys[$k] = ConvertFrom-PbRegKey $sub $SkipKeys $SkipValues "$Path\$k" $Removed } finally { $sub.Close() } }
    }
    return [ordered]@{ Values = $vals; Keys = $keys }
}

# HKCU\$Sub → $Dir\$Rel; нет раздела — исключение
function Export-PbRegKey ([string]$Sub, [string]$Dir, [string]$Rel, $Removed, [string]$SkipKeys, [string]$SkipValues) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Sub)
    if (-not $k) { throw "Раздел реестра HKCU\$Sub не найден." }
    try { $tree = ConvertFrom-PbRegKey $k $SkipKeys $SkipValues $Sub $Removed } finally { $k.Close() }
    $j = $tree | ConvertTo-Json -Depth 50 | ConvertFrom-Json   # тот же фильтр, что и у файлов
    Remove-PbJsonSecrets $j '' $Removed
    $dst = Join-Path $Dir $Rel
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    [IO.File]::WriteAllText($dst, ($j | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding $false))
    return $Rel
}

# JSON → Set-Reg по каждому значению (журнал изменений, откат undo.ps1); пути профиля раскрываются. Возвращает число значений
function Import-PbRegJson ([string]$File, [string]$Sub) {
    $j = Expand-PbPortablePath (Get-Content -LiteralPath $File -Raw -Encoding UTF8) $true | ConvertFrom-Json
    $script:PbRegCount = 0
    function Write-Node ($Node, [string]$Path) {
        if ($Node.Values) {
            foreach ($p in $Node.Values.PSObject.Properties) {
                $v = $p.Value
                if (-not $v.Kind -or $null -eq $v.Data) { continue }   # данные вырезаны фильтром
                $data = switch ($v.Kind) {
                    'DWord' { [int]$v.Data } 'QWord' { [long]$v.Data } 'Binary' { , [Convert]::FromBase64String([string]$v.Data) }
                    'MultiString' { , [string[]]@($v.Data) } default { [string]$v.Data }
                }
                Set-Reg "HKCU:\$Path" $p.Name $data -Type $v.Kind
                $script:PbRegCount++
            }
        }
        if ($Node.Keys) { foreach ($p in $Node.Keys.PSObject.Properties) { Write-Node $p.Value "$Path\$($p.Name)" } }
    }
    Write-Node $j $Sub
    return $script:PbRegCount
}

# общая часть Set-*Config для программ с настройками в реестре
function Set-PbRegConfig ([string]$Rel, [string]$Sub, [string]$What, [string[]]$Proc, [string]$Title) {
    $src = Get-PbSavedConfig $Rel $What
    if (-not $src) { return }
    if ($Proc) { Stop-PbApp $Proc $Title }
    $n = Import-PbRegJson $src $Sub
    Write-Ok "${Title}: настройки применены (HKCU\$Sub, значений: $n)"
    Add-Result $What 'применено'
}

# ---------- Wireshark ----------
# preferences, colorfilters, dfilters, dfilter_macros и профили; recent и recent_common (пути к захватам) — нет

$script:PbWiresharkFiles = @('preferences', 'colorfilters', 'dfilters', 'dfilter_macros', 'dfilter_buttons', 'cfilters', 'io_graphs')

function Export-WiresharkConfig ([string]$Dir) {
    $base = Expand-PbPath '%APPDATA%\Wireshark'
    if (-not (Test-Path -LiteralPath $base)) { throw "Папка $base не найдена: Wireshark на этом компьютере не настраивался." }
    $removed = New-Object System.Collections.ArrayList
    $files = @()
    foreach ($n in $script:PbWiresharkFiles) {
        $f = Join-Path $base $n
        if (Test-Path -LiteralPath $f) { $files += Export-PbConfigFile $f $Dir (Join-Path 'wireshark' $n) 'text' $removed }
    }
    $prof = Join-Path $base 'profiles'
    if (Test-Path -LiteralPath $prof) {
        foreach ($p in (Get-ChildItem -LiteralPath $prof -Directory)) {
            foreach ($f in (Get-ChildItem -LiteralPath $p.FullName -File | Where-Object { $_.Name -notmatch '^recent' })) {
                $files += Export-PbConfigFile $f.FullName $Dir (Join-Path (Join-Path (Join-Path 'wireshark' 'profiles') $p.Name) $f.Name) 'text' $removed
            }
        }
    }
    if (-not $files.Count) { throw "В $base нет файлов настроек." }
    return @{ Files = $files; Removed = @($removed) }
}

function Set-WiresharkConfig {
    $what = 'Wireshark: мои настройки'
    $root = Get-PbSavedConfig 'wireshark\preferences' $what
    if (-not $root) { return }
    Stop-PbApp 'Wireshark' 'Wireshark'
    $srcDir = Split-Path $root
    $base = Expand-PbPath '%APPDATA%\Wireshark'
    foreach ($f in (Get-ChildItem -LiteralPath $srcDir -Recurse -File)) {
        Copy-PbConfigIn $f.FullName (Join-Path $base $f.FullName.Substring($srcDir.Length).TrimStart('\', '/'))
    }
    Write-Ok "Wireshark: настройки применены ($base)"
    Add-Result $what 'применено'
}

# ---------- WinSCP ----------
# только ветка Configuration (параметры программы). Sessions — адреса и учётные данные серверов, не снимается;
# история команд и путей (History) — тоже

$script:PbWinScpKey = 'Software\Martin Prikryl\WinSCP 2\Configuration'

function Export-WinScpConfig ([string]$Dir) {
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbRegKey $script:PbWinScpKey $Dir (Join-Path 'winscp' 'configuration.json') $removed '(?i)^(History|CDCache|LastFingerprints)$' '(?i)^(LastLocal|LastRemote|LastSession)'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-WinScpConfig { Set-PbRegConfig 'winscp\configuration.json' $script:PbWinScpKey 'WinSCP: мои настройки' @('WinSCP') 'WinSCP' }

# ---------- NanaZip ----------
# параметры интерфейса и архивации; история архивов, путей и папок — нет

$script:PbNanaZipKey = 'Software\NanaZip'

function Export-NanaZipConfig ([string]$Dir) {
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbRegKey $script:PbNanaZipKey $Dir (Join-Path 'nanazip' 'registry.json') $removed '' '(?i)History|^PanelPath'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-NanaZipConfig { Set-PbRegConfig 'nanazip\registry.json' $script:PbNanaZipKey 'NanaZip: мои настройки' @('NanaZip', 'NanaZip.Windows') 'NanaZip' }

# ---------- WinMerge ----------
# фильтры, цвета, параметры сравнения; списки недавних файлов и папок — нет

$script:PbWinMergeKey = 'Software\Thingamahoochie\WinMerge'

function Export-WinMergeConfig ([string]$Dir) {
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbRegKey $script:PbWinMergeKey $Dir (Join-Path 'winmerge' 'registry.json') $removed '(?i)recent|mru|history|^Files$' '(?i)recent|mru|^Last'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-WinMergeConfig { Set-PbRegConfig 'winmerge\registry.json' $script:PbWinMergeKey 'WinMerge: мои настройки' @('WinMergeU') 'WinMerge' }

# ---------- Ditto ----------
# параметры программы; база истории буфера обмена (Ditto.db) и пароль сетевой синхронизации — нет

$script:PbDittoKey = 'Software\Ditto'

function Export-DittoConfig ([string]$Dir) {
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbRegKey $script:PbDittoKey $Dir (Join-Path 'ditto' 'registry.json') $removed '' '(?i)^(DBPath|DBPath3|LastPaste|NetworkPassword|SendClients|Clients)'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-DittoConfig { Set-PbRegConfig 'ditto\registry.json' $script:PbDittoKey 'Ditto: мои настройки' @('Ditto') 'Ditto' }

# ---------- System Informer, draw.io, SumatraPDF, KeePassXC, ShareX: файлы в профиле ----------

function Export-SystemInformerConfig ([string]$Dir) {
    $src = Expand-PbPath '%APPDATA%\SystemInformer\settings.xml'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'systeminformer' 'settings.xml') 'text' $removed '' '(?i)name="(\w*Recent\w*|\w*History\w*|ProgramInspectExecutables|FileBrowseExecutable)"'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-SystemInformerConfig {
    $what = 'System Informer: мои настройки'
    $src = Get-PbSavedConfig 'systeminformer\settings.xml' $what
    if (-not $src) { return }
    Stop-PbApp 'SystemInformer' 'System Informer'
    $dst = Expand-PbPath '%APPDATA%\SystemInformer\settings.xml'
    Copy-PbConfigIn $src $dst
    Write-Ok "System Informer: настройки применены ($dst)"
    Add-Result $what 'применено'
}

function Export-DrawioConfig ([string]$Dir) {
    $src = Expand-PbPath '%APPDATA%\draw.io\config.json'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'drawio' 'config.json') 'json' $removed 'recent|lastOpen|lastDir|history|openFiles'
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-DrawioConfig {
    $what = 'draw.io: мои настройки'
    $src = Get-PbSavedConfig 'drawio\config.json' $what
    if (-not $src) { return }
    Stop-PbApp 'draw.io' 'draw.io'
    $dst = Expand-PbPath '%APPDATA%\draw.io\config.json'
    Copy-PbConfigIn $src $dst
    Write-Ok "draw.io: настройки применены ($dst)"
    Add-Result $what 'применено'
}

# SumatraPDF-settings.txt без FileStates (история открытых документов) и SessionData (открытые вкладки)
function Export-SumatraConfig ([string]$Dir) {
    $src = Expand-PbPath '%LOCALAPPDATA%\SumatraPDF\SumatraPDF-settings.txt'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Join-Path 'sumatra' 'SumatraPDF-settings.txt'
    $lines = Remove-PbTextBlocks @(Get-Content -LiteralPath $src -Encoding UTF8) @('FileStates', 'SessionData', 'TabState') $rel $removed
    $lines = @($lines | Where-Object { if ($_ -match '^\s*(TimeOfLastUpdateCheck|OpenCountWeek)\s') { $false } else { $true } })
    Write-PbText (Join-Path $Dir $rel) (Remove-PbTextSecrets $lines $rel $removed) (Test-PbBom $src)
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-SumatraConfig {
    $what = 'SumatraPDF: мои настройки'
    $src = Get-PbSavedConfig 'sumatra\SumatraPDF-settings.txt' $what
    if (-not $src) { return }
    Stop-PbApp 'SumatraPDF' 'SumatraPDF'
    $dst = Expand-PbPath '%LOCALAPPDATA%\SumatraPDF\SumatraPDF-settings.txt'
    Copy-PbConfigIn $src $dst
    Write-Ok "SumatraPDF: настройки применены ($dst)"
    Add-Result $what 'применено'
}

# keepassxc.ini без путей к базам, ключевым файлам и последним папкам (Last…); сами базы не снимаются никогда
function Export-KeePassXCConfig ([string]$Dir) {
    $src = Expand-PbPath '%APPDATA%\KeePassXC\keepassxc.ini'
    if (-not (Test-Path -LiteralPath $src)) { throw "Файл $src не найден." }
    $removed = New-Object System.Collections.ArrayList
    $rel = Export-PbConfigFile $src $Dir (Join-Path 'keepassxc' 'keepassxc.ini') 'text' $removed '' '(?i)^\s*(Last\w*|\w*KeyFile\w*|\w*Database\w*Path\w*|OpenPreviousDatabasesOnStartup\w*)\s*='
    return @{ Files = @($rel); Removed = @($removed) }
}

function Set-KeePassXCConfig {
    $what = 'KeePassXC: мои настройки'
    $src = Get-PbSavedConfig 'keepassxc\keepassxc.ini' $what
    if (-not $src) { return }
    Stop-PbApp 'KeePassXC' 'KeePassXC'
    $dst = Expand-PbPath '%APPDATA%\KeePassXC\keepassxc.ini'
    Copy-PbConfigIn $src $dst
    Write-Ok "KeePassXC: настройки применены ($dst)"
    Add-Result $what 'применено'
    Add-Manual 'KeePassXC: открыть базу паролей вручную (пути к базам не переносятся)'
}

# ApplicationConfig.json и HotkeysConfig.json; UploadersConfig.json (токены сервисов) и история — нет
function Export-ShareXConfig ([string]$Dir) {
    $base = Expand-PbPath '{MyDocuments}\ShareX'
    if (-not (Test-Path -LiteralPath (Join-Path $base 'ApplicationConfig.json'))) { throw "Файл $base\ApplicationConfig.json не найден." }
    $removed = New-Object System.Collections.ArrayList
    $files = @()
    foreach ($n in 'ApplicationConfig.json', 'HotkeysConfig.json') {
        $f = Join-Path $base $n
        if (Test-Path -LiteralPath $f) { $files += Export-PbConfigFile $f $Dir (Join-Path 'sharex' $n) 'json' $removed 'recent|history|lastSave|lastOpen|lastUpload' }
    }
    return @{ Files = $files; Removed = @($removed) }
}

function Set-ShareXConfig {
    $what = 'ShareX: мои настройки'
    if (-not (Get-PbSavedConfig 'sharex\ApplicationConfig.json' $what)) { return }
    Stop-PbApp 'ShareX' 'ShareX'
    $base = Expand-PbPath '{MyDocuments}\ShareX'
    foreach ($n in 'ApplicationConfig.json', 'HotkeysConfig.json') {
        $src = Find-PbConfig "sharex\$n"
        if ($src) { Copy-PbConfigIn $src (Join-Path $base $n) }
    }
    Write-Ok "ShareX: настройки применены ($base)"
    Add-Result $what 'применено'
    Add-Manual 'ShareX: заново подключить сервисы загрузки (их токены не переносятся)'
}

# ---------- снятие: временная папка → сравнение → «Мои данные» ----------

# программы каталога со снятием настроек; Installed — настройки есть на этом компьютере
function Get-PbCaptureApps ($Apps) {
    foreach ($a in @($Apps | Where-Object { $_.Config -and $_.Config.Export })) {
        [pscustomobject]@{ App = $a; Installed = [bool](Get-PbConfigSource $a.Config) }
    }
}

# снять выбранные в $Stage: @{ Id; Name; Files; Removed; Error } на каждую
function Invoke-PbCapture ($Apps, [string]$Stage) {
    New-Item -ItemType Directory -Path $Stage -Force | Out-Null
    foreach ($a in @($Apps)) {
        $r = @{ Id = $a.Id; Name = $a.Name; Files = @(); Removed = @(); Error = $null }
        try {
            $x = & $a.Config.Export $Stage
            $r.Files = @($x.Files); $r.Removed = @($x.Removed)
            # пути профиля → переменные: в репозиторий не попадает имя пользователя, на другом компьютере пути верные
            foreach ($f in $r.Files) { Convert-PbTextFile (Join-Path $Stage $f) { param($t) ConvertTo-PbPortablePath $t } }
        } catch { $r.Error = $_.Exception.Message }
        $r
    }
}

# что изменится в $Target (DataRoot\configs) относительно снятого в $Stage: @{ Rel; State = new|changed|same; Added; Deleted }
function Compare-PbCapture ([string]$Stage, [string[]]$Rels, [string]$Target) {
    foreach ($rel in $Rels) {
        $new = Join-Path $Stage $rel; $old = Join-Path $Target $rel
        if (-not (Test-Path -LiteralPath $old)) {
            @{ Rel = $rel; State = 'new'; Added = @(Get-Content -LiteralPath $new -Encoding UTF8).Count; Deleted = 0 }
            continue
        }
        if ((Get-FileHash -LiteralPath $new).Hash -eq (Get-FileHash -LiteralPath $old).Hash) { @{ Rel = $rel; State = 'same'; Added = 0; Deleted = 0 }; continue }
        $d = @(Compare-Object @(Get-Content -LiteralPath $old -Encoding UTF8) @(Get-Content -LiteralPath $new -Encoding UTF8))
        @{ Rel = $rel; State = 'changed'; Added = @($d | Where-Object { $_.SideIndicator -eq '=>' }).Count; Deleted = @($d | Where-Object { $_.SideIndicator -eq '<=' }).Count }
    }
}

function Copy-PbCapture ([string]$Stage, [string[]]$Rels, [string]$Target) {
    foreach ($rel in $Rels) {
        $dst = Join-Path $Target $rel
        New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Stage $rel) $dst -Force
    }
}
