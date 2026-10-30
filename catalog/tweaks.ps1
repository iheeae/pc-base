# pc-base: каталог настроек Windows.
#
# Профилей и обязательных пунктов нет: каждая настройка — галочка в окне, телеметрия тоже.
# Os           — '10', '11' или оба: где твик вообще имеет смысл (на другой версии он не виден).
# Phase        — 'pre' (до установки программ) или 'post' (после: конфиги Terminal, pwsh).
# Irreversible — $true, если undo.ps1 это не вернёт (снос UWP и т.п.); в окне помечается.
# Apply        — сам твик. Реестр, службы и задачи менять только через Set-Reg / Set-SvcStart /
#                Disable-Task, тогда изменения попадут в журнал и откатятся через undo.ps1.
# Manual       — что доделать руками, попадёт в итоговый список.
# Desc         — что именно меняется; видно в окне при наведении.

$Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$Tweaks = @(

    # ============================== Приватность и телеметрия ==============================

    @{ Id = 'priv.telemetry'; Name = 'Телеметрия: минимум, DiagTrack выключен'; Desc = 'Политика телеметрии на минимум, выключены службы DiagTrack и WAP Push, задачи сбора совместимости, CEIP и отзывов.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
           Set-Reg $dc 'AllowTelemetry' 0
           Set-Reg $dc 'DoNotShowFeedbackNotifications' 1
           Set-Reg $dc 'AllowDeviceNameInTelemetry' 0
           Set-Reg $dc 'LimitDiagnosticLogCollection' 1
           Set-Reg $dc 'DisableOneSettingsDownloads' 1
           Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
           Set-SvcStart 'DiagTrack' 'Disabled'
           Set-SvcStart 'dmwappushservice' 'Disabled'
           Disable-Task '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser'
           Disable-Task '\Microsoft\Windows\Application Experience\' 'ProgramDataUpdater'
           Disable-Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'Consolidator'
           Disable-Task '\Microsoft\Windows\Customer Experience Improvement Program\' 'UsbCeip'
           Disable-Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClient'
           Disable-Task '\Microsoft\Windows\Feedback\Siuf\' 'DmClientOnScenarioDownload'
           Disable-Task '\Microsoft\Windows\DiskDiagnostic\' 'Microsoft-Windows-DiskDiagnosticDataCollector'
       } }

    @{ Id = 'priv.ads'; Name = 'Реклама, рекомендации, автоустановка «предложенных» приложений'; Desc = 'Рекламный ID, «персонализированный опыт», советы и предложения в Пуске, тихая установка рекламируемых приложений, экран «давайте завершим настройку».'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
           $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           foreach ($v in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                          'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'OemPreInstalledAppsEnabled',
                          'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                          'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                          'SubscribedContent-353698Enabled') { Set-Reg $cdm $v 0 }
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
           $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
           Set-Reg $cc 'DisableWindowsConsumerFeatures' 1
           Set-Reg $cc 'DisableSoftLanding' 1
           Set-Reg $cc 'DisableCloudOptimizedContent' 1
           Set-Reg $Adv 'Start_IrisRecommendations' 0
           Set-Reg $Adv 'ShowSyncProviderNotifications' 0
       } }

    @{ Id = 'priv.activity'; Name = 'Журнал действий, сбор ввода, онлайн-распознавание речи'; Desc = 'Журнал действий (Timeline), сбор набранного и рукописного текста «для улучшения», онлайн-распознавание речи.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
           Set-Reg $sys 'PublishUserActivities' 0
           Set-Reg $sys 'UploadUserActivities' 0
           Set-Reg $sys 'EnableActivityFeed' 0
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
           Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
           Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
           Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
       } }

    @{ Id = 'priv.search'; Name = 'Поиск без Bing и веба'; Desc = 'Поиск в Пуске ищет только по ПК: без Bing, веб-подсказок и «главного в поиске».'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
       } }

    @{ Id = 'priv.ai'; Name = 'Copilot и Recall выключены политиками'; Desc = 'Политики: Copilot выключен, Recall (снимки экрана для ИИ) запрещён.'; Group = 'Приватность'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
           Set-Reg $Adv 'ShowCopilotButton' 0
       } }

    # ============================== Проводник ==============================

    @{ Id = 'exp.ext'; Name = 'Показывать расширения файлов'; Desc = 'В Проводнике видно .exe, .pdf и т.д. Сложнее подсунуть «фото.jpg.exe».'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'HideFileExt' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'exp.hidden'; Name = 'Показывать скрытые файлы'; Desc = 'Видны скрытые файлы и папки (AppData и т.п.). Защищённые системные остаются скрытыми.'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'Hidden' 1; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'exp.thispc'; Name = 'Проводник открывается на «Этот компьютер»'; Desc = 'Проводник по Win+E открывает «Этот компьютер» с дисками, а не «Главную».'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'LaunchTo' 1 } }

    @{ Id = 'exp.norecent'; Name = 'Без недавних и частых файлов в быстром доступе'; Desc = 'Быстрый доступ не показывает недавние файлы и частые папки, и они больше не копятся.'; Group = 'Проводник'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
           Set-Reg $Adv 'Start_TrackDocs' 0
       } }

    @{ Id = 'exp.classicmenu'; Name = 'Классическое контекстное меню (без «Показать доп. параметры»)'; Desc = 'Правый клик сразу показывает полное меню, как в Win10, без «Показать дополнительные параметры».'; Group = 'Проводник'; Os = @('11'); Phase = 'pre'
       Apply = { Set-RegDefault 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' ''; $script:PB.NeedExplorerRestart = $true } }

    # ============================== Панель задач ==============================

    @{ Id = 'tb.search'; Name = 'Убрать поиск с панели задач (есть Flow Launcher)'; Desc = 'Убирает поле или значок поиска с панели задач. Поиск по клавише Win остаётся.'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'tb.taskview'; Name = 'Убрать кнопку «Представление задач»'; Desc = 'Убирает кнопку виртуальных рабочих столов. Сами столы работают по Win+Tab.'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'ShowTaskViewButton' 0; $script:PB.NeedExplorerRestart = $true } }

    @{ Id = 'tb.widgets'; Irreversible = $true; Name = 'Снести виджеты / «Новости и интересы»'; Desc = 'Win11: сносит пакет «Мини-приложения» (виджеты, в том числе карточки на экране блокировки). Win10: выключает «Новости и интересы».'; Group = 'Панель задач'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           if ($script:PB.Os -eq '11') {
               Remove-Appx @('MicrosoftWindows.Client.WebExperience')
           } else {
               try { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode' 2 } catch { Write-Warn2 'Feeds закрыт ACL, пропускаю' }
               Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
           }
           $script:PB.NeedExplorerRestart = $true
       } }

    @{ Id = 'tb.chat'; Name = 'Убрать значок «Чат» (Teams)'; Desc = 'Убирает с панели значок «Чат» (домашний Teams).'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { try { Set-Reg $Adv 'TaskbarMn' 0 } catch { Write-Warn2 'TaskbarMn закрыт ACL в этой сборке, пропускаю' } } }

    @{ Id = 'tb.win10junk'; Name = 'Win10: убрать с панели Кортану, «Люди» и «Провести собрание»'; Desc = 'Убирает с панели Win10 кнопку Кортаны, «Люди» и «Провести собрание».'; Group = 'Панель задач'; Os = @('10'); Phase = 'pre'
       Apply = {
           Set-Reg $Adv 'ShowCortanaButton' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People' 'PeopleBand' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1
           $script:PB.NeedExplorerRestart = $true
       } }

    @{ Id = 'tb.win10ink'; Name = 'Win10: убрать Windows Ink и сенсорную клавиатуру с панели'; Desc = 'Убирает с панели Win10 кнопки Windows Ink и сенсорной клавиатуры.'; Group = 'Панель задач'; Os = @('10'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace' 'PenWorkspaceButtonDesiredVisibility' 0
           Set-Reg 'HKCU:\Software\Microsoft\TabletTip\1.7' 'TipbandDesiredVisibility' 0
       } }

    @{ Id = 'start.morepins'; Name = 'Win11: в «Пуске» больше закреплённых, меньше рекомендаций'; Desc = 'Раскладка Пуска «Больше закреплённых»: меньше места под рекомендации.'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'Start_Layout' 1 } }

    @{ Id = 'tb.left';Name = 'Кнопка «Пуск» слева'; Desc = 'Пуск и значки панели задач по левому краю, как в Win10.'; Group = 'Панель задач'; Os = @('11'); Phase = 'pre'
       Apply = { Set-Reg $Adv 'TaskbarAl' 0; $script:PB.NeedExplorerRestart = $true } }

    # ============================== Мусор ==============================

    @{ Id = 'bloat.uwp'; Irreversible = $true; Name = 'Снести мусорные UWP (новости, погода, советы, Clipchamp, Solitaire…)'; Desc = 'Удаляет предустановленные приложения: новости, погода, советы, Solitaire, Clipchamp, To Do, Skype, Почта и Календарь, Фильмы и ТВ и т.п. Вернуть — только из Store.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @(
               'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
               'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.People', 'Microsoft.WindowsMaps',
               'Microsoft.WindowsFeedbackHub', 'Microsoft.549981C3F5F10', 'Clipchamp.Clipchamp', 'Microsoft.Todos',
               'Microsoft.PowerAutomateDesktop', 'Microsoft.SkypeApp', 'MicrosoftTeams', 'Microsoft.MixedReality.Portal',
               'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.Wallet',
               'Microsoft.Messaging', 'Microsoft.OneConnect', 'microsoft.windowscommunicationsapps', 'Microsoft.Windows.DevHome',
               'Microsoft.ZuneVideo', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftJournal'
           )
       } }

    @{ Id = 'bloat.copilot'; Irreversible = $true; Name = 'Снести приложение Copilot'; Desc = 'Удаляет приложение Copilot.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Remove-Appx @('Microsoft.Copilot') } }

    @{ Id = 'bloat.phonelink'; Irreversible = $true; Name = 'Снести Связь с телефоном и Cross Device'; Desc = 'Удаляет «Связь с телефоном» и Cross Device, политика запрещает связку ПК с телефоном.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableMmx' 0
       } }

    @{ Id = 'bloat.xbox'; Irreversible = $true; Name = 'Снести Xbox-компоненты'; Desc = 'Удаляет Xbox-приложения и Game Bar, выключает запись игр. Не для игрового ПК с Game Pass.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Remove-Appx @('Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay',
                         'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider')
           Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
       } }

    @{ Id = 'bloat.onedrive'; Irreversible = $true; Name = 'Снести OneDrive'; Desc = 'Удаляет OneDrive и прячет его из Проводника. Пропускается, если Рабочий стол или Документы перенесены в OneDrive.'; Group = 'Мусор'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
           if (@($usf.Desktop, $usf.Personal, $usf.'My Pictures') -match 'OneDrive') {
               throw 'Рабочий стол/Документы/Изображения перенесены в OneDrive — снос пропущен, сначала верни папки'
           }
           Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
           $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
           if ($setup) { Start-Process $setup -ArgumentList '/uninstall' -Wait }
           if (Get-Command winget -ErrorAction SilentlyContinue) { & winget uninstall --id Microsoft.OneDrive -e --silent --disable-interactivity 2>$null | Out-Null }
           Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
           Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
           $script:PB.NeedExplorerRestart = $true
       } }

    # ============================== Система ==============================

    @{ Id = 'sys.wsl'; Name = 'WSL2 + платформа виртуальных машин (для Docker)'; Desc = 'Включает WSL и платформу виртуальных машин, ставит ядро WSL2 (нужно и для Docker). Потребуется перезагрузка.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           foreach ($f in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
               $st = (Get-WindowsOptionalFeature -Online -FeatureName $f).State
               if ($st -ne 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart | Out-Null; $script:PB.NeedReboot = $true }
           }
           & wsl.exe --install --no-distribution 2>$null | Out-Null
           & wsl.exe --set-default-version 2 2>$null | Out-Null
       }
       Manual = 'после перезагрузки: wsl --install -d <дистрибутив>, если нужен' }

    @{ Id = 'sys.stickykeys'; Name = 'Отключить залипание клавиш по 5×Shift'; Desc = 'Пять нажатий Shift больше не вызывают окно залипания клавиш (спасает в играх).'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' -Type String } }

    @{ Id = 'sys.mouseaccel'; Name = 'Отключить ускорение мыши'; Desc = 'Выключает «Повышенную точность указателя»: курсор двигается строго пропорционально мыши.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' -Type String
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' -Type String
           Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' -Type String
       } }

    @{ Id = 'sys.dark'; Name = 'Тёмная тема'; Desc = 'Тёмная тема для системы и приложений.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0
           Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' 0
       } }

    @{ Id = 'sys.highperf'; Name = 'Схема питания «Высокая производительность» (не для ноутбука)'; Desc = 'Схема питания «Высокая производительность». На ноутбуке пропускается.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           if ($script:PB.IsLaptop) { Write-Warn2 'ноутбук — пропускаю'; return }
           $old = $null
           if ((& powercfg.exe /getactivescheme) -match '([0-9a-fA-F-]{36})') { $old = $Matches[1] }
           & powercfg.exe /setactive SCHEME_MIN
           [void]$script:PB.Changes.Add([ordered]@{ Kind = 'PowerScheme'; Old = $old })
       } }

    @{ Id = 'sys.nohiber'; Name = 'Выключить гибернацию и быстрый запуск'; Desc = 'Выключает гибернацию (удаляет hiberfil.sys, это гигабайты) и быстрый запуск. Обычный сон остаётся.'; Group = 'Система'; Os = @('10', '11'); Phase = 'pre'
       Apply = {
           $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
           & powercfg.exe /hibernate off
           [void]$script:PB.Changes.Add([ordered]@{ Kind = 'Hibernate'; WasEnabled = ($v -ne 0) })
       } }

    # ============================== Среда (после установки программ) ==============================

    @{ Id = 'env.terminal'; Name = 'Windows Terminal: pwsh по умолчанию, Cascadia Code 11, квейк-консоль Alt+`'; Desc = 'Настраивает Windows Terminal: профиль по умолчанию PowerShell 7, шрифт Cascadia Code 11, выезжающая консоль по Alt+` (Alt+Ё), автозапуск в трей.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = { Set-TerminalConfig } }

    @{ Id = 'env.defaultterm'; Name = 'Windows Terminal — терминал по умолчанию для консольных программ'; Desc = 'Все консольные программы открываются в Windows Terminal, а не в старом окне conhost.'; Group = 'Среда'; Os = @('11'); Phase = 'post'
       Apply = {
           Set-Reg 'HKCU:\Console\%%Startup' 'DelegationConsole' '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}' -Type String
           Set-Reg 'HKCU:\Console\%%Startup' 'DelegationTerminal' '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}' -Type String
       } }

    @{ Id = 'env.pwshprofile'; Name = 'Профиль PowerShell 7: подсказки из истории, промпт с веткой git, алиасы'; Desc = 'Ставит профиль pwsh из configs: подсказки из истории, Tab с меню, промпт с веткой git, алиасы ll / which / touch.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = { Set-PwshProfile } }

    @{ Id = 'env.upgrade'; Name = 'Обновить всё, что стоит (winget upgrade --all)'; Desc = 'В конце обновляет все программы, которые знает winget. На рабочем ПК заденет и корпоративный софт.'; Group = 'Среда'; Os = @('10', '11'); Phase = 'post'
       Apply = { & winget upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity } }
)

# ---------- функции для твиков «Среда» ----------

function Set-TerminalConfig {
    $dir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir 'settings.json'
    $pwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    $cfg = $null
    if (Test-Path $file) {
        Copy-Item $file "$file.pc-base_$($script:PB.Stamp).bak" -Force
        try { $cfg = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Warn2 'settings.json не разобрался, пишу заново (копия рядом, .bak)' }
    }
    if (-not $cfg) { $cfg = [pscustomobject]@{ '$schema' = 'https://aka.ms/terminal-profiles-schema' } }

    function Set-Prop ($Obj, [string]$Name, $Value) { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

    Set-Prop $cfg 'defaultProfile' $pwshGuid
    Set-Prop $cfg 'startOnUserLogin' $true
    Set-Prop $cfg 'minimizeToNotificationArea' $true
    Set-Prop $cfg 'disabledProfileSources' @('Windows.Terminal.Azure')

    if (-not $cfg.profiles) { Set-Prop $cfg 'profiles' ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) }
    if ($cfg.profiles -is [array]) { Set-Prop $cfg 'profiles' ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = $cfg.profiles }) }
    if (-not $cfg.profiles.defaults) { Set-Prop $cfg.profiles 'defaults' ([pscustomobject]@{}) }
    Set-Prop $cfg.profiles.defaults 'font' ([pscustomobject]@{ face = 'Cascadia Code'; size = 11 })

    # квейк: старый формат (keys внутри actions) WT сам мигрирует в новый
    $actions = @()
    if ($cfg.actions) { $actions = @($cfg.actions | Where-Object { $_.keys -ne 'alt+sc(41)' -and $_.command -ne 'quakeMode' -and $_.command.action -ne 'quakeMode' }) }
    $actions += [pscustomobject]@{ command = [pscustomobject]@{ action = 'quakeMode' }; keys = 'alt+sc(41)' }
    Set-Prop $cfg 'actions' $actions
    if ($cfg.keybindings) {
        Set-Prop $cfg 'keybindings' @($cfg.keybindings | Where-Object { $_.keys -ne 'alt+sc(41)' })
    }

    $json = $cfg | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding $false))
    Write-Ok "Terminal: $file"
}

function Set-PwshProfile {
    # СЃРІРѕР№ РїСЂРѕС„РёР»СЊ РёР· DataRoot РїРµСЂРµРєСЂС‹РІР°РµС‚ РІСЃС‚СЂРѕРµРЅРЅС‹Р№
    $src = Find-PbConfig 'pwsh_profile.ps1'
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $dst = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    if (Test-Path $dst) { Copy-Item $dst "$dst.pc-base_$($script:PB.Stamp).bak" -Force }
    Copy-Item $src $dst -Force
    Write-Ok "профиль: $dst"
}
