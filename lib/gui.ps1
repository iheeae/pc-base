# pc-base: окно выбора на WPF (есть в Windows PowerShell 5.1 из коробки, внешних библиотек нет).
# Разметка и стили — lib\ui\*.xaml, модель для привязок — lib\ui\model.cs. WPF нужен STA-поток:
# setup.ps1 перезапускает себя с -STA, если запущен иначе.
#   * слева навигация: Программы / Настройки Windows / Файлы с Диска по категориям со счётчиками, внизу «Итог»
#   * в центре карточки категории; значки ⚙ (есть ConfigFn), мастер, необратимо, сайт видны без клика
#   * справа подробности выделенного; у программ с ConfigFn — «Установка: с моими настройками / чистая»
#   * поиск сверху — сразу по всем разделам; «Сохранения ▾» — свои наборы галочек (lib\data.ps1)
#   * слева внизу «Мои данные»: подключить (вход в GitHub, клон своей приватной репы), отправить, отключить и стереть
#   * тема и акцент — как в Windows
#
# Возвращает @{ Apps; Configs; Tweaks; Files; FilesAsk; Name; DryRun } или $null, если окно закрыли.

$script:PbUiDir = Join-Path $PSScriptRoot 'ui'
. (Join-Path $PSScriptRoot 'data.ps1')

function Format-Size ([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} ГБ' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} МБ' -f ($Bytes / 1MB) }
    return '{0:N0} КБ' -f ($Bytes / 1KB)
}

# ---------- оформление ----------

