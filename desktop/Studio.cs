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
using System.Windows.Input;
using System.Windows.Controls.Primitives;
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
        readonly TextBlock projectName = new TextBlock();
        readonly TextBlock connectionBadge = new TextBlock();
        readonly ComboBox layoutPicker = new ComboBox();
        readonly GridSplitter splitter = new GridSplitter();
        Button runButton;
        double splitRatio = 0.54;
        bool changingLayout;
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
            Width = Math.Min(1560, SystemParameters.WorkArea.Width - 40);
            Height = Math.Min(960, SystemParameters.WorkArea.Height - 40);
            MinWidth = 1100; MinHeight = 700;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Microsoft JhengHei UI, Segoe UI");
            Background = Brush("#101e31");
            var buttonStyle = new Style(typeof(Button));
            var template = new ControlTemplate(typeof(Button));
            var chrome = new FrameworkElementFactory(typeof(Border));
            chrome.Name = "Chrome";
            chrome.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
            chrome.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.TemplatedParent) });
            var label = new FrameworkElementFactory(typeof(ContentPresenter));
            label.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            label.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            label.SetBinding(ContentPresenter.MarginProperty, new System.Windows.Data.Binding("Padding") { RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.TemplatedParent) });
            chrome.AppendChild(label); template.VisualTree = chrome;
            var hover = new Trigger { Property = IsMouseOverProperty, Value = true };
            hover.Setters.Add(new Setter(OpacityProperty, 0.83, "Chrome")); template.Triggers.Add(hover);
            var disabled = new Trigger { Property = IsEnabledProperty, Value = false };
            disabled.Setters.Add(new Setter(OpacityProperty, 0.4, "Chrome")); template.Triggers.Add(disabled);
            buttonStyle.Setters.Add(new Setter(TemplateProperty, template));
            Resources.Add(typeof(Button), buttonStyle);
            var shell = new DockPanel { LastChildFill = true }; Content = shell;
            var heading = new DockPanel { Margin = new Thickness(18, 12, 18, 8) };
            DockPanel.SetDock(heading, Dock.Top); shell.Children.Add(heading);
            var brand = new TextBlock { Text = "MARC  無人機工作室", Foreground = Brushes.White, FontSize = 20, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 24, 0) };
            DockPanel.SetDock(brand, Dock.Left); heading.Children.Add(brand);
            connectionBadge.Foreground = Brush("#8ba4b9"); connectionBadge.FontSize = 13;
            connectionBadge.Text = "● 正在啟動"; connectionBadge.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(connectionBadge, Dock.Right); heading.Children.Add(connectionBadge);
            projectName.Foreground = Brush("#bed0df"); projectName.FontSize = 14;
            projectName.TextTrimming = TextTrimming.CharacterEllipsis; projectName.VerticalAlignment = VerticalAlignment.Center;
            heading.Children.Add(projectName);
            var toolbar = new DockPanel { Margin = new Thickness(14, 0, 14, 10) };
            DockPanel.SetDock(toolbar, Dock.Top); shell.Children.Add(toolbar);
            var viewTools = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(viewTools, Dock.Right); toolbar.Children.Add(viewTools);
            viewTools.Children.Add(new TextBlock { Text = "工作區", Foreground = Brush("#8ba4b9"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8,0,8,0) });
            layoutPicker.Width = 120; layoutPicker.FontSize = 13; layoutPicker.VerticalContentAlignment = VerticalAlignment.Center; layoutPicker.Height = 32;
            foreach (var name in new [] { "積木＋場地", "專心編程", "全場飛行" }) layoutPicker.Items.Add(name);
            layoutPicker.SelectedIndex = 0;
            layoutPicker.SelectionChanged += (s, e) => { if (!changingLayout) SetLayout(new [] { "split", "code", "flight" }[layoutPicker.SelectedIndex]); };
            viewTools.Children.Add(layoutPicker);
            var tools = new WrapPanel(); toolbar.Children.Add(tools);
            runButton = AddButton(tools, "▶ 執行", async () => await Execute("window.marcStudio.run();"), true, "#117f76", "執行積木程式 · 編程區 F5");
            runButton.MinWidth = 76;
            AddButton(tools, "■ 停止", async () => { await Execute("window.marcVM.stopAll();"); SetStatus("已停止程式；飛機保持目前位置。可重置後再次試飛。"); }, true, "#933f52", "停止程式並懸停 · 編程區 Shift+F5");
            AddButton(tools, "↺ 重置", async () => await Execute("window.marcStudio.reset();"), true, null, "返回停機坪並復原道具，保留積木 · Ctrl+R");
            AddDivider(tools);
            AddButton(tools, "開啟", async () => await OpenProject(), true, null, "開啟 .sb3 程式 · Ctrl+O");
            AddButton(tools, "儲存", async () => await Execute("window.marcStudio.save();"), true, null, "儲存 .sb3 程式 · Ctrl+S");
            AddDivider(tools);
            AddButton(tools, "遙控器", async () => { EnsureFlightVisible(); await Execute("window.marcStudio.openControllerSettings();"); }, true, null, "控制來源、搖桿模式與裝置校正");
            AddButton(tools, "手機遙控", async () => { EnsureFlightVisible(); await Execute("window.marcStudio.openControllerSettings('phone');"); }, true, null, "掃描 QR Code，以手機虛擬搖桿飛行");
            AddButton(tools, "操作說明", () => { MessageBox.Show(this, "1. 在左側選擇範例，或拖曳無人機積木。\n2. 按「執行」觀察右側飛機；「停止」取消程式並懸停。\n3. 按「重置」返回停機坪，積木保留。\n4. 按「儲存」保留 .sb3 程式。\n\n手機遙控：手機與電腦使用同一 Wi-Fi，掃描 QR Code，關閉設定後將手機橫放。\n\n工作區中央可拖曳調整比例；右上方可切換編程或飛行。\n場地：拖曳旋轉、滾輪縮放、C 切換視角。\n編程區快捷鍵：F5 執行、Shift+F5 停止、Ctrl+R 重置、Ctrl+S 儲存、Ctrl+O 開啟。", "工作室操作說明"); return Task.FromResult(0); }, false, null, "入門步驟與快捷鍵");
            var footer = new Border { Background = Brush("#0c1727"), Padding = new Thickness(18, 8, 18, 8) };
            status.Text = "正在準備模擬場地與無人機積木…";
            status.Foreground = Brush("#a8c0d2"); status.FontSize = 12;
            status.TextTrimming = TextTrimming.CharacterEllipsis;
            footer.Child = status; DockPanel.SetDock(footer, Dock.Bottom); shell.Children.Add(footer);
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(splitRatio, GridUnitType.Star), MinWidth = 340 });
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1-splitRatio, GridUnitType.Star), MinWidth = 360 });
            shell.Children.Add(workspace);
            workspace.Children.Add(editor); Grid.SetColumn(editor, 0);
            splitter.Width = 8; splitter.HorizontalAlignment = HorizontalAlignment.Stretch; splitter.Background = Brush("#20364b"); splitter.ResizeBehavior = GridResizeBehavior.PreviousAndNext;
            splitter.ToolTip = "拖曳調整編程與場地比例";
            splitter.DragCompleted += (s,e) => { if (layout == "split") RememberSplit(); };
            workspace.Children.Add(splitter); Grid.SetColumn(splitter, 1);
            viewport.BackColor = System.Drawing.Color.FromArgb(16, 30, 49);
            flightHost.Child = viewport; workspace.Children.Add(flightHost); Grid.SetColumn(flightHost, 2);
            viewport.SizeChanged += (s,e) => ResizeGame();
            PreviewKeyDown += OnShortcut;
            LoadPreferences(); UpdateTitle();
            Loaded += async (s, e) => { try { await StartEngine(); } catch (Exception ex) { ShowError(ex.Message); } };
            Closing += OnClosing;
            Closed += (s, e) => { SavePreferences(); resizeTimer.Stop(); editor.Dispose(); StopEngine(); };
            resizeTimer.Interval = TimeSpan.FromMilliseconds(80);
            resizeTimer.Tick += (s, e) => ResizeGame();
            resizeTimer.Start();
        }
        static SolidColorBrush Brush(string color) { return (SolidColorBrush)new BrushConverter().ConvertFromString(color); }
        Button AddButton(Panel parent, string text, Func<Task> action, bool requiresEditor, string color, string hint) {
            var button = new Button { Content = text, Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(3,0,3,0), Background = Brush(color ?? "#243c53"), Foreground = Brushes.White, BorderThickness = new Thickness(0), FontSize = 13, ToolTip = hint, Cursor = Cursors.Hand, IsEnabled = !requiresEditor };
            if (requiresEditor) editorButtons.Add(button);
            button.Click += async (s, e) => { try { await action(); } catch (Exception ex) { ShowError(ex.Message); } };
            parent.Children.Add(button);
            return button;
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
                            SetStatus("準備完成 · 選擇範例或拖曳積木，按「執行」試飛；可拖曳中央分隔線調整工作區。");
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
                    resizeTimer.Stop();
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
        void AddDivider(Panel parent) { parent.Children.Add(new Border { Width = 1, Height = 22, Background = Brush("#385067"), Margin = new Thickness(8,6,8,6) }); }
        void EnsureFlightVisible() { if (layout == "code") SetLayout("split"); }
        void RememberSplit() {
            var total = workspace.ColumnDefinitions[0].ActualWidth + workspace.ColumnDefinitions[2].ActualWidth;
            if (total > 0) splitRatio = Math.Max(0.25, Math.Min(0.75, workspace.ColumnDefinitions[0].ActualWidth / total));
        }
        void SetLayout(string next) {
            if (layout == "split" && IsLoaded) RememberSplit();
            layout = next;
            editor.Visibility = next == "flight" ? Visibility.Collapsed : Visibility.Visible;
            flightHost.Visibility = next == "code" ? Visibility.Collapsed : Visibility.Visible;
            workspace.ColumnDefinitions[0].MinWidth = next == "split" ? 340 : 0;
            workspace.ColumnDefinitions[2].MinWidth = next == "split" ? 360 : 0;
            workspace.ColumnDefinitions[0].Width = next == "flight" ? new GridLength(0) : new GridLength(next == "code" ? 1 : splitRatio, GridUnitType.Star);
            workspace.ColumnDefinitions[1].Width = new GridLength(next == "split" ? 8 : 0);
            workspace.ColumnDefinitions[2].Width = next == "code" ? new GridLength(0) : new GridLength(next == "flight" ? 1 : 1-splitRatio, GridUnitType.Star);
            splitter.Visibility = next == "split" ? Visibility.Visible : Visibility.Collapsed;
            changingLayout = true; layoutPicker.SelectedIndex = next == "code" ? 1 : next == "flight" ? 2 : 0; changingLayout = false;
            lastWidth = -1; Dispatcher.BeginInvoke(new Action(ResizeGame));
        }
        string PreferencesPath { get { return Path.Combine(root, ".runtime", "studio-ui.json"); } }
        void LoadPreferences() {
            try {
                if (!File.Exists(PreferencesPath)) return;
                var values = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(PreferencesPath));
                splitRatio = Math.Max(0.25, Math.Min(0.75, Convert.ToDouble(values["split"])));
                Width = Math.Max(MinWidth, Math.Min(SystemParameters.WorkArea.Width, Convert.ToDouble(values["width"])));
                Height = Math.Max(MinHeight, Math.Min(SystemParameters.WorkArea.Height, Convert.ToDouble(values["height"])));
                var next = Convert.ToString(values["layout"]);
                SetLayout(next == "code" || next == "flight" ? next : "split");
                if (Convert.ToBoolean(values["maximized"])) WindowState = WindowState.Maximized;
            } catch { /* Invalid preferences fall back to the default workspace. */ }
        }
        void SavePreferences() {
            try {
                if (layout == "split") RememberSplit();
                var bounds = WindowState == WindowState.Normal ? new Rect(0,0,ActualWidth,ActualHeight) : RestoreBounds;
                Directory.CreateDirectory(Path.GetDirectoryName(PreferencesPath));
                File.WriteAllText(PreferencesPath, json.Serialize(new { split = splitRatio, layout, width = bounds.Width, height = bounds.Height, maximized = WindowState == WindowState.Maximized }));
            } catch { }
        }
        async void OnShortcut(object sender, KeyEventArgs e) {
            if (!ready) return;
            string script = null;
            if (e.Key == Key.F5 && Keyboard.Modifiers == ModifierKeys.None) script = "window.marcVM.greenFlag();";
            if (e.Key == Key.F5 && Keyboard.Modifiers == ModifierKeys.Shift) script = "window.marcVM.stopAll();";
            if (Keyboard.Modifiers == ModifierKeys.Control) {
                if (e.Key == Key.S) script = "window.marcStudio.save();";
                if (e.Key == Key.R) script = "window.marcStudio.reset();";
                if (e.Key == Key.O) { e.Handled = true; try { await OpenProject(); } catch (Exception error) { ShowError(error.Message); } return; }
            }
            if (script == null) return;
            e.Handled = true;
            try { await Execute(script); } catch (Exception error) { ShowError(error.Message); }
        }
        void SetStatus(string text) { status.Text = text; status.ToolTip = text; status.Foreground = Brush("#a8c0d2"); }
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
        async void HandleMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e) {
            if (!e.Source.StartsWith(origin + "/", StringComparison.Ordinal)) return;
            try {
                var data = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson);
                var type = Convert.ToString(data["type"]);
                if (type == "shortcut") {
                    var action = Convert.ToString(data["action"]);
                    if (ready) {
                        if (action == "run") await Execute("window.marcStudio.run();");
                        if (action == "stop") await Execute("window.marcVM.stopAll();");
                        if (action == "reset") await Execute("window.marcStudio.reset();");
                        if (action == "save") await Execute("window.marcStudio.save();");
                        if (action == "open") await OpenProject();
                    }
                }
                if (type == "dirty" && !dirty) { dirty = true; UpdateTitle(); }
                if (type == "state") {
                    var connected = Convert.ToBoolean(data["connected"]);
                    var running = Convert.ToBoolean(data["running"]);
                    connectionBadge.Text = !connected ? "● 連線中斷" : running ? "● 程式執行中" : "● 已連線 · 可試飛";
                    connectionBadge.Foreground = Brush(connected ? "#6ed4bc" : "#ffb5b5");
                    runButton.IsEnabled = ready && connected && !running;
                    runButton.Content = running ? "▶ 執行中" : "▶ 執行";
                }
                if (type == "loaded") { dirty = false; UpdateTitle(); }
                if (type == "reset") SetStatus("已重置至停機坪 · 積木程式保留，可再按「執行」試飛。");
                if (type == "error") ShowError(Convert.ToString(data["message"]));
                if (type == "saved") {
                    var dialog = new SaveFileDialog { Filter = "無人機積木程式 (*.sb3)|*.sb3", Title = "儲存無人機程式", FileName = projectFile == null ? "MARC-flight.sb3" : Path.GetFileName(projectFile) };
                    if (projectFile != null) dialog.InitialDirectory = Path.GetDirectoryName(projectFile);
                    if (dialog.ShowDialog(this) != true) { saveThenClose = false; return; }
                    File.WriteAllBytes(dialog.FileName, Convert.FromBase64String(Convert.ToString(data["base64"])));
                    await editor.ExecuteScriptAsync("window.marcStudio.markSaved();");
                    projectFile = dialog.FileName; dirty = false; UpdateTitle(); SetStatus("已儲存：" + projectFile);
                    if (saveThenClose) { closing = true; Close(); }
                }
            } catch (Exception ex) { saveThenClose = false; ShowError(ex.Message); }
        }
        void UpdateTitle() { var name = projectFile == null ? "未命名程式" : Path.GetFileName(projectFile); projectName.Text = name + (dirty ? "  ·  尚未儲存" : ""); Title = (dirty ? "● " : "") + name + " — MARC 無人機編程工作室"; }
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
        void ShowError(string message) { status.Text = message; status.ToolTip = message; status.Foreground = Brush("#ffc7ca"); }
        static string Quote(string value) { return "\"" + value.Replace("\"", "\\\"") + "\""; }
    }
}
