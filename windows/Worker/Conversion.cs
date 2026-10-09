using System.Diagnostics;

namespace ConvertRight;

internal static class Conversion
{
    internal static readonly HashSet<string> Inputs = new(StringComparer.OrdinalIgnoreCase)
    { ".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg", ".oga", ".opus", ".aif", ".aiff" };

    internal static string[] Codec(string format) => format switch
    {
        "mp3" => ["-codec:a", "libmp3lame", "-q:a", "2"],
        "m4a" => ["-codec:a", "aac", "-b:a", "192k"],
        "wav" => ["-codec:a", "pcm_s16le"],
        _ => throw new ArgumentException("Unsupported output format.")
    };

    internal static async Task<string> Run(string ffmpeg, string input, string format)
    {
        var codec = Codec(format);
        input = Path.GetFullPath(input);
        if (!File.Exists(input) || !Inputs.Contains(Path.GetExtension(input)))
            throw new IOException("The selected file is missing or its format is unsupported.");
        var directory = Path.GetDirectoryName(input)!;
        var temporary = Path.Combine(directory, $".convertright-{Guid.NewGuid():N}.{format}");
        try
        {
            var start = new ProcessStartInfo(ffmpeg)
            {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardError = true, RedirectStandardOutput = true
            };
            foreach (var arg in new[] { "-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-i", input, "-map", "0:a:0", "-vn" }
                .Concat(codec).Append(temporary)) start.ArgumentList.Add(arg);
            using var process = Process.Start(start) ?? throw new IOException("Unable to start the bundled converter.");
            // Drain both streams while FFmpeg runs; a full pipe must not stall the process.
            var error = process.StandardError.ReadToEndAsync();
            var output = process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            await output;
            var detail = await error;
            if (process.ExitCode != 0 || !File.Exists(temporary) || new FileInfo(temporary).Length == 0)
                throw new IOException(string.IsNullOrWhiteSpace(detail) ? "Conversion failed. The file may have no audio track." : detail.Trim());
            return Publish(temporary, directory, Path.GetFileNameWithoutExtension(input), format);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    internal static string Publish(string temporary, string directory, string stem, string format)
    {
        for (var index = 0; index < 100_000; index++)
        {
            var candidate = Path.Combine(directory, $"{stem}{(index == 0 ? "" : $"_{index}")}.{format}");
            try { File.Move(temporary, candidate, overwrite: false); return candidate; }
            catch (IOException) when (File.Exists(candidate) || Directory.Exists(candidate)) { }
        }
        throw new IOException("Too many files share this output name.");
    }
}
