using System.Diagnostics;
using Microsoft.Win32;

namespace ConvertRight;

internal sealed class MainWindow : Form
{
    private readonly ListView files = new() { View = View.Details, FullRowSelect = true, Dock = DockStyle.Fill, AllowDrop = true, BorderStyle = BorderStyle.None, ShowItemToolTips = true };
    private readonly ComboBox format = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(8) };
    private readonly ProgressBar progress = new() { Dock = DockStyle.Bottom, Height = 5 };
    private readonly Button convert = new() { Text = "Convert", AutoSize = true };
    private readonly List<string> paths = [];
    private bool busy;
    private bool paymentBusy;
    private readonly System.Windows.Forms.Timer licenseRefresh = new() { Interval = 2000 };
    private CancellationTokenSource? cancellation;
    private readonly NumericUpDown target = new() { Minimum = 1, Maximum = 100000, Value = 25, Width = 95, AccessibleName = "Target size in MB" };
    private readonly ComboBox resolution = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 125, AccessibleName = "Maximum resolution" };
    private readonly CheckBox mute = new() { Text = "Remove audio", AutoSize = true };
    private readonly Button cancel = new() { Text = "Cancel", AutoSize = true, Enabled = false };

    internal MainWindow()
    {
        Text = "ConvertRight"; Size = new Size(920, 600); MinimumSize = new Size(880, 540);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10); BackColor = Color.FromArgb(244, 246, 249);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 5 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 75));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 85));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 65));
        var title = new Label { Text = "ConvertRight\nDrop audio or video files below. Originals stay unchanged.", AutoSize = true, Font = new Font("Segoe UI", 13), Padding = new Padding(0, 0, 0, 10) };
        var tools = new FlowLayoutPanel { Dock = DockStyle.Fill };
        var add = Button("Add files…", AddFiles);
        var clear = Button("Clear", (_, _) => { if (!busy) { files.Items.Clear(); paths.Clear(); RefreshStatus(); } });
        tools.Controls.AddRange([add, clear]);
        files.Columns.Add("File", 430); files.Columns.Add("Result", 205);
        files.DragEnter += (_, e) => e.Effect = !busy && e.Data?.GetDataPresent(DataFormats.FileDrop) == true ? DragDropEffects.Copy : DragDropEffects.None;
        files.DragDrop += (_, e) => { if (e.Data?.GetData(DataFormats.FileDrop) is string[] incoming) Add(incoming); };
        files.DoubleClick += (_, _) => { if (files.SelectedItems.Count > 0 && files.SelectedItems[0].Tag is string output) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{output}\"") { UseShellExecute = true }); };
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(0, 8, 0, 0) };
        format.Items.AddRange(["MP4", "MP3", "M4A", "WAV"]); format.SelectedIndex = 0;
        resolution.Items.AddRange(["Max 1080p", "Max 720p", "Original"]); resolution.SelectedIndex = 0;
        format.SelectedIndexChanged += (_, _) => { target.Enabled = resolution.Enabled = mute.Enabled = !busy && format.Text == "MP4"; };
        cancel.Click += (_, _) => cancellation?.Cancel();
        convert.BackColor = Color.FromArgb(29, 109, 218); convert.ForeColor = Color.White; convert.FlatStyle = FlatStyle.Flat;
        convert.Click += Convert;
        actions.Controls.AddRange([format, new Label { Text = "Target MB", AutoSize = true, Padding = new Padding(0, 7, 0, 0) }, target, resolution, mute, convert, cancel, status]);
        var footer = new FlowLayoutPanel { Dock = DockStyle.Fill };
        footer.Controls.AddRange([Button("Enable right-click menu", (_, _) => Register(true)), Button("Remove right-click menu", (_, _) => Register(false)), Button("Unlock this PC", async (_, _) => await Payment(false)), Button("Restore purchase", async (_, _) => await Payment(true))]);
        layout.Controls.Add(title); layout.Controls.Add(tools); layout.Controls.Add(files); layout.Controls.Add(actions); layout.Controls.Add(footer);
        Controls.Add(layout); Controls.Add(progress);
        FormClosing += (_, e) => { if (busy) { e.Cancel = true; MessageBox.Show(this, "Please wait for the current conversion to finish.", Text); } };
        licenseRefresh.Tick += (_, _) => { if (!busy && !paymentBusy) { try { RefreshStatus(); } catch { /* A simultaneous activation may be updating the file. */ } } };
        licenseRefresh.Start();
        FormClosed += (_, _) => licenseRefresh.Dispose();
        RefreshStatus();
    }

    private static Button Button(string text, EventHandler click)
    {
        var button = new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.System };
        button.Click += click; return button;
    }

    private void RefreshStatus()
    {
        var state = Program.Load();
        status.Text = state.ActivationToken is null ? $"{Math.Max(0, 5 - state.Used)} free conversions left" : "Unlimited conversions";
    }

    private void AddFiles(object? sender, EventArgs e)
    {
        if (busy) return;
        using var picker = new OpenFileDialog { Multiselect = true, Title = "Choose audio or video files", Filter = "Audio and video|*.mp4;*.mov;*.m4v;*.mkv;*.webm;*.avi;*.mp3;*.m4a;*.aac;*.wav;*.flac;*.ogg;*.oga;*.opus;*.aif;*.aiff" };
        if (picker.ShowDialog(this) == DialogResult.OK) Add(picker.FileNames);
    }

    private void Add(IEnumerable<string> incoming)
    {
        if (busy) return;
        var rejected = 0;
        foreach (var path in incoming)
        {
            if (!File.Exists(path) || !Conversion.Inputs.Contains(Path.GetExtension(path))) { rejected++; continue; }
            if (paths.Contains(path, StringComparer.OrdinalIgnoreCase)) continue;
            paths.Add(path); files.Items.Add(new ListViewItem([Path.GetFileName(path), "Ready"]) { ToolTipText = path });
        }
        if (rejected > 0) MessageBox.Show(this, $"Skipped {rejected} unsupported files or folders.", Text);
    }

    private async void Convert(object? sender, EventArgs e)
    {
        if (busy || paymentBusy || paths.Count == 0) return;
        var state = Program.Load();
        paymentBusy = true; convert.Enabled = false;
        try { if (!await Program.Authorize(state, paths.Count)) return; }
        catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
        finally { paymentBusy = false; convert.Enabled = true; RefreshStatus(); }
        var compression = format.Text == "MP4" ? new CompressionOptions(target.Value, resolution.SelectedIndex == 0 ? 1080 : resolution.SelectedIndex == 1 ? 720 : 0, mute.Checked) : null;
        cancellation = new CancellationTokenSource();
        busy = true; convert.Enabled = format.Enabled = target.Enabled = resolution.Enabled = mute.Enabled = false; cancel.Enabled = compression is not null;
        progress.Maximum = paths.Count; progress.Value = 0;
        var outputFormat = format.Text.ToLowerInvariant();
        var failures = new List<string>();
        try
        {
            for (var index = 0; index < paths.Count; index++)
            {
                if (cancellation.IsCancellationRequested) break;
                files.Items[index].SubItems[1].Text = "Converting…";
                status.Text = $"Converting {index + 1} of {paths.Count}";
                try
                {
                    var output = await Program.ConvertFile(paths[index], outputFormat, compression, cancellation.Token);
                    files.Items[index].Tag = output; files.Items[index].SubItems[1].Text = "Done — double-click to reveal";
                }
                catch (OperationCanceledException) { files.Items[index].SubItems[1].Text = "Cancelled"; break; }
                catch (Exception error) { files.Items[index].SubItems[1].Text = "Failed"; files.Items[index].ToolTipText = error.Message; failures.Add($"{Path.GetFileName(paths[index])}: {error.Message}"); }
                progress.Value = index + 1;
            }
        }
        finally { if (failures.Count > 0) MessageBox.Show(this, string.Join("\n\n", failures.Take(5)), "Some files could not be converted", MessageBoxButtons.OK, MessageBoxIcon.Warning); busy = false; convert.Enabled = true; format.Enabled = true; target.Enabled = resolution.Enabled = mute.Enabled = format.Text == "MP4"; cancel.Enabled = false; cancellation.Dispose(); cancellation = null; RefreshStatus(); }
    }

    private async Task Payment(bool restore)
    {
        if (busy || paymentBusy) return;
        paymentBusy = true; convert.Enabled = false;
        try { await Program.PurchaseOrRestore(restore); }
        catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); }
        finally { paymentBusy = false; convert.Enabled = true; RefreshStatus(); }
    }

    private void Register(bool enable)
    {
        try
        {
            var clsid = @"Software\Classes\CLSID\{731BA7E4-A1CC-4378-B7B5-B9755560DA12}";
            var menu = @"Software\Classes\*\shell\ConvertRight";

            if (enable)
            {
                var dll = Path.Combine(AppContext.BaseDirectory, "ConvertRightShell.dll");
                if (!File.Exists(dll)) throw new IOException("The right-click component is missing. Extract the complete ZIP first.");
                using (var key = Registry.CurrentUser.CreateSubKey(clsid + @"\InprocServer32")) { key.SetValue("", dll); key.SetValue("ThreadingModel", "Apartment"); }
                using (var key = Registry.CurrentUser.CreateSubKey(menu)) { key.SetValue("MUIVerb", "ConvertRight"); key.SetValue("ExplorerCommandHandler", "{731BA7E4-A1CC-4378-B7B5-B9755560DA12}"); key.SetValue("SubCommands", ""); key.SetValue("MultiSelectModel", "Player"); }
                Program.RegisterPaymentProtocol();
            }
            else { Registry.CurrentUser.DeleteSubKeyTree(menu, false); Registry.CurrentUser.DeleteSubKeyTree(clsid, false); }
            MessageBox.Show(this, enable ? "Right-click menu enabled for your Windows account.\nChoose Show more options → ConvertRight.\nKeep this application folder in its current location. If you move it, enable the menu again." : "Right-click menu removed. You can still use this window.", Text);
        }
        catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