# тема по системе: светлая/тёмная, акцент из DWM (запасной #0067C0), Segoe UI Variable, если есть
function Get-UiTheme {
    $dark = $false
    try { $dark = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' -ErrorAction Stop) -eq 0 } catch { }
    $accent = [Windows.Media.Color]::FromRgb(0x00, 0x67, 0xC0)
    try {
        $v = [int64](Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor' -ErrorAction Stop) -band 0xFFFFFFFF
        $accent = [Windows.Media.Color]::FromRgb([byte]($v -band 0xFF), [byte](($v -shr 8) -band 0xFF), [byte](($v -shr 16) -band 0xFF))
    } catch { }
    $fams = @([Windows.Media.Fonts]::SystemFontFamilies | ForEach-Object { $_.Source })
    $font = if ($fams -contains 'Segoe UI Variable Text') { 'Segoe UI Variable Text' } else { 'Segoe UI' }
    return @{ Dark = $dark; Accent = $accent; Font = $font }
}

# кисти, на которые ссылается theme.xaml (DynamicResource)
function Set-UiPalette ($Res, $Theme) {
    function Mix ($A, $B, [double]$T) {
        [Windows.Media.Color]::FromRgb([byte]($A.R + ($B.R - $A.R) * $T), [byte]($A.G + ($B.G - $A.G) * $T), [byte]($A.B + ($B.B - $A.B) * $T))
    }
    function Lum ($C) { (0.2126 * $C.R + 0.7152 * $C.G + 0.0722 * $C.B) / 255 }

    $white = [Windows.Media.Colors]::White; $black = [Windows.Media.Colors]::Black
    $a = $Theme.Accent
    if ($Theme.Dark) {
        $p = @{ Bg = '#202020'; Surface = '#2B2B2B'; SurfaceHover = '#323232'; SurfaceStrong = '#383838'; NavHover = '#2D2D2D'
                Border = '#383838'; Control = '#2D2D2D'; ControlHover = '#353535'; ControlPressed = '#282828'; ControlBorder = '#454545'
                ControlStrong = '#9A9A9A'; Text = '#FFFFFF'; TextMuted = '#ABABAB'; PillBg = '#3A3A3A'; Danger = '#FF99A4'
                DangerSoft = '#442726'; ScrollThumb = '#5C5C5C' }
        $fill = Mix $a $white 0.45
        $fillFg = if ((Lum $fill) -gt 0.45) { $black } else { $white }
        $text = Mix $a $white 0.5
        $soft = [Windows.Media.Color]::FromArgb(0x33, $text.R, $text.G, $text.B)
    } else {
        $p = @{ Bg = '#F3F3F3'; Surface = '#FFFFFF'; SurfaceHover = '#F5F5F5'; SurfaceStrong = '#E6E6E6'; NavHover = '#EBEBEB'
                Border = '#E5E5E5'; Control = '#FBFBFB'; ControlHover = '#F3F3F3'; ControlPressed = '#EDEDED'; ControlBorder = '#D1D1D1'
                ControlStrong = '#8A8A8A'; Text = '#1B1B1B'; TextMuted = '#5F5F5F'; PillBg = '#EDEDED'; Danger = '#C42B1C'
                DangerSoft = '#FDE7E9'; ScrollThumb = '#C2C2C2' }
        $fill = if ((Lum $a) -gt 0.45) { Mix $a $black 0.35 } else { $a }
        $fillFg = $white
        $text = $fill
        $soft = [Windows.Media.Color]::FromArgb(0x1F, $fill.R, $fill.G, $fill.B)
    }
    $colors = @{ Accent = $fill; AccentFg = $fillFg; AccentText = $text; AccentSoft = $soft }
    foreach ($k in $p.Keys) { $colors[$k] = [Windows.Media.ColorConverter]::ConvertFromString($p[$k]) }
    $colors.Focus = $colors.Text
    # BaseObject: иначе в словарь попадает обёртка PSObject и WPF видит строку вместо кисти
    foreach ($k in $colors.Keys) {
        $b = New-Object Windows.Media.SolidColorBrush $colors[$k]; $b.Freeze()
        $Res[$k] = $b.PSObject.BaseObject
    }
    $Res['UiFont'] = (New-Object Windows.Media.FontFamily $Theme.Font).PSObject.BaseObject
}

# значок окна: монограмма «pb» на плашке цвета акцента. Рисуется на лету — бинарных файлов в репе нет
function New-UiIcon ($Res, [int]$Size = 64) {
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $r = $Size * 0.22
    $dc.DrawRoundedRectangle($Res['Accent'], $null, (New-Object Windows.Rect 0, 0, $Size, $Size), $r, $r)
    $tf = New-Object Windows.Media.Typeface (New-Object Windows.Media.FontFamily 'Segoe UI'), 'Normal', 'Bold', 'Normal'
    $ft = New-Object Windows.Media.FormattedText 'pb', ([Globalization.CultureInfo]::InvariantCulture), 'LeftToRight', $tf, ($Size * 0.56), $Res['AccentFg']
    $g = $ft.BuildGeometry((New-Object Windows.Point 0, 0))
    $b = $g.Bounds
    $g.Transform = New-Object Windows.Media.TranslateTransform (($Size - $b.Width) / 2 - $b.X), (($Size - $b.Height) / 2 - $b.Y)
    $dc.DrawGeometry($Res['AccentFg'], $null, $g)
    $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $frame = [Windows.Media.Imaging.BitmapFrame]::Create($bmp)
    $frame.Freeze()
    return $frame
}

function Read-Xaml ([string]$Name) {
    $fs = [IO.File]::OpenRead((Join-Path $script:PbUiDir $Name))
    try { return [Windows.Markup.XamlReader]::Load($fs) } finally { $fs.Dispose() }
}

# один раз на процесс: модель, DPI, WPF, общие ресурсы. Возвращает тему.
function Initialize-Ui {
    if ($script:PbUiTheme) { return $script:PbUiTheme }
    if (-not ('PcBase.Item' -as [type])) { Add-Type -Path (Join-Path $script:PbUiDir 'model.cs') }
    [PcBase.Native]::EnableDpiAwareness()
    [PcBase.Native]::SetAppId('pc-base')
    [AppContext]::SetSwitch('Switch.System.Windows.DoNotScaleForDpiChanges', $false)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    # Application нужен, чтобы стили видели и всплывающие меню/подсказки; Run() не зовём, окна — через ShowDialog
    $app = [Windows.Application]::Current
    if (-not $app) { $app = New-Object Windows.Application; $app.ShutdownMode = 'OnExplicitShutdown' }
    $theme = Get-UiTheme
    $res = New-Object Windows.ResourceDictionary
    $res.MergedDictionaries.Add((Read-Xaml 'theme.xaml'))
    Set-UiPalette $res $theme
    $app.Resources = $res
    $theme.Icon = New-UiIcon $res
    $script:PbUiTheme = $theme
    return $theme
}

function New-UiWindow ([string]$Xaml, $Theme) {
    $w = Read-Xaml $Xaml
    $w.Icon = $Theme.Icon
    $dark = [bool]$Theme.Dark
    $w.add_SourceInitialized({ param($s) [PcBase.Native]::SetDarkTitleBar((New-Object Windows.Interop.WindowInteropHelper $s).Handle, $dark) }.GetNewClosure())
    return $w
}

# сообщение / подтверждение в стиле окна. $Lines — строки или @{ Text; Tone = 'danger'|'muted'|'strong' }.
# Возвращает $true, если нажата главная кнопка. С -WithInput — поле ввода, возвращает введённое или $null.
function Show-UiMessage {
    param($Owner, [string]$Title, $Lines, [string]$Primary = 'Понятно', [string]$Secondary, [switch]$SafeDefault,
        [switch]$WithInput, [string]$InputValue)
    $theme = Initialize-Ui
    $d = New-UiWindow 'dialog.xaml' $theme
    if ($Owner) { $d.Owner = $Owner } else { $d.WindowStartupLocation = 'CenterScreen' }
    $d.FindName('Head').Text = $Title
    $body = $d.FindName('Body')
    foreach ($l in @($Lines)) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,4,0,0'; $tb.LineHeight = 20
        if ($l -is [hashtable]) {
            $tb.Text = $l.Text
            switch ($l.Tone) {
                'danger' { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Danger') }
                'muted'  { $tb.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextMuted') }
                'strong' { $tb.FontWeight = 'SemiBold' }
            }
            if ($l.Gap) { $tb.Margin = '0,16,0,0' }
        } else { $tb.Text = [string]$l }
        [void]$body.Children.Add($tb)
    }
    $bp = $d.FindName('Primary'); $bs = $d.FindName('Secondary')
    $bp.Content = $Primary
    $bp.add_Click({ $d.DialogResult = $true })
    if ($Secondary) { $bs.Content = $Secondary; $bs.IsCancel = $true } else { $bs.Visibility = 'Collapsed'; $bp.IsCancel = $true }
    $box = $d.FindName('Input')
    if ($WithInput) {
        $box.Visibility = 'Visible'; $box.Text = $InputValue; $bp.IsDefault = $true
        $d.add_ContentRendered({ [void]$box.Focus(); $box.SelectAll() })
        if (-not $d.ShowDialog()) { return $null }
        return $box.Text
    }
    $d.add_ContentRendered({ if ($SafeDefault -and $Secondary) { [void]$bs.Focus() } else { [void]$bp.Focus() } })
    return [bool]$d.ShowDialog()
}

function Get-Plural ([int]$N, [string]$One, [string]$Few, [string]$Many) {
    $m10 = $N % 10; $m100 = $N % 100
    if ($m10 -eq 1 -and $m100 -ne 11) { return $One }
    if ($m10 -ge 2 -and $m10 -le 4 -and ($m100 -lt 12 -or $m100 -gt 14)) { return $Few }
    return $Many
}

function New-Fact ([string]$Label, [string]$Value, [string]$Tone = '') {
    $f = New-Object PcBase.Fact
    $f.Label = $Label; $f.Value = $Value; $f.Tone = $Tone
    return $f
}

function New-FileItem ($File, [string]$CatKey, [string]$Group) {
    $it = New-Object PcBase.Item
    $it.Key = 'file:' + $File.Name; $it.Kind = 'file'; $it.Id = $File.Name; $it.Name = $File.Name
    $sz = if ($File.PSIsContainer) { 'папка' } else { Format-Size $File.Length }
    $dt = $File.LastWriteTime.ToString('dd.MM.yyyy')
    $it.Desc = "$sz · изменён $dt"
    $it.FullDesc = 'Скопируется с Диска в «Рабочий стол\pc-base-exe». Ничего не ставится — запускаешь сам.'
    $it.CatKey = $CatKey; $it.CatName = $Group; $it.GroupTitle = $Group
    $it.SearchText = "$($File.Name)`nдиск`npc-base-exe"
    $it.Facts.Add((New-Fact 'Размер' $sz))
    $it.Facts.Add((New-Fact 'Изменён' $dt))
    $it.Facts.Add((New-Fact 'Что будет' 'Только скачать'))
    return $it
}

# ---------- окошко файлов с Диска — когда в главном окне Диск ещё не был виден ----------

function Show-FilePicker {
    param($Items, [string[]]$Preselect)
    $theme = Initialize-Ui
    $w = New-UiWindow 'files.xaml' $theme
    $list = $w.FindName('List'); $sum = $w.FindName('Summary')
    $rows = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    foreach ($i in $Items) {
        $it = New-FileItem $i 'files' 'pc-base-exe'
        $it.IsChecked = $Preselect -contains $i.Name
        $rows.Add($it)
    }
    $list.ItemsSource = $rows
    function Update-Sum { $sum.Text = "Выбрано $(@($rows | Where-Object { $_.IsChecked }).Count) из $($rows.Count)" }
    foreach ($it in $rows) { $it.add_PropertyChanged({ Update-Sum }) }
    Update-Sum
    $w.FindName('All').add_Click({ foreach ($it in $rows) { $it.IsChecked = $true } })
    $w.FindName('None').add_Click({ foreach ($it in $rows) { $it.IsChecked = $false } })
    $w.FindName('Ok').add_Click({ $w.DialogResult = $true })
    $list.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Space' -and $list.SelectedItem) { $list.SelectedItem.IsChecked = -not $list.SelectedItem.IsChecked; $e.Handled = $true }
    })
    if (-not $w.ShowDialog()) { return $null }
    $out = @($rows | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id })
    return $out
}

# ---------- главное окно ----------

