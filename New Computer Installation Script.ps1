Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalStringProperty {
	param(
		[Parameter(Mandatory)]
		$InputObject,
		[Parameter(Mandatory)]
		[string]$PropertyName
	)

	$prop = $InputObject.PSObject.Properties[$PropertyName]
	if ($null -eq $prop -or $null -eq $prop.Value) {
		return $null
	}

	return [string]$prop.Value
}

function Write-Section {
	param(
		[Parameter(Mandatory)]
		[string]$Title,
		[ConsoleColor]$Color = [ConsoleColor]::Cyan
	)

	$line = ('=' * 78)
	Write-Host ''
	Write-Host $line -ForegroundColor DarkGray
	Write-Host ("  {0}" -f $Title) -ForegroundColor $Color
	Write-Host $line -ForegroundColor DarkGray
}

function Write-ItemLine {
	param(
		[Parameter(Mandatory)]
		[string]$Label,
		[Parameter(Mandatory)]
		[string]$Value,
		[ConsoleColor]$Color = [ConsoleColor]::Gray
	)

	Write-Host (" - {0}: {1}" -f $Label, $Value) -ForegroundColor $Color
}

function Get-DirectoryFromCandidatePath {
	param(
		[string]$PathText
	)

	if ([string]::IsNullOrWhiteSpace($PathText)) {
		return $null
	}

	$trimmed = $PathText.Trim().Trim('"')
	if ([string]::IsNullOrWhiteSpace($trimmed)) {
		return $null
	}

	# Registry icon values can include an index suffix such as ",0".
	$trimmed = $trimmed -replace ',\d+$', ''

	if (Test-Path -LiteralPath $trimmed -PathType Container -ErrorAction SilentlyContinue) {
		return $trimmed
	}

	if (Test-Path -LiteralPath $trimmed -PathType Leaf -ErrorAction SilentlyContinue) {
		return (Split-Path -Path $trimmed -Parent)
	}

	if ($trimmed -match '\\[^\\]+\.[A-Za-z0-9]{2,5}$') {
		return (Split-Path -Path $trimmed -Parent)
	}

	return $trimmed
}

function Get-RegistryInstalledPrograms {
	$uninstallRoots = @(
		'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
		'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
		'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
	)

	$programs = foreach ($path in $uninstallRoots) {
		Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
			Where-Object { -not [string]::IsNullOrWhiteSpace((Get-OptionalStringProperty -InputObject $_ -PropertyName 'DisplayName')) } |
			ForEach-Object {
				$displayName = Get-OptionalStringProperty -InputObject $_ -PropertyName 'DisplayName'
				$displayVersion = Get-OptionalStringProperty -InputObject $_ -PropertyName 'DisplayVersion'
				$publisher = Get-OptionalStringProperty -InputObject $_ -PropertyName 'Publisher'
				$displayIconRaw = Get-OptionalStringProperty -InputObject $_ -PropertyName 'DisplayIcon'
				$installLocation = Get-OptionalStringProperty -InputObject $_ -PropertyName 'InstallLocation'

				$exePath = $null
				if (-not [string]::IsNullOrWhiteSpace($displayIconRaw)) {
					$exePath = ($displayIconRaw -replace ',\d+$', '').Trim('"')
				}

				[PSCustomObject]@{
					Name = $displayName
					Version = $displayVersion
					Publisher = $publisher
					InstallLocation = $installLocation
					DisplayIcon = $exePath
				}
			}
	}

	$programs |
		Sort-Object Name -Unique
}

function Get-ProgramPathText {
	param(
		[Parameter(Mandatory)]
		$Program
	)

	$directory = Get-DirectoryFromCandidatePath -PathText $Program.InstallLocation
	if (-not [string]::IsNullOrWhiteSpace($directory)) {
		return $directory
	}

	$directory = Get-DirectoryFromCandidatePath -PathText $Program.DisplayIcon
	if (-not [string]::IsNullOrWhiteSpace($directory)) {
		return $directory
	}

	return '(path unavailable)'
}

