# Changelog

All notable changes to this project are documented in this file.

## [x.x.x] - Unreleased

### Added

- Optional `DesiredVersion` support per package in `packages.json`, passed to WinGet via `--version` when specified.
- Optional `InstallScope` support per package in `packages.json`, validated to `user` or `machine` and passed via `--scope`.

### Changed

- Moved installer package definitions out of the script and into `packages.json`.
- Added `Ollama.Ollama` to the managed package list.
- Marked all managed packages with `InstallScope: "machine"` for system-level installs by default.
- Renamed installer script to `launch_new_machine_install_script.ps1` and updated documentation references.

## [0.1.0] - 2026-03-31

Initial commit focused on hardening and polishing the Windows new-machine installer workflow.

### Added

- Robust WinGet installer pipeline with strict mode enabled.
- Pre-install installed-app detection and skip logic.
- Interactive package selection menu (toggle by index, all/none, continue, quit).
- Colorized sectioned output for readability.
- End-of-run summaries for skipped, successful, and failed installs.
- Package path resolution in summary output when available.

### Changed

- Hardened optional-property access for registry uninstall entries.
- Improved WinGet JSON index parsing by exporting to a temporary file and parsing defensively.
- Isolated process exit-code handling to avoid false failure reports.
- Reduced noisy spinner/progress output while preserving meaningful status lines.
- Fixed strict-mode edge cases around single-item selection list shape/type behavior.

### Notes

- Script execution may require a per-session execution policy bypass in PowerShell.
- Manual-install-only tools and additional setup steps are documented in the checklist file.
