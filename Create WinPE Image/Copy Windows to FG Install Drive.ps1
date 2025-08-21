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

param(
	[Parameter(Mandatory=$true, Position = 0)]
	[String]$fgInstallDriveLetter,
	[Parameter(Mandatory=$true, Position = 1)]
	[String]$fgWindowsDriveLetter
)

$thisDriveTitle = "FG Install `"$fgInstallDriveLetter`" | FG WINDOWS `"$fgWindowsDriveLetter`""

$Host.UI.RawUI.WindowTitle = "Copying - $thisDriveTitle"

Write-Output "`n  $thisDriveTitle"

$startDate = Get-Date
Write-Output "`n  Starting at $startDate..."

$windows10featureVersion = '22H2' # 22H2 is the FINAL feature update for Windows 10: https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-client-roadmap-update/ba-p/3805227
$windows11featureVersion = '24H2'

$winPEmajorVersion = '11' # It is fine to use WinPE/WinRE from Windows 11 even when Windows 10 will be installed.
$winPEfeatureVersion = $windows11featureVersion

$basePath = "$HOME\Documents\Free Geek"
if (Test-Path "$HOME\Documents\Free Geek.lnk") {
	$basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Documents\Free Geek.lnk").TargetPath
}

$winPEoutputPath = "$basePath\WinPE $winPEmajorVersion $winPEfeatureVersion"
$winPEsourcePath = "$winPEoutputPath\media"

$verificationError = $false

if (Test-Path $winPEsourcePath) {
	Write-Output "`n  Updating WinPE Contents on `"$fgWindowsDriveLetter`"..."

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
	Remove-Item "$fgWindowsDriveLetter\bootmgr*", "$fgWindowsDriveLetter\EFI\Boot\bootx64.efi" -Force -ErrorAction Stop
	Move-Item "$fgWindowsDriveLetter\EFI\Microsoft\Boot\bootmgfw.efi" "$fgWindowsDriveLetter\EFI\Microsoft\Boot\WinPE.efi" -Force -ErrorAction Stop

	if (Test-Path "$winPEoutputPath\boot.wim.checksum") {
		$bootWimChecksum = Get-Content "$winPEoutputPath\boot.wim.checksum" -First 1
	} else {
		Write-Output "    Calculating Checksum for WinPE boot.wim..."
		$bootWimChecksum = (Get-FileHash "$winPEsourcePath\sources\boot.wim" -Algorithm 'SHA256').Hash
		Set-Content "$winPEoutputPath\boot.wim.checksum" $bootWimChecksum
	}

	Write-Output "    Verifying WinPE boot.wim..."
	$verifyStartDate = Get-Date
	if ($bootWimChecksum -eq (Get-FileHash "$fgWindowsDriveLetter\sources\boot.wim" -Algorithm 'SHA256').Hash) { # Compare filesizes before checksum
		$verifyEndDate = Get-Date
		Write-Output "      Verified WinPE boot.wim at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)"
	} else {
		$verifyEndDate = Get-Date
		Write-Host "      FAILED to Verify WinPE boot.wim at $verifyEndDate ($([math]::Round(($verifyEndDate - $verifyStartDate).TotalMinutes, 2)) Minutes)" -ForegroundColor Red
		Remove-Item "$fgWindowsDriveLetter\sources\boot.wim" -Force -ErrorAction Stop
		$verificationError = $true
	}

	$copyWinPEendDate = Get-Date
	Write-Output "    Copied WinPE at $copyWinPEendDate ($([math]::Round(($copyWinPEEndDate - $copyWinPEstartDate).TotalMinutes, 2)) Minutes)"
} else {
	Write-Host "  NO WINPE SOURCE FOLDER" -ForegroundColor Yellow
	$verificationError = $true
}

if (-not $verificationError) {
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
			$thisWindowsFeatureVersion = $windows11featureVersion
			if ($thisWindowsMajorVersion -eq '10') {
				$thisWindowsFeatureVersion = $windows10featureVersion
			}

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
						$latestWimChecksum = (Get-FileHash $latestWimPath -Algorithm 'SHA256').Hash
						Set-Content "$latestWimPath.checksum" $latestWimChecksum
					}

					if (Test-Path "$thisVolumeOSImagesPath\$latestWimFilename") {
						Write-Output "    Verifying Existing $latestWimFilename..."
						$verifyExistingStartDate = Get-Date
						if ($latestWimChecksum -eq (Get-FileHash "$thisVolumeOSImagesPath\$latestWimFilename" -Algorithm 'SHA256').Hash) { # Compare filesizes before checksum
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
						if ($latestWimChecksum -eq (Get-FileHash "$thisVolumeOSImagesPath\$latestWimFilename" -Algorithm 'SHA256').Hash) { # Compare filesizes before checksum
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
