# pc-base: окно выбора на WPF (есть в Windows PowerShell 5.1 из коробки, внешних библиотек нет).
# Разметка и стили — lib\ui\*.xaml, модель для привязок — lib\ui\model.cs. WPF нужен STA-поток:
# setup.ps1 перезапускает себя с -STA, если запущен иначе.
#   * слева навигация: Программы / Настройки Windows / Файлы с Диска по категориям со счётчиками, внизу «Итог»
#   * в центре карточки категории; значки ⚙ (есть ConfigFn), мастер, необратимо, сайт видны без клика
#   * справа подробности выделенного; у программ с ConfigFn — «Установка: с моими настройками / чистая»
#   * поиск сверху — сразу по всем разделам; наборы галочек — selections\*.json
#   * тема и акцент — как в Windows
#
# Возвращает @{ Apps; Configs; Tweaks; Files; FilesAsk; Name; DryRun } или $null, если окно закрыли.

$script:PbUiDir = Join-Path $PSScriptRoot 'ui'

function Read-SelectionFile ([string]$Path) {
    $j = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
        Apps     = @($j.Apps | Where-Object { $_ })
        Configs  = @($j.Configs | Where-Object { $_ })
        Tweaks   = @($j.Tweaks | Where-Object { $_ })
        Files    = @($j.Files | Where-Object { $_ })
        FilesAsk = [bool]$j.FilesAsk
    }
}

function Save-SelectionFile ([string]$Path, [hashtable]$Sel) {
    $json = [ordered]@{
        Apps = @($Sel.Apps); Configs = @($Sel.Configs); Tweaks = @($Sel.Tweaks)
        Files = @($Sel.Files); FilesAsk = [bool]$Sel.FilesAsk
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}

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
# Возвращает $true, если нажата главная кнопка.
function Show-UiMessage {
    param($Owner, [string]$Title, $Lines, [string]$Primary = 'Понятно', [string]$Secondary, [switch]$SafeDefault)
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
        [hashtable]$Initial,
        [string]$SelDir,
        [bool]$DryRun = $true,
        [bool]$IsDomain = $false,
        [string]$Title = 'pc-base'
    )

    $theme = Initialize-Ui
    $win = New-UiWindow 'main.xaml' $theme
    $ctl = @{}
    foreach ($n in 'Logo', 'HostChips', 'Search', 'SearchKey', 'SearchClear', 'SetBtn', 'SetBtnText', 'Nav', 'NavBottom', 'ListTitle', 'ListHint', 'CatButtons', 'CatAll', 'CatNone',
        'List', 'ListEmpty', 'DetailHint', 'Detail', 'RbMineText', 'PcNameLabel', 'PcName', 'PcNameFixed', 'PcNameCur', 'ModePlan', 'ModeApply', 'Summary', 'SaveBtn', 'OkBtn') {
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
            $it.HasConfig = [bool]$a.ConfigFn; $it.ConfigName = $a.ConfigName; $it.ConfigDesc = $a.ConfigDesc
            if ($a.ConfigFn -and $a.ConfigFile -and -not (Find-PbConfig $a.ConfigFile)) {
                $it.ConfigAvailable = $false
                $it.ConfigHint = "Нет configs\$($a.ConfigFile) ни в своих данных ($($script:PB.DataRoot)), ни в движке. Подключи свои данные — и вариант станет доступен."
            }
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
    $ui = @{ Mode = 'cat'; Cat = $null; Nav = $null; Words = @(); Busy = $false; Bulk = $false; SetName = $null; Result = $null; Name = $null }
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

    # загрузка набора заменяет текущий выбор целиком
    function Set-Selection ([hashtable]$Sel) {
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
    }

    function Import-Set ([string]$Path) {
        try {
            Set-Selection (Read-SelectionFile $Path)
            $ui.SetName = [IO.Path]::GetFileNameWithoutExtension($Path)
            $ctl.SetBtnText.Text = "Набор: $($ui.SetName)"
        } catch {
            [void](Show-UiMessage -Owner $win -Title 'Набор не читается' -Lines @($Path, @{ Text = $_.Exception.Message; Tone = 'muted' }))
        }
    }

    function Fill-SetMenu {
        $m = $ctl.SetBtn.ContextMenu
        $m.Items.Clear()
        if ($SelDir -and (Test-Path $SelDir)) {
            foreach ($f in (Get-ChildItem $SelDir -Filter *.json | Sort-Object Name)) {
                $mi = New-Object Windows.Controls.MenuItem
                $mi.Header = $f.BaseName; $mi.Tag = $f.FullName
                [void]$m.Items.Add($mi)
            }
        }
        if ($m.Items.Count) { [void]$m.Items.Add((New-Object Windows.Controls.Separator)) }
        $mi = New-Object Windows.Controls.MenuItem
        $mi.Header = 'Открыть файл…'; $mi.Tag = '?open'
        [void]$m.Items.Add($mi)
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

    $ctl.SetBtn.add_ContextMenuOpening({ Fill-SetMenu })
    $ctl.SetBtn.add_Click({
        Fill-SetMenu
        $ctl.SetBtn.ContextMenu.PlacementTarget = $ctl.SetBtn
        $ctl.SetBtn.ContextMenu.IsOpen = $true
    })
    $ctl.SetBtn.ContextMenu.AddHandler([Windows.Controls.MenuItem]::ClickEvent, [Windows.RoutedEventHandler]{
        param($s, $e)
        $tag = [string]$e.OriginalSource.Tag
        if (-not $tag) { return }
        if ($tag -eq '?open') {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = 'Набор pc-base (*.json)|*.json'
            if ($SelDir -and (Test-Path $SelDir)) { $dlg.InitialDirectory = $SelDir }
            if ($dlg.ShowDialog($win)) { Import-Set $dlg.FileName }
        } else { Import-Set $tag }
    })

    $ctl.SaveBtn.add_Click({
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'Набор pc-base (*.json)|*.json'; $dlg.DefaultExt = 'json'
        if ($ui.SetName) { $dlg.FileName = $ui.SetName }
        if ($SelDir) { New-Item -ItemType Directory $SelDir -Force | Out-Null; $dlg.InitialDirectory = $SelDir }
        if ($dlg.ShowDialog($win)) {
            Save-SelectionFile $dlg.FileName (Get-Chosen)
            $ui.SetName = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
            $ctl.SetBtnText.Text = "Набор: $($ui.SetName)"
        }
    })

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
    if ($Initial) { Set-Selection $Initial } else { Update-Counts }
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