function Show-SelectionDialog {
    param(
        $Apps, $Tweaks,
        $DriveItems,                 # файлы pc-base-exe, если Диск уже виден; $null — не виден
        [hashtable]$Initial,         # сохранение, с которым открыть окно (Read-SaveFile)
        [bool]$DryRun = $true,
        [bool]$IsDomain = $false,
        [string]$Title = 'pc-base'
    )

    $theme = Initialize-Ui
    $win = New-UiWindow 'main.xaml' $theme
    $ctl = @{}
    foreach ($n in 'Logo', 'HostChips', 'Search', 'SearchKey', 'SearchClear', 'SetBtn', 'SetBtnText', 'Nav', 'NavBottom', 'ListTitle', 'ListHint', 'CatButtons', 'CatAll', 'CatNone',
        'List', 'ListEmpty', 'DetailHint', 'Detail', 'RbMineText', 'PcNameLabel', 'PcName', 'PcNameFixed', 'PcNameCur', 'ModePlan', 'ModeApply', 'Summary', 'SaveBtn', 'OkBtn',
        'Notice', 'NoticeIcon', 'NoticeText', 'NoticeClose', 'DataIcon', 'DataStatus', 'DataBtn', 'DataLogin', 'DataCode', 'DataOpen') {
        $ctl[$n] = $win.FindName($n)
    }
    # 1200×800, но не больше рабочей области (1080p на 150 % — это 1280×~700)
    $wa = [Windows.SystemParameters]::WorkArea
    $win.Width = [Math]::Max($win.MinWidth, [Math]::Min(1200, $wa.Width - 48))
    $win.Height = [Math]::Max($win.MinHeight, [Math]::Min(800, $wa.Height - 48))
    $win.Title = $Title
    $ctl.Logo.Source = $theme.Icon
    $ctl.HostChips.ItemsSource = @($env:COMPUTERNAME, "Windows $($script:PB.Os)") + @(if ($IsDomain) { 'в домене' })

    # --- модель: пункты и навигация ---
    $items = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $nav = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $cats = [ordered]@{}            # CatKey -> NavEntry
    $first = @{}                    # раздел -> первая категория (Ctrl+1/2/3)
    $secLabel = @{ apps = 'Программы'; tweaks = 'Настройки Windows'; files = 'Файлы с Google Drive — только скачать, ничего не ставится' }
    function Add-Nav ([string]$Kind, [string]$Section, [string]$Name, [string]$Key) {
        $e = New-Object PcBase.NavEntry
        $e.Kind = $Kind; $e.Section = $Section; $e.Name = $Name; $e.Key = $Key
        $nav.Add($e)
        if ($Kind -eq 'cat') { $cats[$Key] = $e; if (-not $first[$Section]) { $first[$Section] = $e } }
        return $e
    }

    [void](Add-Nav 'header' 'apps' 'ПРОГРАММЫ')
    foreach ($grp in ($Apps | Group-Object { $_.Category })) {
        $ck = 'apps|' + $grp.Name
        [void](Add-Nav 'cat' 'apps' $grp.Name $ck)
        foreach ($a in $grp.Group) {
            $it = New-Object PcBase.Item
            $it.Key = 'app:' + $a.Id; $it.Kind = 'app'; $it.Id = $a.Id; $it.Name = $a.Name
            $it.Desc = $a.Desc; $it.FullDesc = $a.Desc
            $it.CatKey = $ck; $it.CatName = "Программы · $($grp.Name)"; $it.GroupTitle = $it.CatName
            $it.Interactive = [bool]$a.Interactive; $it.IsWeb = $a.Source -eq 'web'
            $it.HasConfig = [bool]$a.ConfigFn; $it.ConfigName = $a.ConfigName; $it.ConfigDesc = $a.ConfigDesc; $it.ConfigFile = $a.ConfigFile
            $it.SearchText = @($a.Name, $a.Desc, $a.Id, $a.WingetId, $grp.Name, $a.Note) -join "`n"
            if ($a.Source -eq 'web') {
                $it.Facts.Add((New-Fact 'Источник' 'Официальный сайт: свежая версия, без валидной подписи издателя не запускается'))
                $it.Facts.Add((New-Fact 'Страница загрузки' $a.PageUrl 'mono'))
            } else { $it.Facts.Add((New-Fact 'Источник' "winget: $($a.WingetId)" 'mono')) }
            if ($a.Note) { $it.Facts.Add((New-Fact 'Пометка' $a.Note)) }
            if ($a.Interactive) { $it.Facts.Add((New-Fact 'Установка' 'Тихо не ставится: откроется мастер установки, пройти руками.')) }
            if ($a.Manual) { $it.Facts.Add((New-Fact 'Потом руками' $a.Manual)) }
            $items.Add($it)
        }
    }

    [void](Add-Nav 'header' 'tweaks' 'НАСТРОЙКИ WINDOWS')
    foreach ($grp in ($Tweaks | Group-Object { $_.Group })) {
        $ck = 'tweaks|' + $grp.Name
        [void](Add-Nav 'cat' 'tweaks' $grp.Name $ck)
        foreach ($t in $grp.Group) {
            $it = New-Object PcBase.Item
            $it.Key = 'tweak:' + $t.Id; $it.Kind = 'tweak'; $it.Id = $t.Id; $it.Name = $t.Name
            $it.Desc = $t.Desc; $it.FullDesc = $t.Desc
            $it.CatKey = $ck; $it.CatName = "Настройки Windows · $($grp.Name)"; $it.GroupTitle = $it.CatName
            $it.Irreversible = [bool]$t.Irreversible
            $it.SearchText = @($t.Name, $t.Desc, $t.Id, $grp.Name, $t.Manual) -join "`n"
            if ($t.Irreversible) { $it.Facts.Add((New-Fact 'Необратимо' 'undo.ps1 это не вернёт, только точка восстановления.' 'danger')) }
            if ($t.Manual) { $it.Facts.Add((New-Fact 'Потом руками' $t.Manual)) }
            $items.Add($it)
        }
    }

    [void](Add-Nav 'header' 'files' 'ФАЙЛЫ С ДИСКА')
    $driveOnline = $null -ne $DriveItems
    $fk = 'files|pc-base-exe'
    $fileCat = Add-Nav 'cat' 'files' 'pc-base-exe' $fk
    if ($driveOnline) {
        foreach ($i in $DriveItems) { $items.Add((New-FileItem $i $fk 'Файлы с Диска · pc-base-exe')) }
    } else {
        $secLabel.files = 'Google Drive на этом ПК сейчас не виден'
        $it = New-Object PcBase.Item
        $it.Key = 'files:ask'; $it.Kind = 'ask'; $it.Id = 'ask'; $it.Name = 'Диск сейчас не подключён'
        $it.Desc = 'Отметь — выбрать файлы во время прогона'
        $it.FullDesc = 'Google Drive на этом ПК сейчас не виден, поэтому списка файлов нет. Отметь — во время прогона pc-base подключит Диск (поставит Google Drive и попросит войти) и покажет список pc-base-exe с галочками.'
        $it.CatKey = $fk; $it.CatName = 'Файлы с Диска · pc-base-exe'; $it.GroupTitle = $it.CatName
        $it.SearchText = "диск`npc-base-exe`nфайлы`ngoogle drive"
        $it.Facts.Add((New-Fact 'Что будет' 'Только скачать: файлы копируются в «Рабочий стол\pc-base-exe», ничего не ставится.'))
        $items.Add($it)
    }
    $navSummary = New-Object PcBase.NavEntry
    $navSummary.Kind = 'summary'; $navSummary.Name = 'Итог'; $navSummary.Key = 'summary'
    $navBottom = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $navBottom.Add($navSummary)

    # --- состояние окна ---
    # Mode: cat — категория слева, search — результаты поиска, summary — экран «Итог»
    $ui = @{ Mode = 'cat'; Cat = $null; Nav = $null; Words = @(); Busy = $false; Bulk = $false; SaveName = $null; Result = $null; Name = $null
             Job = $null; PushAgain = $false; CodeShown = $null }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($items)
    $groupBy = New-Object Windows.Data.PropertyGroupDescription 'GroupTitle'

    function Test-Search ($o) {
        foreach ($w in $ui.Words) { if ($o.SearchText.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }
        return $true
    }
    function Test-Visible ($o) {
        if ($ui.Mode -eq 'search') { return (Test-Search $o) }
        if ($ui.Mode -eq 'summary') { return $o.IsChecked }
        return $o.CatKey -eq $ui.Cat
    }
    $view.Filter = [Predicate[object]]{ param($o) Test-Visible $o }

    function Get-Chosen {
        $on = @{}
        foreach ($it in $items) { if ($it.IsChecked) { $on[$it.Key] = $it } }
        return @{
            Apps     = @($Apps | Where-Object { $on.ContainsKey('app:' + $_.Id) } | ForEach-Object { $_.Id })
            Configs  = @($Apps | Where-Object { $_.ConfigFn -and $on.ContainsKey('app:' + $_.Id) -and $on['app:' + $_.Id].ConfigOn } | ForEach-Object { $_.Id })
            Tweaks   = @($Tweaks | Where-Object { $on.ContainsKey('tweak:' + $_.Id) } | ForEach-Object { $_.Id })
            Files    = @($items | Where-Object { $_.Kind -eq 'file' -and $_.IsChecked } | ForEach-Object { $_.Id } | Sort-Object)
            FilesAsk = $on.ContainsKey('files:ask')
        }
    }

    # счётчики «выбрано/всего» слева и сводка внизу
    function Update-Counts {
        $sel = @{}; $tot = @{}; $n = 0
        foreach ($it in $items) {
            $tot[$it.CatKey]++
            if ($it.IsChecked) { $sel[$it.CatKey]++; $n++ }
        }
        foreach ($k in $cats.Keys) {
            $s = [int]$sel[$k]; $t = [int]$tot[$k]
            $cats[$k].CountText = "$s/$t"
            $cats[$k].IsFull = $t -gt 0 -and $s -eq $t
        }
        if (-not $driveOnline) {
            $ask = $sel[$fk] -gt 0
            $fileCat.CountText = if ($ask) { 'при прогоне' } else { '' }
            $fileCat.IsFull = $ask
        }
        $navSummary.CountText = if ($n) { "$n" } else { '' }

        $c = Get-Chosen
        $parts = @("$($c.Apps.Count) $(Get-Plural $c.Apps.Count 'программа' 'программы' 'программ')$(if ($c.Configs.Count) { " (⚙ $($c.Configs.Count))" })",
            "$($c.Tweaks.Count) $(Get-Plural $c.Tweaks.Count 'настройка' 'настройки' 'настроек')")
        if ($driveOnline) { $parts += "$($c.Files.Count) $(Get-Plural $c.Files.Count 'файл' 'файла' 'файлов')" } elseif ($c.FilesAsk) { $parts += 'файлы при прогоне' }
        $ctl.Summary.Text = $parts -join ' · '
        $ctl.Summary.ToolTip = "Выбрано: программ $($c.Apps.Count), из них с моими настройками $($c.Configs.Count); настроек Windows $($c.Tweaks.Count)" +
            $(if ($driveOnline) { "; файлов с Диска $($c.Files.Count)" } elseif ($c.FilesAsk) { '; файлы с Диска — выбор во время прогона' })
    }

    # подсветка категорий с совпадениями, пока идёт поиск
    function Update-NavHits {
        $on = $ui.Mode -eq 'search'
        $hits = @{}
        if ($on) { foreach ($it in $items) { if (Test-Search $it) { $hits[$it.CatKey]++ } } }
        foreach ($k in $cats.Keys) {
            $cats[$k].IsHit = $on -and $hits[$k] -gt 0
            $cats[$k].IsDim = $on -and -not $hits[$k]
        }
        $navSummary.IsDim = $on
    }

    function Update-View {
        $view.GroupDescriptions.Clear()
        if ($ui.Mode -ne 'cat') { $view.GroupDescriptions.Add($groupBy) }
        $view.Refresh()
        $n = $view.Count
        $ctl.CatButtons.Visibility = if ($ui.Mode -eq 'cat' -and ($driveOnline -or $ui.Cat -ne $fk)) { 'Visible' } else { 'Collapsed' }
        switch ($ui.Mode) {
            'search' {
                $ctl.ListTitle.Text = "Поиск: «$($ctl.Search.Text.Trim())»"
                $ctl.ListHint.Text = "Найдено: $n  ·  клик по категории слева — перейти туда, Esc — очистить"
                $ctl.ListEmpty.Text = 'Ничего не нашлось. Ищется по названию, описанию, id, winget-ID и категории.'
            }
            'summary' {
                $ctl.ListTitle.Text = 'Итог'
                $ctl.ListHint.Text = 'Всё, что отмечено, по разделам. Сними галочку, если передумал'
                $ctl.ListEmpty.Text = 'Пока ничего не выбрано.'
            }
            default {
                $e = $cats[$ui.Cat]
                $ctl.ListTitle.Text = $e.Name
                $ctl.ListHint.Text = $secLabel[$e.Section]
                $ctl.ListEmpty.Text = if ($e.Section -eq 'files') { 'Папка pc-base-exe на Диске пуста.' } else { 'Здесь пусто.' }
            }
        }
        $ctl.ListEmpty.Visibility = if ($n) { 'Collapsed' } else { 'Visible' }
        if ($n) { $ctl.List.ScrollIntoView($view.GetItemAt(0)) }
    }

    function Open-Nav ($e) {
        $ui.Nav = $e
        if ($e.Kind -eq 'summary') { $ui.Mode = 'summary' } else { $ui.Mode = 'cat'; $ui.Cat = $e.Key }
        Update-NavHits
        Update-View
    }

    # отметка в навигации: категории — в верхнем списке, «Итог» — в нижнем; $null — снять везде (идёт поиск)
    function Set-NavMark ($e) {
        $ui.Busy = $true
        $ctl.Nav.SelectedItem = if ($e -and $e.Kind -eq 'cat') { $e } else { $null }
        $ctl.NavBottom.SelectedItem = if ($e -and $e.Kind -eq 'summary') { $e } else { $null }
        $ui.Busy = $false
    }

    # перейти как кликом (через SelectionChanged) и поставить фокус на пункт
    function Select-Nav ($e) {
        $lb = if ($e.Kind -eq 'summary') { $ctl.NavBottom } else { $ctl.Nav }
        $lb.SelectedItem = $e
        $c = $lb.ItemContainerGenerator.ContainerFromItem($e)
        if ($c) { [void]$c.Focus() }
    }

    function Set-Checked ($List, [bool]$On) {
        $ui.Bulk = $true
        foreach ($it in @($List)) { $it.IsChecked = $On }
        $ui.Bulk = $false
        Update-Counts
    }

    # загрузка сохранения заменяет текущий выбор целиком. Возвращает, сколько id из него нет в каталоге этого ПК
    function Set-Selection ([hashtable]$Sel) {
        $known = @{}
        foreach ($it in $items) { $known["$($it.Kind):$($it.Id)"] = $true }
        $miss = @($Sel.Apps | Where-Object { -not $known["app:$_"] }).Count + @($Sel.Tweaks | Where-Object { -not $known["tweak:$_"] }).Count
        $ui.Bulk = $true
        foreach ($it in $items) {
            $on = switch ($it.Kind) {
                'app'   { $Sel.Apps -contains $it.Id }
                'tweak' { $Sel.Tweaks -contains $it.Id }
                'file'  { $Sel.Files -contains $it.Id }
                'ask'   { [bool]($Sel.FilesAsk -or $Sel.Files.Count) }
            }
            $it.IsChecked = [bool]$on
            if ($it.HasConfig) { $it.ConfigOn = [bool]$on -and ($Sel.Configs -contains $it.Id) }
        }
        $ui.Bulk = $false
        Update-Counts
        if ($ui.Mode -ne 'cat') { Update-NavHits; Update-View }
        return $miss
    }

    # уведомление над списком: ok — акцентом, warn — красным
    function Show-Notice ([string]$Text, [string]$Tone = 'ok') {
        $warn = $Tone -eq 'warn'
        $ctl.NoticeText.Text = $Text
        $ctl.NoticeIcon.Text = if ($warn) { [string][char]0xE7BA } else { [string][char]0xE73E }
        $ctl.Notice.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($warn) { 'DangerSoft' } else { 'AccentSoft' }))
        $ctl.Notice.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($warn) { 'Danger' } else { 'AccentText' }))
        $ctl.NoticeIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($warn) { 'Danger' } else { 'AccentText' }))
        $ctl.Notice.Visibility = 'Visible'
    }

    function Set-SaveName ([string]$Name) {
        $ui.SaveName = $Name
        $ctl.SetBtnText.Text = if ($Name) { $Name } else { 'Сохранения' }
    }

    function Import-Save ([string]$Path) {
        try { $s = Read-SaveFile $Path }
        catch { [void](Show-UiMessage -Owner $win -Title 'Сохранение не читается' -Lines @($Path, @{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        $miss = Set-Selection $s
        Set-SaveName $s.Name
        $msg = "Открыто «$($s.Name)»"
        if ($s.Machine) { $msg += " — сохранено на $($s.Machine), $($s.Created.ToString('dd.MM.yyyy HH:mm'))" }
        if ($miss) { Show-Notice "$msg. Пропущено пунктов, которых нет в каталоге этого ПК (удалены или не для этой версии Windows): $miss." 'warn' }
        else { Show-Notice $msg }
    }

    # пока идёт фоновая отправка или подключение, git своих данных трогать нельзя
    function Test-DataBusy {
        if (-not $ui.Job) { return $false }
        Show-Notice 'Подожди пару секунд: идёт обмен с GitHub.' 'warn'
        return $true
    }

    function Save-Current {
        if (Test-DataBusy) { return }
        $c = Get-Chosen
        $where = if (Test-PbDataConnected) { "В Мои данные ($($script:PB.DataRoot)) и сразу в GitHub — увидишь на любом своём ПК." }
                 else { "На этом ПК ($(Get-PbLocalSaveDir)). Подключишь Мои данные — предложу перенести." }
        $def = if ($ui.SaveName) { $ui.SaveName } else { 'Мой набор' }
        $name = Show-UiMessage -Owner $win -Title 'Сохранить текущее' -WithInput -InputValue $def -Primary 'Сохранить' -Secondary 'Отмена' `
            -Lines @("Отмечено: $($ctl.Summary.Text)", @{ Text = $where; Tone = 'muted' })
        if ($null -eq $name) { return }
        $name = $name.Trim()
        if (-not $name) { return }
        if (@(Get-PbSaves | Where-Object { $_.Name -eq $name }).Count -and $name -ne $ui.SaveName) {
            if (-not (Show-UiMessage -Owner $win -Title "«$name» уже есть" -Lines @('Перезаписать его текущими галочками?') -Primary 'Перезаписать' -Secondary 'Назад' -SafeDefault)) { return }
        }
        try { [void](Save-PbSave $name $c) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не сохранилось' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        Set-SaveName $name
        if (Test-PbDataConnected) { Show-Notice "Сохранено «$name» в Мои данные, отправляю в GitHub…"; Start-DataJob 'push' }
        else { Show-Notice "Сохранено «$name» на этом ПК." }
        Update-DataBox
    }

    function Rename-Save ([string]$Path) {
        if (Test-DataBusy) { return }
        $old = (Read-SaveFile $Path).Name
        $new = Show-UiMessage -Owner $win -Title 'Переименовать' -WithInput -InputValue $old -Primary 'Переименовать' -Secondary 'Отмена' -Lines @("Сохранение «$old»")
        if ($null -eq $new -or -not $new.Trim() -or $new.Trim() -eq $old) { return }
        $new = $new.Trim()
        try { [void](Rename-PbSave $Path $new) }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не переименовалось' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        if ($ui.SaveName -eq $old) { Set-SaveName $new }
        Show-Notice "«$old» → «$new»"
        if (Test-PbDataConnected) { Start-DataJob 'push' }
    }

    function Remove-Save ([string]$Path) {
        if (Test-DataBusy) { return }
        $name = (Read-SaveFile $Path).Name
        $lines = @("Сохранение «$name» пропадёт с этого ПК.")
        if (Test-PbDataConnected) { $lines += @{ Text = 'Оно в Моих данных: удалится и на GitHub, но останется в истории репы.'; Tone = 'muted' } }
        if (-not (Show-UiMessage -Owner $win -Title 'Удалить сохранение?' -Lines $lines -Primary 'Удалить' -Secondary 'Назад' -SafeDefault)) { return }
        try { Remove-PbSave $Path }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не удалилось' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })); return }
        if ($ui.SaveName -eq $name) { Set-SaveName $null }
        Show-Notice "Удалено «$name»."
        if (Test-PbDataConnected) { Start-DataJob 'push' }
    }

    function New-MenuText ([string]$Text, [string]$Style) {
        $mi = New-Object Windows.Controls.MenuItem
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = $Text; $tb.TextWrapping = 'Wrap'; $tb.MaxWidth = 320
        if ($Style) { $tb.Style = $win.FindResource($Style) }
        $mi.Header = $tb; $mi.IsHitTestVisible = $false; $mi.Focusable = $false
        return $mi
    }

    function New-IconButton ([string]$Glyph, [string]$Tag, [string]$Tip) {
        $b = New-Object Windows.Controls.Button
        $b.Style = $win.FindResource('IconButton'); $b.Tag = $Tag; $b.ToolTip = $Tip
        $g = New-Object Windows.Controls.TextBlock
        $g.Style = $win.FindResource('Glyph'); $g.Text = $Glyph; $g.FontSize = 14; $g.IsHitTestVisible = $false
        $b.Content = $g
        return $b
    }

    # «Сохранения ▾»: свои сохранения (имя, дата, с какого ПК, переименовать, удалить), сохранить текущее, открыть файл
    function Fill-SaveMenu {
        $m = $ctl.SetBtn.ContextMenu
        $m.Items.Clear()
        $saves = @(Get-PbSaves)
        [void]$m.Items.Add((New-MenuText $(if (Test-PbDataConnected) { 'В МОИХ ДАННЫХ' } else { 'НА ЭТОМ ПК' }) 'SectionLabel'))
        if (-not $saves.Count) {
            [void]$m.Items.Add((New-MenuText 'Сохранений пока нет. «Сохранить текущее…» запишет то, что отмечено сейчас.' 'Muted'))
        }
        foreach ($s in $saves) {
            $mi = New-Object Windows.Controls.MenuItem
            $mi.Tag = $s.Path
            $g = New-Object Windows.Controls.Grid
            $g.MinWidth = 300
            foreach ($w in '*', 'Auto', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $w; $g.ColumnDefinitions.Add($cd) }
            $sp = New-Object Windows.Controls.StackPanel
            $sp.VerticalAlignment = 'Center'
            $t1 = New-Object Windows.Controls.TextBlock
            $t1.Text = $s.Name; $t1.FontWeight = 'SemiBold'; $t1.TextTrimming = 'CharacterEllipsis'; $t1.MaxWidth = 260
            $t2 = New-Object Windows.Controls.TextBlock
            $t2.Style = $win.FindResource('Caption')
            $t2.Text = $s.Created.ToString('dd.MM.yyyy HH:mm') + $(if ($s.Machine) { " · $($s.Machine)" })
            [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
            $b1 = New-IconButton ([string][char]0xE70F) "?ren|$($s.Path)" 'Переименовать'
            $b2 = New-IconButton ([string][char]0xE74D) "?del|$($s.Path)" 'Удалить'
            [Windows.Controls.Grid]::SetColumn($b1, 1); [Windows.Controls.Grid]::SetColumn($b2, 2)
            $b1.Margin = '8,0,0,0'
            [void]$g.Children.Add($sp); [void]$g.Children.Add($b1); [void]$g.Children.Add($b2)
            $mi.Header = $g
            [void]$m.Items.Add($mi)
        }
        [void]$m.Items.Add((New-Object Windows.Controls.Separator))
        foreach ($p in @(@('Сохранить текущее…   Ctrl+S', '?save'), @('Открыть файл…', '?open'))) {
            $mi = New-Object Windows.Controls.MenuItem
            $mi.Header = $p[0]; $mi.Tag = $p[1]
            [void]$m.Items.Add($mi)
        }
    }

    # --- Мои данные ---
    function Update-ConfigAvail {
        $on = Test-PbDataConnected
        foreach ($it in $items) {
            if (-not ($it.HasConfig -and $it.ConfigFile)) { continue }
            $ok = [bool](Find-PbConfig $it.ConfigFile)
            $it.ConfigAvailable = $ok
            $it.ConfigHint = if ($ok) { '' }
                elseif ($on) { "В Моих данных нет configs\$($it.ConfigFile). Сними настройки на настроенном ПК инструментом из tools\ и отправь в свою репу." }
                else { 'Своих настроек на этом ПК нет: подключи Мои данные (слева внизу) — и вариант станет доступен.' }
        }
    }

    # кнопка справа (⋯, …) или отдельной строкой на всю ширину («Подключить», «Отмена»)
    function Set-DataBtnWide ([bool]$Wide) {
        [Windows.Controls.Grid]::SetRow($ctl.DataBtn, [int]$Wide)
        [Windows.Controls.Grid]::SetColumn($ctl.DataBtn, $(if ($Wide) { 0 } else { 2 }))
        [Windows.Controls.Grid]::SetColumnSpan($ctl.DataBtn, $(if ($Wide) { 3 } else { 1 }))
        $ctl.DataBtn.Margin = if ($Wide) { '0,10,0,0' } else { '8,0,0,0' }
    }

    function Update-DataBox {
        $tone = 'TextMuted'
        Set-DataBtnWide ([bool]($ui.Job -and $ui.Job.Action -eq 'connect') -or -not (Test-PbDataConnected))
        if ($ui.Job) {
            $ctl.DataStatus.Text = if ($ui.Job.Sync.Step) { $ui.Job.Sync.Step } else { 'обмен с GitHub…' }
            $ctl.DataBtn.Content = if ($ui.Job.Action -eq 'connect') { 'Отмена' } else { '…' }
            $ctl.DataBtn.IsEnabled = $ui.Job.Action -eq 'connect'
        } else {
            $st = Get-PbDataState
            $ctl.DataBtn.IsEnabled = $true
            if (-not $st.Connected) {
                $ctl.DataStatus.Text = 'не подключены'
                $ctl.DataBtn.Content = 'Подключить'
                $ctl.DataBtn.ToolTip = 'Войти в GitHub и подключить свою приватную репу: сохранения на всех ПК, свои настройки программ'
            } else {
                $tone = if ($st.Pending) { 'Danger' } else { 'AccentText' }
                $ctl.DataStatus.Text = "подключены$(if ($st.User) { " ($($st.User))" })$(if ($st.Pending) { " · не отправлено: $($st.Pending)" })"
                $g = New-Object Windows.Controls.TextBlock
                $g.Style = $win.FindResource('Glyph'); $g.Text = [string][char]0xE712; $g.FontSize = 14
                $ctl.DataBtn.Content = $g
                $ctl.DataBtn.ToolTip = "Мои данные: $($script:PB.DataRoot)$(if ($st.Repo) { " ← $($st.Repo)" })"
            }
        }
        $ctl.DataStatus.ToolTip = $ctl.DataStatus.Text
        $ctl.DataIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $tone)
    }

    # фоновая работа с GitHub (connect / push) в отдельном runspace: окно не замерзает, ход — через $Sync
    $jobTimer = New-Object Windows.Threading.DispatcherTimer
    $jobTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    function Start-DataJob ([string]$Action) {
        if ($ui.Job) { if ($Action -eq 'push') { $ui.PushAgain = $true }; return }
        $sync = [hashtable]::Synchronized(@{ Step = ''; Code = $null; Url = $null; Pid = $null })
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Root, $DataRoot, $Sync, $Action)
            . (Join-Path $Root 'lib\common.ps1'); . (Join-Path $Root 'lib\data.ps1')
            $script:PB.Root = $Root; $script:PB.DataRoot = $DataRoot
            switch ($Action) { 'connect' { Connect-PbData $Sync } 'push' { Push-PbData } }
        })
        foreach ($a in @($script:PB.Root, $script:PB.DataRoot, $sync, $Action)) { [void]$ps.AddArgument($a) }
        $ui.Job = @{ Ps = $ps; Handle = $ps.BeginInvoke(); Sync = $sync; Action = $Action }
        $jobTimer.Start()
        Update-DataBox
    }

    function Complete-DataJob ($Job, $Result, [string]$Err) {
        $ctl.DataLogin.Visibility = 'Collapsed'; $ui.CodeShown = $null
        if ($Job.Action -eq 'push') {
            if (-not $Err -and @($Result)[-1] -eq $true) { $ctl.NoticeText.Text = $ctl.NoticeText.Text -replace ', отправляю в GitHub…$', ' и отправлено в GitHub.' -replace '^Обмениваюсь с GitHub…$', 'Мои данные синхронизированы с GitHub.' }
            else { Show-Notice 'Нет связи с GitHub: всё записано в Мои данные на этом ПК и уйдёт при следующем запуске.' 'warn' }
            Update-DataBox
            if ($ui.PushAgain) { $ui.PushAgain = $false; Start-DataJob 'push' }
            return
        }
        Update-DataBox
        if ($Err) { [void](Show-UiMessage -Owner $win -Title 'Мои данные не подключились' -Lines @(@{ Text = $Err; Tone = 'muted' })); return }
        Update-ConfigAvail
        $login = @($Result)[-1]
        Show-Notice "Мои данные подключены: $login → $($script:PB.DataRoot)."
        $local = @(Get-PbSaves -LocalOnly)
        if (-not $local.Count) { return }
        $names = ($local | ForEach-Object { "• $($_.Name)" }) -join "`n"
        $ok = Show-UiMessage -Owner $win -Title 'Перенести сохранения?' -Primary 'Перенести' -Secondary 'Оставить' -Lines @(
            "На этом ПК есть сохранения, сделанные без входа: $($local.Count).", $names,
            @{ Text = 'Перенесу в Мои данные и отправлю в GitHub; совпадёт имя — добавлю номер, ничего не пропадёт.'; Tone = 'muted'; Gap = $true })
        if (-not $ok) { return }
        try { $n = Move-PbLocalSaves; Show-Notice "Перенесено в Мои данные: $n, отправляю в GitHub…"; Start-DataJob 'push' }
        catch { [void](Show-UiMessage -Owner $win -Title 'Не перенеслось' -Lines @(@{ Text = $_.Exception.Message; Tone = 'muted' })) }
    }

    $jobTimer.add_Tick({
        $j = $ui.Job
        if (-not $j) { $jobTimer.Stop(); return }
        # вход в GitHub: показать код и один раз открыть страницу
        if ($j.Sync.Code -and $ui.CodeShown -ne $j.Sync.Code) {
            $ui.CodeShown = $j.Sync.Code
            $ctl.DataCode.Text = $j.Sync.Code; $ctl.DataLogin.Visibility = 'Visible'
            try { [Windows.Clipboard]::SetText($j.Sync.Code) } catch { }
            if ($j.Sync.Url) { Start-Process $j.Sync.Url }
        }
        if (-not $j.Handle.IsCompleted) { Update-DataBox; return }
        $jobTimer.Stop()
        $res = $null; $err = $null
        try { $res = $j.Ps.EndInvoke($j.Handle) }
        catch { $err = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message } }
        $j.Ps.Dispose(); $ui.Job = $null
        Complete-DataJob $j $res $err
    })

    function Connect-Data {
        $ok = Show-UiMessage -Owner $win -Title 'Подключить Мои данные?' -Primary 'Подключить' -Secondary 'Отмена' -Lines @(
            'Откроется вход в GitHub в браузере — по одноразовому коду.',
            "Мои данные — твоя приватная репа pc-base-private на GitHub (нет — создам) с клоном в $($script:PB.DataRoot): сохранения на всех ПК и свои настройки программ.",
            @{ Text = 'Без входа всё работает и так. Уйти с чужого ПК чисто — «Отключить и стереть с этого ПК».'; Tone = 'muted'; Gap = $true })
        if ($ok) { Start-DataJob 'connect' }
    }

    function Disconnect-Data {
        if (Test-DataBusy) { return }
        $st = Get-PbDataState
        $lines = @('С этого ПК сотрётся:') + @(Get-PbEraseList | ForEach-Object { "• $_" })
        if ($st.Pending) { $lines += @{ Text = "Не отправлено в GitHub: $($st.Pending) — пропадёт. Сначала «Отправить сейчас»."; Tone = 'danger'; Gap = $true } }
        $lines += @{ Text = 'На GitHub ничего не удаляется: на другом ПК подключишься снова.'; Tone = 'muted'; Gap = $true }
        if (-not (Show-UiMessage -Owner $win -Title 'Отключить и стереть с этого ПК?' -Lines $lines -Primary 'Стереть' -Secondary 'Назад' -SafeDefault)) { return }
        $fail = @(Disconnect-PbData)
        Update-ConfigAvail; Update-DataBox
        if ($ui.SaveName -and -not @(Get-PbSaves | Where-Object { $_.Name -eq $ui.SaveName }).Count) { Set-SaveName $null }
        if ($fail.Count) { Show-Notice ('Стёрто не всё: ' + ($fail -join '; ')) 'warn' } else { Show-Notice 'Мои данные отключены, вход в GitHub и токены с этого ПК стёрты.' }
    }

    function Update-OkBtn {
        if ($ctl.ModeApply.IsChecked) {
            $ctl.OkBtn.Content = 'Применить'
            $ctl.OkBtn.Style = $win.FindResource('AccentButton')
        } else {
            $ctl.OkBtn.Content = 'Показать план'
            $ctl.OkBtn.ClearValue([Windows.FrameworkElement]::StyleProperty)
        }
    }

    # --- события ---
    $onChange = {
        param($s, $e)
        if ($ui.Bulk) { return }
        if ($e.PropertyName -eq 'IsChecked' -or $e.PropertyName -eq 'ConfigOn') { Update-Counts }
    }
    foreach ($it in $items) { $it.add_PropertyChanged($onChange) }

    $onNav = {
        param($s)
        if ($ui.Busy) { return }
        $e = $s.SelectedItem
        if (-not $e -or ($e.Kind -ne 'cat' -and $e.Kind -ne 'summary')) { return }
        Set-NavMark $e
        $pick = $null
        if ($ui.Mode -eq 'search') {
            # из поиска — в категорию: поиск сбрасывается, выделяется первое совпадение в ней
            foreach ($it in $items) { if ($it.CatKey -eq $e.Key -and (Test-Search $it)) { $pick = $it; break } }
            $ui.Busy = $true; $ctl.Search.Text = ''; $ui.Busy = $false
            $ui.Words = @()
        }
        Open-Nav $e
        if ($pick) { $ctl.List.SelectedItem = $pick; $ctl.List.ScrollIntoView($pick) }
    }
    $ctl.Nav.add_SelectionChanged($onNav)
    $ctl.NavBottom.add_SelectionChanged($onNav)

    $ctl.Search.add_TextChanged({
        $ctl.SearchClear.Visibility = if ($ctl.Search.Text) { 'Visible' } else { 'Collapsed' }
        $ctl.SearchKey.Visibility = if ($ctl.Search.Text) { 'Collapsed' } else { 'Visible' }
        if ($ui.Busy) { return }
        $f = $ctl.Search.Text.Trim()
        if ($f) {
            $ui.Words = @($f -split '\s+' | Where-Object { $_ })
            if ($ui.Mode -ne 'search') { $ui.Mode = 'search'; Set-NavMark $null }
        } elseif ($ui.Mode -eq 'search') {
            $ui.Words = @()
            $ui.Mode = if ($ui.Nav.Kind -eq 'summary') { 'summary' } else { 'cat' }
            Set-NavMark $ui.Nav
        }
        Update-NavHits
        Update-View
    })
    $ctl.SearchClear.add_Click({ $ctl.Search.Text = ''; [void]$ctl.Search.Focus() })

    $ctl.List.add_SelectionChanged({
        $it = $ctl.List.SelectedItem
        if ($it) {
            $ctl.Detail.DataContext = $it
            if ($it.HasConfig -and $it.ConfigName) { $ctl.RbMineText.Text = $it.ConfigName.Substring(0, 1).ToUpper() + $it.ConfigName.Substring(1) }
            $ctl.Detail.Visibility = 'Visible'; $ctl.DetailHint.Visibility = 'Collapsed'
        } else {
            $ctl.Detail.Visibility = 'Collapsed'; $ctl.DetailHint.Visibility = 'Visible'
        }
    })
    # значок ⚙ в карточке переключает вариант установки
    $ctl.List.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $b = $e.OriginalSource
        if ($b -is [Windows.Controls.Button] -and $b.Tag -eq 'cfg') {
            $it = $b.DataContext
            if (-not $it.ConfigAvailable) { $ctl.List.SelectedItem = $it; $e.Handled = $true; return }
            $it.ConfigOn = -not $it.ConfigOn
            $ctl.List.SelectedItem = $it
            $e.Handled = $true
        }
    })
    $ctl.List.add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq 'Space' -and $ctl.List.SelectedItem) {
            $ctl.List.SelectedItem.IsChecked = -not $ctl.List.SelectedItem.IsChecked
            $e.Handled = $true
        }
    })

    $ctl.CatAll.add_Click({ Set-Checked @($items | Where-Object { $_.CatKey -eq $ui.Cat }) $true })
    $ctl.CatNone.add_Click({ Set-Checked @($items | Where-Object { $_.CatKey -eq $ui.Cat }) $false })

    $ctl.SetBtn.add_ContextMenuOpening({ Fill-SaveMenu })
    $ctl.SetBtn.add_Click({
        Fill-SaveMenu
        $ctl.SetBtn.ContextMenu.PlacementTarget = $ctl.SetBtn
        $ctl.SetBtn.ContextMenu.IsOpen = $true
    })
    $ctl.SetBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $tag = [string]$e.Source.Tag
        if (-not $tag) { return }
        if ($tag -eq '?save') { Save-Current }
        elseif ($tag -eq '?open') {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Сохранение pc-base (*.json)|*.json'
            $d = Get-PbSaveDir; if (Test-Path $d) { $dlg.InitialDirectory = $d }
            if ($dlg.ShowDialog($win)) { Import-Save $dlg.FileName }
        } else { Import-Save $tag }
    })
    # значки «переименовать» / «удалить» внутри пункта меню
    $ctl.SetBtn.ContextMenu.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $tag = [string]$e.OriginalSource.Tag
        if ($tag -notmatch '^\?(ren|del)\|(.+)$') { return }
        $e.Handled = $true
        $act = $Matches[1]; $path = $Matches[2]
        $ctl.SetBtn.ContextMenu.IsOpen = $false
        if ($act -eq 'ren') { Rename-Save $path } else { Remove-Save $path }
    })
    $ctl.SaveBtn.add_Click({ Save-Current })
    $ctl.NoticeClose.add_Click({ $ctl.Notice.Visibility = 'Collapsed' })

    $ctl.DataBtn.add_Click({
        if ($ui.Job -and $ui.Job.Action -eq 'connect') {
            if ($ui.Job.Sync.Pid) { Stop-Process -Id $ui.Job.Sync.Pid -Force -ErrorAction SilentlyContinue }
            return
        }
        if (-not (Test-PbDataConnected)) { Connect-Data; return }
        $m = $ctl.DataBtn.ContextMenu
        $m.Items.Clear()
        $st = Get-PbDataState
        $acts = @()
        if ($st.Pending) { $acts += , @("Отправить сейчас (не отправлено: $($st.Pending))", 'push') } else { $acts += , @('Обновить из GitHub', 'push') }
        $acts += , @("Открыть папку $($script:PB.DataRoot)", 'open')
        $acts += , @('Отключить и стереть с этого ПК…', 'erase')
        foreach ($p in $acts) { $mi = New-Object Windows.Controls.MenuItem; $mi.Header = $p[0]; $mi.Tag = $p[1]; [void]$m.Items.Add($mi) }
        $m.PlacementTarget = $ctl.DataBtn
        $m.IsOpen = $true
    })
    $ctl.DataBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        switch ([string]$e.Source.Tag) {
            'push'  { Show-Notice 'Обмениваюсь с GitHub…'; Start-DataJob 'push' }
            'open'  { Start-Process explorer.exe $script:PB.DataRoot }
            'erase' { Disconnect-Data }
        }
    })
    $ctl.DataOpen.add_Click({ if ($ui.Job -and $ui.Job.Sync.Url) { Start-Process $ui.Job.Sync.Url } })

    # перетащил .json на окно — открыть как сохранение
    $win.AllowDrop = $true
    $win.add_PreviewDragOver({
        param($s, $e)
        $f = @($e.Data.GetData([Windows.DataFormats]::FileDrop))
        $e.Effects = if ($f.Count -eq 1 -and $f[0] -like '*.json') { 'Copy' } else { 'None' }
        $e.Handled = $true
    })
    $win.add_PreviewDrop({
        param($s, $e)
        $f = @($e.Data.GetData([Windows.DataFormats]::FileDrop))
        if ($f.Count -eq 1 -and $f[0] -like '*.json') { $e.Handled = $true; Import-Save $f[0] }
    })
    $win.add_Closed({ if ($ui.Job -and $ui.Job.Sync.Pid) { Stop-Process -Id $ui.Job.Sync.Pid -Force -ErrorAction SilentlyContinue } })

    # в домене имя не трогаем (Rename-Computer требует доменную учётку) — вместо поля просто текст
    if ($IsDomain) {
        $ctl.PcNameCur.Text = $env:COMPUTERNAME
        $ctl.PcNameFixed.Visibility = 'Visible'
        $ctl.PcNameLabel.Visibility = 'Collapsed'; $ctl.PcName.Visibility = 'Collapsed'
    }
    $ctl.PcName.add_TextChanged({ $ctl.PcName.ClearValue([Windows.Controls.Control]::BorderBrushProperty) })

    $ctl.ModePlan.IsChecked = $DryRun
    $ctl.ModeApply.IsChecked = -not $DryRun
    $ctl.ModePlan.add_Checked({ Update-OkBtn })
    $ctl.ModeApply.add_Checked({ Update-OkBtn })

    $ctl.OkBtn.add_Click({
        $name = if ($IsDomain) { '' } else { $ctl.PcName.Text.Trim() }
        if ($name -and ($name -notmatch '^[A-Za-z0-9-]{1,15}$' -or $name -match '^\d+$')) {
            $ctl.PcName.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Danger')
            [void](Show-UiMessage -Owner $win -Title 'Имя ПК не подходит' -Lines @('Латиница, цифры и дефис, до 15 символов, не одни цифры. Пусто — имя не трогать.'))
            [void]$ctl.PcName.Focus()
            return
        }
        $c = Get-Chosen
        if (-not $c.Apps.Count -and -not $c.Tweaks.Count -and -not $c.Files.Count -and -not $c.FilesAsk -and -not $name) {
            [void](Show-UiMessage -Owner $win -Title 'Ничего не выбрано' -Lines @('Отметь хотя бы одну программу, настройку или файл — или впиши новое имя ПК.'))
            return
        }
        if ($ctl.ModeApply.IsChecked) {
            $irr = @($Tweaks | Where-Object { $_.Irreversible -and $c.Tweaks -contains $_.Id }).Count
            $lines = @("Программ: $($c.Apps.Count)$(if ($c.Configs.Count) { ", из них с моими настройками: $($c.Configs.Count)" })",
                "Настроек Windows: $($c.Tweaks.Count)")
            if ($irr) { $lines += @{ Text = "Необратимых: $irr — откат только точкой восстановления"; Tone = 'danger' } }
            if ($c.Files.Count) { $lines += "Файлов с Диска: $($c.Files.Count)" } elseif ($c.FilesAsk) { $lines += 'Файлы с Диска: выбрать во время прогона' }
            $lines += if ($name) { "Имя ПК: $env:COMPUTERNAME → $($name.ToUpper())" } else { "Имя ПК: $env:COMPUTERNAME, не меняется" }
            $lines += @{ Text = 'Это боевой прогон: изменения применятся сразу. Перед ними создаётся точка восстановления, откат — undo.ps1.'; Tone = 'muted'; Gap = $true }
            if (-not (Show-UiMessage -Owner $win -Title "Применить к $($env:COMPUTERNAME)?" -Lines $lines -Primary 'Применить' -Secondary 'Назад' -SafeDefault)) { return }
        }
        $ui.Result = $c; $ui.Name = $name
        $win.DialogResult = $true
    })

    # горячие клавиши: Ctrl+F — поиск, Esc — очистить его, Ctrl+1/2/3 — разделы
    $win.add_PreviewKeyDown({
        param($s, $e)
        $ctrl = [Windows.Input.Keyboard]::Modifiers -eq [Windows.Input.ModifierKeys]::Control
        if ($ctrl -and $e.Key -eq 'F') { [void]$ctl.Search.Focus(); $ctl.Search.SelectAll(); $e.Handled = $true; return }
        if ($ctrl -and $e.Key -eq 'S') { $e.Handled = $true; Save-Current; return }
        if ($e.Key -eq 'Escape' -and $ctl.Search.Text) { $ctl.Search.Text = ''; $e.Handled = $true; return }
        if ($ctrl) {
            $sec = switch ($e.Key) { { $_ -in 'D1', 'NumPad1' } { 'apps' } { $_ -in 'D2', 'NumPad2' } { 'tweaks' } { $_ -in 'D3', 'NumPad3' } { 'files' } }
            if ($sec -and $first[$sec]) { Select-Nav $first[$sec]; $e.Handled = $true }
        }
    })

    # --- старт ---
    $ctl.Nav.ItemsSource = $nav
    $ctl.NavBottom.ItemsSource = $navBottom
    $ctl.List.ItemsSource = $items
    Update-ConfigAvail
    Update-Counts
    Update-DataBox
    if ($Initial) {
        $miss = Set-Selection $Initial
        Set-SaveName $Initial.Name
        if ($miss) { Show-Notice "Открыто «$($Initial.Name)». Пропущено пунктов, которых нет в каталоге этого ПК: $miss." 'warn' }
    }
    Update-OkBtn
    $start = $first['apps']; if (-not $start) { $start = @($cats.Values)[0] }
    $ctl.Nav.SelectedItem = $start
    $win.add_ContentRendered({ Select-Nav $ctl.Nav.SelectedItem })

    if (-not $win.ShowDialog()) { return $null }

    $out = $ui.Result
    $out.Name = if ($ui.Name) { $ui.Name.ToUpper() } else { $null }
    $out.DryRun = [bool]$ctl.ModePlan.IsChecked
    return $out
}