function Get-WingetListIndex {
	$wingetIndex = @{}

	# Export to a temp file so console noise/progress text cannot corrupt JSON parsing.
	$tempPath = Join-Path -Path $env:TEMP -ChildPath ("winget-export-{0}.json" -f [guid]::NewGuid())

	try {
		& winget export --include-versions --accept-source-agreements --output $tempPath --disable-interactivity 2>$null | Out-Null
		if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempPath)) {
			return $wingetIndex
		}

		$json = Get-Content -LiteralPath $tempPath -Raw -ErrorAction Stop
		if ([string]::IsNullOrWhiteSpace($json)) {
			return $wingetIndex
		}

		try {
			$parsed = $json | ConvertFrom-Json -ErrorAction Stop
		}
		catch {
			return $wingetIndex
		}

		if ($null -eq $parsed -or $null -eq $parsed.Sources) {
			return $wingetIndex
		}
	}
	finally {
		if (Test-Path -LiteralPath $tempPath) {
			Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
		}
	}

	foreach ($source in $parsed.Sources) {
		if ($null -eq $source.Packages) {
			continue
		}

		foreach ($pkg in $source.Packages) {
			if (-not [string]::IsNullOrWhiteSpace($pkg.PackageIdentifier)) {
				$version = $null
				if ($null -ne $pkg.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace([string]$pkg.Version)) {
					$version = [string]$pkg.Version
				}
				elseif ($null -ne $pkg.PSObject.Properties['PackageVersion'] -and -not [string]::IsNullOrWhiteSpace([string]$pkg.PackageVersion)) {
					$version = [string]$pkg.PackageVersion
				}

				$wingetIndex[$pkg.PackageIdentifier] = [PSCustomObject]@{
					Installed = $true
					Version = $version
				}
			}
		}
	}

	return $wingetIndex
}

function Get-WingetInstalledVersion {
	param(
		[Parameter(Mandatory)]
		[string]$Id,
		[Parameter(Mandatory)]
		[hashtable]$WingetIndex
	)

	if (-not $WingetIndex.ContainsKey($Id)) {
		return $null
	}

	$entry = $WingetIndex[$Id]
	if ($null -eq $entry -or $entry -is [bool]) {
		return $null
	}

	if ($null -eq $entry.PSObject.Properties['Version']) {
		return $null
	}

	$version = [string]$entry.Version
	if ([string]::IsNullOrWhiteSpace($version)) {
		return $null
	}

	return $version.Trim()
}

function Test-DesiredVersionMatch {
	param(
		[string]$DesiredVersion,
		[string]$WingetVersion,
		[string]$RegistryVersion
	)

	if ([string]::IsNullOrWhiteSpace($DesiredVersion)) {
		return $true
	}

	$desired = $DesiredVersion.Trim()
	$candidates = @($WingetVersion, $RegistryVersion) |
		Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

	if ($candidates.Count -eq 0) {
		return $false
	}

	foreach ($candidate in $candidates) {
		if ([string]::Equals(([string]$candidate).Trim(), $desired, [System.StringComparison]::OrdinalIgnoreCase)) {
			return $true
		}
	}

	return $false
}

