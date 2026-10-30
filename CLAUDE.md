# pc-base — инструкции для Claude Code (движок)

Публичный движок развёртывания и обслуживания Windows-ПК: одно окно с каталогом программ, настроек Windows и файлов.
Общаемся по-русски, на «ты», без канцелярита.

**Это публичная репа — ничего личного.** Личное (журнал, планы, issues, аудиты, свои настройки программ, наборы)
живёт в приватной репе владельца и на ПК лежит в `C:\pc-base-private` (`$script:PB.DataRoot`). Здесь — только код,
каталог, встроенные настройки по умолчанию, README.

## Жёсткие ограничения
- **Windows PowerShell 5.1 + .NET Framework 4.8** — на чистой Windows больше ничего нет. Никакого PS7-синтаксиса
  (`??`, `?.`, тернарник, `ForEach-Object -Parallel`), никаких внешних модулей и DLL. GUI — WPF из коробки;
  `Add-Type` для своего `lib/ui/model.cs` (C# 5) — можно.
- **Кодировка:** `.ps1` / `.psd1` / `.xaml` / `.cs` — UTF-8 с BOM, иначе 5.1 ломает кириллицу. `bootstrap.ps1` — только ASCII
  (идёт через `irm | iex`). JSON — UTF-8 без BOM.
- **Реестр, службы, задачи** — только через `Set-Reg` / `Set-SvcStart` / `Disable-Task` из `lib/common.ps1`,
  иначе изменение не попадёт в журнал и `undo.ps1` его не откатит.
- **Каталог** (`catalog/apps.psd1`) — только бесплатное навсегда и без условий. Исключения: Npcap, Docker Desktop.
- **Секреты и личное не коммитить**: пароли, ключи, токены, конфиги VPN, учётки, имена ПК и людей, работодатели.
  Свои настройки программ — в своих данных, не в `configs/` движка (`.gitignore` это страхует).
- **Режим «План» по умолчанию**: окно стартует в нём, боевой прогон — только после явного подтверждения. Не ломать.
- Всё, что читает свои настройки, ищет их через `Find-PbConfig` (сначала `DataRoot\configs`, потом `Root\configs`);
  нет нигде — вариант «с моими настройками» недоступен, прогон не падает.

## Проверки перед коммитом
```powershell
# синтаксис всех скриптов
Get-ChildItem -Recurse -Include *.ps1,*.psd1 | ForEach-Object {
  $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null
  if ($e) { "$($_.Name): $($e[0].Message) @ $($e[0].Extent.StartLineNumber)" } }
# каталог грузится, id уникальны
$a = (Import-PowerShellDataFile ./catalog/apps.psd1).Apps; . ./catalog/tweaks.ps1
@($a.Id) + @($Tweaks.Id) | Group-Object | Where-Object Count -gt 1   # должно быть пусто
```
```bash
# BOM: должно быть ef bb bf у всего, кроме bootstrap.ps1
for f in $(git ls-files '*.ps1' '*.psd1' '*.xaml' '*.cs'); do printf '%s ' "$f"; head -c3 "$f" | od -An -tx1; done
# bootstrap.ps1 — только ASCII: должно быть пусто
LC_ALL=C grep -nP '[^\x00-\x7F]' bootstrap.ps1
# личное: должно быть пусто
grep -rniE 'IHEEAE|ilyai|ЛАНИТ|LANIT|ВИСМО|VISMO|Хваев|Khvaev|gmail|isidor|C:\\Users\\[a-z]' . --exclude-dir=.git
```
Имя владельца `iheeae` в URL репы и Pages — допустимо. В примерах — `PC-01`, `user`, `Мой набор`.
Окно на Linux не открывается: если живой Windows нет — так и пиши в PR и давай чек-лист ручной проверки.

## Карта
```
bootstrap.ps1        загрузчик: winget, git, клон в C:\pc-base (старую копию отодвигает), setup.ps1
setup.ps1            точка входа: права, git pull движка и своих данных, окно, прогон, итог
undo.ps1             откат по журналу изменений
lib/common.ps1       $script:PB (Root, DataRoot…), Find-PbConfig, реестр/службы/задачи с журналом, winget, установка с сайта, Диск
lib/gui.ps1          окно выбора (Show-SelectionDialog), окошко файлов (Show-FilePicker), значок, тема
lib/ui/              main/files/dialog.xaml, theme.xaml (стили), model.cs (модель для привязок)
lib/configs.ps1      перенос настроек программ (функции из поля ConfigFn)
catalog/apps.psd1    программы       catalog/tweaks.ps1  настройки Windows
configs/             встроенное по умолчанию (pwsh_profile.ps1) и README с форматом своих данных
tools/               снятие настроек программ с настроенного ПК (пишет в свои данные, не сюда)
.github/workflows/   pages.yml — bootstrap.ps1 на GitHub Pages: irm iheeae.github.io/pc-base | iex
```
