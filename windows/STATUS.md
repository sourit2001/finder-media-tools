# Implementation status — 2026-10-05

Accepted distribution: portable Windows 11 x64 application, optional per-user classic context menu under Show more options, no certificate installation or elevation.

Implemented: window with file picker/drag-and-drop, output format selection, batch progress, per-file results and reveal output; native Explorer DLL; bundled FFmpeg and runtime; non-overwriting output and original preservation; successful-conversion trial accounting; optional HKCU menu/protocol registration and removal.

Default CI now builds the portable ZIP and verifies that the real application window opens with its expected controls. Conversion engine tests cover all three formats, complete decoding, video extraction, original preservation, Unicode paths, concurrent output collisions and cleanup after failures. The earlier MSIX build and native DLL compilation passed on Windows; the new portable workflow is being verified separately.

Remaining acceptance: owner testing on physical Windows 11 for the right-click menu and actual downloaded EXE. Windows checkout/activation server changes remain on the sibling landing-page review branch and have not been deployed. Payment is disabled until that deployment and end-to-end verification are complete. Do not describe this as a released paid product.
