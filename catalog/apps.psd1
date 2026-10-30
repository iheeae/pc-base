# pc-base: каталог программ. Это главный файл, который правится руками.
#
# ПРАВИЛО: в каталоге только то, что бесплатно навсегда и без условий (без лицензий, пробных периодов
# и ограничений до активации). Исключения: Npcap (бесплатен до 5 систем, без ограничений
# с Nmap/Wireshark) и Docker Desktop (бесплатен для себя и небольших компаний).
# Платное и условно-бесплатное — в pc-base-exe на Диске, ставится руками.
#
# Источники:
#   Source = 'winget' — найди ID командой  winget search <имя>  и добавь WingetId.
#   Source = 'web'    — когда в winget нет или там старьё: скачать с официального сайта.
#                       PageUrl — страница загрузки, FileRegex — имя файла с группой (?<v>версия),
#                       BaseUrl — куда дописать имя файла, Signer — regex издателя в цифровой подписи
#                       (без валидной подписи файл не запустится), Detect — DisplayName для «уже стоит».
#
# Профилей нет: в окне видно всё, отмечаешь что нужно. Повторяющиеся наборы
# сохраняются кнопкой «Сохранить набор» в папку selections\ (обычный JSON со списком Id).
#
# Всё, чего нет в winget или что ставишь руками, — кидаешь в папку pc-base-exe
# в корне Google Drive. Каталог её не касается: вся папка скачивается на рабочий стол.
#
# Поля:
#   Category    — группа в окне выбора
#   Os          — @('10') или @('11'): программа существует только для этой версии (на другой не видна)
#   Interactive — $true, если тихо поставить нельзя (откроется мастер, пройти руками)
#   Scope       — 'machine' или 'user' (по умолчанию — как решит пакет)
#   Override    — свои ключи установщика (заменяют стандартные)
#   Manual      — что доделать руками после установки (попадёт в итоговый список)
#   Note        — короткая пометка (покажется в описании)
#   Desc        — что это за программа и на каких условиях она бесплатна; видно в окне при наведении
#   ConfigFn    — имя функции из lib\configs.ps1, которая переносит твои настройки программы;
#                 в окне у программы появится значок ⚙ и выбор «Установка: ConfigName / чистая»
#   ConfigName  — подпись этого варианта (обычно 'с моими настройками')
#   ConfigDesc  — что именно переносится
#   ConfigFile  — файл настроек внутри configs\ (свои данные или движок); нет ни там, ни там —
#                 вариант «с моими настройками» в окне недоступен
#
# Порядок в списке = порядок установки (Основа идёт первой: git нужен самой базе).

