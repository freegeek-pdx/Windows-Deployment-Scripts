########################################################################################################################################
##                                                                                                                                    ##
##   DO NOT RUN THIS SCRIPT DIRECTLY, LAUNCH "Run Update Windows on FG Install Drives.cmd" INSTEAD WHICH WILL RUN IT FOR EACH DRIVE   ##
##                                                                                                                                    ##
########################################################################################################################################

#
# MIT License
#
# Copyright (c) 2025 Free Geek
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

#Requires -RunAsAdministrator

param(
	[Parameter(Mandatory=$true, Position = 0)]
	[String]$fgInstallDriveLetter,
	[Parameter(Mandatory=$true, Position = 1)]
	[String]$fgWindowsDriveLetter,
	[Parameter(Mandatory=$true, Position = 2)]
	[String]$updateResourcesOnlyString
)

$updateResourcesOnly = ($updateResourcesOnlyString -eq 'True')

$thisDriveTitle = "FG Install `"$fgInstallDriveLetter`" | FG WINDOWS `"$fgWindowsDriveLetter`""

$Host.UI.RawUI.WindowTitle = "Copying - $thisDriveTitle"

$winPEmajorVersion = '11' # It is fine to use WinPE/WinRE from Windows 11 even when Windows 10 will be installed.
$winPEfeatureVersion = '24H2' # WinPE version in the December 2024 ADK is 10.0.26100.1 (11 24H2).

$windowsFeatureVersionsForMajorVersions = @{
	'11' = '25H2' # Build 26200
	# '11' = '24H2' # Build 26100
	# '11' = '23H2' # Build 22631
	# '11' = '22H2' # Build 22621
	# '11' = '21H2' # Build 22000

	'10' = '22H2' # 22H2 is the FINAL feature update for Windows 10: https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-client-roadmap-update/ba-p/3805227
}

$winREfeatureVersionsForWindowsFeatureVersions = @{
	# NOTE: Some (not all) WinRE version included within Windows 11 are one feature version back.
	# (ie. Windows 25H2 includes WinRE 24H2, and Windows 23H2 includes WinRE 22H2)

	'25H2' = '24H2'
	'23H2' = '22H2'
}

Write-Output "`n  $thisDriveTitle"

$startDate = Get-Date
Write-Output "`n  Starting at $startDate..."

$winREfeatureVersion = $windowsFeatureVersionsForMajorVersions[$winPEmajorVersion]
if ($winREfeatureVersionsForWindowsFeatureVersions.ContainsKey($winREfeatureVersion)) {
	$winREfeatureVersion = $winREfeatureVersionsForWindowsFeatureVersions[$winREfeatureVersion]
}

$basePath = "$Env:PUBLIC\Windows Deployment"
if (Test-Path "$Env:PUBLIC\Windows Deployment.lnk") {
	$basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$Env:PUBLIC\Windows Deployment.lnk").TargetPath
}

if (-not (Test-Path $basePath)) {
	New-Item -ItemType 'Directory' -Path $basePath -ErrorAction Stop | Out-Null
}

$winPEorRE = 'WinPE'
$winPEoutputPath = "$basePath\$winPEorRE $winPEmajorVersion $winPEfeatureVersion"
if (-not (Test-Path $winPEoutputPath)) {
	$winPEorRE = 'WinRE'
	$winPEoutputPath = "$basePath\$winPEorRE $winPEmajorVersion Pro $winREfeatureVersion"
}

$winPEsourcePath = "$winPEoutputPath\media"

$verificationError = $false