function Get-PackageDefinitions {
	param(
		[Parameter(Mandatory)]
		[string]$ConfigPath
	)

	if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
		throw "Package configuration file not found: $ConfigPath"
	}

	$json = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
	if ([string]::IsNullOrWhiteSpace($json)) {
		throw "Package configuration file is empty: $ConfigPath"
	}

	$parsed = $json | ConvertFrom-Json -ErrorAction Stop

	$sourcePackages = $null
	if ($parsed -is [System.Array]) {
		$sourcePackages = $parsed
	}
	elseif ($null -ne $parsed.PSObject.Properties['packages']) {
		$sourcePackages = @($parsed.packages)
	}
	else {
		throw "Package configuration must be an array or an object with a 'packages' array: $ConfigPath"
	}

	$result = New-Object System.Collections.Generic.List[object]

	foreach ($entry in @($sourcePackages)) {
		if ($null -eq $entry) {
			continue
		}

		$name = Get-OptionalStringProperty -InputObject $entry -PropertyName 'Name'
		$id = Get-OptionalStringProperty -InputObject $entry -PropertyName 'Id'
		$source = Get-OptionalStringProperty -InputObject $entry -PropertyName 'Source'
		$desiredVersion = Get-OptionalStringProperty -InputObject $entry -PropertyName 'DesiredVersion'
		$installScope = Get-OptionalStringProperty -InputObject $entry -PropertyName 'InstallScope'

		if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id)) {
			throw "Each package entry must define Name and Id. File: $ConfigPath"
		}

		$scopeNormalized = $null
		if (-not [string]::IsNullOrWhiteSpace($installScope)) {
			$scopeCandidate = $installScope.Trim().ToLowerInvariant()
			if ($scopeCandidate -notin @('user', 'machine')) {
				throw "InstallScope must be 'user' or 'machine' when provided. Package: $($name.Trim()) | File: $ConfigPath"
			}

			$scopeNormalized = $scopeCandidate
		}

		$result.Add([PSCustomObject]@{
			Name = $name.Trim()
			Id = $id.Trim()
			Source = if ([string]::IsNullOrWhiteSpace($source)) { $null } else { $source.Trim() }
			DesiredVersion = if ([string]::IsNullOrWhiteSpace($desiredVersion)) { $null } else { $desiredVersion.Trim() }
			InstallScope = $scopeNormalized
		})
	}

	if ($result.Count -eq 0) {
		throw "No package entries were found in: $ConfigPath"
	}

	return @($result.ToArray())
}

function Find-RegistryProgramForPackage {
	param(
		[Parameter(Mandatory)]
		[string]$PackageName,
		[Parameter(Mandatory)]
		[array]$RegistryPrograms
	)

	$exactMatch = $RegistryPrograms |
		Where-Object { $_.Name -ieq $PackageName } |
		Select-Object -First 1

	if ($null -ne $exactMatch) {
		return $exactMatch
	}

	$escapedName = [regex]::Escape($PackageName)
	$wordBoundaryPattern = "(?i)(^|[^a-z0-9])$escapedName([^a-z0-9]|$)"
	$boundaryMatch = $RegistryPrograms |
		Where-Object { $_.Name -match $wordBoundaryPattern } |
		Select-Object -First 1

	if ($null -ne $boundaryMatch) {
		return $boundaryMatch
	}

	$match = $RegistryPrograms |
		Where-Object { $_.Name -like "*$PackageName*" } |
		Select-Object -First 1

	if ($null -ne $match) {
		return $match
	}

	return $null
}

function Install-WingetPackage {
	param(
		[Parameter(Mandatory)]
		$Package
	)

	$args = @(
		'install',
		'-e',
		'--id', $Package.Id,
		'--accept-package-agreements',
		'--accept-source-agreements',
		'--disable-interactivity'
	)

	if (-not [string]::IsNullOrWhiteSpace($Package.Source)) {
		$args += @('--source', $Package.Source)
	}

	if (-not [string]::IsNullOrWhiteSpace($Package.DesiredVersion)) {
		$args += @('--version', $Package.DesiredVersion)
	}

	if (-not [string]::IsNullOrWhiteSpace($Package.InstallScope)) {
		$args += @('--scope', $Package.InstallScope)
	}

	# Keep useful status lines while suppressing spinner/progress noise.
	$output = & winget @args 2>&1
	$lastLine = $null
	foreach ($lineObj in $output) {
		$line = [string]$lineObj
		if ([string]::IsNullOrWhiteSpace($line)) {
			continue
		}

		if ($line -match '^\s*[\|/\\-]\s*$') {
			continue
		}

		if ($line -match '\b(KB|MB|GB)\b\s*/\s*\d') {
			continue
		}

		if ($line -match '[^\x00-\x7F]{3,}') {
			continue
		}

		if ($line -eq $lastLine) {
			continue
		}

		Write-Host ("   {0}" -f $line) -ForegroundColor DarkGray
		$lastLine = $line
	}

	if ($null -eq $LASTEXITCODE) {
		return 0
	}

	return [int]$LASTEXITCODE
}

