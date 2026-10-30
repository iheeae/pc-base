# Tabula Rasa: проверки без окна и без сети — разбор вывода winget (русский и английский), свой каталог, фильтр секретов,
# снятие настроек, разметка репозитория данных, имена ассетов. Запуск из корня репозитория:
#   powershell -ExecutionPolicy Bypass -File tests\run.ps1        (или pwsh -File tests/run.ps1)
# Нужен git. Всё пишется во временную папку; сеть, gh и «Мои данные» на этом компьютере не затрагиваются.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($f in 'common', 'data', 'files', 'catalog', 'configs') { . (Join-Path (Join-Path $root 'lib') "$f.ps1") }
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
            Check 'вкладка: 9 программ, на «компьютере» есть Git и Vivaldi' ($cap.Count -eq 9 -and (($cap | Where-Object Installed | ForEach-Object { $_.App.Id }) -join ',') -eq 'git,vivaldi') ($cap | ForEach-Object { "$($_.App.Id)=$($_.Installed)" })
            $res = @(Invoke-PbCapture @($catalog | Where-Object { $_.Id -eq 'vivaldi' }) $stage)
            $v = Get-Content (Join-Path $stage $res[0].Files[0]) -Raw | ConvertFrom-Json
            Check 'vivaldi: тема и вкладки есть, sync и mail вырезаны, profile не взят' ($v.vivaldi.theme.current -eq 'dark' -and $v.vivaldi.tabs.stack -and -not $v.vivaldi.sync -and -not $v.vivaldi.mail -and -not $v.profile -and $res[0].Removed.Count -eq 2) @($v, $res[0].Removed)
        } finally { $env:LOCALAPPDATA = $oldLa }
        Check '{MyDocuments} раскрывается' ((Expand-PbPath '{MyDocuments}\x') -eq ([Environment]::GetFolderPath('MyDocuments') + '\x'))
        # применение Git сохраняет вход в GitHub на целевом компьютере
        $script:PB.DataRoot = $target | Split-Path; Rename-Item $target 'configs'
        Write-PbText (Join-Path $home2 '.gitconfig') @('[credential "https://github.com"]', '    helper = target-helper')
        Set-GitConfig
        $after = @(Get-Content (Join-Path $home2 '.gitconfig') -Encoding UTF8)
        Check 'git: применение сохраняет credential компьютера' (($after -contains '    helper = target-helper') -and ($after -contains '    st = status') -and -not ($after -match 'gh auth')) $after
    } finally { $env:USERPROFILE = $oldProfile }

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
