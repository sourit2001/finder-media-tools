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

    internal MainWindow()
    {
        Text = "ConvertRight"; Size = new Size(760, 540); MinimumSize = new Size(660, 420);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10); BackColor = Color.FromArgb(244, 246, 249);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), ColumnCount = 1, RowCount = 5 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 75));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
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
        format.Items.AddRange(["MP3", "M4A", "WAV"]); format.SelectedIndex = 0;
        convert.BackColor = Color.FromArgb(29, 109, 218); convert.ForeColor = Color.White; convert.FlatStyle = FlatStyle.Flat;
        convert.Click += Convert;
        actions.Controls.AddRange([format, convert, status]);
        var footer = new FlowLayoutPanel { Dock = DockStyle.Fill };
        footer.Controls.AddRange([Button("Enable right-click menu", (_, _) => Register(true)), Button("Remove right-click menu", (_, _) => Register(false))]);
        layout.Controls.Add(title); layout.Controls.Add(tools); layout.Controls.Add(files); layout.Controls.Add(actions); layout.Controls.Add(footer);
        Controls.Add(layout); Controls.Add(progress);
        FormClosing += (_, e) => { if (busy) { e.Cancel = true; MessageBox.Show(this, "Please wait for the current conversion to finish.", Text); } };
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
        if (busy || paths.Count == 0) return;
        var state = Program.Load();
        if (!await Program.Authorize(state, paths.Count)) return;
        busy = true; convert.Enabled = false; format.Enabled = false;
        progress.Maximum = paths.Count; progress.Value = 0;
        var outputFormat = format.Text.ToLowerInvariant();
        var failures = new List<string>();
        try
        {
            for (var index = 0; index < paths.Count; index++)
            {
                files.Items[index].SubItems[1].Text = "Converting…";
                status.Text = $"Converting {index + 1} of {paths.Count}";
                try
                {
                    var output = await Program.ConvertFile(paths[index], outputFormat);
                    files.Items[index].Tag = output; files.Items[index].SubItems[1].Text = "Done — double-click to reveal";
                }
                catch (Exception error) { files.Items[index].SubItems[1].Text = "Failed"; files.Items[index].ToolTipText = error.Message; failures.Add($"{Path.GetFileName(paths[index])}: {error.Message}"); }
                progress.Value = index + 1;
            }
        }
        finally { if (failures.Count > 0) MessageBox.Show(this, string.Join("\n\n", failures.Take(5)), "Some files could not be converted", MessageBoxButtons.OK, MessageBoxIcon.Warning); busy = false; convert.Enabled = true; format.Enabled = true; RefreshStatus(); }
    }

    private void Register(bool enable)
    {
        try
        {
            var clsid = @"Software\Classes\CLSID\{731BA7E4-A1CC-4378-B7B5-B9755560DA12}";
            var menu = @"Software\Classes\*\shell\ConvertRight";
            var protocol = @"Software\Classes\convertright";
            if (enable)
            {
                var dll = Path.Combine(AppContext.BaseDirectory, "ConvertRightShell.dll");
                if (!File.Exists(dll)) throw new IOException("The right-click component is missing. Extract the complete ZIP first.");
                using (var key = Registry.CurrentUser.CreateSubKey(clsid + @"\InprocServer32")) { key.SetValue("", dll); key.SetValue("ThreadingModel", "Apartment"); }
                using (var key = Registry.CurrentUser.CreateSubKey(menu)) { key.SetValue("MUIVerb", "ConvertRight"); key.SetValue("ExplorerCommandHandler", "{731BA7E4-A1CC-4378-B7B5-B9755560DA12}"); key.SetValue("SubCommands", ""); key.SetValue("MultiSelectModel", "Player"); }
                using (var key = Registry.CurrentUser.CreateSubKey(protocol)) { key.SetValue("", "URL:ConvertRight"); key.SetValue("URL Protocol", ""); }
                using (var key = Registry.CurrentUser.CreateSubKey(protocol + @"\shell\open\command")) key.SetValue("", $"\"{Environment.ProcessPath}\" \"%1\"");
            }
            else { Registry.CurrentUser.DeleteSubKeyTree(menu, false); Registry.CurrentUser.DeleteSubKeyTree(clsid, false); Registry.CurrentUser.DeleteSubKeyTree(protocol, false); }
            MessageBox.Show(this, enable ? "Right-click menu enabled for your Windows account.\nChoose Show more options → ConvertRight.\nKeep this application folder in its current location. If you move it, enable the menu again." : "Right-click menu removed. You can still use this window.", Text);
        }
        catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
