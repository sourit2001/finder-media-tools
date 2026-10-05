# Implementation status — 2026-10-05

Agreed scope: Windows 11; independent Mac and Windows purchases; real Windows
testing by the owner. First implementation targets Windows 11 x64. Five free
successful file conversions and $1 per installation follow the current Mac model.

Implemented locally:

- Native modern Explorer context menu and three audio format subcommands.
- Separate self-contained conversion worker, batch processing, collision-safe
  output publication, first-audio extraction and failure cleanup.
- Persistent Windows trial/license state and Windows payment protocol activation.
- MSIX manifest, test signing/install/uninstall scripts, pinned FFmpeg preparation.
- Windows CI workflow and Chinese real-machine test guide.
- Sibling landing-page server changes for Windows checkout/activation/status and
  stored-platform callback routing; defaults remain compatible with Mac clients.

Verified:

- Conversion worker C# compilation: passed, zero warnings/errors.
- Self-contained Windows x64 worker publish: passed; executable is available
  locally in `out/worker/ConvertRight.exe`. It is not a complete installer and has
  not been executed on Windows.
- Real FFmpeg conversion tests on macOS: 13 checks passed, including full output
  decoding, video audio extraction, Unicode paths, concurrent output collisions,
  preservation of originals, missing files and no-audio cleanup.
- Landing-page production build and all 8 tests: passed.
- Manifest XML and COM/menu CLSID consistency: passed.
- Standalone TypeScript check still reports existing missing Cloudflare worker
  type declarations. No remaining errors were reported in the changed API routes.

Not yet verified:

- Native C++ DLL compilation and Windows SDK manifest validation.
- MSIX install, actual modern Explorer menu and conversions on Windows hardware.
- Windows payment flow, refund revocation and production signing.

The initial GitHub connector tree creation returned 403 `Resource not accessible
by integration`. A later network-enabled check confirmed that Git/gh authentication
and repository/workflow scopes are valid. Source changes are being submitted on
separate review branches. Server changes have not been deployed; the public Windows
download has not been enabled. Test builds disable payments.

Next: create a draft branch and PR containing only Windows files plus its CI
workflow, run the Windows build,
repair any compiler/package errors and deliver the resulting test ZIP for hardware
testing. Deploy the server routes and enable payments only after those checks.
