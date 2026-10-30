# Tabula Rasa — инструкции для Claude Code (движок)

Публичный движок развёртывания и обслуживания компьютеров с Windows: одно окно с каталогом программ, настроек
Windows и файлов. Название в интерфейсе и текстах — «Tabula Rasa», технически (репозитории, URL, папки, id) — `tabula-rasa`.
С владельцем общаемся по-русски, на «ты», без канцелярита; правило ниже про тон касается только самой программы.

**Это публичный репозиторий — ничего личного.** Личное (журнал, планы, issues, аудиты, свои настройки программ,
сохранения) живёт в приватном репозитории владельца и на компьютере лежит в `C:\tabula-rasa-private`
(`$script:PB.DataRoot`). Здесь — только код, каталог, встроенные настройки по умолчанию, README.

## Жёсткие ограничения
- **Windows PowerShell 5.1 + .NET Framework 4.8** — на чистой Windows больше ничего нет. Никакого PS7-синтаксиса
  (`??`, `?.`, тернарник, `ForEach-Object -Parallel`), никаких внешних модулей и DLL. GUI — WPF из коробки;
  `Add-Type` для своего `lib/ui/model.cs` (C# 5) — можно.
- **Кодировка:** `.ps1` / `.psd1` / `.xaml` / `.cs` — UTF-8 с BOM, иначе 5.1 ломает кириллицу. `bootstrap.ps1` — только ASCII
  (идёт через `irm | iex`). JSON — UTF-8 без BOM.
- **Реестр, службы, задачи** — только через `Set-Reg` / `Set-SvcStart` / `Disable-Task` из `lib/common.ps1`,
  иначе изменение не попадёт в журнал и `undo.ps1` его не откатит.
- **Каталог** (`catalog/apps.psd1`) — только бесплатное навсегда и без условий. Исключения: Npcap, Docker Desktop.
  Бесплатность в описаниях не пишется; открытый код — полем `OpenSource = $true` (проверять по факту, лицензия OSI),
  условия и закрытый код — полем `License`.
- **Секреты и личное не коммитить**: пароли, ключи, токены, конфиги VPN, учётки, имена компьютеров и людей, работодатели.
  Свои настройки программ — в «Моих данных», не в `configs/` движка (`.gitignore` это страхует).
- **Режим «План» по умолчанию**: окно стартует в нём, применение — только после явного подтверждения. Не ломать.
- Всё, что читает свои настройки, ищет их через `Find-PbConfig` (сначала `DataRoot\configs`, потом `Root\configs`);
  нет нигде — вариант «с моими настройками» недоступен, прогон не падает.
- **Мои данные**: git в `DataRoot` — только через `lib/data.ps1`; сеть (push, вход) — только в фоне, окно не ждёт.
  «Отключить и удалить» не трогать без нужды и не тестировать на живом входе — в тестах глушить `gh`, `cmdkey`, глобальный git.
- **Старые места** (`C:\pc-base`, `C:\pc-base-private`, `%LOCALAPPDATA%\pc-base`, `%ProgramData%\pc-base`) — в `$script:PbLegacy`.
  Переезд — `Move-PbLegacyDir` / `Update-PbOrigin` в `setup.ps1` и свой в `bootstrap.ps1`; ничего не удалять.

## Тексты программы
Всё, что видит пользователь (окна, диалоги, уведомления, подсказки, вывод `setup.ps1` / `undo.ps1` / `bootstrap.ps1`,
`Desc` / `Manual` / `Note` / `ConfigDesc` / `License` в каталоге и твиках, README) — профессиональным тоном, как в Windows:
- безлично или нейтрально; если без обращения нельзя — «вы» со строчной. Никаких «ты», «твой», «тебе»;
- без разговорных конструкций и тире вместо сказуемого, полными предложениями, одна мысль — одно предложение;
- термины: «компьютер» (в чипах и коротких подписях можно «ПК»), «репозиторий», «удалить», «установить».

## Проверки перед коммитом
```powershell
# синтаксис всех скриптов
Get-ChildItem -Recurse -Include *.ps1,*.psd1 | ForEach-Object {
  $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
  if ($e) { "$($_.Name): $($e[0].Message) @ $($e[0].Extent.StartLineNumber)" } }
# каталог грузится, id уникальны
$a = (Import-PowerShellDataFile ./catalog/apps.psd1).Apps; . ./catalog/tweaks.ps1
@($a.Id) + @($Tweaks.Id) | Group-Object | Where-Object Count -gt 1   # должно быть пусто
# тон: должно быть пусто (границы слов — юникодные, grep -w для кириллицы не работает)
$bad = '(?<!\p{L})(ты|твой|твоя|твоё|твои|твоих|твоим|твоей|тебе|тебя|снести|снесёт|сносит|снос|репа|репы|репу|репе|бесплатно)(?!\p{L})'
Get-ChildItem -Recurse -Include *.ps1,*.psd1,*.xaml,*.cs | Select-String -Pattern $bad |
  Where-Object { $_.Line -notmatch 'бесплатн\w* (навсегда|до|для|без)' } | ForEach-Object { "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" }
```
```bash
# BOM: должно быть ef bb bf у всего, кроме bootstrap.ps1
for f in $(git ls-files '*.ps1' '*.psd1' '*.xaml' '*.cs'); do printf '%s ' "$f"; head -c3 "$f" | od -An -tx1; done
# bootstrap.ps1 — только ASCII: должно быть пусто
LC_ALL=C grep -nP '[^\x00-\x7F]' bootstrap.ps1
# личное: должно быть пусто (кроме iheeae в URL)
grep -rniE 'IHEEAE|ilyai|ЛАНИТ|LANIT|ВИСМО|VISMO|Хваев|Khvaev|gmail|isidor|C:\\Users\\[a-z]' . --exclude-dir=.git
```
Имя владельца `iheeae` в URL репозитория и Pages — допустимо. В примерах — `PC-01`, `user`, `Мой набор`.
Окно на Linux не открывается: если живой Windows нет — так и пиши в PR и давай чек-лист ручной проверки.

## Карта
```
bootstrap.ps1        загрузчик: winget, git, переезд C:\pc-base, клон в C:\tabula-rasa (постороннюю копию отодвигает), setup.ps1
setup.ps1            точка входа: права, переезд старых папок, git pull, синхронизация «Моих данных», окно, прогон, итог
undo.ps1             откат по журналу изменений (ищет и в старой папке логов)
lib/common.ps1       $script:PB (Root, DataRoot…), $script:PbLegacy, Find-PbConfig, реестр/службы/задачи с журналом, winget, установка с сайта, Диск
lib/data.ps1         сохранения (Read-/Write-SaveFile, Save-/Rename-/Remove-PbSave), Мои данные (Connect-/Disconnect-PbData, Push-PbData)
lib/gui.ps1          окно выбора (Show-SelectionDialog), окно файлов (Show-FilePicker), значок «TR», тема; фоновые задачи — runspace + DispatcherTimer
lib/ui/              main/files/dialog.xaml, theme.xaml (стили), model.cs (модель для привязок)
lib/configs.ps1      перенос настроек программ (функции из поля ConfigFn)
catalog/apps.psd1    программы       catalog/tweaks.ps1  настройки Windows
configs/             встроенное по умолчанию (pwsh_profile.ps1) и README с форматом «Моих данных»
tools/               снятие настроек программ с настроенного компьютера (пишет в «Мои данные», не сюда)
.github/workflows/   pages.yml — bootstrap.ps1 на GitHub Pages: irm iheeae.github.io/tabula-rasa | iex
```
