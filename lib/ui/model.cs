// pc-base: модель окна выбора для WPF-привязок. Подключается из lib\gui.ps1 через Add-Type.
// C# 5 (компилятор .NET Framework 4.8, что есть в Windows PowerShell 5.1): без =>, ?., $"" и т.п.
// Правила выбора живут здесь, в сеттерах, чтобы их не обходила ни одна кнопка окна:
//   снял программу — сбросился вариант «с моими настройками»; выбрал «с моими» — программа отметилась.

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PcBase
{
    public class Bindable : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise(string name)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }

    // строка блока «подробности» справа: подпись, значение, тон (''/accent/danger)
    public class Fact
    {
        public string Label { get; set; }
        public string Value { get; set; }
        public string Tone { get; set; }
    }

    // пункт каталога: программа (app), настройка (tweak), файл с Диска (file), «выбрать при прогоне» (ask)
    public class Item : Bindable
    {
        public Item() { Facts = new List<Fact>(); }

        public string Key { get; set; }          // app:<id>, tweak:<id>, file:<имя>, files:ask
        public string Kind { get; set; }
        public string Id { get; set; }
        public string Name { get; set; }
        public string Desc { get; set; }         // одна строка в карточке
        public string FullDesc { get; set; }     // полный текст справа
        public string CatKey { get; set; }       // apps|Повседневное
        public string CatName { get; set; }
        public string GroupTitle { get; set; }   // «Программы · Повседневное» — заголовок группы в поиске и в «Итоге»
        public string SearchText { get; set; }
        public bool Interactive { get; set; }
        public bool Irreversible { get; set; }
        public bool IsWeb { get; set; }
        public bool HasConfig { get; set; }
        // файл настроек нашёлся (в своих данных или в движке); нет — «с моими» не включается
        private bool _cfgAvail = true;
        public bool ConfigAvailable
        {
            get { return _cfgAvail; }
            set { if (_cfgAvail == value) return; _cfgAvail = value; if (!value) ConfigOn = false; Raise("ConfigAvailable"); }
        }
        private string _cfgHint;                 // почему «с моими» недоступно
        public string ConfigHint { get { return _cfgHint; } set { _cfgHint = value; Raise("ConfigHint"); } }
        public string ConfigFile { get; set; }   // файл настроек внутри configs\ — чтобы перепроверить после входа
        public string ConfigName { get; set; }
        public string ConfigDesc { get; set; }
        public List<Fact> Facts { get; private set; }

        private bool _checked;
        public bool IsChecked
        {
            get { return _checked; }
            set
            {
                if (_checked == value) return;
                _checked = value;
                if (!value && _config) { _config = false; Raise("ConfigOn"); Raise("ConfigOff"); }
                Raise("IsChecked");
            }
        }

        private bool _config;
        public bool ConfigOn
        {
            get { return _config; }
            set
            {
                if (!HasConfig || !_cfgAvail) value = false;
                if (_config == value) return;
                _config = value;
                Raise("ConfigOn"); Raise("ConfigOff");
                if (value) IsChecked = true;
            }
        }
        public bool ConfigOff
        {
            get { return !_config; }
            set { ConfigOn = !value; }
        }
    }

    // строка навигации слева: заголовок раздела (header), категория (cat), разделитель (sep), «Итог» (summary)
    public class NavEntry : Bindable
    {
        public string Key { get; set; }
        public string Kind { get; set; }
        public string Section { get; set; }
        public string Name { get; set; }

        private string _count = "";
        public string CountText { get { return _count; } set { if (_count != value) { _count = value; Raise("CountText"); } } }

        private bool _full;
        public bool IsFull { get { return _full; } set { if (_full != value) { _full = value; Raise("IsFull"); } } }

        private bool _dim;
        public bool IsDim { get { return _dim; } set { if (_dim != value) { _dim = value; Raise("IsDim"); } } }

        private bool _hit;
        public bool IsHit { get { return _hit; } set { if (_hit != value) { _hit = value; Raise("IsHit"); } } }
    }

    public static class Native
    {
        [DllImport("shcore.dll")]
        private static extern int SetProcessDpiAwareness(int value);
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        // своя группа на панели задач: без этого окно садится в группу powershell.exe и берёт его значок
        public static void SetAppId(string appId)
        {
            try { SetCurrentProcessExplicitAppUserModelID(appId); } catch (Exception) { }
        }

        // до первого окна WPF: иначе на 125–150 % Windows растягивает картинку и она мылится
        public static void EnableDpiAwareness()
        {
            try { if (SetProcessDpiAwareness(2) == 0) return; } catch (Exception) { }
            try { SetProcessDPIAware(); } catch (Exception) { }
        }

        // тёмный заголовок окна (Windows 10 20H1+ и 11); на старых сборках молча ничего не делает
        public static void SetDarkTitleBar(IntPtr hwnd, bool dark)
        {
            int v = dark ? 1 : 0;
            try { if (DwmSetWindowAttribute(hwnd, 20, ref v, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref v, 4); } catch (Exception) { }
        }
    }
}