function Get-InstalledCommandPath {
	param(
		[Parameter(Mandatory)]
		[string]$CommandName
	)

	$cmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandType -in @('Application', 'ExternalScript') } |
		Select-Object -First 1

	if ($null -eq $cmd) {
		return $null
	}

	return $cmd.Source
}

function Select-PackagesToInstall {
	param(
		[Parameter(Mandatory)]
		[System.Collections.Generic.List[object]]$PendingPackages
	)

	if ($PendingPackages.Count -eq 0) {
		return @()
	}

	$selected = @{}
	for ($i = 0; $i -lt $PendingPackages.Count; $i++) {
		$selected[$i] = $true
	}

	while ($true) {
		Write-Section -Title 'Pending Install Selection' -Color Yellow
		Write-Host 'Toggle which packages to install before continuing.' -ForegroundColor Gray
		Write-Host ''

		for ($i = 0; $i -lt $PendingPackages.Count; $i++) {
			$pkg = $PendingPackages[$i]
			$mark = if ($selected[$i]) { 'x' } else { ' ' }
			$versionText = if (-not [string]::IsNullOrWhiteSpace($pkg.DesiredVersion)) { " (target: $($pkg.DesiredVersion))" } else { '' }
			$scopeText = if (-not [string]::IsNullOrWhiteSpace($pkg.InstallScope)) { " | scope: $($pkg.InstallScope)" } else { '' }
			Write-Host (" {0,2}. [{1}] {2} [{3}]{4}{5}" -f ($i + 1), $mark, $pkg.Name, $pkg.Id, $versionText, $scopeText) -ForegroundColor White
		}

		Write-Host ''
		Write-Host 'Commands: number list to toggle (e.g. 1,3,5), A=all, N=none, C=continue, Q=quit' -ForegroundColor DarkGray
		$inputValue = Read-Host 'Selection'

		if ([string]::IsNullOrWhiteSpace($inputValue) -or $inputValue -match '^[cC]$') {
			break
		}

		if ($inputValue -match '^[qQ]$') {
			return $null
		}

		if ($inputValue -match '^[aA]$') {
			for ($i = 0; $i -lt $PendingPackages.Count; $i++) {
				$selected[$i] = $true
			}
			continue
		}

		if ($inputValue -match '^[nN]$') {
			for ($i = 0; $i -lt $PendingPackages.Count; $i++) {
				$selected[$i] = $false
			}
			continue
		}

		$tokens = $inputValue -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
		$invalid = $false

		foreach ($token in $tokens) {
			$number = 0
			if (-not [int]::TryParse($token, [ref]$number)) {
				$invalid = $true
				continue
			}

			$index = $number - 1
			if ($index -lt 0 -or $index -ge $PendingPackages.Count) {
				$invalid = $true
				continue
			}

			$selected[$index] = -not $selected[$index]
		}

		if ($invalid) {
			Write-Host 'Some entries were invalid and were ignored.' -ForegroundColor Yellow
		}
	}

	$result = New-Object System.Collections.Generic.List[object]
	for ($i = 0; $i -lt $PendingPackages.Count; $i++) {
		if ($selected[$i]) {
			$result.Add($PendingPackages[$i])
		}
	}

	return @($result.ToArray())
}
$packageConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'packages.json'
$packages = Get-PackageDefinitions -ConfigPath $packageConfigPath

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
	Write-Host 'winget was not found on this machine. Install App Installer from Microsoft Store first.' -ForegroundColor Red
	exit 1
}

Write-Section -Title 'New Machine Package Installer' -Color Green
Write-Host 'This script checks installed apps first, skips existing packages, then installs missing ones.' -ForegroundColor Gray
Write-Host ("Package config: {0}" -f $packageConfigPath) -ForegroundColor DarkGray

