# pc-base: перенос настроек программ (галочка «с моими настройками» под программой в окне).
# Каждая функция здесь указывается в каталоге полем ConfigFn, файл данных — полем ConfigFile.
# Данные лежат в configs\<программа>\ своих данных (DataRoot) или движка (Root), ищет их Find-PbConfig.
# Снимаются они инструментами из tools\ на уже настроенном ПК.

function Merge-JsonObject ($Dst, $Src) {
    foreach ($p in $Src.PSObject.Properties) {
        $d = $Dst.PSObject.Properties[$p.Name]
        if ($d -and $d.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) { Merge-JsonObject $d.Value $p.Value }
        else { $Dst | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
}

# Vivaldi: вливает сохранённое поддерево "vivaldi" (интерфейс, панели, вкладки, поведение) в Preferences профиля.
# Расширения, пароли, почта, аккаунты и синхронизация не переносятся — их нет в prefs.json (см. tools\export-vivaldi.ps1).
function Set-VivaldiConfig {
    $what = 'Vivaldi: мои настройки'
    $src = Find-PbConfig 'vivaldi\prefs.json'
    if (-not $src) {
        Write-Warn2 "нет configs\vivaldi\prefs.json ни в $($script:PB.DataRoot), ни в движке — Vivaldi остаётся чистым"
        Add-Result $what 'пропущено' 'нет configs\vivaldi\prefs.json'
        Add-Manual 'Vivaldi: снять свои настройки через tools\export-vivaldi.ps1 на настроенном ПК и положить в свои данные'
        return
    }
    if (Get-Process vivaldi -ErrorAction SilentlyContinue) {
        Write-Warn2 'Vivaldi запущен — закрываю, иначе он перезапишет настройки при выходе'
        Get-Process vivaldi -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    $dir = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data\Default'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir 'Preferences'
    $saved = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json
    if (Test-Path $file) {
        Copy-Item $file "$file.pc-base_$($script:PB.Stamp).bak" -Force
        $cur = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    } else { $cur = [pscustomobject]@{} }
    Merge-JsonObject $cur $saved
    [IO.File]::WriteAllText($file, ($cur | ConvertTo-Json -Depth 100 -Compress), (New-Object Text.UTF8Encoding $false))
    Write-Ok "Vivaldi: настройки влиты в $file"
    Add-Result $what 'применено'
    Add-Manual 'Vivaldi: при первом запуске проверить, что интерфейс подхватился; для закладок и паролей войти в Vivaldi Sync'
}