if (Test-Path $winPEsourcePath) {
	Write-Output "`n  Updating $winPEorRE Contents on `"$fgWindowsDriveLetter`"..."

	$copyWinPEstartDate = Get-Date
	Remove-Item "$fgWindowsDriveLetter\*" -Recurse -Force -ErrorAction Stop # If updating an existing drive, just delete the contents (without re-formatting it) to re-copy the latest.
	Copy-Item "$winPEsourcePath\*" $fgWindowsDriveLetter -Recurse -ErrorAction Stop
	# NOTE: DO NOT use "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\MakeWinPEMedia.cmd"
	# script because it would reformat the specified drive letter, and also set it to be the bootable partition in Legacy BIOS mode,
	# which is unnecessary and would break our existing Legacy BIOS GRUB boot in "FG BOOT" partition.
	# So, without wanting those parts of the script, the only relevant portion is simply copying the files to the specified drive letter which we easily can manually instead.

	# For simplicity for technicians, DO NOT want this WinPE to show up in firmware boot menus,
	# only want to have the single "FG BOOT" partition be bootable (in both Legacy BIOS and UEFI mode),
	# and the GRUB menu in the "FG BOOT" partition has an menu entry to "Install Windows" by chainloading "\EFI\Microsoft\Boot\WinPE.efi" (which "bootmgfw.efi" will be renamed to below).
	# NOTE: There is no option to install Windows in the Legacy BIOS mode GRUB menu since only Windows 11 can be installed, and UEFI mode is a Microsoft requirement for Windows 11.
	Remove-Item "$fgWindowsDriveLetter\bootmgr*", "$fgWindowsDriveLetter\EFI\Boot\boot*.efi" -Force -ErrorAction Stop
	if (Test-Path "$fgWindowsDriveLetter\EFI\Microsoft\Boot\bootmgfw.efi") { # This file may not exist here yet since "MakeWinPEMedia.cmd" copies it into place, which would not have been run (see notes above).
		Move-Item "$fgWindowsDriveLetter\EFI\Microsoft\Boot\bootmgfw.efi" "$fgWindowsDriveLetter\EFI\Microsoft\Boot\WinPE.efi" -Force -ErrorAction Stop
	} elseif (Test-Path "$winPEoutputPath\bootbins\bootmgfw.efi") {
		# FUTURE NOTE: At some point may need to use the "Windows UEFI CA 2023" signed version at "bootmgfw_EX.efi" instead ("MakeWinPEMedia.cmd" has a "/bootex" option to use it).
			# This is because the Microsoft Secure Boot Certificate will expire in June 2026:
			# https://support.microsoft.com/en-us/topic/windows-secure-boot-certificate-expiration-and-ca-updates-7ff40d33-95dc-4c3c-8725-a9b95457578e
			# https://lwn.net/Articles/1029767/
			# https://fwupd.github.io/libfwupdplugin/uefi-db.html

		Copy-Item "$winPEoutputPath\bootbins\bootmgfw.efi" "$fgWindowsDriveLetter\EFI\Microsoft\Boot\WinPE.efi" -Force -ErrorAction Stop
	}

	if (-not (Test-Path "$fgWindowsDriveLetter\EFI\Microsoft\Boot\WinPE.efi")) {
		Write-Host "      FAILED to Rename or Copy WinPE.efi" -ForegroundColor Red
		$verificationError = $true
	}

	if (Test-Path "$winPEoutputPath\boot.wim.checksum") {
		$bootWimChecksum = Get-Content "$winPEoutputPath\boot.wim.checksum" -First 1
	} else {
		Write-Output "    Calculating Checksum for $winPEorRE boot.wim..."
		$bootWimChecksum = (Get-FileHash "$winPEsourcePath\sources\boot.wim").Hash
		Set-Content "$winPEoutputPath\boot.wim.checksum" $bootWimChecksum
	}

	Write-Output "    Verifying $winPEorRE boot.wim..."
	$verifyStartDate = Get-Date
	if ($bootWimChecksum -eq (Get-FileHash "$fgWindowsDriveLetter\sources\boot.wim").Hash) { # Compare filesizes before checksum
		$verifyEndDate = Get-Date
		Write-Output "      Verified $winPEorRE boot.wim at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)"
	} else {
		$verifyEndDate = Get-Date
		Write-Host "      FAILED to Verify $winPEorRE boot.wim at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)" -ForegroundColor Red
		Remove-Item "$fgWindowsDriveLetter\sources\boot.wim" -Force -ErrorAction Stop
		$verificationError = $true
	}

	$copyWinPEendDate = Get-Date
	Write-Output "    Copied $winPEorRE at $copyWinPEendDate ($([math]::Round(($copyWinPEEndDate - $copyWinPEstartDate).TotalMinutes, 2)) Minutes)"
} else {
	Write-Host "  NO WINPE SOURCE FOLDER" -ForegroundColor Yellow
	$verificationError = $true
}

if (-not $verificationError) {
	if ($updateResourcesOnly) {
		Write-Host "`n  SKIPPED UPDATING WINDOWS INSTALLATION IMAGES - UPDATING RESOURCES ONLY" -ForegroundColor Yellow
	} else {
		Write-Output "`n  Updating `"windows-resources\os-images`" Folder Contents on `"$fgInstallDriveLetter`"..."

		if (-not (Test-Path "$fgInstallDriveLetter\windows-resources")) {
			New-Item -ItemType 'Directory' -Path "$fgInstallDriveLetter\windows-resources" -ErrorAction Stop | Out-Null
		}

		$thisVolumeOSImagesPath = "$fgInstallDriveLetter\windows-resources\os-images"
		if (-not (Test-Path $thisVolumeOSImagesPath)) {
			New-Item -ItemType 'Directory' -Path $thisVolumeOSImagesPath -ErrorAction Stop | Out-Null
		}

		$windowsMajorVersions = @('11', '10')

		foreach ($thisWindowsMajorVersion in $windowsMajorVersions) {
			$windowsEditions = @('Pro')
			if ($thisWindowsMajorVersion -eq '11') { # Only include Home for Windows 11 installs since Windows 10 is only kept around for testing and Firmware updates (and will never be licensed or sold) so only Pro is necessary.
				$windowsEditions += 'Home'
			}

			foreach ($thisWindowsEdition in $windowsEditions) {
				$thisWindowsFeatureVersion = $windowsFeatureVersionsForMajorVersions[$thisWindowsMajorVersion]

				$thisWindowsImageSourcePath = "$basePath\Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion"

				if (-not (Test-Path $thisWindowsImageSourcePath)) {
					# NOTE: Windows source folders may have a version suffix ("v1", "v2", etc) from the source ISOs,
					# so if the folders are not found check for up to 10 version suffix folder names.

					for ($possibleISOversionSuffix = 10; $possibleISOversionSuffix -ge 1; $possibleISOversionSuffix --) {
						$thisWindowsImageSourcePath = "$basePath\Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion v$possibleISOversionSuffix"
						if (Test-Path $thisWindowsImageSourcePath) {
							break
						}
					}
				}

				if (Test-Path $thisWindowsImageSourcePath) {
					if ($latestWim = Get-ChildItem "$thisWindowsImageSourcePath\Windows-$thisWindowsMajorVersion-$thisWindowsEdition-$thisWindowsFeatureVersion-*.wim" -Exclude '*-TEMP.wim' | Sort-Object -Property LastWriteTime | Select-Object -Last 1) {
						$latestWimPath = $latestWim.FullName
						$latestWimFilename = $latestWim.Name

						if (Test-Path "$thisVolumeOSImagesPath\Windows-$thisWindowsMajorVersion-$thisWindowsEdition-*.wim") {
							Remove-Item "$thisVolumeOSImagesPath\Windows-$thisWindowsMajorVersion-$thisWindowsEdition-*.wim" -Exclude $latestWimFilename -Force -ErrorAction Stop
						}

						if (Test-Path "$latestWimPath.checksum") {
							$latestWimChecksum = Get-Content "$latestWimPath.checksum" -First 1
						} else {
							Write-Output "    Calculating Checksum for Source $latestWimFilename..."
							$latestWimChecksum = (Get-FileHash $latestWimPath).Hash
							Set-Content "$latestWimPath.checksum" $latestWimChecksum
						}

						if (Test-Path "$thisVolumeOSImagesPath\$latestWimFilename") {
							Write-Output "    Verifying Existing $latestWimFilename..."
							$verifyExistingStartDate = Get-Date
							if ($latestWimChecksum -eq (Get-FileHash "$thisVolumeOSImagesPath\$latestWimFilename").Hash) { # Compare filesizes before checksum
								$verifyExistingEndDate = Get-Date
								Write-Output "      KEEPING Verified Existing $latestWimFilename`n        at $verifyExistingEndDate ($([math]::Round(($verifyExistingEndDate - $verifyExistingStartDate).TotalMinutes, 2)) Minutes)"
							} else {
								$verifyExistingEndDate = Get-Date
								Write-Host "      DELETING Invalid Existing $latestWimFilename`n        at $verifyExistingEndDate ($([math]::Round(($verifyExistingEndDate - $verifyExistingStartDate).TotalMinutes, 2)) Minutes)" -ForegroundColor Yellow
								Remove-Item "$fgInstallDriveLetter\$latestWimFilename" -Force -ErrorAction Stop
							}
						}

						if (-not (Test-Path "$thisVolumeOSImagesPath\$latestWimFilename")) {
							Write-Output "    Copying Latest Windows $thisWindowsMajorVersion $thisWindowsEdition Install Image: $latestWimFilename..."
							$copyStartDate = Get-Date
							Copy-Item $latestWimPath $thisVolumeOSImagesPath -ErrorAction Stop
							$copyEndDate = Get-Date
							Write-Output "      Copied $latestWimFilename at $copyEndDate ($([math]::Round(($copyEndDate - $copyStartDate).TotalMinutes, 2)) Minutes)"

							Write-Output "    Verifying $latestWimFilename..."
							$verifyStartDate = Get-Date
							if ($latestWimChecksum -eq (Get-FileHash "$thisVolumeOSImagesPath\$latestWimFilename").Hash) { # Compare filesizes before checksum
								$verifyEndDate = Get-Date
								Write-Output "      Verified $latestWimFilename at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)"
							} else {
								$verifyEndDate = Get-Date
								Write-Host "      FAILED to Verify $latestWimFilename at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)" -ForegroundColor Red
								Remove-Item "$thisVolumeOSImagesPath\$latestWimFilename" -Force -ErrorAction Stop
								$verificationError = $true
							}
						}
					} else {
						Write-Host "    NO WINDOWS $thisWindowsMajorVersion $thisWindowsEdition INSTALL IMAGE FILE" -ForegroundColor Yellow
					}
				} else {
					Write-Host "    NO WINDOWS $thisWindowsMajorVersion $thisWindowsEdition INSTALL IMAGE FOLDER" -ForegroundColor Yellow
				}
			}
		}
	}
}


if (-not $verificationError) {
	Write-Output "`n  Updating `"windows-resources\setup-resources`" Folder Contents on `"$fgInstallDriveLetter`"..."

	if (Test-Path "$fgInstallDriveLetter\windows-resources\setup-resources") {
		Remove-Item "$fgInstallDriveLetter\windows-resources\setup-resources" -Recurse -Force -ErrorAction Stop
	}

	$setupResourcesSourcePath = "$(Split-Path -Parent $PSScriptRoot)\Setup Resources"
	if (Test-Path $setupResourcesSourcePath) {
		$copySetupResourcesStartDate = Get-Date
		Copy-Item $setupResourcesSourcePath "$fgInstallDriveLetter\windows-resources\setup-resources" -Recurse -ErrorAction Stop
		$copySetupResourcesEndDate = Get-Date
		Write-Output "    Copied Setup Resources at $copySetupResourcesEndDate ($([math]::Round(($copySetupResourcesEndDate - $copySetupResourcesStartDate).TotalMinutes, 2)) Minutes)"
	} else {
		Write-Host "  NO SETUP RESOURCES SOURCE FOLDER" -ForegroundColor Yellow
	}


	Write-Output "`n  Updating `"windows-resources\app-installers`" Folder Contents on `"$fgInstallDriveLetter`"..."

	if (Test-Path "$fgInstallDriveLetter\windows-resources\app-installers") {
		Remove-Item "$fgInstallDriveLetter\windows-resources\app-installers" -Recurse -Force -ErrorAction Stop
	}

	$appInstallersSourcePath = "$PSScriptRoot\App Installers"
	if (Test-Path $appInstallersSourcePath) {
		New-Item -ItemType 'Directory' -Path "$fgInstallDriveLetter\windows-resources\app-installers" -ErrorAction Stop | Out-Null

		Get-ChildItem $appInstallersSourcePath -Exclude '*.sh', '*.ps1' -ErrorAction Stop | ForEach-Object {
			$copyAppInstallersStartDate = Get-Date
			Copy-Item $_ "$fgInstallDriveLetter\windows-resources\app-installers" -Recurse -Force -ErrorAction Stop
			$copyAppInstallersEndDate = Get-Date
			Write-Output "    Copied `"$($_.Name)`" App Installers at $copyAppInstallersEndDate ($([math]::Round(($copyAppInstallersEndDate - $copyAppInstallersStartDate).TotalMinutes, 2)) Minutes)"
		}
	} else {
		Write-Host "    NO APP INSTALLERS SOURCE FOLDER" -ForegroundColor Yellow
	}
}

if (Test-Path "$fgInstallDriveLetter\windows-ERROR.txt") {
	Remove-Item "$fgInstallDriveLetter\windows-ERROR.txt" -Force -ErrorAction Stop
}

if (Test-Path "$fgInstallDriveLetter\windows-updated.txt") {
	Remove-Item "$fgInstallDriveLetter\windows-updated.txt" -Force -ErrorAction Stop
}

if ($verificationError) {
	Set-Content "$fgInstallDriveLetter\windows-ERROR.txt" $(Get-Date -UFormat '%Y%m%d')

	Write-Host "`n  ERROR COPYING SOME FILES" -ForegroundColor Red

	$Host.UI.RawUI.WindowTitle = "ERROR - $thisDriveTitle"
} else {
	Set-Content "$fgInstallDriveLetter\windows-updated.txt" $(Get-Date -UFormat '%Y%m%d')

	Write-Host "`n  SUCCESSFULLY COPIED ALL FILES" -ForegroundColor Green

	$Host.UI.RawUI.WindowTitle = "DONE - $thisDriveTitle"
}

$endDate = Get-Date

$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
Read-Host "`n  Finished $thisDriveTitle at $endDate ($([math]::Round(($endDate - $startDate).TotalMinutes, 2)) Minutes)" | Out-Null
[System.Environment]::Exit(0) # This script is launched with "-NoExit" so that any Stop errors don't close the window immediatly. But if we got here, we want the window to close after pressing Enter (and just running "exit" doesn't do that).
