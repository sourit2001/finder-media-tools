using System.Diagnostics;
using System.Security.Cryptography;
using ConvertRight;

var ffmpeg = args.Length == 1 ? Path.GetFullPath(args[0]) : throw new ArgumentException("Pass the FFmpeg executable path.");
var directory = Path.Combine(Path.GetTempPath(), "ConvertRight-tests-中文 & space-" + Guid.NewGuid());
Directory.CreateDirectory(directory);
try
{
    async Task Exec(params string[] arguments)
    {
        var start = new ProcessStartInfo(ffmpeg) { UseShellExecute = false, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        var errors = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var detail = await errors;
        if (process.ExitCode != 0) throw new Exception(detail);
    }
    void Check(bool condition, string detail) { if (!condition) throw new Exception(detail); Console.WriteLine("PASS " + detail); }
    var input = Path.Combine(directory, "音频 & (sample).wav");
    await Exec("-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.3", input);
    var before = SHA256.HashData(File.ReadAllBytes(input));
    foreach (var format in new[] { "mp3", "m4a", "wav" })
    {
        var result = await Conversion.Run(ffmpeg, input, format);
        Check(File.Exists(result), $"{format} output exists");
        await Exec("-hide_banner", "-loglevel", "error", "-i", result, "-f", "null", "-");
        Check(before.SequenceEqual(SHA256.HashData(File.ReadAllBytes(input))), $"{format} preserves source");
    }
    var first = Path.Combine(directory, "音频 & (sample).mp3");
    var firstHash = SHA256.HashData(File.ReadAllBytes(first));
    var next = await Conversion.Run(ffmpeg, input, "mp3");
    Check(next.EndsWith("_1.mp3"), "existing output is numbered");
    Check(firstHash.SequenceEqual(SHA256.HashData(File.ReadAllBytes(first))), "existing output is unchanged");
    var parallel = await Task.WhenAll(Conversion.Run(ffmpeg, input, "mp3"), Conversion.Run(ffmpeg, input, "mp3"));
    Check(parallel.Distinct().Count() == 2, "concurrent outputs never overwrite one another");
    var video = Path.Combine(directory, "with audio.mp4");
    await Exec("-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=size=32x32:duration=0.3", "-f", "lavfi", "-i", "sine=duration=0.3", "-c:v", "mpeg4", "-c:a", "aac", "-shortest", video);
    var extracted = await Conversion.Run(ffmpeg, video, "m4a");
    await Exec("-hide_banner", "-loglevel", "error", "-i", extracted, "-f", "null", "-");
    Check(File.Exists(extracted), "video audio is extracted and fully decodes");
    var silent = Path.Combine(directory, "silent.mp4");
    await Exec("-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=size=32x32:duration=0.2", "-c:v", "mpeg4", silent);
    var failed = false;
    try { await Conversion.Run(ffmpeg, silent, "mp3"); } catch (IOException) { failed = true; }
    Check(failed && !File.Exists(Path.Combine(directory, "silent.mp3")), "no-audio failure leaves no output");
    Check(!Directory.GetFiles(directory, ".convertright-*").Any(), "temporary outputs are cleaned up");
    var missing = false;
    try { await Conversion.Run(ffmpeg, Path.Combine(directory, "missing.mp4"), "wav"); } catch (IOException) { missing = true; }
    Check(missing, "missing input is rejected");
}
finally { Directory.Delete(directory, recursive: true); }
