using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace ConvertRight;

internal sealed class LicenseState
{
    public string InstallationId { get; set; } = $"windows-{Guid.NewGuid()}";
    public int Used { get; set; }
    public string? ActivationToken { get; set; }
    public DateTimeOffset? LastVerified { get; set; }
}

internal sealed record LicenseReply(bool Active, bool Pending, bool Retry, string? ActivationToken);

internal static class Program
{
    private const int Limit = 5;
    private static readonly string DataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ConvertRight");
    private static readonly string StatePath = Path.Combine(DataDirectory, "license-v1.json");
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly HttpClient Client = new() { BaseAddress = new Uri("https://convertright.app/"), Timeout = TimeSpan.FromSeconds(20) };
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);

    private static void Message(string text) => MessageBoxW(IntPtr.Zero, text, "ConvertRight", 0x40);
    private static void Open(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

    [STAThread]
    private static int Main(string[] args)
    {
        using var gate = new Mutex(false, @"Local\ConvertRight.Windows.Worker.v1");
        var acquired = false;
        try
        {
            Directory.CreateDirectory(DataDirectory);
            try { acquired = gate.WaitOne(TimeSpan.FromSeconds(5)); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) { Message("Another conversion is running. Please wait for it to finish, then try again."); return 2; }
            return Run(args).GetAwaiter().GetResult();
        }
        catch (Exception error)
        {
            try { Log(error.ToString()); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            Message($"{error.Message}\n\nFor help, see the log in:\n{DataDirectory}");
            return 1;
        }
        finally { if (acquired) gate.ReleaseMutex(); }
    }

    private static LicenseState Load()
    {
        if (!File.Exists(StatePath)) { var fresh = new LicenseState(); Save(fresh); return fresh; }
        var state = JsonSerializer.Deserialize<LicenseState>(File.ReadAllText(StatePath), JsonOptions)
            ?? throw new IOException("Unable to read the license file. Contact support before removing it.");
        if (!state.InstallationId.StartsWith("windows-", StringComparison.Ordinal) || state.Used < 0)
            throw new IOException("The license file is invalid. Contact support before removing it.");
        return state;
    }

    private static void Save(LicenseState state)
    {
        var pending = StatePath + ".tmp";
        File.WriteAllText(pending, JsonSerializer.Serialize(state));
        File.Move(pending, StatePath, overwrite: true);
    }

    private static void Log(string message)
    {
        var path = Path.Combine(DataDirectory, "conversion.log");
        if (File.Exists(path) && new FileInfo(path).Length > 2_000_000) File.Move(path, path + ".previous", overwrite: true);
        File.AppendAllText(path, $"{DateTimeOffset.Now:O} {message}\n");
    }

    private static async Task<int> Run(string[] args)
    {
        var state = Load();
        if (args.Length == 1 && Uri.TryCreate(args[0], UriKind.Absolute, out var link)
            && link.Scheme == "convertright" && link.Host == "unlock")
        {
            var query = link.Query.TrimStart('?').Split('&').Select(part => part.Split('=', 2))
                .FirstOrDefault(part => part.Length == 2 && part[0] == "session");
            var session = query is null ? "" : Uri.UnescapeDataString(query[1]);
            if (!Guid.TryParse(session, out _)) throw new ArgumentException("Invalid payment confirmation link.");
            for (var attempt = 0; attempt < 11; attempt++)
            {
                var reply = await Post("api/license/activate", new { sessionId = session, installationId = state.InstallationId, platform = "windows" });
                if (reply.Active && reply.ActivationToken?.Length == 64)
                {
                    state.ActivationToken = reply.ActivationToken;
                    state.LastVerified = DateTimeOffset.UtcNow;
                    Save(state);
                    Message("Unlimited conversions unlocked for this Windows PC.\nReturn to File Explorer and convert any file.");
                    return 0;
                }
                if (!reply.Pending && !reply.Retry) throw new IOException("This purchase could not be activated for this Windows PC.");
                await Task.Delay(2000);
            }
            Message("Payment is still being confirmed. Refresh the payment confirmation page in your browser to retry activation. You do not need to pay again.");
            return 2;
        }
        if (args.Length != 2 || args[0] != "--request")
        {
            Message($"Select audio or video files in File Explorer, then right-click ConvertRight and choose MP3, M4A or WAV.\n\nFree conversions remaining: {Math.Max(0, Limit - state.Used)}");
            return 0;
        }
        var request = Path.GetFullPath(args[1]);
        var requestsDirectory = Path.Combine(DataDirectory, "Requests") + Path.DirectorySeparatorChar;
        if (!request.StartsWith(requestsDirectory, StringComparison.OrdinalIgnoreCase) || !request.EndsWith(".request", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Invalid conversion request location.");
        string[] lines;
        try
        {
            if (new FileInfo(request).Length > 16_000_000) throw new ArgumentException("Too many selected files.");
            lines = File.ReadAllLines(request, Encoding.Unicode);
        }
        finally { File.Delete(request); }
        if (lines.Length < 2 || lines.Length > 10_001) throw new ArgumentException("No files selected, or too many selected files.");
        var format = lines[0];
        _ = Conversion.Codec(format);
        var paths = lines.Skip(1).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (paths.Any(p => !Path.IsPathFullyQualified(p) || !File.Exists(p) || !Conversion.Inputs.Contains(Path.GetExtension(p))))
            throw new ArgumentException("Select supported audio or video files only.");
        if (!await Authorize(state, paths.Length)) return 2;
        var ffmpeg = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        if (!File.Exists(ffmpeg)) throw new IOException("The bundled converter is missing. Reinstall ConvertRight.");
        var failures = new List<string>();
        foreach (var input in paths)
        {
            try
            {
                var result = await Conversion.Run(ffmpeg, input, format);
                Log($"Created: {result}");
                if (state.ActivationToken is null) { state.Used++; Save(state); }
            }
            catch (Exception error) { Log($"Failed: {input}: {error}"); failures.Add(Path.GetFileName(input)); }
        }
        if (failures.Count > 0) Message($"Converted {paths.Length - failures.Count} of {paths.Length} files.\n\nThese files could not be converted (they may have no audio track or the folder may be read-only):\n{string.Join("\n", failures.Take(10))}\n\nYour original files are unchanged. See conversion.log for details.");
        return failures.Count == 0 ? 0 : 1;
    }

    private static async Task<bool> Authorize(LicenseState state, int count)
    {
        if (state.ActivationToken is not null)
        {
            var age = state.LastVerified is { } last ? DateTimeOffset.UtcNow - last : TimeSpan.MaxValue;
            if (age >= TimeSpan.Zero && age < TimeSpan.FromDays(7)) return true;
            var reply = await Post("api/license/status", new { installationId = state.InstallationId, activationToken = state.ActivationToken, platform = "windows" });
            if (reply.Active) { state.LastVerified = DateTimeOffset.UtcNow; Save(state); return true; }
            if (reply.Retry)
            {
                if (age >= TimeSpan.Zero && age < TimeSpan.FromDays(14)) return true;
                Message("Connect to the internet so ConvertRight can verify your purchase.");
                return false;
            }
            state.ActivationToken = null;
            state.LastVerified = null;
            Save(state);
        }
        if (state.Used + count <= Limit) return true;
        var remaining = Math.Max(0, Limit - state.Used);
        if (remaining > 0)
        {
            Message($"You have {remaining} free conversions left, but selected {count} files. Select fewer files and try again.");
            return false;
        }
        // Test builds never initiate a real payment against an undeployed backend.
        if (!File.Exists(Path.Combine(AppContext.BaseDirectory, "payments-enabled.txt")))
        {
            Message("Your five free conversions are complete. This test build does not accept payments yet.");
            return false;
        }
        if (MessageBoxW(IntPtr.Zero, "Your five free conversions are complete.\nPay $1 once to unlock this Windows PC. Mac licenses are purchased separately.\n\nContinue to payment?", "ConvertRight", 0x24) == 6)
            Open($"https://convertright.app/api/checkout?platform=windows&installation_id={Uri.EscapeDataString(state.InstallationId)}");
        return false;
    }

    private static async Task<LicenseReply> Post(string path, object body)
    {
        try
        {
            using var response = await Client.PostAsJsonAsync(path, body);
            if (response.StatusCode == HttpStatusCode.TooManyRequests || (int)response.StatusCode >= 500)
                return new(false, false, true, null);
            if (!response.IsSuccessStatusCode) return new(false, false, false, null);
            return await response.Content.ReadFromJsonAsync<LicenseReply>(JsonOptions) ?? new(false, false, true, null);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or JsonException)
        { Log($"License verification unavailable: {error.Message}"); return new(false, false, true, null); }
    }
}
