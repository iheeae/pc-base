# Tabula Rasa: удаление с этого компьютера — «поставил нужное и ушёл». Остаётся только то, что сделала программа
# (установленные программы, настройки Windows); самой программы, её данных и следов входа в GitHub не остаётся.
#
# Программа не может удалить себя, пока работает: окно пишет скрипт очистки во временную папку и запускает его скрытым
# процессом (Start-PbSelfRemove), затем закрывается. Скрипт ждёт завершения процесса, удаляет выбранное, показывает
# итог системным сообщением и удаляет сам себя. Удаляются только папки, в имени которых есть tabula-rasa / Tabula Rasa /
# pc-base (Test-PbSafeRemovePath); «Мои данные» — только если это клон своего репозитория tabula-rasa-private.

# части удаления: engine — всегда; остальное — по выбору (в окне все отмечены)
function Get-PbSelfRemoveParts {
    $desk = [Environment]::GetFolderPath('Desktop'); $docs = [Environment]::GetFolderPath('MyDocuments')
    $j = { param($Base, $Leaf) if ($Base) { Join-Path $Base $Leaf } }   # нет папки (не Windows, нет профиля) — нет пути
    $engine = @($script:PB.Root, (& $j $env:LOCALAPPDATA 'tabula-rasa'), (& $j $env:TEMP 'tabula-rasa'),
        $script:PbLegacy.Root, $script:PbLegacy.Local) | Where-Object { $_ }
    $logs = @((& $j $env:ProgramData 'tabula-rasa'), $script:PbLegacy.Program, (& $j $docs 'Tabula Rasa')) | Where-Object { $_ }
    $dataDirs = @(@($script:PB.DataRoot, $script:PbLegacy.DataRoot) | Where-Object { $_ -and (Test-PbOwnDataRoot $_) })
    return @(
        @{ Key = 'engine'; Name = 'Программа Tabula Rasa'; Fixed = $true; Paths = @($engine)
           Desc = 'Папка программы, кэш, настройки окна, профили на этом компьютере, временные файлы установщиков.' }
        @{ Key = 'data'; Name = 'Мои данные и вход в GitHub'; Paths = $dataDirs
           Desc = 'Локальная копия «Моих данных», выход из GitHub CLI, сохранённый токен git для github.com. Данные на GitHub не удаляются.' }
        @{ Key = 'logs'; Name = 'Журналы и отчёты'; Paths = @($logs)
           Desc = 'Журналы выполнения и изменений, отчёты. После удаления журналов откат через Tabula Rasa станет невозможен, останется точка восстановления Windows.' }
        @{ Key = 'git'; Name = 'Git и GitHub CLI'; Paths = @()
           Desc = 'Удаляются через winget вместе с настройками git, которые добавила Tabula Rasa. Снимите отметку, если Git нужен на этом компьютере.' }
        @{ Key = 'files'; Name = 'Загруженные файлы'; Paths = @(@(& $j $desk 'tabula-rasa-files') | Where-Object { $_ })
           Desc = 'Папка «Рабочий стол\tabula-rasa-files» с файлами из раздела «Файлы».' }
    )
}

# удалять можно только свою папку: полный путь, не корень диска, имя — tabula-rasa / Tabula Rasa / pc-base
function Test-PbSafeRemovePath ([string]$Path) {
    if (-not $Path -or -not [IO.Path]::IsPathRooted($Path)) { return $false }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ($full.Length -le 3) { return $false }
    $leaf = Split-Path $full -Leaf
    return ($leaf -match '^(tabula-rasa|Tabula Rasa|pc-base)(-private|-files)?$')
}

# «Мои данные» — клон своего репозитория (origin …/tabula-rasa-private или старый pc-base-private), а не любая папка из -DataRoot
function Test-PbOwnDataRoot ([string]$Dir) {
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return $false }
    if (-not (Test-PbSafeRemovePath $Dir)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return $true }   # папка без git — локальная, по имени
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $true }
    $o = & git -C $Dir remote get-url origin 2>$null
    return (-not $o) -or ($o -match '/(tabula-rasa|pc-base)-private(\.git)?/?$')
}

function ConvertTo-PbPsLiteral ([string]$S) { "'" + ($S -replace "'", "''") + "'" }

