# configs — встроенные настройки и формат «Моих данных»

Эта папка содержит только встроенные настройки без личных данных: `pwsh_profile.ps1` — профиль PowerShell 7 по умолчанию.

Пользовательские настройки программ хранятся в «Моих данных» — приватном репозитории `<логин>/tabula-rasa-private`,
который окно Tabula Rasa подключает и клонирует в `C:\tabula-rasa-private` (другое расположение задаётся
параметром `setup.ps1 -DataRoot <папка>`). Структура:

```
C:\tabula-rasa-private\
  tabula-rasa.json          версия разметки (создаёт Tabula Rasa)
  README.md, .gitignore     создаются в новом репозитории; в существующем — только если их нет
  saves\*.json              сохранения (Version, Name, Created, Machine, Apps, Tweaks, Configs, Files)
  catalog\apps.psd1         собственный каталог программ (только winget и поля описания)
  configs\
    pwsh_profile.ps1        профиль PowerShell 7, заменяет встроенный
    vivaldi\prefs.json      Vivaldi: поддерево vivaldi из Preferences
    wt\settings.json        Windows Terminal
    vscode\                 settings.json, keybindings.json, extensions.txt
    npp\                    Notepad++: config.xml без истории и сеансов, shortcuts.xml, stylers.xml, contextMenu.xml
    flow\Settings.json      Flow Launcher
    everything\Everything.ini
    powertoys\              settings.json общий и модулей
    git\gitconfig           .gitconfig без [credential] и http.extraheader
    wireshark\              preferences, фильтры, макросы, profiles\ (без recent и recent_common)
    winscp\configuration.json   реестр WinSCP 2\Configuration (без Sessions и History)
    nanazip\, winmerge\, ditto\   registry.json — реестр программы без истории и недавних файлов
    systeminformer\settings.xml, drawio\config.json, sumatra\SumatraPDF-settings.txt, keepassxc\keepassxc.ini,
    sharex\ApplicationConfig.json и HotkeysConfig.json
```

Пути профиля пользователя в снятых файлах записаны переменными `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`
и раскрываются при применении. Формат `registry.json`: `{ "Values": { "<имя>": { "Kind": "DWord", "Data": 1 } },
"Keys": { "<подраздел>": { … } } }`; применяется через `Set-Reg`, поэтому отменяется `undo.ps1`.

Файлы раздела «Файлы» хранятся не в папках репозитория, а ассетами его релиза `files` (`tools/upload-files.ps1`);
в сохранении поле `Files` содержит имена ассетов.

Tabula Rasa ищет каждый файл настроек сначала в «Моих данных», затем здесь. Если файла нет ни там, ни там, вариант
«с моими настройками» в окне недоступен (с пояснением), а выполнение продолжается.

## Снятие настроек
Режим окна «Снятие настроек» на настроенном компьютере: выбрать программы, проверить изменения, подтвердить.
Строки и ключи, похожие на пароли, токены, cookies и сеансы, а также длинные base64-значения вырезаются до записи.
Для Vivaldi есть и консольный вариант: `powershell -ExecutionPolicy Bypass -File C:\tabula-rasa\tools\export-vivaldi.ps1`
(файл записывается в «Мои данные», коммит выполняется вручную).

## Добавление программы с переносом настроек
Поле `Config` в `catalog/apps.psd1` (`File`, `From`, `Export`, `Import`, `Desc`, `Skip`) и две функции в `lib/configs.ps1`:
`Export-<Программа>Config <папка configs>` возвращает `@{ Files; Removed }`, `Set-<Программа>Config` применяет сохранённое.
Общие помощники: `Export-PbConfigFile` (файл с фильтром секретов), `Get-PbSavedConfig`, `Copy-PbConfigIn` (с копией `.bak`),
`Stop-PbApp`. Секреты (пароли, токены, ключи, учётные данные) в снимок попадать не должны; проверка — `tests\run.ps1`.
