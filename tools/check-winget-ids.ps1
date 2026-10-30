# Tabula Rasa: все ли WingetId каталога существуют в источнике winget (репозиторий microsoft/winget-pkgs).
# Ловит переименованные и удалённые пакеты. Запускается в CI раз в неделю (.github/workflows/ci.yml), можно и вручную:
#   powershell -ExecutionPolicy Bypass -File tools\check-winget-ids.ps1
# Пакет Publisher.Name лежит в manifests/<первая буква>/Publisher/Name. Токен GitHub (GITHUB_TOKEN или GH_TOKEN) —
# необязательно, без него действует лимит 60 запросов в час. Код выхода 1, если хотя бы одного пакета нет.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot
$apps = @((Import-PowerShellDataFile (Join-Path $root 'catalog\apps.psd1')).Apps | Where-Object { $_.WingetId })
$h = @{ 'User-Agent' = 'tabula-rasa-ci'; Accept = 'application/vnd.github+json' }
$token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }
if ($token) { $h.Authorization = "Bearer $token" }

$missing = @(); $errors = @()
foreach ($a in $apps) {
    $id = [string]$a.WingetId
    $path = 'manifests/' + $id.Substring(0, 1).ToLower() + '/' + (($id -split '\.') -join '/')
    $url = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$([uri]::EscapeUriString($path))"
    try {
        [void](Invoke-RestMethod -Uri $url -Headers $h -UseBasicParsing)
        Write-Host "ok   $id"
    } catch {
        $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -eq 404) { $missing += "$($a.Name): $id"; Write-Host "НЕТ  $id" -ForegroundColor Red }
        else { $errors += "$($a.Name): $id — $($_.Exception.Message)"; Write-Host "?    $id — $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
Write-Host ''
if ($errors.Count) { Write-Host "Не удалось проверить: $($errors.Count)" -ForegroundColor Yellow }
if ($missing.Count) { Write-Host "Нет в источнике winget ($($missing.Count)):" -ForegroundColor Red; $missing | ForEach-Object { Write-Host "  $_" }; exit 1 }
if ($errors.Count) { exit 1 }
Write-Host "Все пакеты найдены: $($apps.Count)" -ForegroundColor Green