Write-Section -Title 'Collecting Installed Program Data' -Color Yellow
$registryPrograms = Get-RegistryInstalledPrograms
$wingetIndex = Get-WingetListIndex
$commandHints = @{
	'Git.Git' = 'git'
}

$alreadyInstalled = New-Object System.Collections.Generic.List[object]
$toInstall = New-Object System.Collections.Generic.List[object]

foreach ($pkg in $packages) {
	$wingetVersion = Get-WingetInstalledVersion -Id $pkg.Id -WingetIndex $wingetIndex
	$registryMatch = Find-RegistryProgramForPackage -PackageName $pkg.Name -RegistryPrograms $registryPrograms
	$registryVersion = if ($null -ne $registryMatch) { [string]$registryMatch.Version } else { $null }
	$commandName = $null
	$commandPath = $null
	$versionMatches = Test-DesiredVersionMatch -DesiredVersion $pkg.DesiredVersion -WingetVersion $wingetVersion -RegistryVersion $registryVersion

	if ($commandHints.ContainsKey($pkg.Id)) {
		$commandName = $commandHints[$pkg.Id]
		$commandPath = Get-InstalledCommandPath -CommandName $commandName
	}

	$isDetected = ($WingetIndex.ContainsKey($pkg.Id) -or $null -ne $registryMatch -or $null -ne $commandPath)

	if ($isDetected -and $versionMatches) {
		$pathText = if ($null -ne $registryMatch) {
			Get-ProgramPathText -Program $registryMatch
		}
		elseif ($null -ne $commandPath) {
			$commandPath
		}
		else {
			'(path unavailable)'
		}

		$detectedBy = @()
		if ($WingetIndex.ContainsKey($pkg.Id)) { $detectedBy += 'winget' }
		if ($null -ne $registryMatch) { $detectedBy += 'registry' }
		if ($null -ne $commandPath) { $detectedBy += 'command' }
		$versionText = if (-not [string]::IsNullOrWhiteSpace($pkg.DesiredVersion)) { $pkg.DesiredVersion } else { '(not pinned)' }
		$scopeText = if (-not [string]::IsNullOrWhiteSpace($pkg.InstallScope)) { $pkg.InstallScope } else { '(default)' }
		$detectedVersion = if (-not [string]::IsNullOrWhiteSpace($wingetVersion)) {
			$wingetVersion
		}
		elseif (-not [string]::IsNullOrWhiteSpace($registryVersion)) {
			$registryVersion
		}
		else {
			'(unknown)'
		}

		$alreadyInstalled.Add([PSCustomObject]@{
			Name = $pkg.Name
			Id = $pkg.Id
			Path = $pathText
			DetectedBy = ($detectedBy -join ', ')
			DesiredVersion = $versionText
			InstallScope = $scopeText
			DetectedVersion = $detectedVersion
		})
	}
	else {
		$toInstall.Add($pkg)
	}
}

Write-Host ("Detected target packages: {0}" -f $packages.Count) -ForegroundColor Gray
Write-Host ("Already installed:        {0}" -f $alreadyInstalled.Count) -ForegroundColor Green
Write-Host ("Pending install:          {0}" -f $toInstall.Count) -ForegroundColor Yellow

if ($alreadyInstalled.Count -gt 0) {
	Write-Section -Title 'Already Installed (Skipped)' -Color Green
	foreach ($item in ($alreadyInstalled | Sort-Object Name)) {
		Write-Host (" - {0} [{1}]" -f $item.Name, $item.Id) -ForegroundColor DarkGreen
		Write-ItemLine -Label 'Detected By' -Value $item.DetectedBy -Color DarkGray
		Write-ItemLine -Label 'Detected Version' -Value $item.DetectedVersion -Color DarkGray
		Write-ItemLine -Label 'Desired Version' -Value $item.DesiredVersion -Color DarkGray
		Write-ItemLine -Label 'Install Scope' -Value $item.InstallScope -Color DarkGray
		Write-ItemLine -Label 'Path' -Value $item.Path -Color DarkGray
	}
}

