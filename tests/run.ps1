# Tabula Rasa: проверки без окна и без сети — разбор вывода winget (русский и английский), свой каталог, фильтр секретов,
# снятие настроек, разметка репозитория данных, имена ассетов. Запуск из корня репозитория:
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1        (или pwsh -File tests/run.ps1)
# Нужен git. Всё пишется во временную папку; сеть, gh и «Мои данные» на этом компьютере не затрагиваются.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($f in 'common', 'data', 'files', 'catalog', 'configs', 'status', 'run') { . (Join-Path (Join-Path $root 'lib') "$f.ps1") }
$script:PB.Root = $root

$script:Fails = 0; $script:Count = 0
function Check ([string]$Name, [bool]$Ok, $Got) {
    $script:Count++
    if ($Ok) { Write-Host "  ok   $Name" -ForegroundColor Green }
    else { $script:Fails++; Write-Host "  FAIL $Name$(if ($null -ne $Got) { " — получено: $($Got | Out-String -Width 200)".TrimEnd() })" -ForegroundColor Red }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tabula-rasa-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    # ---------- winget search ----------
    Write-Host 'winget search'
    $en = @(
        "   - `r   \ `r",
        'Name                  Id                          Version Match          Source',
        '-------------------------------------------------------------------------------',
        'Notepad++             Notepad++.Notepad++         8.7.1                  winget',
        'Notepad Next          dail8859.NotepadNext        0.9     Tag: notepad   winget',
        'Notepad Fork          Some.VeryLongIdentifierTha… 1.0                    winget',
        '',
        'Additional entries'
    )
    $r = ConvertFrom-PbWingetTable $en
    Check 'en: две строки, усечённый id отброшен' ($r.Count -eq 2) $r
    Check 'en: имя с пробелом' ($r[1].Name -eq 'Notepad Next' -and $r[1].Id -eq 'dail8859.NotepadNext' -and $r[1].Version -eq '0.9') $r[1]
    $ru = @(
        "`r   / `r",
        'Имя        ИД                   Версия    Совпадение',
        '----------------------------------------------------',
        '7-Zip      7zip.7zip            24.08',
        'NanaZip    M2Team.NanaZip       5.0.1263  Tag: 7zip',
        'PeaZip     Giorgiotani.Peazip   10.0      Tag: 7zip'
    )
    $r = ConvertFrom-PbWingetTable $ru
    Check 'ru: три строки без колонки «Источник»' ($r.Count -eq 3) $r
    Check 'ru: позиции по заголовку' ($r[0].Id -eq '7zip.7zip' -and $r[1].Version -eq '5.0.1263' -and $r[2].Name -eq 'PeaZip') $r
    Check 'нет таблицы — пусто' (@(ConvertFrom-PbWingetTable @('No package found matching input criteria.')).Count -eq 0)
    $m = Merge-PbWingetResults '7-zip' @(@($r[2], $r[1]), @($r[0], $r[1]))
    Check 'сортировка: точное имя первым, дубли убраны' ($m.Count -eq 3 -and $m[0].Id -eq '7zip.7zip' -and $m[1].Id -eq 'Giorgiotani.Peazip') ($m | Select-Object Name, Rank)
    $m = Merge-PbWingetResults 'notepad' @(, @(
        [pscustomobject]@{ Name = 'Notepad++'; Id = 'Notepad++.Notepad++'; Version = '' },
        [pscustomobject]@{ Name = 'Microsoft Windows Notepad'; Id = 'x.y'; Version = '' },
        [pscustomobject]@{ Name = 'notepad'; Id = 'a.b'; Version = '' }))
    Check 'сортировка: точное → начало имени → остальное' (($m.Id -join ',') -eq 'a.b,Notepad++.Notepad++,x.y') $m.Id

    $show = @('Found Notepad++ [Notepad++.Notepad++]', 'Version: 8.7.1', 'Publisher: Notepad++ Team', 'Description:', '  Notepad++ is a free source code editor', '  and Notepad replacement.', 'Homepage: https://notepad-plus-plus.org/', 'License: GPL-3.0')
    $s = ConvertFrom-PbWingetShow $show
    Check 'show en: издатель и многострочное описание' ($s.Publisher -eq 'Notepad++ Team' -and $s.Description -eq 'Notepad++ is a free source code editor and Notepad replacement.') $s
    $s = ConvertFrom-PbWingetShow @('Найдено 7-Zip [7zip.7zip]', 'Версия: 24.08', 'Издатель: Igor Pavlov', 'Описание: Архиватор', 'Лицензия: LGPL-2.1')
    Check 'show ru' ($s.Publisher -eq 'Igor Pavlov' -and $s.Description -eq 'Архиватор' -and $s.License -eq 'LGPL-2.1') $s

    # ---------- свой каталог ----------
    Write-Host 'свой каталог'
    $script:PB.DataRoot = Join-Path $tmp 'data'
    New-Item -ItemType Directory -Path (Join-Path $script:PB.DataRoot 'catalog') -Force | Out-Null
    $builtin = @('git', 'vivaldi')
    Check 'верная запись' ($null -eq (Test-PbUserApp @{ Id = 'my.obs'; Name = 'OBS'; WingetId = 'OBSProject.OBSStudio'; Source = 'winget' } $builtin))
    Check 'web запрещён' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Source = 'web' } $builtin))
    Check 'Override запрещён' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Override = '/S' } $builtin))
    Check 'id встроенного запрещён' ([bool](Test-PbUserApp @{ Id = 'git'; Name = 'X'; WingetId = 'A.B' } $builtin))
    Check 'скриптблок не строка' ([bool](Test-PbUserApp @{ Id = 'x'; Name = { 'код' }; WingetId = 'A.B' } $builtin))
    Check 'Interactive не bool' ([bool](Test-PbUserApp @{ Id = 'x'; Name = 'X'; WingetId = 'A.B'; Interactive = 'yes' } $builtin))
    $id1 = New-PbUserAppId 'Notepad++.Notepad++' @(); $id2 = New-PbUserAppId 'Notepad++.Notepad++' @($id1)
    Check 'New-PbUserAppId: допустимый и уникальный' ($id1 -eq 'my.notepadpp.notepadpp' -and $id2 -eq "$id1-2" -and -not (Test-PbUserApp @{ Id = $id2; Name = 'N'; WingetId = 'Notepad++.Notepad++' } @($id1))) @($id1, $id2)
    Write-PbUserCatalog @(@{ Id = 'my.obs'; Name = "OBS 'Studio'"; Desc = 'Запись экрана'; Category = 'Медиа'; Source = 'winget'; WingetId = 'OBSProject.OBSStudio'; OpenSource = $true; Mine = $true })
    $c = Read-PbUserCatalog $builtin
    Check 'запись и чтение: кавычки, кириллица, bool' ($c.Apps.Count -eq 1 -and $c.Apps[0].Name -eq "OBS 'Studio'" -and $c.Apps[0].Category -eq 'Медиа' -and $c.Apps[0].OpenSource -eq $true -and $c.Apps[0].Mine) $c
    Check 'файл каталога с BOM' (Test-PbBom (Get-PbUserCatalogPath))
    $p = Get-PbUserCatalogPath
    [IO.File]::WriteAllText($p, "@{ Apps = @(`n @{ Id = 'my.a'; Name = 'A'; WingetId = 'A.A' }`n @{ Id = 'my.b'; Name = 'B'; Source = 'web'; WingetId = 'B.B' }`n @{ Id = 'my.a'; Name = 'A2'; WingetId = 'A.A2' }`n @{ Id = 'my.c'; Name = 'C'; WingetId = 'C.C'; Category = 'Своё' }`n) }", (New-Object Text.UTF8Encoding $true))
    $c = Read-PbUserCatalog $builtin
    Check 'ошибочные пропущены с сообщением' ($c.Apps.Count -eq 2 -and $c.Errors.Count -eq 2 -and $c.Apps[0].Category -eq 'Мой каталог') ($c.Errors)
    [IO.File]::WriteAllText($p, "@{ Apps = @( @{ Id = 'my.a'; Name = 'A'; WingetId = 'A.A'; Note = { Remove-Item C:\ } } ) }", (New-Object Text.UTF8Encoding $true))
    $c = Read-PbUserCatalog $builtin
    Check 'скриптблок в файле — файл не загружается' ($c.Apps.Count -eq 0 -and $c.Errors.Count -eq 1) $c.Errors

    # ---------- фильтр секретов ----------
    Write-Host 'фильтр секретов'
    $rm = New-Object System.Collections.ArrayList
    $j = '{"theme":"dark","github":{"token":"x"},"list":["ok","ghp_0123456789abcdefghijABCDEFGHIJ0123456789"],"nested":{"apiKey":"k","size":11},"Path":"C:\\Users\\user\\AppData\\Local\\Programs\\Microsoft VS Code\\bin\\code.cmd"}' | ConvertFrom-Json
    Remove-PbJsonSecrets $j '' $rm
    Check 'json: token, apiKey и токен в массиве удалены' ($null -eq $j.github.token -and $null -eq $j.nested.apiKey -and $j.nested.size -eq 11 -and @($j.list).Count -eq 1 -and $rm.Count -eq 3) $rm
    Check 'json: путь не принят за токен' ([bool]$j.Path)
    $rm = New-Object System.Collections.ArrayList
    $t = Remove-PbTextSecrets @('[general]', 'theme = dark', 'password=123', '  "github.token": "abc",', 'x = ghp_0123456789abcdefghijABCDEFGHIJ0123456789', 'font = Cascadia') 'a.ini' $rm
    Check 'текст: строки с секретами удалены' (($t -join '|') -eq '[general]|theme = dark|font = Cascadia' -and $rm.Count -eq 3) $t

    # ---------- снятие настроек: Git, временная папка, сравнение ----------
    Write-Host 'снятие настроек'
    $home2 = Join-Path $tmp 'home'; New-Item -ItemType Directory -Path $home2 | Out-Null
    $oldProfile = $env:USERPROFILE; $env:USERPROFILE = $home2
    try {
        $gc = @('[user]', '    name = user', '[credential "https://github.com"]', '    helper = !gh auth git-credential', '[alias]', '    st = status', '[http]', '    extraheader = AUTHORIZATION: basic xyz')
        Write-PbText (Join-Path $home2 '.gitconfig') $gc
        $stage = Join-Path $tmp 'stage'
        $app = @{ Id = 'git'; Name = 'Git'; Config = @{ Export = 'Export-GitConfig' } }
        $res = @(Invoke-PbCapture @($app) $stage)
        $out = @(Get-Content (Join-Path $stage $res[0].Files[0]) -Encoding UTF8)
        Check 'git: без credential и extraheader' (-not $res[0].Error -and ($out -join '|') -eq '[user]|    name = user|[alias]|    st = status|[http]' -and $res[0].Removed.Count -eq 2) @($out, $res[0].Removed, $res[0].Error)
        $target = Join-Path $tmp 'target'
        $cmp = @(Compare-PbCapture $stage $res[0].Files $target)
        Check 'сравнение: новый файл' ($cmp[0].State -eq 'new' -and $cmp[0].Added -eq 5) $cmp[0]
        Copy-PbCapture $stage $res[0].Files $target
        Check 'сравнение: без изменений' ((@(Compare-PbCapture $stage $res[0].Files $target))[0].State -eq 'same')
        Write-PbText (Join-Path $home2 '.gitconfig') ($gc + '    lg = log --oneline')
        $res = @(Invoke-PbCapture @($app) $stage)
        $cmp = @(Compare-PbCapture $stage $res[0].Files $target)
        Check 'сравнение: изменён, +1' ($cmp[0].State -eq 'changed' -and $cmp[0].Added -eq 1 -and $cmp[0].Deleted -eq 0) $cmp[0]
        $res = @(Invoke-PbCapture @(@{ Id = 'npp'; Name = 'Notepad++'; Config = @{ Export = 'Export-NppConfig' } }) $stage)
        Check 'нет настроек — ошибка, без исключения' ([bool]$res[0].Error) $res[0]
        # Vivaldi: только поддерево vivaldi, без синхронизации и токенов; вкладка видит только то, что есть на компьютере
        $oldLa = $env:LOCALAPPDATA; $env:LOCALAPPDATA = Join-Path $tmp 'la'
        try {
            $pd = Join-Path $env:LOCALAPPDATA (Join-Path 'Vivaldi' (Join-Path 'User Data' 'Default'))
            New-Item -ItemType Directory -Path $pd -Force | Out-Null
            '{"profile":{"name":"user"},"vivaldi":{"theme":{"current":"dark"},"sync":{"server":"x"},"mail":{"on":true},"tabs":{"stack":true}}}' | Set-Content (Join-Path $pd 'Preferences') -Encoding UTF8
            $catalog = (Import-PowerShellDataFile (Join-Path (Join-Path $root 'catalog') 'apps.psd1')).Apps
            $cap = @(Get-PbCaptureApps $catalog)
            Check 'вкладка: 19 программ, на «компьютере» есть Git и Vivaldi' ($cap.Count -eq 19 -and (($cap | Where-Object Installed | ForEach-Object { $_.App.Id }) -join ',') -eq 'git,vivaldi') ($cap | ForEach-Object { "$($_.App.Id)=$($_.Installed)" })
            $res = @(Invoke-PbCapture @($catalog | Where-Object { $_.Id -eq 'vivaldi' }) $stage)
            $v = Get-Content (Join-Path $stage $res[0].Files[0]) -Raw | ConvertFrom-Json
            Check 'vivaldi: тема и вкладки есть, sync и mail вырезаны, profile не взят' ($v.vivaldi.theme.current -eq 'dark' -and $v.vivaldi.tabs.stack -and -not $v.vivaldi.sync -and -not $v.vivaldi.mail -and -not $v.profile -and $res[0].Removed.Count -eq 2) @($v, $res[0].Removed)
        } finally { $env:LOCALAPPDATA = $oldLa }
        Check '{MyDocuments} раскрывается' ((Expand-PbPath '{MyDocuments}\x') -eq ([Environment]::GetFolderPath('MyDocuments') + [IO.Path]::DirectorySeparatorChar + 'x'))
        # применение Git сохраняет вход в GitHub на целевом компьютере
        $script:PB.DataRoot = $target | Split-Path; Rename-Item $target 'configs'
        Write-PbText (Join-Path $home2 '.gitconfig') @('[credential "https://github.com"]', '    helper = target-helper')
        Set-GitConfig
        $after = @(Get-Content (Join-Path $home2 '.gitconfig') -Encoding UTF8)
        Check 'git: применение сохраняет credential компьютера' (($after -contains '    helper = target-helper') -and ($after -contains '    st = status') -and -not ($after -match 'gh auth')) $after
    } finally { $env:USERPROFILE = $oldProfile }

    # ---------- пути профиля, вторая партия, реестр ----------
    Write-Host 'пути профиля и вторая партия'
    $saved = @{}; foreach ($n in 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $u = 'C:\' + 'Users\user'   # склеено, чтобы проверка на личное (C:\Users\<имя>) не срабатывала на пример
        $env:USERPROFILE = $u; $env:APPDATA = "$u\AppData\Roaming"; $env:LOCALAPPDATA = "$u\AppData\Local"
        $t = @("path=$u\AppData\Roaming\Wireshark\x", ('"p": "' + $u.Replace('\', '\\') + '\\AppData\\Local\\Programs\\code.cmd",'),
            'file = c:/users/user/.ssh/config', "other = $($u)name\x", "home=$u") -join "`n"
        $p = ConvertTo-PbPortablePath $t
        $exp = @('path=%APPDATA%\Wireshark\x', '"p": "%LOCALAPPDATA%\\Programs\\code.cmd",', 'file = %USERPROFILE%/.ssh/config', "other = $($u)name\x", 'home=%USERPROFILE%') -join "`n"
        Check 'пути → переменные: \, \\, /, регистр, чужой профиль не задет' ($p -eq $exp) $p
        $env:USERPROFILE = 'D:\Профили\Пётр'; $env:APPDATA = 'D:\Профили\Пётр\AppData\Roaming'; $env:LOCALAPPDATA = 'D:\Профили\Пётр\AppData\Local'
        Check 'переменные → пути другого компьютера, текст' ((Expand-PbPortablePath 'path=%APPDATA%\Wireshark x=%userprofile%/.ssh') -eq 'path=D:\Профили\Пётр\AppData\Roaming\Wireshark x=D:/Профили/Пётр/.ssh')
        Check 'переменные → пути, JSON' ((Expand-PbPortablePath '"p": "%LOCALAPPDATA%\\Programs"' $true) -eq '"p": "D:\\Профили\\Пётр\\AppData\\Local\\Programs"')
        $env:USERPROFILE = Join-Path $tmp 'u2'; $env:APPDATA = Join-Path $env:USERPROFILE 'Roaming'; $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'Local'

        # снятие: пути заменяются во всех файлах, кодировка UTF-16 сохраняется
        $ws = Join-Path $env:APPDATA 'Wireshark'
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $ws 'profiles') 'Work') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $ws 'preferences'), "gui.fileopen.dir: $(Join-Path $env:USERPROFILE 'caps')`n", (New-Object Text.UTF8Encoding $false))
        [IO.File]::WriteAllText((Join-Path $ws 'recent'), "recent.capture_file: x.pcap`n")
        [IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $ws 'profiles') 'Work') 'colorfilters'), "@TCP@tcp@[0,0,0]`n")
        [IO.File]::WriteAllText((Join-Path (Join-Path (Join-Path $ws 'profiles') 'Work') 'recent_common'), "x`n")
        $st2 = Join-Path $tmp 'stage2'
        $res = @(Invoke-PbCapture @(@{ Id = 'wireshark'; Name = 'Wireshark'; Config = @{ Export = 'Export-WiresharkConfig' } }) $st2)
        $prefs = Get-Content (Join-Path $st2 (Join-Path 'wireshark' 'preferences')) -Raw
        Check 'wireshark: recent не взяты, профиль взят' (-not $res[0].Error -and $res[0].Files.Count -eq 2 -and -not ($res[0].Files -match 'recent')) $res[0]
        Check 'wireshark: путь профиля заменён на %USERPROFILE%' ($prefs -match '%USERPROFILE%' -and $prefs -notmatch [regex]::Escape($env:USERPROFILE)) $prefs
        $u16 = Join-Path $tmp 'u16.txt'
        [IO.File]::WriteAllText($u16, "a=$($env:APPDATA)\x", (New-Object Text.UnicodeEncoding $false, $true))
        Convert-PbTextFile $u16 { param($t) ConvertTo-PbPortablePath $t }
        $b = [IO.File]::ReadAllBytes($u16)
        Check 'UTF-16 остаётся UTF-16' ($b[0] -eq 0xFF -and $b[1] -eq 0xFE -and (Read-PbTextFile $u16).Text -eq 'a=%APPDATA%\x')

        # применение раскрывает переменные под этот компьютер
        $script:PB.DataRoot = Join-Path $tmp 'data2'
        Copy-PbCapture $st2 $res[0].Files (Join-Path $script:PB.DataRoot 'configs')
        Remove-Item $ws -Recurse -Force
        Set-WiresharkConfig | Out-Null
        $back = Get-Content (Join-Path $ws 'preferences') -Raw
        Check 'wireshark: применение раскрыло путь' ($back -match [regex]::Escape((Join-Path $env:USERPROFILE 'caps'))) $back

        # KeePassXC: пути к базам и Last… вырезаются; SumatraPDF: блоки FileStates и SessionData
        $kp = Join-Path $env:APPDATA 'KeePassXC'; New-Item -ItemType Directory -Path $kp -Force | Out-Null
        Write-PbText (Join-Path $kp 'keepassxc.ini') @('[General]', 'ConfigVersion=2', 'LastDatabases=C:/db.kdbx', 'LastKeyFiles=@Variant(x)', 'LastDir=C:/x', '[Security]', 'LockDatabaseIdle=true')
        $res = @(Invoke-PbCapture @(@{ Id = 'keepassxc'; Name = 'KeePassXC'; Config = @{ Export = 'Export-KeePassXCConfig' } }) $st2)
        $ini = @(Get-Content (Join-Path $st2 $res[0].Files[0]))
        Check 'keepassxc: Last… вырезаны' (($ini -join '|') -eq '[General]|ConfigVersion=2|[Security]|LockDatabaseIdle=true' -and $res[0].Removed.Count -eq 3) $ini
        $su = Join-Path $env:LOCALAPPDATA 'SumatraPDF'; New-Item -ItemType Directory -Path $su -Force | Out-Null
        Write-PbText (Join-Path $su 'SumatraPDF-settings.txt') @('Theme = Dark', 'FileStates [', '  [', '    FilePath = C:\doc.pdf', '  ]', ']', 'SessionData [', ']', 'ZoomDefault = fit page', 'TimeOfLastUpdateCheck = 0 0')
        $res = @(Invoke-PbCapture @(@{ Id = 'sumatra'; Name = 'SumatraPDF'; Config = @{ Export = 'Export-SumatraConfig' } }) $st2)
        $su2 = @(Get-Content (Join-Path $st2 $res[0].Files[0]))
        Check 'sumatra: без FileStates, SessionData и служебного' (($su2 -join '|') -eq 'Theme = Dark|ZoomDefault = fit page') $su2

        # реестр: JSON → Set-Reg (подменён: в тестах реестр не трогаем), вырезанное фильтром не пишется
        $script:Calls = New-Object System.Collections.ArrayList
        function Set-Reg { param($Path, $Name, $Value, $Type) [void]$script:Calls.Add("$Path|$Name|$Type|$(@($Value) -join ',')") }
        $rj = Join-Path $tmp 'reg.json'
        [IO.File]::WriteAllText($rj, '{ "Values": { "Theme": { "Kind": "DWord", "Data": 2 }, "Editor": { "Kind": "String", "Data": "%LOCALAPPDATA%\\Programs\\x.exe" }, "Cut": { "Kind": "String" } },
          "Keys": { "Interface": { "Values": { "Big": { "Kind": "QWord", "Data": 5000000000 }, "List": { "Kind": "MultiString", "Data": [ "a", "b" ] }, "Bin": { "Kind": "Binary", "Data": "AQID" } } } } }')
        $n = Import-PbRegJson $rj 'Software\Test'
        Check 'реестр: 5 значений через Set-Reg, вырезанное пропущено' ($n -eq 5 -and $script:Calls.Count -eq 5) $script:Calls
        Check 'реестр: типы и раскрытый путь' (($script:Calls -contains 'HKCU:\Software\Test|Theme|DWord|2') -and ($script:Calls -contains "HKCU:\Software\Test|Editor|String|$($env:LOCALAPPDATA)\Programs\x.exe") -and
            ($script:Calls -contains 'HKCU:\Software\Test\Interface|Big|QWord|5000000000') -and ($script:Calls -contains 'HKCU:\Software\Test\Interface|List|MultiString|a,b') -and
            ($script:Calls -contains 'HKCU:\Software\Test\Interface|Bin|Binary|1,2,3')) $script:Calls
        Remove-Item function:Set-Reg
    } finally { foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) } }

    # ---------- разметка репозитория данных ----------
    Write-Host 'разметка'
    function New-TestRepo ([string]$Name) {
        $d = Join-Path $tmp $Name
        & git init -q $d
        & git -C $d config user.name test; & git -C $d config user.email test@example.com; & git -C $d config core.autocrlf false
        return $d
    }
    $script:PB.DataRoot = New-TestRepo 'fresh'
    [IO.File]::WriteAllText((Join-Path $script:PB.DataRoot 'README.md'), "# tabula-rasa-private`n")
    & git -C $script:PB.DataRoot add -A; & git -C $script:PB.DataRoot commit -q -m init
    Check 'новый репозиторий — empty' ((Get-PbDataLayout) -eq 'empty') (Get-PbDataLayout)
    $plan = Get-PbLayoutPlan -Fresh
    Install-PbDataLayout $plan
    $files = @((Invoke-PbGit ls-files).Out)
    Check 'разметка: все файлы одним коммитом' ((Get-PbDataLayout) -eq 'ok' -and $files -contains 'tabula-rasa.json' -and $files -contains 'catalog/apps.psd1' -and $files -contains 'saves/.gitkeep' -and $files -contains '.gitignore' -and @((Invoke-PbGit log --oneline).Out).Count -eq 2) $files
    Check 'README заменён' ((Get-Content (Join-Path $script:PB.DataRoot 'README.md') -Raw) -match 'Мои данные Tabula Rasa')
    Check 'пустой каталог читается' ((Read-PbUserCatalog @()).Errors.Count -eq 0)
    Check 'после разметки план пуст' (@(Get-PbLayoutPlan).Count -eq 0) (Get-PbLayoutPlan)

    $script:PB.DataRoot = New-TestRepo 'foreign'
    $r = $script:PB.DataRoot
    New-Item -ItemType Directory (Join-Path $r 'docs') | Out-Null
    [IO.File]::WriteAllText((Join-Path $r 'README.md'), "# Свои данные`n`nМой журнал и планы.`nЕщё строка.`n")
    [IO.File]::WriteAllText((Join-Path (Join-Path $r 'docs') 'plan.md'), "план`n")
    [IO.File]::WriteAllText((Join-Path $r '.gitignore'), "*.log`nsecrets/`n")
    New-Item -ItemType Directory (Join-Path $r 'saves') | Out-Null
    [IO.File]::WriteAllText((Join-Path (Join-Path $r 'saves') 'a.json'), '{}')
    & git -C $r add -A; & git -C $r commit -q -m init
    Check 'чужой репозиторий — foreign' ((Get-PbDataLayout) -eq 'foreign') (Get-PbDataLayout)
    $plan = Get-PbLayoutPlan
    $rels = @($plan | ForEach-Object { $_.Rel })
    Check 'foreign: README и saves не трогаются' ($rels -notcontains 'README.md' -and $rels -notcontains 'saves/.gitkeep' -and $rels -contains 'configs/.gitkeep' -and $rels -contains 'catalog/apps.psd1') $rels
    Check 'foreign: .gitignore дополняется, *.log не повторяется' (($plan | Where-Object { $_.Rel -eq '.gitignore' }).Append -notcontains '*.log') $plan
    $before = (Get-Content (Join-Path $r 'README.md') -Raw)
    Install-PbDataLayout $plan
    $gi = Get-Content (Join-Path $r '.gitignore') -Encoding UTF8
    Check 'foreign: ничего не удалено и не перезаписано' ((Get-Content (Join-Path $r 'README.md') -Raw) -eq $before -and (Test-Path (Join-Path (Join-Path $r 'docs') 'plan.md')) -and $gi[0] -eq '*.log' -and $gi -contains '*.kdbx' -and (Get-PbDataLayout) -eq 'ok') $gi

    [IO.File]::WriteAllText((Join-Path $r 'tabula-rasa.json'), '{ "format": 99 }')
    Check 'манифест новее — только чтение' ((Get-PbDataLayout) -eq 'new' -and (Test-PbDataReadOnly))
    $blocked = $false
    try { Save-PbSave 'x' @{ Apps = @(); Tweaks = @(); Configs = @(); Files = @() } | Out-Null } catch { $blocked = $_.Exception.Message -match 'Обновите программу' }
    Check 'только чтение: сохранение не записывается' ($blocked -and -not (Test-Path (Join-Path (Join-Path $r 'saves') 'x.json')))
    $blocked = $false
    try { Add-PbUserApp @{ Id = 'my.x'; Name = 'X'; WingetId = 'X.X' } @() } catch { $blocked = $true }
    Check 'только чтение: каталог не меняется' $blocked

    # ---------- надёжность прогона: таймаут winget, коды, журнал изменений, кеш model.cs ----------
    Write-Host 'надёжность прогона'
    $script:PB.LogDir = Join-Path $tmp 'logs'
    $ps = (Get-Process -Id $PID).Path   # тот же PowerShell вместо winget: спит дольше лимита
    $r = Invoke-PbWingetTimed @('-NoProfile', '-Command', 'Write-Output начало; Start-Sleep 60') 0.05 'test.slow' $ps
    Check 'таймаут: процесс снят через ~3 с, кода нет' ($r.TimedOut -and $null -eq $r.Code -and $r.Seconds -lt 15) $r
    Check 'таймаут: вывод в отдельном журнале' ((Get-Content $r.Log -Raw) -match 'начало') (Get-Content $r.Log -Raw)
    $r = Invoke-PbWingetTimed @('-NoProfile', '-Command', 'Write-Output "с пробелом"; exit 7') 1 'test.code' $ps
    Check 'код выхода и аргумент с пробелами' (-not $r.TimedOut -and $r.Code -eq 7 -and (Get-Content $r.Log -Raw) -match 'с пробелом') $r
    Check 'вывод возвращается строками (для поиска)' (@($r.Out) -contains 'с пробелом') $r.Out
    Check 'коды winget: уже установлено, нет пакета, система не поддерживает' ((Get-PbWingetCodeInfo -1978335135).Ok -and -not (Get-PbWingetCodeInfo -1978335212).Ok -and
        (Get-PbWingetCodeInfo -1978334957).Text -match 'не поддерживает' -and (Get-PbWingetCodeInfo 5).Text -match '0x00000005')
    $script:PB.Changes.Clear()
    Add-PbChange ([ordered]@{ Kind = 'Reg'; Path = 'HKCU:\Software\X'; Name = 'A' })
    $j = Join-Path $script:PB.LogDir "changes_$($script:PB.Stamp).json"
    Check 'журнал изменений пишется сразу, без конца прогона' ((Test-Path $j) -and (@(Get-Content $j -Raw | ConvertFrom-Json)).Count -eq 1)
    $mc = Join-Path $tmp 'modelcache'
    $probe = "`$ErrorActionPreference = 'Stop'; . '$((Join-Path (Join-Path $root 'lib') 'common.ps1'))'; `$script:PbUiDir = '$((Join-Path (Join-Path $root 'lib') 'ui'))'; " +
        "`$a = [Management.Automation.Language.Parser]::ParseFile('$((Join-Path (Join-Path $root 'lib') 'gui.ps1'))', [ref]`$null, [ref]`$null); " +
        "`$f = `$a.FindAll({ `$args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and `$args[0].Name -eq 'Import-PbModel' }, `$true)[0]; " +
        ". ([scriptblock]::Create(`$f.Extent.Text)); Import-PbModel '$mc'; ([type]'PcBase.Item').Assembly.Location"
    $first = & $ps -NoProfile -Command $probe
    $second = & $ps -NoProfile -Command $probe
    Check 'model.cs: собран в кеш один раз и загружается из него' ($first -like "$mc*" -and $second -eq $first -and @(Get-ChildItem $mc -Filter *.dll).Count -eq 1) @($first, $second)

    # ---------- статус твиков (CheckOnly): чтение подменено, в тестах ничего не меняется ----------
    Write-Host 'статус твиков'
    . (Join-Path (Join-Path $root 'lib') 'common.ps1')   # настоящий Set-Reg: секция про реестр выше подменяла его
    $script:PB.Root = $root; $script:PB.LogDir = Join-Path $tmp 'logs'
    $script:FakeReg = @{ 'HKCU:\X|A' = 1; 'HKCU:\X|B' = 0; 'HKCU:\X|S' = 'abc'; 'HKCU:\X|M' = @('a', 'b'); 'HKCU:\X|N' = -1 }
    function Get-PbRegValue ([string]$Path, [string]$Name) { $k = "$Path|$Name"; if ($script:FakeReg.ContainsKey($k)) { @{ Exists = $true; Value = $script:FakeReg[$k] } } else { @{ Exists = $false } } }
    function Get-PbSvcMode ([string]$Name) { @{ DiagTrack = 'Disabled'; Other = 'Auto' }[$Name] }
    function Get-PbTaskState ([string]$P, [string]$N) { @{ T1 = 'Disabled'; T2 = 'Ready' }[$N] }
    function Test-PbAppxPresent ([string]$Name) { $Name -eq 'Still.There' }
    $before = $script:PB.Changes.Count
    $tw = @(
        @{ Id = 't.all'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; Set-Reg 'HKCU:\X' 'S' 'abc' -Type String; Set-Reg 'HKCU:\X' 'M' @('a', 'b') -Type MultiString; Set-Reg 'HKCU:\X' 'N' 0xFFFFFFFF; Set-SvcStart 'DiagTrack' 'Disabled'; Disable-Task '\' 'T1' } }
        @{ Id = 't.part'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; Set-Reg 'HKCU:\X' 'B' 1; Disable-Task '\' 'T2' } }
        @{ Id = 't.no'; Apply = { Set-Reg 'HKCU:\X' 'Missing' 1; Set-SvcStart 'Other' 'Disabled' } }
        @{ Id = 't.appx'; Apply = { Remove-Appx @('Gone.App', 'Still.There') } }
        @{ Id = 't.unsafe'; Apply = { Set-Reg 'HKCU:\X' 'A' 1; & powercfg.exe /hibernate off } }
        @{ Id = 't.nothing'; Apply = { Set-SvcStart 'NoSuchService' 'Disabled' } }
        @{ Id = 't.check'; Check = { $true }; Apply = { Stop-Process -Name explorer } }
    )
    $st = @($tw | ForEach-Object { "$($_.Id)=$(Get-PbTweakStatus $_)" }) -join ' '
    Check 'твики: применено / частично / нет / Appx / небезопасный / нечего проверять / свой Check' ($st -eq 't.all=applied t.part=partial t.no=no t.appx=partial t.unsafe=unknown t.nothing=unknown t.check=applied') $st
    Check 'проверка ничего не пишет в журнал изменений' ($script:PB.Changes.Count -eq $before -and -not $script:PB.CheckOnly)
    . (Join-Path (Join-Path $root 'catalog') 'tweaks.ps1')
    $unk = @($Tweaks | Where-Object { -not $_.Check -and -not (Test-PbTweakCheckable $_) } | ForEach-Object { $_.Id }) -join ','
    Check 'каталог: без проверки только env.terminal, env.pwshprofile, env.upgrade' ($unk -eq 'env.terminal,env.pwshprofile,env.upgrade') $unk
    foreach ($f in 'Get-PbRegValue', 'Get-PbSvcMode', 'Get-PbTaskState', 'Test-PbAppxPresent') { Remove-Item "function:$f" }
    . (Join-Path (Join-Path $root 'lib') 'common.ps1')   # вернуть настоящие функции чтения
    $script:PB.Root = $root

    # ---------- статус программ ----------
    Write-Host 'статус программ'
    $en = @("`r  - `r",
        'Name               Id                    Version      Available    Source',
        '---------------------------------------------------------------------------',
        'Git                Git.Git               2.46.0       2.47.1       winget',
        'Notepad++ (64-bit) Notepad++.Notepad++   8.7.1                     winget',
        'Windows Terminal   Microsoft.WindowsTer… 1.21                      winget')
    $w = ConvertFrom-PbWingetList $en
    Check 'winget list en: обновление, без обновления, усечённый id отброшен' ($w['git.git'].Available -eq '2.47.1' -and $w['notepad++.notepad++'].Version -eq '8.7.1' -and -not $w['notepad++.notepad++'].Available -and $w.Count -eq 2) ($w | ConvertTo-Json)
    $ru = @('Имя            ИД                    Версия   Доступно',
        '--------------------------------------------------------',
        '7-Zip 24.08    7zip.7zip             24.08',
        'Vivaldi        Vivaldi.Vivaldi       6.9.1    7.0.3215')
    $w2 = ConvertFrom-PbWingetList $ru
    Check 'winget list ru: 4 колонки, «Доступно» четвёртая' ($w2['vivaldi.vivaldi'].Available -eq '7.0.3215' -and $w2['7zip.7zip'].Version -eq '24.08' -and -not $w2['7zip.7zip'].Available) ($w2 | ConvertTo-Json)
    $w3 = ConvertFrom-PbWingetList @('Name  Id       Version Source', '------------------------------', 'Ditto Ditto.Ditto 3.24 winget')
    Check 'winget list: 4 колонки с «Источником» — не обновление' (-not $w3['ditto.ditto'].Available) ($w3 | ConvertTo-Json)
    $entries = @(@{ Name = 'Git version 2.46.0'; Version = '2.46.0' }, @{ Name = 'GitHub CLI'; Version = '2.60' }, @{ Name = 'Npcap 1.80'; Version = '1.80' })
    Check 'реестр: «Git» не путается с «GitHub CLI», Detect для сайта' ((Find-PbUninstallEntry @{ Name = 'Git' } $entries).Version -eq '2.46.0' -and (Find-PbUninstallEntry @{ Name = 'GitHub CLI' } $entries).Version -eq '2.60' -and
        (Find-PbUninstallEntry @{ Name = 'Npcap'; Detect = 'Npcap*' } $entries) -and -not (Find-PbUninstallEntry @{ Name = 'Gi' } $entries))
    $git = @{ Id = 'git'; Name = 'Git'; WingetId = 'Git.Git' }; $vs = @{ Id = 'vscode'; Name = 'VS Code'; WingetId = 'Microsoft.VisualStudioCode' }
    $np = @{ Id = 'npcap'; Name = 'Npcap'; Source = 'web'; Detect = 'Nothing*' }
    $s1 = @((Get-PbAppStatus $git $entries $null).Kind, (Get-PbAppStatus $vs $entries $null).Kind, (Get-PbAppStatus $np $entries $null).Kind) -join ','
    Check 'шаг 1 (реестр): установлено / неизвестно до winget / сайт — не установлено' ($s1 -eq 'installed,unknown,missing') $s1
    $s2 = Get-PbAppStatus $git $entries $w; $s3 = Get-PbAppStatus $vs $entries $w
    Check 'шаг 2 (winget): обновление с версиями, нет в winget и реестре — не установлено' ($s2.Kind -eq 'update' -and $s2.Text -eq 'обновление: 2.46.0 → 2.47.1' -and $s3.Kind -eq 'missing') @($s2, $s3)

    # ---------- план и прогон (установка, твики и вопрос подменены) ----------
    Write-Host 'план и прогон'
    $script:PB.Results.Clear(); $script:PB.Manual.Clear(); $script:PB.Changes.Clear(); $script:PB.DataRoot = Join-Path $tmp 'nodata'
    $tws = @(@{ Id = 'p.a'; Name = 'Твик А'; Phase = 'pre'; Apply = {} }, @{ Id = 'p.irr'; Name = 'Удалить X'; Phase = 'pre'; Irreversible = $true; Apply = {} },
             @{ Id = 'p.post'; Name = 'После'; Phase = 'post'; Apply = {} })
    $aps = @(@{ Id = 'a1'; Name = 'Прог 1'; Source = 'winget'; WingetId = 'A.One' }, @{ Id = 'a2'; Name = 'Прог 2'; Source = 'web'; Interactive = $true },
             @{ Id = 'a3'; Name = 'Прог 3'; Source = 'winget'; WingetId = 'A.Three'; Config = @{ File = 'nothing\x.json'; Import = 'Set-NoConfig' } })
    $sel = @{ Apps = @('a1', 'a2', 'a3'); Tweaks = @('p.a', 'p.irr', 'p.post'); Configs = @('a3'); Files = @('f.zip'); FileTitles = @('Файл.zip'); Name = 'PC-02'; Upgrades = @('a1') }
    $stat = @{ Apps = @{ a1 = @{ Kind = 'update'; Text = 'обновление: 1 → 2' }; a3 = @{ Kind = 'installed' } }; Tweaks = @{ 'p.a' = 'applied' } }
    $plan = Get-PbRunPlan $sel $aps $tws $stat
    $ph = ($plan | ForEach-Object { $_.Phase }) -join ''
    Check 'план: фазы по порядку' ($ph -eq '1223334567') $ph
    $pn = @($plan | ForEach-Object { $_.PhaseName } | Select-Object -Unique) -join '|'
    Check 'план: названия фаз совпадают с номерами' ($pn -eq 'Точка восстановления|Настройки Windows|Программы|Настройки программ|Файлы|Среда|Имя компьютера') $pn
    $notes = @{}; foreach ($x in $plan) { $notes[$x.Key] = $x.Note }
    Check 'план: пометки — обновление, уже установлено, сайт и мастер, нет настроек, необратимо, уже применено' ($notes['app:a1'] -eq 'обновление: 1 → 2' -and $notes['app:a3'] -match 'уже установлено' -and
        $notes['app:a2'] -match 'сайта' -and $notes['app:a2'] -match 'мастер' -and $notes['config:a3'] -match 'нет' -and $notes['tweak:p.irr'] -match 'необратимо' -and $notes['tweak:p.a'] -match 'уже применено') ($notes | ConvertTo-Json)
    Check 'план: пусто — пустой план' ((Get-PbRunPlan @{ Apps = @(); Tweaks = @(); Configs = @(); Files = @() } $aps $tws $null).Count -eq 0)

    function Invoke-Tweak ($T) { Add-Result $T.Name 'применено' }
    function Install-App ($A) { if ($A.Id -eq 'a2') { Add-Result $A.Name 'ОШИБКА' 'подпись не прошла' } else { Add-Result $A.Name 'установлено' } }
    function Initialize-Winget { $true }
    function Invoke-PbWingetTimed { @{ Code = 0 } }
    function Set-NoConfig { Add-Result 'Прог 3: мои настройки' 'пропущено' 'нет файла' }
    function Save-PbFiles ($Names) { Add-Result 'Файл' 'загружено' }
    function Rename-Computer { param($NewName, [switch]$Force) }
    function Request-PbAnswer ($Text, $Items) { $script:Asked = @($Items); $false }   # «не выполнять необратимое»
    # отчёт — во временную папку, не в «Документы» этого компьютера
    $script:PB.LogDir = Join-Path $tmp 'logs1'
    function Get-PbReportDir { Join-Path $tmp 'reports' }
    $sync = [hashtable]::Synchronized(@{})
    Invoke-PbRun $plan $sel $aps $tws $sync 6>$null | Out-Null
    $states = ($plan | ForEach-Object { "$($_.Key)=$($_.State)" }) -join ' '
    Check 'прогон: без точки восстановления необратимое снято, ошибка и пропуск видны' ($states -eq 'restore=skip tweak:p.a=done tweak:p.irr=skip app:a1=done app:a2=error app:a3=done config:a3=skip files=done tweak:p.post=done rename=done') $states
    Check 'прогон: спросили про необратимое, итог и флаги' (($script:Asked -join ',') -eq 'Удалить X' -and $sync.Done -and $sync.NeedReboot -and ($plan | Where-Object Key -eq 'app:a2').Detail -match 'подпись' -and $script:PB.Upgrades -contains 'a1') $sync
    $rep = [string]$sync.Report
    $html = if ($rep -and (Test-Path $rep)) { Get-Content $rep -Raw -Encoding UTF8 } else { '' }
    Check 'отчёт: в папке отчётов и копия в журналах' ($rep -like (Join-Path (Join-Path $tmp 'reports') 'report_*.html') -and
        (Test-Path (Join-Path $script:PB.LogDir (Split-Path $rep -Leaf)))) $rep
    $failBlock = if ($html -match '(?s)Что не получилось(.*?)</div>') { $Matches[1] } else { '' }
    Check 'отчёт: ошибка в «Что не получилось», шаги по фазам, перезагрузка' ($failBlock -match 'Прог 2' -and $failBlock -match 'подпись не прошла' -and $failBlock -notmatch 'Прог 1' -and
        $html -match 'Нужна перезагрузка' -and $html -match 'Настройки Windows' -and $html -match 'class="st error">ошибка' -and $html -match 'Выполнено: 6') ($html.Length)
    $saveEnv = @{ USERPROFILE = $env:USERPROFILE; USERNAME = $env:USERNAME; APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
    try {
        $prof = 'C:\' + 'Users\' + 'jdoe'
        $env:USERPROFILE = $prof; $env:USERNAME = 'jdoe'; $env:APPDATA = "$prof\AppData\Roaming"; $env:LOCALAPPDATA = "$prof\AppData\Local"
        $p1 = Protect-PbReportText "$prof\AppData\Local\X\a.log; $prof\Desktop; пользователь jdoe; jdoe2"
        Check 'отчёт: пути профиля — переменными, имя пользователя скрыто' ($p1 -eq '%LOCALAPPDATA%\X\a.log; %USERPROFILE%\Desktop; пользователь <пользователь>; jdoe2') $p1
        $st = New-PbStep 3 'app' 'app:x' '<script>alert(1)</script> & Co' 'x'; $st.State = 'error'; $st.Detail = "$prof\a.txt"
        $h2 = New-PbReportHtml @($st) @{ Computer = 'PC-01'; Windows = 'Windows 11'; Started = (Get-Date); Finished = (Get-Date); Engine = 'dev'; Manual = @('Войти <в> почту'); LogDir = 'C:\ProgramData\tabula-rasa\logs' }
        Check 'отчёт: HTML экранирован, личного нет' ($h2 -notmatch '<script>' -and $h2 -match '&lt;script&gt;' -and $h2 -match '&amp; Co' -and $h2 -match 'Войти &lt;в&gt; почту' -and
            $h2 -notmatch 'jdoe' -and $h2 -match '%USERPROFILE%\\a.txt' -and $h2 -match 'PC-01') ($h2.Length)
    } finally { foreach ($k in $saveEnv.Keys) { Set-Item "env:$k" $saveEnv[$k] } }
    $plan2 = Get-PbRunPlan $sel $aps $tws $null
    $sync2 = [hashtable]::Synchronized(@{ StopAfter = $true })
    Invoke-PbRun $plan2 $sel $aps $tws $sync2 6>$null | Out-Null
    Check 'прогон: «остановить» — остальные шаги пропущены' (@($plan2 | Where-Object { $_.State -ne 'skip' }).Count -eq 0 -and ($plan2[1].Detail -eq 'прогон остановлен'))
    foreach ($f in 'Invoke-Tweak', 'Install-App', 'Initialize-Winget', 'Invoke-PbWingetTimed', 'Set-NoConfig', 'Save-PbFiles', 'Rename-Computer', 'Request-PbAnswer') { Remove-Item "function:$f" -ErrorAction SilentlyContinue }
    . (Join-Path (Join-Path $root 'lib') 'common.ps1'); . (Join-Path (Join-Path $root 'lib') 'files.ps1'); . (Join-Path (Join-Path $root 'lib') 'run.ps1')
    $script:PB.Root = $root; $script:PB.LogDir = Join-Path $tmp 'logs2'; $script:PB.DataRoot = Join-Path $tmp 'nodata'
    New-Item -ItemType Directory $script:PB.LogDir -Force | Out-Null
    '[{"Kind":"Reg"},{"Kind":"Reg"}]' | Set-Content (Join-Path $script:PB.LogDir 'changes_2026-10-01_101500.json')
    '[{"Kind":"Reg"}]' | Set-Content (Join-Path $script:PB.LogDir 'changes_2026-10-30_090000.json')
    $logs = @(Get-PbChangeLogs)
    Check 'журналы для отката: новые первыми, дата из имени, число записей' ($logs.Count -eq 2 -and $logs[0].Count -eq 1 -and $logs[1].Date -eq [datetime]'2026-10-01 10:15:00' -and $logs[1].Count -eq 2) ($logs | ConvertTo-Json)

    # ---------- заставка ----------
    Write-Host 'заставка'
    . (Join-Path (Join-Path $root 'lib') 'splash.ps1')
    $sx = Get-PbSplashXaml
    $okXml = $true; try { [void][xml]$sx } catch { $okXml = $false }
    Check 'заставка: разметка — корректный XML, все цвета подставлены' ($okXml -and $sx -notmatch '"@\w+"' -and $sx -match 'x:Name="Step"' -and $sx -match 'PART_Indicator') $sx.Length
    Set-PbSplash 'шаг' 0.5 6>$null
    Close-PbSplash
    Check 'заставка: без запуска — вызовы ничего не делают' ($null -eq $script:PbSplash)

    # ---------- имена ассетов ----------
    Write-Host 'имена ассетов'
    Check 'транслит' ((ConvertTo-PbAssetName 'Отчёт 2024 (итог).pdf') -eq 'Otchet_2024_itog.pdf')
    Check 'заглавные слова' ((ConvertTo-PbAssetName 'ЩУКА.exe') -eq 'SHCHUKA.exe')
    Check 'пустое имя' ((ConvertTo-PbAssetName '日本語.txt') -eq 'file.txt')
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Fails) { Write-Host "Ошибок: $($script:Fails) из $($script:Count)" -ForegroundColor Red; exit 1 }
Write-Host "Все проверки пройдены: $($script:Count)" -ForegroundColor Green