@{
    Apps = @(
        @{ Id = 'git';       Name = 'Git'; Desc = 'Система контроля версий. Нужна самой pc-base, чтобы подтягивать обновления. Бесплатно, open source.';                 Category = 'Основа'; Source = 'winget'; WingetId = 'Git.Git';                    Scope = 'machine'; Note = 'нужен самой базе для обновлений' }
        @{ Id = 'gh';        Name = 'GitHub CLI'; Desc = 'Консольный клиент GitHub: вход в аккаунт, клоны приватных реп, issues. Бесплатно, open source.';          Category = 'Основа'; Source = 'winget'; WingetId = 'GitHub.cli';                 Scope = 'machine'; Note = 'вход в GitHub для приватной репы' }
        @{ Id = 'pwsh';      Name = 'PowerShell 7'; Desc = 'Современный PowerShell 7, ставится рядом со старым 5.1: быстрее, нормальный UTF-8. Бесплатно, open source.';        Category = 'Основа'; Source = 'winget'; WingetId = 'Microsoft.PowerShell';       Scope = 'machine' }
        @{ Id = 'wt';        Name = 'Windows Terminal'; Desc = 'Терминал с вкладками, панелями и выезжающей консолью по хоткею. В Win11 уже есть. Бесплатно, open source.';    Category = 'Основа'; Source = 'winget'; WingetId = 'Microsoft.WindowsTerminal'; Note = 'в Win11 уже есть, в Win10 ставится' }
        @{ Id = 'vivaldi';   Name = 'Vivaldi'; Desc = 'Браузер, в котором отключается всё лишнее. Можно поставить чистым или с твоими настройками (⚙, блок «Установка»). Бесплатно.';             Category = 'Повседневное'; Source = 'winget'; WingetId = 'Vivaldi.Vivaldi'; ConfigFn = 'Set-VivaldiConfig'; ConfigFile = 'vivaldi\prefs.json'; ConfigName = 'с моими настройками'; ConfigDesc = 'Переносит твои настройки Vivaldi (интерфейс, панели, вкладки, поведение) из configs\vivaldi\prefs.json. Расширения, пароли, почта и аккаунты не переносятся.';            Scope = 'machine'; Manual = 'войти в Vivaldi Sync' }
        @{ Id = 'everything';Name = 'Everything'; Desc = 'Мгновенный поиск файлов по имени на всех дисках (читает индекс NTFS), показывает размеры папок. Бесплатно.';          Category = 'Повседневное'; Source = 'winget'; WingetId = 'voidtools.Everything';       Scope = 'machine'; Manual = 'в настройках включить «Размеры папок» (Indexes → Index folder size)' }
        @{ Id = 'flow';      Name = 'Flow Launcher'; Desc = 'Лаунчер по Alt+Space: запуск программ, поиск файлов через Everything, калькулятор, команды. Замена поиску в Пуске. Бесплатно, open source.';       Category = 'Повседневное'; Source = 'winget'; WingetId = 'Flow-Launcher.Flow-Launcher'; Manual = 'Settings → Plugins → Explorer → Index/Content Search Engine: Everything' }
        @{ Id = 'aimp';      Name = 'AIMP'; Desc = 'Лёгкий аудиоплеер. Бесплатно.';                Category = 'Повседневное'; Source = 'winget'; WingetId = 'AIMP.AIMP';                   Scope = 'machine' }
        @{ Id = 'radmin';    Name = 'Radmin VPN'; Desc = 'Виртуальная локальная сеть поверх интернета, для игр по LAN с друзьями. Бесплатно.';          Category = 'Игры'; Source = 'winget'; WingetId = 'Famatech.RadminVPN';          Scope = 'machine'; Note = 'для игр' }
        @{ Id = 'steam';     Name = 'Steam'; Desc = 'Клиент Steam: игры, Wallpaper Engine. Бесплатно.';               Category = 'Игры'; Source = 'winget'; WingetId = 'Valve.Steam';                 Scope = 'machine'; Manual = 'войти, поставить Wallpaper Engine' }
        @{ Id = 'wireshark'; Name = 'Wireshark'; Desc = 'Анализатор сетевого трафика. Для захвата нужен Npcap (отметь его тоже). Бесплатно, open source.';           Category = 'Сеть и ИБ'; Source = 'winget'; WingetId = 'WiresharkFoundation.Wireshark'; Scope = 'machine'; Manual = 'для захвата нужен Npcap — он есть в каталоге (Сеть и ИБ)' }
        @{ Id = 'iperf3';    Name = 'iperf3'; Desc = 'Замер пропускной способности сети между двумя точками. Бесплатно, open source.';              Category = 'Сеть и ИБ'; Source = 'winget'; WingetId = 'ar51an.iPerf3'; Note = 'portable, команда iperf3 сразу в PATH' }
        @{ Id = 'npcap';     Name = 'Npcap';               Desc = 'Драйвер захвата пакетов для Wireshark и Nmap. Бесплатно до 5 систем, без ограничений вместе с Nmap / Wireshark. В winget его нет (лицензия запрещает раздачу): качается с npcap.com, подпись проверяется.'; Category = 'Сеть и ИБ'; Source = 'web'; PageUrl = 'https://npcap.com/'; FileRegex = 'npcap-(?<v>\d+(?:\.\d+)+)\.exe'; BaseUrl = 'https://npcap.com/dist/'; Signer = 'Insecure\.Com'; Detect = 'Npcap*'; Interactive = $true }
        @{ Id = 'nmap';      Name = 'Nmap + Zenmap';       Desc = 'Сканер сети и портов, Zenmap — его графическая оболочка. Бесплатно для использования. В winget только древняя 7.80, поэтому свежая версия качается с nmap.org, подпись проверяется. Внутри предложит поставить и Npcap.'; Category = 'Сеть и ИБ'; Source = 'web'; PageUrl = 'https://nmap.org/download.html'; FileRegex = 'nmap-(?<v>\d+(?:\.\d+)+)-setup\.exe'; BaseUrl = 'https://nmap.org/dist/'; Signer = 'Insecure\.Com'; Detect = 'Nmap*'; Interactive = $true }
        @{ Id = 'advip';     Name = 'Advanced IP Scanner'; Desc = 'Сканер локальной сети с RDP / Radmin-подключением в один клик. Бесплатно, закрытый код (Famatech, разработчик Radmin).'; Category = 'Сеть и ИБ'; Source = 'winget'; WingetId = 'Famatech.AdvancedIPScanner' }
        @{ Id = 'sysinfo';   Name = 'System Informer'; Desc = 'Продвинутый диспетчер задач (бывший Process Hacker): процессы, службы, сеть, диски. Бесплатно, open source.';     Category = 'Система'; Source = 'winget'; WingetId = 'WinsiderSS.SystemInformer' }
        @{ Id = 'sysint';    Name = 'Sysinternals Suite'; Desc = 'Утилиты Microsoft Sysinternals: Process Explorer, Autoruns, TCPView, PsExec и другие. Бесплатно.';  Category = 'Система'; Source = 'winget'; WingetId = 'Microsoft.Sysinternals.Suite'; Note = 'portable, все утилиты в PATH, RDCMan внутри' }
        @{ Id = 'ditto';     Name = 'Ditto'; Desc = 'История буфера обмена с поиском. Бесплатно, open source.';               Category = 'Повседневное'; Source = 'winget'; WingetId = 'Ditto.Ditto'; Manual = 'ограничить срок хранения истории' }
        @{ Id = 'nanazip';   Name = 'NanaZip'; Desc = 'Архиватор на движке 7-Zip с нормальным контекстным меню Win11. Бесплатно, open source.';             Category = 'Повседневное'; Source = 'winget'; WingetId = 'M2Team.NanaZip'; Note = '7-Zip с нормальным контекстным меню' }
        @{ Id = 'winscp';    Name = 'WinSCP'; Desc = 'Клиент SFTP / SCP / FTP. Бесплатно, open source.';              Category = 'Сеть и ИБ'; Source = 'winget'; WingetId = 'WinSCP.WinSCP' }
        @{ Id = 'npp';       Name = 'Notepad++'; Desc = 'Лёгкий текстовый редактор с подсветкой синтаксиса. Бесплатно, open source.';           Category = 'Разработка'; Source = 'winget'; WingetId = 'Notepad++.Notepad++' }
        @{ Id = 'docker';    Name = 'Docker Desktop';      Desc = 'Контейнеры на Windows через WSL2 (отметь и настройку «WSL2»). ИСКЛЮЧЕНИЕ из правила бесплатности: бесплатно для себя, учёбы и компаний до 250 человек и 10 млн $ выручки, иначе подписка.'; Category = 'Разработка'; Source = 'winget'; WingetId = 'Docker.DockerDesktop'; Scope = 'machine'; Manual = 'запустить после перезагрузки, принять лицензию' }
        @{ Id = 'vscode';    Name = 'VS Code'; Desc = 'Редактор кода с расширениями. Бесплатно.';             Category = 'Разработка'; Source = 'winget'; WingetId = 'Microsoft.VisualStudioCode'; Scope = 'machine' }
        @{ Id = 'keepassxc'; Name = 'KeePassXC'; Desc = 'Менеджер паролей с локальной зашифрованной базой. Бесплатно, open source.';           Category = 'Повседневное'; Source = 'winget'; WingetId = 'KeePassXCTeam.KeePassXC' }
        @{ Id = 'sharex';    Name = 'ShareX'; Desc = 'Скриншоты и запись экрана с редактором, OCR и загрузкой. Бесплатно, open source.';              Category = 'Повседневное'; Source = 'winget'; WingetId = 'ShareX.ShareX' }
        @{ Id = 'drawio';    Name = 'draw.io'; Desc = 'Редактор схем и диаграмм, работает офлайн. Бесплатно, open source.';             Category = 'Разработка'; Source = 'winget'; WingetId = 'JGraph.Draw' }
        @{ Id = 'sumatra';   Name = 'SumatraPDF'; Desc = 'Быстрая читалка PDF, EPUB, DjVu. Бесплатно, open source.';          Category = 'Повседневное'; Source = 'winget'; WingetId = 'SumatraPDF.SumatraPDF' }
        @{ Id = 'winmerge';  Name = 'WinMerge'; Desc = 'Сравнение и слияние файлов и папок. Бесплатно, open source.';            Category = 'Разработка'; Source = 'winget'; WingetId = 'WinMerge.WinMerge' }
        @{ Id = 'angryip';   Name = 'Angry IP Scanner'; Desc = 'Быстрый сканер IP-адресов и портов. Нужна Java. Бесплатно, open source.';    Category = 'Сеть и ИБ'; Source = 'winget'; WingetId = 'angryziber.AngryIPScanner'; Note = 'нужна Java' }
        @{ Id = 'powertoys'; Name = 'PowerToys'; Desc = 'Набор утилит Microsoft: редактор hosts и PATH, OCR с экрана, предпросмотр, переназначение клавиш. Бесплатно, open source.';           Category = 'Повседневное'; Source = 'winget'; WingetId = 'Microsoft.PowerToys' }
        @{ Id = 'gdrive';    Name = 'Google Drive'; Desc = 'Клиент Google Drive. pc-base подтягивает его сам, когда качает pc-base-exe. Бесплатно.';        Category = 'Повседневное'; Source = 'winget'; WingetId = 'Google.GoogleDrive'; Note = 'для pc-base-exe подтянется сам, отдельно ставить не нужно' }
    )
}