if ($toInstall.Count -gt 0) {
	$selected = Select-PackagesToInstall -PendingPackages $toInstall
	if ($null -eq $selected) {
		Write-Host ''
		Write-Host 'Installation cancelled by user.' -ForegroundColor Yellow
		exit 0
	}

	$normalizedSelection = New-Object System.Collections.Generic.List[object]
	foreach ($pkg in @($selected)) {
		if ($null -ne $pkg) {
			$normalizedSelection.Add($pkg)
		}
	}
	$toInstall = $normalizedSelection
	Write-Host ''
	Write-Host ("Selected for install:      {0}" -f $toInstall.Count) -ForegroundColor Cyan
}

$installedNow = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]

if ($toInstall.Count -gt 0) {
	Write-Section -Title 'Installing Missing Packages' -Color Cyan

	$index = 0
	foreach ($pkg in $toInstall) {
		$index++
		Write-Host ''
		Write-Host ("[{0}/{1}] {2} ({3})" -f $index, $toInstall.Count, $pkg.Name, $pkg.Id) -ForegroundColor White

		try {
			$exitCode = Install-WingetPackage -Package $pkg
			if ($exitCode -eq 0) {
				Write-Host '   Installed successfully.' -ForegroundColor Green
				$installedNow.Add([PSCustomObject]@{
					Name = $pkg.Name
					Id = $pkg.Id
					ExitCode = $exitCode
				})
			}
			else {
				Write-Host ("   Install failed with exit code {0}." -f $exitCode) -ForegroundColor Red
				$failed.Add([PSCustomObject]@{
					Name = $pkg.Name
					Id = $pkg.Id
					ExitCode = $exitCode
					Reason = 'winget returned non-zero exit code'
				})
			}
		}
		catch {
			Write-Host ("   Install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
			$failed.Add([PSCustomObject]@{
				Name = $pkg.Name
				Id = $pkg.Id
				ExitCode = -1
				Reason = $_.Exception.Message
			})
		}
	}
}

Write-Section -Title 'Summary' -Color Magenta
Write-Host ("Skipped (already installed): {0}" -f $alreadyInstalled.Count) -ForegroundColor Green
Write-Host ("Installed this run:          {0}" -f $installedNow.Count) -ForegroundColor Cyan
Write-Host ("Failed installs:             {0}" -f $failed.Count) -ForegroundColor Red

if ($installedNow.Count -gt 0) {
	Write-Host ''
	Write-Host 'Installed Successfully:' -ForegroundColor Cyan
	$registryProgramsAfter = Get-RegistryInstalledPrograms
	foreach ($item in ($installedNow | Sort-Object Name)) {
		Write-Host (" - {0} [{1}]" -f $item.Name, $item.Id) -ForegroundColor DarkCyan

		$registryMatch = Find-RegistryProgramForPackage -PackageName $item.Name -RegistryPrograms $registryProgramsAfter
		$resolvedPath = $null
		if ($null -ne $registryMatch) {
			$resolvedPath = Get-ProgramPathText -Program $registryMatch
		}
		elseif ($commandHints.ContainsKey($item.Id)) {
			$resolvedPath = Get-DirectoryFromCandidatePath -PathText (Get-InstalledCommandPath -CommandName $commandHints[$item.Id])
		}

		if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
			$resolvedPath = '(path unavailable)'
		}

		Write-ItemLine -Label 'Path' -Value $resolvedPath -Color DarkGray
	}
}

if ($failed.Count -gt 0) {
	Write-Host ''
	Write-Host 'Failed Installs:' -ForegroundColor Red
	foreach ($item in ($failed | Sort-Object Name)) {
		Write-Host (" - {0} [{1}] | ExitCode: {2} | Reason: {3}" -f $item.Name, $item.Id, $item.ExitCode, $item.Reason) -ForegroundColor DarkRed
	}

	Write-Host ''
	Write-Host 'Tip: re-run failed packages individually to troubleshoot source or installer issues.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
