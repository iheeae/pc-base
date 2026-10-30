# Снимает настройки Vivaldi с этого ПК для pc-base: только поддерево "vivaldi" из Preferences
# (интерфейс, панели, вкладки, поведение). Всё, что похоже на аккаунты, почту, синхронизацию,
# токены и пароли, вырезается. Расширения не трогаются — они вне этого поддерева.
#
#   powershell -ExecutionPolicy Bypass -File export-vivaldi.ps1 [-Out <файл.json>]
# По умолчанию пишет в свои данные: C:\pc-base-private\configs\vivaldi\prefs.json (или -DataRoot), если они есть
# на этом ПК, иначе рядом с собой. В папку движка не пишет никогда: она — клон публичной репы.
param([string]$Out, [string]$DataRoot = 'C:\pc-base-private')

$prefs = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data\Default\Preferences'
if (-not (Test-Path $prefs)) { Write-Host "Нет $prefs — Vivaldi тут не настраивался" -ForegroundColor Red; exit 1 }
if (-not $Out) {
    $base = Join-Path $DataRoot 'configs'
    $Out = if (Test-Path $base) { Join-Path $base 'vivaldi\prefs.json' } else { Join-Path $PSScriptRoot 'vivaldi_prefs.json' }
}

$deny = 'sync|mail|calendar|account|contact|feed|password|passwd|token|secret|auth|login|oauth|email|cookie|session|credential|private|key$'
$removed = New-Object System.Collections.ArrayList
function Remove-Sensitive ($Obj, [string]$Path) {
    if ($Obj -is [pscustomobject]) {
        foreach ($p in @($Obj.PSObject.Properties)) {
            $full = "$Path.$($p.Name)"
            if ($p.Name -match $deny) { [void]$removed.Add($full); $Obj.PSObject.Properties.Remove($p.Name); continue }
            Remove-Sensitive $p.Value $full
        }
    } elseif ($Obj -is [array]) { foreach ($x in $Obj) { Remove-Sensitive $x $Path } }
}

$j = Get-Content $prefs -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $j.vivaldi) { Write-Host 'В Preferences нет раздела vivaldi' -ForegroundColor Red; exit 1 }
$v = $j.vivaldi
Remove-Sensitive $v 'vivaldi'

New-Item -ItemType Directory -Path (Split-Path $Out) -Force | Out-Null
$json = [pscustomobject]@{ vivaldi = $v } | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false))

Write-Host "Готово: $Out ($([math]::Round((Get-Item $Out).Length / 1KB)) КБ)" -ForegroundColor Green
Write-Host "Разделы: $(@($v.PSObject.Properties.Name) -join ', ')" -ForegroundColor Gray
if ($removed.Count) { Write-Host "Вырезано как чувствительное: $($removed.Count) ключ(ей)" -ForegroundColor Yellow; $removed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray } }
