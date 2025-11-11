#
# MIT License
#
# Copyright (c) 2021 Free Geek
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# Inspired by Driver Automation Tool (https://msendpointmgr.com/driver-automation-tool/) but DOES NOT use same folder structure as Driver Automation Tool
# Created a simplified script instead of using Driver Automation Tool directly to be able to download the latest Driver Pack for each model regardless of OS version and without having to choose the specific OS version
# as well as being able to more efficiently only download unique Driver Packs and then reference the correct unique Driver Pack for each model (since multiple models use the same Driver Pack).

# https://www.dell.com/support/kbdoc/en-us/000122176/driver-pack-catalog
# https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment
# https://www.dell.com/support/kbdoc/en-us/000180533/dell-command-deploy-driver-packs

$ProgressPreference = 'SilentlyContinue' # Not showing progress makes "Invoke-WebRequest" downloads MUCH faster: https://stackoverflow.com/a/43477248

if (Test-Path "$PSScriptRoot\DriverPackCatalog-Dell.cab") {
	Remove-Item "$PSScriptRoot\DriverPackCatalog-Dell.cab" -Force
}

if ($IsWindows -or ($null -eq $IsWindows)) {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
}

Invoke-WebRequest -Uri 'http://downloads.dell.com/catalog/DriverPackCatalog.cab' -OutFile "$PSScriptRoot\DriverPackCatalog-Dell.cab"

if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path "$PSScriptRoot\DriverPackCatalog-Dell.cab")) {
	$expandExitCode = (Start-Process 'expand' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList "`"$PSScriptRoot\DriverPackCatalog-Dell.cab`"", "`"$PSScriptRoot\DriverPackCatalog-Dell-NEW.xml`"").ExitCode

	if ($expandExitCode -ne 0) {
		Write-Output ">>> EXPANSION FAILED (EXIT CODE $expandExitCode) <<<"
	}

	if ((Test-Path "$PSScriptRoot\DriverPackCatalog-Dell-NEW.xml") -and (Test-Path "$PSScriptRoot\DriverPackCatalog-Dell.xml")) {
		Remove-Item "$PSScriptRoot\DriverPackCatalog-Dell.xml" -Force
	}

	Move-Item "$PSScriptRoot\DriverPackCatalog-Dell-NEW.xml" "$PSScriptRoot\DriverPackCatalog-Dell.xml" -Force
}

Get-Date

[xml]$dellDriverPackCatalogXML = Get-Content "$PSScriptRoot\DriverPackCatalog-Dell.xml"

# Create Dictionary with $computerModel as key to overwrite old keys with new ones to only download the latest Driver reference.
$driverPacksForSystemIDs = @{}

# Collect all System IDs for Model Names to verify that there are no situations where the wrong Driver Pack could be set for a Model Name
$systemIDsForModelNames = @{}

foreach ($thisDriverPack in $dellDriverPackCatalogXML.DriverPackManifest.DriverPackage) {
	$thisDriverPackSupportedOS = ($thisDriverPack.SupportedOperatingSystems.OperatingSystem | Where-Object 'osArch' -eq 'x64')

	if (($thisDriverPack.type -ne 'winpe') -and ($null -ne $thisDriverPackSupportedOS) -and $thisDriverPackSupportedOS.osCode.StartsWith('Windows')) {
		$systemIDs = ($thisDriverPack.SupportedSystems.Brand.Model.systemID | Where-Object { $_ -ne '06e6' }) # System ID "06e6" is used by both  "latitude 5175" AND "latitude 5179" but each model refers to unique driver packs, so just EXCLUDE the System ID and only rely on the Model Name in this case.

		if ($null -ne $systemIDs) {
			$systemIDs = $systemIDs.Trim().ToLower()
		} else {
			$systemIDs = @()
		}

		if ($systemIDs -is [string]) {
			$systemIDs = @($systemIDs)
		}

		$modelNames = $thisDriverPack.SupportedSystems.Brand.Model.name.Trim().ToLower()

		if ($modelNames -is [string]) {
			$modelNames = @($modelNames)
		}

		$modelNames = ($modelNames | Sort-Object -Unique)

		$modelNames = $modelNames.Replace('precision precision', 'precision') # Fix typo in DriverPackCatalog from Jan 15th, 2021

		$modelNameVariants = @()

		foreach ($thisModelName in $modelNames) {
			# Some Dell Driver Packs have a "-" between the model name and "vPro" or "non-vPro" but the model name may or may not, so include both variants in the Driver Pack model keys.
			if ($thisModelName.EndsWith(' vpro')) {
				$modelNameVariants += $thisModelName.Replace(' vpro', '-vpro')
			} elseif ($thisModelName.EndsWith(' non-vpro')) {
				$modelNameVariants += $thisModelName.Replace(' non-vpro', '-non-vpro')
			} elseif ($thisModelName.EndsWith('-non-vpro')) {
				$modelNameVariants += $thisModelName.Replace('-non-vpro', ' non-vpro')
			} elseif ($thisModelName.EndsWith('-vpro')) {
				$modelNameVariants += $thisModelName.Replace('-vpro', ' vpro')
			}

			if ($null -eq $systemIDsForModelNames[$thisModelName]) {
				$systemIDsForModelNames[$thisModelName] = @()
			}
			$systemIDsForModelNames[$thisModelName] += $systemIDs
		}

		foreach ($thisModelNameVariant in $modelNameVariants) {
			if ($null -eq $systemIDsForModelNames[$thisModelNameVariant]) {
				$systemIDsForModelNames[$thisModelNameVariant] = @()
			}
			$systemIDsForModelNames[$thisModelNameVariant] += $systemIDs
		}

		$systemIDs += $modelNames
		$systemIDs += $modelNameVariants

		$systemIDs = ($systemIDs | Sort-Object -Unique)

		$cabOrExeDownloadURL = "https://downloads.dell.com/$($thisDriverPack.path)"
		$cabOrExeFileName = Split-Path $thisDriverPack.path -Leaf

		foreach ($thisSystemID in $systemIDs) {
			$addDriver = $true

			$osVersionNumber = [decimal]($thisDriverPackSupportedOS.osCode -Replace '[^0-9.]')

			if ($driverPacksForSystemIDs[$thisSystemID]) {
				if ($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber -gt $osVersionNumber) {
					# Write-Output "Skipping OLDER DRIVERS - $thisSystemID - $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber) > $osVersionNumber"
					$addDriver = $false
				} elseif (($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber -eq $osVersionNumber) -and ((Get-Date $driverPacksForSystemIDs[$thisSystemID].date) -gt (Get-Date $thisDriverPack.dateTime))) {
					# Write-Output "Skipping OLDER DRIVERS - $thisSystemID - $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber) == $osVersionNumber && $(Get-Date $driverPacksForSystemIDs[$thisSystemID].date) > $(Get-Date $thisDriverPack.dateTime)"
					$addDriver = $false
				}
			}

			if ($addDriver) {
				$hashSHA256 = ($thisDriverPack.Cryptography.Hash | Where-Object 'algorithm' -like 'SHA2*').InnerText # A few are listed as 'SHA2' while most are 'SHA256'
				if ($null -eq $hashSHA256) { # And a few use hash type specific Keys instead of just 'Hash'
					$hashSHA256 = ($thisDriverPack.Cryptography.hSHA2 | Where-Object 'algorithm' -like 'SHA2*').InnerText
				}

				$driverPacksForSystemIDs[$thisSystemID] = [ordered]@{
					SystemID = $thisSystemID
					DownloadURL = $cabOrExeDownloadURL
					HashSHA256 = $hashSHA256
					OSVersionNumber = $osVersionNumber
					Date = $thisDriverPack.dateTime
					Size = $thisDriverPack.size
					FileName = $cabOrExeFileName
					DriverPackID = $cabOrExeFileName.Replace('.CAB', '').Replace('.exe', '')
				}
			}
		}
	}
}


# As of 2021-01-22 the following 3 conflicts were detected and are ACCEPTABLE. Check again periodically.
# CONFLICT - 04e4 (E6420 XFR-win7-A01-PFXP1) != latitude e6420 (E6420-win8-A03-0D34V) && 7 / 8
# CONFLICT - 0860 (3430-win10-A08-HTT83) != precision 3430 tower (3430-win10-A07-HDC50) && 10 / 10
# CONFLICT - 0861 (3430-win10-A08-HTT83) != precision 3430 tower (3430-win10-A07-HDC50) && 10 / 10
# PS. The following conflict check code is what helped be discovery that '04e4' is used by two different model names and to exclude it, which is done above.
<#
foreach ($theseSystemIDsForModelNames in ($systemIDsForModelNames.GetEnumerator() | Sort-Object -Property Key)) {
	$theseSystemIDs = ($theseSystemIDsForModelNames.Value | Sort-Object -Unique)

	foreach ($thisSystemID in $theseSystemIDs) {
		if ($driverPacksForSystemIDs[$thisSystemID].DriverPackID -ne $driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].DriverPackID) {
			Write-Output "CONFLICT - $thisSystemID ($($driverPacksForSystemIDs[$thisSystemID].DriverPackID)) != $($theseSystemIDsForModelNames.Key) ($($driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].DriverPackID))"
		}
	}
}
#>

$uniqueDriverPacks = @{}
$allUnqiueDriverPacksSize = 0
$redundantDriverPacksSize = 0

foreach ($thisDriverPack in ($driverPacksForSystemIDs.GetEnumerator() | Sort-Object -Property Key)) {
	$redundantDriverPacksSize += $thisDriverPack.Value.Size

	if (-not $uniqueDriverPacks[$thisDriverPack.Value.DriverPackID]) {
		$allUnqiueDriverPacksSize += $thisDriverPack.Value.Size
		$uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] = @($thisDriverPack.Value)
	} else {
		$uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] += $thisDriverPack.Value
	}
}

# We won't need to download all of these, but here are the stats:
# $driverPacksForSystemIDs.Count # 655 as of 01/18/21
# $redundantDriverPacksSize # 621819890978 = 621 GB as of 01/18/21

# THIS IS ALL WE ACTUALL NEED TO DOWNLOAD, SO THAT'S WHAT WE'LL DO:
# $uniqueDriverPacks.Count # 300 as of 01/18/21
# $allUnqiueDriverPacksSize # 270632872288 = 270 GB as of 01/18/21

$cabOrExeCount = 0
$downloadedCount = 0
$validatedCABorEXEcount = 0
$expandedCount = 0
$notEnoughSpaceCount = 0

$dellDriverPacksPath = 'F:\SMB\Drivers\Packs\Dell'

