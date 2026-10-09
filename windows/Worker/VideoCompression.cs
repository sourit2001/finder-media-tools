using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace ConvertRight;

internal sealed record CompressionOptions(decimal Megabytes, int MaxHeight = 1080, bool Mute = false);
internal static class VideoCompression
{
    internal static readonly HashSet<string> Inputs = new(StringComparer.OrdinalIgnoreCase) { ".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi" };
    private static async Task<string> Execute(string binary, IEnumerable<string> args, CancellationToken cancellation)
    {
        var start = new ProcessStartInfo(binary) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var arg in args) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new IOException("Unable to start the bundled video processor.");
        using var registration = cancellation.Register(() => { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } });
        var errors = process.StandardError.ReadToEndAsync();
        var output = process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();
        var detail = await errors; var result = await output;
        cancellation.ThrowIfCancellationRequested();
        if (process.ExitCode != 0) throw new IOException(string.IsNullOrWhiteSpace(detail) ? "Video processing failed." : detail.Trim());
        return result;
    }
    internal static async Task<string> Run(string ffmpeg, string probe, string input, CompressionOptions options, CancellationToken cancellation = default)
    {
        if (options.Megabytes < 1 || options.Megabytes > 100000 || options.MaxHeight is not (0 or 720 or 1080)) throw new ArgumentException("Choose 1–100,000 MB and original, 1080p or 720p resolution.");
        input = Path.GetFullPath(input);
        if (!File.Exists(input) || !Inputs.Contains(Path.GetExtension(input))) throw new IOException("Choose a supported local video file.");
        var metadata = await Execute(probe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", input], cancellation);
        using var document = JsonDocument.Parse(metadata);
        var duration = double.Parse(document.RootElement.GetProperty("format").GetProperty("duration").GetString()!, CultureInfo.InvariantCulture);
        if (!double.IsFinite(duration) || duration <= 0) throw new IOException("This video's duration could not be read.");
        var streams = document.RootElement.GetProperty("streams").EnumerateArray().ToArray();
        if (!streams.Any(s => s.GetProperty("codec_type").GetString() == "video")) throw new IOException("This file has no video track.");
        var video = streams.First(s => s.GetProperty("codec_type").GetString() == "video");
        if (video.TryGetProperty("color_transfer", out var transfer) && transfer.GetString() is "smpte2084" or "arib-std-b67")
            throw new IOException("HDR video is not supported by this Windows version. Export an SDR copy before compressing.");
        var hasAudio = !options.Mute && streams.Any(s => s.GetProperty("codec_type").GetString() == "audio");
        var limit = (long)(options.Megabytes * 1_000_000);
        var audioRate = hasAudio ? 96000 : 0;
        var videoRate = (long)(limit * 8d * .94 / duration - audioRate);
        if (videoRate < 32000) throw new IOException("The selected size is too small for this duration. Choose a larger target or remove audio.");
        var directory = Path.GetDirectoryName(input)!;
        var work = Path.Combine(directory, $".convertright-{Guid.NewGuid():N}");
        Directory.CreateDirectory(work);
        var temporary = Path.Combine(work, "output.mp4");
        var passlog = Path.Combine(work, "pass");
        try
        {
            for (var attempt = 0; attempt < 3; attempt++)
            {
                var common = new List<string> { "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", input, "-map", "0:v:0", "-c:v", "libx264", "-preset", "medium", "-b:v", videoRate.ToString(CultureInfo.InvariantCulture), "-pix_fmt", "yuv420p" };
                if (options.MaxHeight > 0) common.AddRange(["-vf", $"scale=w='min(iw,{options.MaxHeight * 16 / 9})':h='min(ih,{options.MaxHeight})':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1"]);
                else common.AddRange(["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1"]);
                await Execute(ffmpeg, common.Concat(["-pass", "1", "-passlogfile", passlog, "-an", "-f", "null", OperatingSystem.IsWindows() ? "NUL" : "/dev/null"]), cancellation);
                var second = common.Concat(["-pass", "2", "-passlogfile", passlog]).ToList();
                if (hasAudio) second.AddRange(["-map", "0:a:0", "-c:a", "aac", "-b:a", "96k"]); else second.Add("-an");
                second.AddRange(["-movflags", "+faststart", temporary]);
                await Execute(ffmpeg, second, cancellation);
                if (new FileInfo(temporary).Length < limit)
                {
                    // Decode every frame before publishing; never leave a truncated successful result.
                    await Execute(ffmpeg, ["-v", "error", "-xerror", "-i", temporary, "-f", "null", "-"], cancellation);
                    cancellation.ThrowIfCancellationRequested();
                    return Conversion.Publish(temporary, directory, Path.GetFileNameWithoutExtension(input) + "_compressed", "mp4");
                }
                videoRate = (long)(videoRate * .85);
            }
            throw new IOException("The output could not meet this size. Choose a larger target.");
        }
        finally { Directory.Delete(work, recursive: true); }
    }
}
