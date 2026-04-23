# Scriptopolis

Scriptopolis contains practical automation for setting up a fresh Windows machine.

The primary asset in this repo is a hardened PowerShell installer script that uses WinGet to install a curated software stack, detects pre-installed apps, supports interactive package selection, and produces clear end-of-run summaries.

This repo also includes an ArchWSL bootstrap shell script for quickly preparing a fresh Arch Linux distro in WSL2 with development tooling, shell customization, and package-manager setup.

## Quick Start

Run in PowerShell:

1. Set temporary execution policy for the current session.
2. Launch the script.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& ".\new_machine\launch_new_machine_install_script.ps1"
```

## ArchWSL Quick Start

Run in Arch Linux on WSL as root:

```bash
cd /mnt/c/Users/syrco/Projects/Code/Scriptopolis/new_machine
chmod +x quick-setup.sh
./quick-setup.sh
```

Then restart the distro so the configured default user is applied.

## Primary Files

- `new_machine/launch_new_machine_install_script.ps1`: Main installer workflow.
- `New Computer Install Check List.md`: Companion checklist and manual-install notes.
- `new_machine/quick-setup.sh`: ArchWSL bootstrap workflow (root/user setup, packages, Homebrew, yay, shell tooling).
- `reference/clean-detailed.omp.json`: Oh My Posh theme copied by the bootstrap script into the Linux user config.

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

## What The ArchWSL Script Does

- Verifies root execution and initializes pacman keyring/update flow.
- Creates/configures a dev user and sudo access for the wheel group.
- Installs core development tooling from pacman, including nano, zsh, compiler toolchains, and CLI utilities.
- Installs yay from AUR and installs configured AUR packages.
- Installs Homebrew and configures shell startup files for brew shellenv.
- Installs opencode with Homebrew.
- Installs Oh My Posh plus prerequisites and ensures ~/.local/bin is on PATH.
- Copies the local theme file from reference/clean-detailed.omp.json when available, with upstream download fallback.
- Adds guarded Oh My Posh zsh initialization so shell startup does not fail if the binary is missing.
- Writes /etc/wsl.conf to set the configured default WSL user.

## Notes

- PowerShell is recommended over Git Bash for this script.
- Some tools may still require manual installation or post-install configuration. See the checklist for those cases.
- The ArchWSL bootstrap script is intended for Arch Linux running in WSL2 and should be run from inside that distro.
- The shell script currently stores credentials in plain text variables for automation convenience. Review and adjust before sharing or reusing broadly.