foreach ($theseRedundantDriverPacks in ($uniqueDriverPacks.GetEnumerator() | Sort-Object -Property Key)) {
	$thisUniqueDriverPack = $theseRedundantDriverPacks.Value | Select-Object -First 1

	$cabOrExeCount ++
	Write-Output '----------'
	Write-Output "UNIQUE DRIVER PACK CAB/EXE $cabOrExeCount (USED BY $($theseRedundantDriverPacks.Value.Count) SYSTEM IDs):"

	if ($IsWindows -or ($null -eq $IsWindows)) {
		$theseRedundantDriverPacks.Value.SystemID -Join ', '
	} else {
		foreach ($thisRedundantDriverPack in $theseRedundantDriverPacks.Value) {
			Write-Output '-----'
			$thisRedundantDriverPack | Format-Table -AutoSize -HideTableHeaders
		}
	}

	if ($IsWindows -or ($null -eq $IsWindows)) {
		$thisUniqueDriverPack.DownloadURL
	}

	if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $dellDriverPacksPath)) {
		$cabOrExeDownloadPath = "$dellDriverPacksPath\Unique Driver Pack CABs"
		$cabOrExeExpansionPath = "$dellDriverPacksPath\Unique Driver Packs"

		if (-not (Test-Path $cabOrExeDownloadPath)) {
			New-Item -ItemType 'Directory' -Force -Path $cabOrExeDownloadPath | Out-Null
		}

		if (-not (Test-Path $cabOrExeExpansionPath)) {
			New-Item -ItemType 'Directory' -Force -Path $cabOrExeExpansionPath | Out-Null
		}

		if (-not (Test-Path "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)")) {
			if (Test-Path "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)") {
				Remove-Item "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
			}

			if ((Get-Volume (Get-Item $dellDriverPacksPath).PSDrive.Name).SizeRemaining -ge 10GB) {
				Write-Output 'DOWNLOADING...'
				Invoke-WebRequest -Uri $thisUniqueDriverPack.DownloadURL -OutFile "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)"

				if (Test-Path "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)") {
					$downloadedCount ++

					Write-Output 'VALIDATING CAB/EXE...'
					if (($null -ne $thisUniqueDriverPack.HashSHA256) -and ($thisUniqueDriverPack.HashSHA256 -ne '')) {
						if ((Get-FileHash "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)").Hash -eq $thisUniqueDriverPack.HashSHA256) {
							$validatedCABorEXEcount ++
						} else {
							Write-Output '>>> INVALID - DELETING CAB/EXE <<<'
							Remove-Item "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
						}
					} else {
						Write-Output '!!! NO HASH TO VALIDATE !!!'
					}

					if (Test-Path "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)") {
						Write-Output 'EXPANDING...'

						# CAB expand will FAIL unless we make all necessary directories first (but EXE extraction would not).
						New-Item -ItemType 'Directory' -Force -Path "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" | Out-Null

						$expandExitCode = 9999
						if ($thisUniqueDriverPack.FileName.EndsWith('.CAB')) {
							$expandExitCode = (Start-Process 'expand' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList "`"$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)`"", '/f:*', "`"$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)`"").ExitCode
						} else {
							$expandExitCode = (Start-Process "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)" -NoNewWindow -Wait -PassThru -ArgumentList '/s', "/e=`"$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)`"").ExitCode
						}

						Remove-Item "$cabOrExeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force

						if ($expandExitCode -eq 0) {
							$expandedCount ++
						} else {
							Write-Output ">>> EXPANSION FAILED (EXIT CODE $expandExitCode) - DELETING FOLDER <<<"

							if (Test-Path "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
								Remove-Item "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Recurse -Force
							}
						}
					}
				}
			} else {
				Write-Output 'NOT ENOUGH FREE SPACE TO DOWNLOAD'
				$notEnoughSpaceCount ++
			}
		} else {
			# TODO: Check for basic expected structure to validate expansion.
			Write-Output 'ALREADY DOWNLOADED AND EXPANDED'
		}

		if (Test-Path "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
			# Delete any x86 folders in expanded directory to save space. RESULTED IN 46 GB SAVED!

			Get-ChildItem "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Directory | Get-ChildItem -Directory | Get-ChildItem -Directory | ForEach-Object {
				if ($_.FullName.StartsWith($dellDriverPacksPath)) {
					if ($_.Name.ToLower() -eq 'x86') {
						$x86folderDisplayPath = $_.FullName -Split ('\\Dell\\')
						Write-Output "DELETING x86 FOLDER: $($x86folderDisplayPath[1])"
						Remove-Item $_.FullName -Recurse -Force
					}
				}
			}
		}

		if (Test-Path "$cabOrExeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
			foreach ($thisRedundantDriverPack in $theseRedundantDriverPacks.Value) {
				if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $dellDriverPacksPath)) {
					Set-Content "$dellDriverPacksPath\$($thisRedundantDriverPack.SystemID).txt" "Unique Driver Packs\$($thisRedundantDriverPack.DriverPackID)"
				}
			}
		}
	}
}

if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $dellDriverPacksPath)) {
	Write-Output '----------'
	Write-Output 'CHECKING FOR STRAY DRIVER PACKS...'

	$allReferencedDriverPacks = @()

	Get-ChildItem "$dellDriverPacksPath\*" -File -Include '*.txt' | ForEach-Object {
		$thisDriverPack = ($_ | Get-Content -First 1)

		if (($null -ne $thisDriverPack) -and $thisDriverPack.Contains('\')) {
			$thisDriverPack = $thisDriverPack.Split('\')[1]

			if (-not $allReferencedDriverPacks.Contains($thisDriverPack)) {
				$allReferencedDriverPacks += $thisDriverPack
			}
		}
	}

	Get-ChildItem "$dellDriverPacksPath\Unique Driver Packs" | ForEach-Object {
		if (-not $allReferencedDriverPacks.Contains($_.Name)) {
			Write-Output "DELETING STRAY DRIVER PACK: $($_.Name)"
			Remove-Item $_.FullName -Recurse -Force
		}
	}

	if (Test-Path "$dellDriverPacksPath\Unique Driver Pack CABs") {
		Remove-Item "$dellDriverPacksPath\Unique Driver Pack CABs" -Recurse -Force
	}
}

Write-Output '----------'
Write-Output "FINISHED AT: $(Get-Date)"
Write-Output "DETECTED: $($uniqueDriverPacks.Count) Unique Dell Driver Packs (for $($driverPacksForSystemIDs.Count) System IDs)"
Write-Output "DOWNLOADED: $downloadedCount"
Write-Output "VALIDATED CAB/EXEs: $validatedCABorEXEcount"
Write-Output "EXPANDED: $expandedCount"
Write-Output "NOT ENOUGH SPACE TO DOWNLOAD: $notEnoughSpaceCount"
Write-Output '----------'

if ($IsWindows -or ($null -eq $IsWindows)) {
	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
}

Read-Host 'DONE - PRESS ENTER TO EXIT' | Out-Null
