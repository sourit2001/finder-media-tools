# Windows portable 0.2.0

Completed: local self-contained win-x64 build; target-size MP4 compression using two-pass H.264/AAC; original/maximum 1080p/720p; optional mute; cancellation; output-size check and full decode; non-overwrite output publication; bundled ffprobe; portable ZIP with runtime, FFmpeg and license notices. Existing audio conversion and optional per-user Explorer audio menu retained.

Verified on macOS using the shared .NET compression code and real FFmpeg: 4K to 1920x1080, target size, full decode, source preservation, silent video, cancellation, existing audio regression suite. Windows executable compiled, ZIP integrity and contents verified.

Not yet verified on a real Windows PC: window interaction, drag/drop, bundled Windows FFmpeg execution, Explorer integration. Paid Windows activation remains disabled. Windows HDR input is rejected explicitly. A 5GB/10GB source has not been tested. No public deployment has been made from this checkout.