# скрипт очистки для выбранных частей ($Keys) — текст; ждёт процесс $WaitPid
function New-PbSelfRemoveScript ([string[]]$Keys, [int]$WaitPid) {
    $parts = @(Get-PbSelfRemoveParts | Where-Object { $_.Fixed -or $Keys -contains $_.Key })
    $dirs = @($parts | ForEach-Object { $_.Paths } | Where-Object { $_ -and (Test-PbSafeRemovePath $_) } | Select-Object -Unique)
    $lit = { param($a) '@(' + (@($a | ForEach-Object { ConvertTo-PbPsLiteral $_ }) -join ', ') + ')' }
    $doData = [bool]($Keys -contains 'data'); $doGit = [bool]($Keys -contains 'git')
    return @"
# Tabula Rasa: удаление с этого компьютера. Скрипт создан программой и удалит сам себя.
`$ErrorActionPreference = 'SilentlyContinue'
`$fail = New-Object System.Collections.ArrayList
`$p = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
if (`$p) { [void]`$p.WaitForExit(120000) }
Start-Sleep -Seconds 1
`$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
foreach (`$d in "`$env:ProgramFiles\Git\cmd", "`$env:ProgramFiles\GitHub CLI") { if (Test-Path `$d) { `$env:Path += ";`$d" } }
if (`$$doData) {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        `$users = @(& gh auth status --hostname github.com 2>&1 | ForEach-Object { "`$_" } | ForEach-Object { if (`$_ -match 'account (\S+)') { `$Matches[1] } })
        foreach (`$u in `$users) { & gh auth logout --hostname github.com --user `$u *> `$null }
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        foreach (`$h in 'github.com', 'gist.github.com') { & git config --global --unset-all "credential.https://`$h.helper" 2>`$null }
        "protocol=https``nhost=github.com``n``n" | & git credential reject 2>`$null
    }
    & cmdkey.exe /delete:git:https://github.com *> `$null
}
if (Get-Command git -ErrorAction SilentlyContinue) {
    # записи git, которые добавила Tabula Rasa (загрузчик): safe.directory для её папок
    foreach (`$v in @(& git config --global --get-all safe.directory 2>`$null)) {
        if (`$v -match '(tabula-rasa|pc-base)') { & git config --global --unset safe.directory ('^' + [regex]::Escape(`$v) + '$') 2>`$null }
    }
    if (`$$doGit) { & git config --global --unset core.quotepath 2>`$null }
}
if (`$$doGit -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    foreach (`$id in 'GitHub.cli', 'Git.Git') {
        & winget uninstall --id `$id -e --silent --disable-interactivity --accept-source-agreements *> `$null
        if (`$LASTEXITCODE -ne 0 -and `$LASTEXITCODE -ne -1978335212) { [void]`$fail.Add("`${id}: winget вернул `$LASTEXITCODE") }
    }
}
foreach (`$dir in $(& $lit $dirs)) {
    if (-not (Test-Path -LiteralPath `$dir)) { continue }
    for (`$i = 0; `$i -lt 10 -and (Test-Path -LiteralPath `$dir); `$i++) {
        Get-ChildItem -LiteralPath `$dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { `$_.Attributes = 'Normal' } catch { } }
        Remove-Item -LiteralPath `$dir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath `$dir) { Start-Sleep -Seconds 1 }
    }
    if (Test-Path -LiteralPath `$dir) { [void]`$fail.Add("папка `$dir используется и не удалена") }
}
Add-Type -AssemblyName PresentationFramework
`$text = if (`$fail.Count) { "Tabula Rasa удалена с этого компьютера, кроме:``n``n" + (`$fail -join "``n") + "``n``nЭти папки можно удалить вручную." } else { 'Tabula Rasa удалена с этого компьютера. Установленные программы и применённые настройки Windows сохранены.' }
[void][Windows.MessageBox]::Show(`$text, 'Tabula Rasa', 'OK', `$(if (`$fail.Count) { 'Warning' } else { 'Information' }))
Remove-Item -LiteralPath `$PSCommandPath -Force -ErrorAction SilentlyContinue
"@
}

# записать скрипт во временную папку и запустить скрытым процессом; окно после этого закрывается
function Start-PbSelfRemove ([string[]]$Keys) {
    $file = Join-Path ([IO.Path]::GetTempPath()) ("tabula-rasa-remove-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    [IO.File]::WriteAllText($file, (New-PbSelfRemoveScript $Keys $PID), (New-Object Text.UTF8Encoding $true))
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $ps -WindowStyle Hidden -WorkingDirectory ([IO.Path]::GetTempPath()) `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$file`"") -ErrorAction Stop | Out-Null
    return $file
}
