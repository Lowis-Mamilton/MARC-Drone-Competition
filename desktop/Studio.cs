using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Forms.Integration;
using Microsoft.Web.WebView2.Wpf;
using Microsoft.Web.WebView2.Core;
using Microsoft.Win32;
using System.Web.Script.Serialization;
using Forms = System.Windows.Forms;

namespace MarcStudio {
    public class Studio : Window {
        readonly string root;
        readonly WebView2 editor = new WebView2();
        readonly Forms.Panel viewport = new Forms.Panel();
        readonly WindowsFormsHost flightHost = new WindowsFormsHost();
        readonly Grid workspace = new Grid();
        readonly TextBlock status = new TextBlock();
        readonly List<Button> editorButtons = new List<Button>();
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 64 * 1024 * 1024 };
        Process engine;
        IntPtr gameWindow;
        string origin;
        string projectFile;
        bool dirty, ready, closing, saveThenClose, startingWeb, engineStarted, engineReady;
        string layout = "split";
        readonly System.Windows.Threading.DispatcherTimer resizeTimer = new System.Windows.Threading.DispatcherTimer();
        int lastWidth = -1, lastHeight = -1;
        static readonly IntPtr Zero = IntPtr.Zero;
        delegate bool EnumProc(IntPtr hwnd, IntPtr state);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr data);
        [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
        [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr data);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
        [DllImport("user32.dll", SetLastError=true)] static extern bool MoveWindow(IntPtr hwnd, int x, int y, int width, int height, bool repaint);
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        [STAThread] public static void Main(string[] args) {
            SetProcessDPIAware();
            var project = args.Length > 0 ? Path.GetFullPath(args[0]) : Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
            var app = new Application();
            try { app.Run(new Studio(project)); }
            catch (Exception error) { MessageBox.Show(error.ToString(), "MARC 編程工作室"); }
        }
        public Studio(string project) {
            root = project;
            Title = "MARC 無人機編程工作室";
            Width = 1600; Height = 1000; MinWidth = 1200; MinHeight = 760;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = Brush("#102039");
            var shell = new DockPanel { LastChildFill = true };
            Content = shell;
            var toolbar = new WrapPanel { Background = Brush("#102039"), Margin = new Thickness(10, 8, 10, 8) };
            DockPanel.SetDock(toolbar, Dock.Top); shell.Children.Add(toolbar);
            toolbar.Children.Add(new TextBlock { Text = "MARC  無人機編程工作室", Foreground = Brushes.White, FontSize = 20, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 20, 0) });
            AddButton(toolbar, "▶ 執行", async () => await Execute("window.marcVM.greenFlag();"), true, "#167d72");
            AddButton(toolbar, "■ 停止", async () => await Execute("window.marcVM.stopAll();"), true, "#9b3a4c");
            AddButton(toolbar, "↺ 重置", async () => await Execute("window.marcStudio.reset();"), true, null);
            AddButton(toolbar, "開啟 .sb3", async () => await OpenProject(), true, null);
            AddButton(toolbar, "儲存 .sb3", async () => await Execute("window.marcStudio.save();"), true, null);
            AddButton(toolbar, "遙控器設定", async () => { SetLayout("split"); await Execute("window.marcStudio.openControllerSettings();"); }, true, null);
            AddButton(toolbar, "手機遙控", async () => { SetLayout("split"); await Execute("window.marcStudio.openControllerSettings('phone');"); }, true, null);
            AddButton(toolbar, "積木＋場地", () => { SetLayout("split"); return Task.FromResult(0); }, false, null);
            AddButton(toolbar, "專心編程", () => { SetLayout("code"); return Task.FromResult(0); }, false, null);
            AddButton(toolbar, "全場飛行", () => { SetLayout("flight"); return Task.FromResult(0); }, false, null);
            var footer = new Border { Background = Brush("#102039"), Padding = new Thickness(16, 7, 16, 7) };
            status.Text = "正在啟動模擬場地與內建積木編輯器…";
            status.Foreground = Brush("#c1e5ef"); status.FontSize = 13;
            footer.Child = status; DockPanel.SetDock(footer, Dock.Bottom); shell.Children.Add(footer);
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.1, GridUnitType.Star) });
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            shell.Children.Add(workspace);
            workspace.Children.Add(editor); Grid.SetColumn(editor, 0);
            var splitter = new GridSplitter { Width = 6, HorizontalAlignment = HorizontalAlignment.Stretch, Background = Brush("#31526b"), ResizeBehavior = GridResizeBehavior.PreviousAndNext };
            workspace.Children.Add(splitter); Grid.SetColumn(splitter, 1);
            viewport.BackColor = System.Drawing.Color.FromArgb(16, 32, 57);
            flightHost.Child = viewport; workspace.Children.Add(flightHost); Grid.SetColumn(flightHost, 2);
            Loaded += async (s, e) => { try { await StartEngine(); } catch (Exception ex) { ShowError(ex.Message); } };
            Closing += OnClosing;
            Closed += (s, e) => { resizeTimer.Stop(); editor.Dispose(); StopEngine(); };
            resizeTimer.Interval = TimeSpan.FromMilliseconds(80);
            resizeTimer.Tick += (s, e) => ResizeGame();
            resizeTimer.Start();
        }
        static SolidColorBrush Brush(string color) { return (SolidColorBrush)new BrushConverter().ConvertFromString(color); }
        void AddButton(Panel parent, string text, Func<Task> action, bool requiresEditor, string color) {
            var button = new Button { Content = text, Padding = new Thickness(13, 8, 13, 8), Margin = new Thickness(3), Background = Brush(color ?? "#23435c"), Foreground = Brushes.White, BorderThickness = new Thickness(0), FontSize = 14, IsEnabled = !requiresEditor };
            if (requiresEditor) editorButtons.Add(button);
            button.Click += async (s, e) => { try { await action(); } catch (Exception ex) { ShowError(ex.Message); } };
            parent.Children.Add(button);
        }
        async Task StartEngine() {
            if (engineStarted) return;
            engineStarted = true;
            var exe = Path.Combine(root, ".runtime", "engine", "Godot.exe");
            if (!File.Exists(exe)) throw new FileNotFoundException("找不到開發用 Godot 引擎。", exe);
            Directory.CreateDirectory(Path.Combine(root, ".runtime", "logs"));
            var args = "--path " + Quote(root) + " --wid " + viewport.Handle.ToInt64() + " --resolution 700x850 --position 0,0 --log-file " + Quote(Path.Combine(root, ".runtime", "logs", "studio-godot.log")) + " -- --studio-embedded";
            var info = new ProcessStartInfo(exe, args) { WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = false, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            info.EnvironmentVariables["APPDATA"] = Path.Combine(root, ".runtime", "studio-user");
            info.EnvironmentVariables["LOCALAPPDATA"] = Path.Combine(root, ".runtime", "studio-user");
            engine = new Process { StartInfo = info, EnableRaisingEvents = true };
            engine.OutputDataReceived += (s, e) => {
                if (e.Data == null) return;
                var match = Regex.Match(e.Data, @"MARC_SCRATCH_URL=(http://127\.0\.0\.1:\d+)/scratch/");
                if (match.Success) Dispatcher.BeginInvoke(new Action(async () => { engineReady = true; ResizeGame(); await StartEditor(match.Groups[1].Value); }));
            };
            engine.ErrorDataReceived += (s, e) => {
                if (e.Data != null && e.Data.Contains("SCRIPT ERROR")) Dispatcher.BeginInvoke(new Action(() => ShowError(e.Data)));
            };
            engine.Exited += (s, e) => Dispatcher.BeginInvoke(new Action(() => {
                if (!closing) { ready = false; foreach (var b in editorButtons) b.IsEnabled = false; ShowError("模擬場地已關閉，請重新開啟工作室。"); }
            }));
            if (!engine.Start()) throw new Exception("無法啟動模擬場地。");
            engine.BeginOutputReadLine(); engine.BeginErrorReadLine();
            File.AppendAllText(Path.Combine(root, ".runtime", "logs", "studio-native.log"), "START pid=" + engine.Id + " parent=" + viewport.Handle + Environment.NewLine);
            for (int i = 0; i < 100 && gameWindow == Zero; i++) { await Task.Delay(100); ResizeGame(); }
            if (gameWindow == Zero) throw new Exception("無法嵌入模擬場地視窗，請檢查 studio-godot.log。");
        }
        async Task StartEditor(string address) {
            if (startingWeb || closing) return;
            startingWeb = true; origin = address;
            try {
                var options = new CoreWebView2EnvironmentOptions();
                var debugFile = Path.Combine(root, ".runtime", "studio", "cdp-port.txt");
                int debugPort;
                if (File.Exists(debugFile) && Int32.TryParse(File.ReadAllText(debugFile), out debugPort) && debugPort > 1024 && debugPort < 65536) options.AdditionalBrowserArguments = "--remote-debugging-port=" + debugPort;
                var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(root, ".runtime", "studio-webview"), options);
                await editor.EnsureCoreWebView2Async(environment);
                editor.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                editor.CoreWebView2.Settings.IsStatusBarEnabled = false;
                editor.CoreWebView2.NewWindowRequested += (s, e) => { e.Handled = true; };
                editor.CoreWebView2.NavigationStarting += (s, e) => {
                    if (!e.Uri.StartsWith(origin + "/", StringComparison.Ordinal) && e.Uri != "about:blank") e.Cancel = true;
                };
                editor.CoreWebView2.WebMessageReceived += HandleMessage;
                editor.CoreWebView2.NavigationCompleted += async (s, e) => {
                    if (!e.IsSuccess) { ShowError("內建編輯器載入失敗：" + e.WebErrorStatus); return; }
                    for (int i = 0; i < 120 && !closing; i++) {
                        await Task.Delay(250);
                        var result = await editor.ExecuteScriptAsync("Boolean(window.marcReady && window.marcVM && window.marcVM.runtime.targets.length && window.marcConnection && window.marcConnection.connected)");
                        if (result == "true") {
                            ready = true; foreach (var b in editorButtons) b.IsEnabled = true;
                            status.Text = "已連線  ·  左側拖曳積木，按「執行」控制右側飛機  ·  專案可儲存為 .sb3";
                            return;
                        }
                    }
                    if (!closing) ShowError("編輯器連線逾時，請重新開啟工作室。");
                };
                editor.Source = new Uri(origin + "/scratch/?locale=zh-tw&embedded=1");
            } catch (Exception ex) { ShowError("內建編輯器無法啟動：" + ex.Message); }
        }
        void ResizeGame() {
            if (engine == null || engine.HasExited || !engineReady) return;
            if (gameWindow == Zero) {
                EnumProc findWindow = (hwnd, state) => {
                    uint pid; GetWindowThreadProcessId(hwnd, out pid);
                    if (pid == engine.Id) { gameWindow = hwnd; return false; }
                    return true;
                };
                EnumChildWindows(viewport.Handle, findWindow, Zero);
                if (gameWindow == Zero) EnumWindows(findWindow, Zero);
                if (gameWindow != Zero) {
                    long style = GetWindowLongPtr(gameWindow, -16).ToInt64();
                    SetWindowLongPtr(gameWindow, -16, new IntPtr((style & ~0x80CF0000L) | 0x46000000L));
                    var oldParent = SetParent(gameWindow, viewport.Handle);
                    int parentError = Marshal.GetLastWin32Error();
                    File.AppendAllText(Path.Combine(root, ".runtime", "logs", "studio-native.log"), "EMBED hwnd=" + gameWindow + " oldParent=" + oldParent + " currentParent=" + GetParent(gameWindow) + " error=" + parentError + " style=" + style + " size=" + viewport.ClientSize + Environment.NewLine);
                }
            }
            int w = viewport.ClientSize.Width, h = viewport.ClientSize.Height;
            if (gameWindow != Zero && w > 0 && h > 0 && (w != lastWidth || h != lastHeight)) {
                MoveWindow(gameWindow, 0, 0, w, h, true); lastWidth = w; lastHeight = h;
            }
        }
        void SetLayout(string next) {
            layout = next;
            editor.Visibility = next == "flight" ? Visibility.Collapsed : Visibility.Visible;
            flightHost.Visibility = next == "code" ? Visibility.Collapsed : Visibility.Visible;
            workspace.ColumnDefinitions[0].Width = next == "flight" ? new GridLength(0) : new GridLength(next == "code" ? 1 : 1.1, GridUnitType.Star);
            workspace.ColumnDefinitions[1].Width = new GridLength(next == "split" ? 6 : 0);
            workspace.ColumnDefinitions[2].Width = next == "code" ? new GridLength(0) : new GridLength(1, GridUnitType.Star);
            foreach (UIElement child in workspace.Children) if (child is GridSplitter) child.Visibility = next == "split" ? Visibility.Visible : Visibility.Collapsed;
            lastWidth = -1;
        }
        async Task Execute(string script) {
            if (!ready) throw new Exception("積木編輯器尚未準備完成。");
            await editor.ExecuteScriptAsync(script);
        }
        async Task OpenProject() {
            if (dirty && MessageBox.Show(this, "載入將取代目前程式，是否繼續？", "開啟專案", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
            var dialog = new OpenFileDialog { Filter = "無人機積木程式 (*.sb3)|*.sb3", Title = "開啟無人機程式" };
            if (dialog.ShowDialog(this) != true) return;
            var bytes = File.ReadAllBytes(dialog.FileName);
            if (bytes.Length > 20 * 1024 * 1024) throw new Exception("專案檔案超過 20 MB。");
            projectFile = dialog.FileName;
            await Execute("window.marcStudio.load(" + json.Serialize(Convert.ToBase64String(bytes)) + ");");
        }
        void HandleMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e) {
            if (!e.Source.StartsWith(origin + "/", StringComparison.Ordinal)) return;
            try {
                var data = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson);
                var type = Convert.ToString(data["type"]);
                if (type == "dirty") { dirty = true; UpdateTitle(); }
                if (type == "loaded") { dirty = false; UpdateTitle(); }
                if (type == "reset") { status.Text = "已重置至停機坪  ·  積木程式保留，可再次按「執行」試飛"; status.Foreground = Brush("#c1e5ef"); }
                if (type == "error") ShowError(Convert.ToString(data["message"]));
                if (type == "saved") {
                    var dialog = new SaveFileDialog { Filter = "無人機積木程式 (*.sb3)|*.sb3", Title = "儲存無人機程式", FileName = projectFile == null ? "MARC-flight.sb3" : Path.GetFileName(projectFile) };
                    if (projectFile != null) dialog.InitialDirectory = Path.GetDirectoryName(projectFile);
                    if (dialog.ShowDialog(this) != true) { saveThenClose = false; return; }
                    File.WriteAllBytes(dialog.FileName, Convert.FromBase64String(Convert.ToString(data["base64"])));
                    projectFile = dialog.FileName; dirty = false; UpdateTitle(); status.Text = "已儲存：" + projectFile;
                    if (saveThenClose) { closing = true; Close(); }
                }
            } catch (Exception ex) { saveThenClose = false; ShowError(ex.Message); }
        }
        void UpdateTitle() { Title = (dirty ? "● " : "") + (projectFile == null ? "未命名程式" : Path.GetFileName(projectFile)) + " — MARC 無人機編程工作室"; }
        async void OnClosing(object sender, System.ComponentModel.CancelEventArgs e) {
            if (closing) return;
            if (dirty && ready) {
                var answer = MessageBox.Show(this, "關閉前要儲存目前的積木程式嗎？", "尚未儲存", MessageBoxButton.YesNoCancel);
                if (answer == MessageBoxResult.Cancel) { e.Cancel = true; return; }
                if (answer == MessageBoxResult.Yes) { e.Cancel = true; saveThenClose = true; await Execute("window.marcStudio.save();"); return; }
            }
            closing = true;
        }
        void StopEngine() { try { if (engine != null && !engine.HasExited) engine.Kill(); } catch {} }
        void ShowError(string message) { status.Text = message; status.Foreground = Brush("#ffc7ca"); }
        static string Quote(string value) { return "\"" + value.Replace("\"", "\\\"") + "\""; }
    }
}
