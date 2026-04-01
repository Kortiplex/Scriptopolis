# Scriptopolis

Scriptopolis contains practical automation for setting up a fresh Windows machine.

The primary asset in this repo is a hardened PowerShell installer script that uses WinGet to install a curated software stack, detects pre-installed apps, supports interactive package selection, and produces clear end-of-run summaries.

## Quick Start

Run in PowerShell:

1. Set temporary execution policy for the current session.
2. Launch the script.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& ".\new_machine\launch_new_machine_install_script.ps1"
```

## Primary Files

- `new_machine/launch_new_machine_install_script.ps1`: Main installer workflow.
- `New Computer Install Check List.md`: Companion checklist and manual-install notes.

## What The Installer Does

- Runs under strict mode with defensive error handling.
- Verifies WinGet availability before attempting installs.
- Detects already-installed software using multiple signals:
	- WinGet export index
	- Registry uninstall entries
	- Command-path hints for selected tools
- Skips detected packages instead of reinstalling.
- Lets you choose what to install with an interactive pre-install menu.
- Installs missing packages via WinGet with reduced console noise.
- Prints a final summary of:
	- skipped/already installed
	- installed successfully in this run
	- failed installs with exit code and reason

## Notes

- PowerShell is recommended over Git Bash for this script.
- Some tools may still require manual installation or post-install configuration. See the checklist for those cases.
