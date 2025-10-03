#################################################################
##                                                             ##
##   TO RUN THIS SCRIPT, LAUNCH "Run Create WinPE Image.cmd"   ##
##                                                             ##
#################################################################

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

# Requires ADK with WinPE Add-On: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install

# Reference (Adding PowerShell to WinPE): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe
# Reference (Optimize and Shrink WinPE): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-optimize

# IMPORTANT: "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat" must be run from within the CMD launcher file first for "copype" to work.

$Host.UI.RawUI.WindowTitle = 'Create WinPE Image'

$createISO = $false;
$includeResourcesInUSB = $false;

$windows10featureVersion = '22H2' # 22H2 is the FINAL feature update for Windows 10: https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-client-roadmap-update/ba-p/3805227
$windows11featureVersion = '25H2'

$winPEmajorVersion = '11' # It is fine to use WinPE/WinRE from Windows 11 even when Windows 10 will be installed.
$winPEfeatureVersion = $windows11featureVersion
$winREfeatureVersion = $winPEfeatureVersion

$basePath = "$HOME\Documents\Free Geek"
if (Test-Path "$HOME\Documents\Free Geek.lnk") {
	$basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Documents\Free Geek.lnk").TargetPath
}

$winPEname = "WinPE-$winPEmajorVersion-$winPEfeatureVersion"

$winPEoutputPath = "$basePath\$($winPEname.Replace('-', ' '))"

$winPEextraDriversPath = "$basePath\WinPE Extra Drivers to Install"
$winREnetDriversPath = "$basePath\WinRE Network Drivers for USB Install"

$winREimagesSourcePath = "$basePath\Windows $winPEmajorVersion Pro $winREfeatureVersion"

if (-not (Test-Path $winREimagesSourcePath)) {
	# NOTE: Windows source folders may have a version suffix ("v1", "v2", etc) from the source ISOs,
	# so if the folders are not found check for up to 10 version suffix folder names.

	for ($possibleISOversionSuffix = 10; $possibleISOversionSuffix -ge 1; $possibleISOversionSuffix --) {
		$winREimagesSourcePath = "$basePath\Windows $winPEmajorVersion Pro $winREfeatureVersion v$possibleISOversionSuffix"
		if (Test-Path $winREimagesSourcePath) {
			break
		}
	}
}

$winREname = "WinRE-$winPEmajorVersion-Pro-$winREfeatureVersion"

$setupResourcesSourcePath = "$(Split-Path -Parent $PSScriptRoot)\Setup Resources" # Used to include "setup-resources" folder in WinPE USB
$appInstallersSourcePath = "$PSScriptRoot\App Installers" # Used to include "app-installers" folder in WinPE USB

Write-Output "`n  Creating WinPE Image...`n`n`n`n" # Add empty lines for PowerShell progress UI

$systemTempDir = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine') # Get SYSTEM (not user) temporary directory, which should be "\Windows\Temp".
if (-not (Test-Path $systemTempDir)) {
	$systemTempDir = '\Windows\Temp'
}

if ((Test-Path "$systemTempDir\mountPE") -and ((Get-ChildItem "$systemTempDir\mountPE").Count -gt 0)) {
	Write-Output "`n  Unmounting Previously Mounted WinPE Image..."
	Dismount-WindowsImage -Path "$systemTempDir\mountPE" -Discard -ErrorAction Stop | Out-Null
	Remove-Item "$systemTempDir\mountPE" -Recurse -Force -ErrorAction Stop
}

$updateResourcesOnly = $false

if (Test-Path "$winPEoutputPath\media\sources\boot.wim") {
	if ((-not (Test-Path "$winPEoutputPath\$winPEname.wim")) -and (Test-Path "$winPEoutputPath\WinRE-$winPEmajorVersion-$winREfeatureVersion.wim")) {
		$winPEname = "WinRE-$winPEmajorVersion-$winREfeatureVersion"
	}

	$promptCaption = "  `"$winPEname`" Has Already Been Created - Want do you want to do?"
	$promptChoices = 'E&xit', '&Update Resources Only', 'Delete and Re-&Create'

	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
	$promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 1)
	Write-Output ''

	if ($promptResponse -eq 0) {
		exit 0
	} elseif ($promptResponse -eq 1) {
		$updateResourcesOnly = $true
	} elseif (Test-Path $winPEoutputPath) {
		Remove-Item $winPEoutputPath -Recurse -Force -ErrorAction Stop
	}
}


# Launch "Download Latest Windows App Installers.ps1" and "Download Network Drivers for WinRE USB Install from Cache.ps1" in external PowerShell windows (minimized) to run simultaneously.
# They both should finish before those updated files are used within this script.
Start-Process 'powershell' -WindowStyle Minimized -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle Minimized', '-ExecutionPolicy Unrestricted', "-File `"$PSScriptRoot\App Installers\Download Latest Windows App Installers.ps1`"" -ErrorAction Stop
Start-Process 'powershell' -WindowStyle Minimized -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle Minimized', '-ExecutionPolicy Unrestricted', "-File `"$PSScriptRoot\Download Network Drivers for WinRE USB Install from Cache.ps1`"" -ErrorAction Stop


if ($updateResourcesOnly) {
	if (Test-Path "$winPEoutputPath\media\sources\boot.wim") {
		if (Test-Path "$winPEoutputPath\$winPEname.wim") {
			Write-Output "`n  Deleting Previous `"boot.wim`" to Update Resources Within `"$winPEname.wim`"..."
			Remove-Item "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop

			Write-Output "  Moving Previous `"$winPEname.wim`" to `"boot.wim`" to Update Resources..."
			Move-Item "$winPEoutputPath\$winPEname.wim" "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
		}
	} else {
		Write-Host "`n    ERROR: `"boot.wim`" DOES NOT EXIST - CANNOT UPDATE RESOURCES - THIS SHOULD NOT HAVE HAPPENED" -ForegroundColor Red
		exit 1
	}
} else {
	if (Test-Path $winPEoutputPath) {
		Remove-Item $winPEoutputPath -Recurse -Force -ErrorAction Stop
	}

	Write-Output "`n  Copying New WinPE Image from ADK..."
	$copypeExitCode = (Start-Process 'copype' -NoNewWindow -Wait -PassThru -ArgumentList 'amd64', "`"$winPEoutputPath`"").ExitCode

	if ($copypeExitCode -ne 0) {
		Write-Host "`n    ERROR: FAILED TO RUN COPYPE - EXIT CODE: $copypeExitCode" -ForegroundColor Red
		exit $copypeExitCode
	}

	# Delete the "mount" folder created by ADK since we won't use it.
	Remove-Item "$winPEoutputPath\mount" -Recurse -Force -ErrorAction Stop

	if ((Test-Path "$winPEoutputPath\media\sources\boot.wim") -and (Test-Path $winREimagesSourcePath) -and ($latestWinRE = Get-ChildItem "$winREimagesSourcePath\$winREname-*.wim" -Exclude '*-TEMP.wim' | Sort-Object -Property LastWriteTime | Select-Object -Last 1)) {
		$latestWinREpath = $latestWinRE.FullName
		$latestWinREfilename = $latestWinRE.BaseName

		$promptCaption = "  Would you like to REPLACE WinPE from the ADK with $latestWinREfilename from Windows $winPEmajorVersion Pro ($winREfeatureVersion)?"
		$promptMessage = "`n  WinRE can support Wi-Fi (with the correct drivers) and Audio and also has the `"BCD`" and `"boot.sdi`" files built-in`n  for iPXE/wimboot to extract and load automatically without having to include and specify them seperately.`n`n"
		$promptChoices = '&Yes', '&No'

		# Info about replacing WinPE with WinRE: https://msendpointmgr.com/2018/03/06/build-a-winpe-with-wireless-support/

		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		$promptResponse = $Host.UI.PromptForChoice($promptCaption, $promptMessage, $promptChoices, 0)
		Write-Output ''

		if ($promptResponse -eq 0) {
			Remove-Item "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
			Copy-Item $latestWinREpath "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
		}
	} else {
		Write-Host "    NO WINRE IMAGE FILE FOUND" -ForegroundColor Yellow
	}
}


$startDate = Get-Date
Write-Output "`n  Starting at $startDate..."

$wimDetails = Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop
$wimDetails # Print wimDetails

$wimImageBaseName = 'WinPE'
if ($wimDetails.ImageName -like '*Recovery Environment*') {
	$wimImageBaseName = 'WinRE'
	$winPEname = "$wimImageBaseName-$winPEmajorVersion-$winREfeatureVersion"
}

function Add-WinPECustomizations {
	$excludedCompareWinPeWimContentPaths = @('\Install\', '\Windows\Microsoft.NET\', '\Windows\servicing\', '\Windows\System32\CatRoot\', '\Windows\System32\DriverStore\FileRepository\', '\Windows\WinSxS\') # Exclude these paths from the difference comparison because these are the paths we expect to be different (even though "\Install\" and "\Windows\Microsoft.NET\" will only exist on the updated image, exclude them too to make the comparison lists smaller so the comparison is faster).
	$sourceWinPeWimSizeBytes = (Get-Item "$winPEoutputPath\media\sources\boot.wim").Length
	$sourceWinPeWimContentPaths = Get-WindowsImageContent -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 | Select-String $excludedCompareWinPeWimContentPaths -SimpleMatch -NotMatch # Exclude paths from the source lists since it's more efficient than letting them be compared and ignoring them from the results.

	Write-Output "`n  Mounting $winPEname Image..."

	if (-not (Test-Path "$systemTempDir\mountPE")) {
		New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE" -ErrorAction Stop | Out-Null
	}

	# Dism /Mount-Image /ImageFile:"C:\WinPE_amd64_PS\media\sources\boot.wim" /Index:1 /MountDir:"C:\WinPE_amd64_PS\mount"
	Mount-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -Path "$systemTempDir\mountPE" -CheckIntegrity -ErrorAction Stop | Out-Null


	Write-Output "`n  Increasing $winPEname Scratch Space..."
	# Increase WinPE Scratch Space: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize#add-temporary-storage-scratch-space
	# If too manu GUI apps get launched during testing it appears the limited default of 32 MB of scratch space can get used up and then other stuff can fail to load such as required DISM PowerShell modules.

	Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Get-ScratchSpace'

	# PowerShell equivalent of DISM's "/Set-ScratchSpace" does not seem to exist.
	$dismSetScratchSpaceExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Set-ScratchSpace:512').ExitCode

	if ($dismSetScratchSpaceExitCode -ne 0) {
		Write-Host "`n    ERROR: FAILED TO INCREASE $winPEname SCRATCH SPACE - EXIT CODE: $dismSetScratchSpaceExitCode" -ForegroundColor Red
		exit $dismSetScratchSpaceExitCode
	}


	$winPEoptionalFeatures = (Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Enabled).FeatureName | Sort-Object -Unique
	# Pre-Installed WinPE Features: *NONE*
	# Pre-Installed WinRE Features: Microsoft-Windows-WinPE-ATBroker-Package, Microsoft-Windows-WinPE-AudioCore-Package, Microsoft-Windows-WinPE-AudioDrivers-Package, Microsoft-Windows-WinPE-Narrator-Package, Microsoft-Windows-WinPE-Speech-TTS-Package, Microsoft-Windows-WinPE-SRH-Package, WinPE-EnhancedStorage, WinPE-FMAPI-Package, WinPE-HTA, WinPE-Rejuv, WinPE-Scripting, WinPE-SecureStartup, WinPE-SRT, WinPE-StorageWMI, WinPE-TPM, WinPE-WDS-Tools, WinPE-WiFi, WinPE-WMI

	Write-Output "`n  Installed Features BEFORE PowerShell: $($winPEoptionalFeatures -Join ', ')"

	Write-Output "`n  Installing PowerShell Into $winPEname Image..."
	$winPEpackagesToInstall = @('WMI', 'NetFX', 'Scripting', 'PowerShell', 'StorageWMI', 'DismCmdlets')
	foreach ($thisWinPEpackageToInstall in $winPEpackagesToInstall) {
		if ($winPEoptionalFeatures -notcontains "WinPE-$thisWinPEpackageToInstall") { # Some of these will already be installed if we are starting with a WinRE image...
			$packageStartDate = Get-Date
			Write-Output "    Installing $thisWinPEpackageToInstall Package Into $winPEname Image at $packageStartDate..."
			# Dism /Add-Package /Image:"C:\WinPE_amd64_PS\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-PACKAGENAME.cab"
			Add-WindowsPackage -Path "$systemTempDir\mountPE" -PackagePath "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-$thisWinPEpackageToInstall.cab" -WarningAction Stop -ErrorAction Stop | Out-Null
			# Dism /Add-Package /Image:"C:\WinPE_amd64_PS\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-PACKAGENAME_en-us.cab"
			Add-WindowsPackage -Path "$systemTempDir\mountPE" -PackagePath "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-$($thisWinPEpackageToInstall)_en-us.cab" -WarningAction Stop -ErrorAction Stop | Out-Null
			$packageEndDate = Get-Date
			Write-Output "      Finished Installing at $packageEndDate ($([math]::Round(($packageEndDate - $packageStartDate).TotalMinutes, 2)) Minutes)"
		} else {
			Write-Output "    $thisWinPEpackageToInstall Package ALREADY INSTALLED"
		}
	}

	$winPEoptionalFeatures = (Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Enabled).FeatureName | Sort-Object -Unique
	Write-Output "`n  Installed Features AFTER PowerShell: $($winPEoptionalFeatures -Join ', ')"

	Write-Output "`n  Disabled Features: $((Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Disabled | Sort-Object -Unique).FeatureName -Join ', ')"


	Write-Output "`n  Setting LongPathsEnabled in $winPEname Registry..."

	# IMPORTANT: Some Lenovo Driver Packs create very long paths and LongPathsEnabled needs to be set in WinPE to be able to successfully read the files at long paths within these Driver Packs.
	# https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=powershell#enable-long-paths-in-windows-10-version-1607-and-later
	# To edit registry of offline wim: https://www.tenforums.com/tutorials/95002-dism-edit-registry-offline-image.html

	$regLoadExitCode = (Start-Process 'reg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList 'load', "HKLM\OFFLINE-$winPEname-SYSTEM", "`"$systemTempDir\mountPE\Windows\System32\Config\System`"").ExitCode

	if ($regLoadExitCode -eq 0) {
		$winPEfileSystemRegistryPath = "HKLM:\OFFLINE-$winPEname-SYSTEM\ControlSet001\Control\FileSystem"

		if (Test-Path $winPEfileSystemRegistryPath) {
			if ((Get-ItemProperty $winPEfileSystemRegistryPath).LongPathsEnabled -ne 1) {
				Set-ItemProperty $winPEfileSystemRegistryPath -Name 'LongPathsEnabled' -Value 1 -Type 'DWord' -Force | Out-Null

				if ((Get-ItemProperty $winPEfileSystemRegistryPath).LongPathsEnabled -eq 1) {
					Write-Output "    Set LongPathsEnabled to 1 in $winPEname Registry"
				} else {
					Write-Output "    !!! FAILED TO SET LongPathsEnabled TO 1 IN $winPEname REGISTRY !!!"
				}
			} else {
				Write-Output "    LongPathsEnabled Already Set to 1 in $winPEname Registry"
			}
		} else {
			Write-Output "    !!! $winPEname SYSTEM REGISTRY PATH NOT FOUND !!!"
		}
	} else {
		Write-Output "    !!! FAILED TO LOAD $winPEname SYSTEM REGISTRY !!!"
	}

	$regUnloadExitCode = (Start-Process 'reg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList 'unload', "HKLM\OFFLINE-$winPEname-SYSTEM").ExitCode

	if ($regUnloadExitCode -ne 0) {
		Write-Output "    !!! FAILED TO UNLOAD $winPEname SYSTEM REGISTRY !!!"
	}


	if (Test-Path "$PSScriptRoot\Process Explorer Exports for Missing DLLs") {
		$processExplorerExportsToParse = Get-ChildItem "$PSScriptRoot\Process Explorer Exports for Missing DLLs\*" -Include '*.exe.txt', '*.dll.txt'

		# NOTE ABOUT DETECTING REQUIRED DLLs FOR AN APP:
		# Before exporting the list of DLLs as described below, click around in the desired app and perform all the actions that will be performed in WinPE so any extra DLLs get loaded as they may not be needed/loaded yet right when an app launches.

		# Process Explorer: https://docs.microsoft.com/en-us/sysinternals/downloads/process-explorer
		# In Process Explorer, first make sure "Show Lower Pane" is enabled and the "DLLs" tab is select and visible in the lower pane (otherwise the list of DLLs will not get exported in the next step).
		# Then, select desired running process (such as "javaw.exe") in the list and choose "Save" to save the process info (which includes DLLs) into a text file (ending in ".exe.txt") into the "Process Explorer Exports for Missing DLLs" for parsing below.
		# IMPORTANT: Any missing DLLs detected will be copied from the running version of Windows into WinPE/WinRE, so the running version should be compatible with the feature version (ie. Win 10 22H2) as the WinPE/WinRE version.

		if ($processExplorerExportsToParse.Count -gt 0) {
			Write-Output "`n  Checking Process Explorer Exports for Missing DLLs in $winPEname Image..."

			$copiedDLLcount = 0

			# When re-detecting Java QA Helper DLLs on Windows 10 21H2 with Java 17.0.1 to make sure everything was up-to-date,
			# new DLLs were detected since the last time when last detected on Windows 10 2004 with Java 15.
			# But, the new set of DLLs caused Wpeinit.exe to stall and then exit with error code -2147023436.
			# So, ignore any problematic DLLs here in code so that any future DLL detections don't accidentally bring this issue back.
			# The one problematic DLL listed here was figured out through trial and error by arbitrarily ignoring sets of the new DLLs until Wpeinit.exe worked with the fewest possible DLLs ignored.
			$ignoreMissingDLLs = @('policymanager.dll')

			$processExplorerExportsToParse | ForEach-Object {
				Write-Output "    Analyzing `"$($_.Name)`" Process Explorer Export for Missing DLLs..."

				foreach ($thisProcessExplorerLogLine in (Get-Content $_.FullName)) {
					if ($thisProcessExplorerLogLine.Contains('\Windows\System32\') -and (-not ($thisProcessExplorerLogLine.Contains('\DriverStore\FileRepository\'))) -and (-not ($thisProcessExplorerLogLine.EndsWith('.exe')))) {
						$thisDLLPathInOS = $thisProcessExplorerLogLine -Replace '^[^:\\]*:\\', '\'
						$thisDLLPathInWinPE = $thisProcessExplorerLogLine -Replace '^[^:\\]*:\\', "$systemTempDir\mountPE\"

						if (-not (Test-Path $thisDLLPathInWinPE)) {
							if ($ignoreMissingDLLs.Contains($(Split-Path $thisDLLPathInOS -Leaf))) {
								Write-Output "      Ignoring Missing DLL From `"$($_.BaseName)`": $thisDLLPathInOS"
							} else {
								Write-Output "      Copying Missing DLL From `"$($_.BaseName)`" Into $winPEname Image: $thisDLLPathInOS"
								Copy-Item $thisDLLPathInOS $thisDLLPathInWinPE -ErrorAction Stop
								$copiedDLLcount ++
							}
						}
					}
				}
			}

			Write-Output "    Copied $copiedDLLcount Missing DLLs Into $winPEname Image"
		} else {
			Write-Host "`n  NO EXPORTS IN `"Process Explorer Exports for Missing DLLs`" TO PARSE" -ForegroundColor Yellow
		}
	} else {
		Write-Host "`n  NO `"Process Explorer Exports for Missing DLLs`" FOLDER" -ForegroundColor Yellow
	}


	if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\W32tm.exe")) {
		Write-Output "`n  Copying `"W32tm.exe`" Into $winPEname Image..."

		# Install W32tm.exe into WinPE so we can sync time in WinPE to be sure QA Helper can be installed since if time is far off HTTPS will fail.
		Copy-Item '\Windows\System32\W32tm.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
	}

	if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\taskkill.exe")) {
		Write-Output "`n  Copying `"taskkill.exe`" Into $winPEname Image for QA Helper to Use..."

		# Install taskkill.exe into WinPE so we can call it from QA Helper for convenience of not having to rely on killing with PowerShell (which is slower to load).
		Copy-Item '\Windows\System32\taskkill.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
	}

	if ($winPEoptionalFeatures -contains 'Microsoft-Windows-WinPE-AudioDrivers-Package') {
		# WinRE supports audio, so add these files for QA Helper to be able to use.

		if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\SndVol.exe")) {
			Write-Output "`n  Copying `"SndVol.exe`" Into $winPEname Image for QA Helper Audio Test..."

			Copy-Item '\Windows\System32\SndVol.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
		}

		if (-not (Test-Path "$systemTempDir\mountPE\Windows\Media")) {
			Write-Output "`n  Copying Success and Error Sound Files Into $winPEname Image for QA Helper to Use..."

			New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE\Windows\Media" -ErrorAction Stop | Out-Null

			Copy-Item '\Windows\Media\Windows Foreground.wav' "$systemTempDir\mountPE\Windows\Media" -Force -ErrorAction Stop
			Copy-Item '\Windows\Media\Windows Exclamation.wav' "$systemTempDir\mountPE\Windows\Media" -Force -ErrorAction Stop
		}
	}


	if (Test-Path "$PSScriptRoot\System32 Folder Resources") {
		$system32FolderResourcesToCopy = Get-ChildItem "$PSScriptRoot\System32 Folder Resources"

		if ($system32FolderResourcesToCopy.Count -gt 0) {
			Write-Output "`n  Copying System32 Folder Resources Into $winPEname Image..."
			Copy-Item "$PSScriptRoot\System32 Folder Resources\*" "$systemTempDir\mountPE\Windows\System32" -Recurse -Force -ErrorAction Stop
		} else {
			Write-Host "`n  NOTHING IN `"System32 Folder Resources`" TO COPY" -ForegroundColor Yellow
		}
	} else {
		Write-Host "`n  NO `"System32 Folder Resources`" FOLDER" -ForegroundColor Yellow
	}


	if (Test-Path "$PSScriptRoot\Install Folder Resources") {
		$windows11SupportedProcessorsListsBasePath = "$(Split-Path -Parent $PSScriptRoot)\Other Stuff\Windows 11 Supported Processors Lists"
		if (-not (Test-Path "$windows11SupportedProcessorsListsBasePath\Windows 11 Supported Processors Lists $(Get-Date -Format 'yyyy.M.d')")) {
			Write-Output "`n  Updating Latest Windows 11 Supported Processors Lists for WhyNotWin11 to Use..."
			Start-Process 'powershell' -NoNewWindow -Wait -ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy Unrestricted', "-File `"$windows11SupportedProcessorsListsBasePath\Update Windows 11 Supported Processors Lists.ps1`"" -ErrorAction Stop
		}

		$windows11SupportedProcessorsListsInInstallFolderScriptsBasePath = "$PSScriptRoot\Install Folder Resources\Scripts\Windows 11 Supported Processors Lists"
		if (Test-Path $windows11SupportedProcessorsListsInInstallFolderScriptsBasePath) {
			Remove-Item $windows11SupportedProcessorsListsInInstallFolderScriptsBasePath -Recurse -Force -ErrorAction Stop
		}

		New-Item -ItemType 'Directory' -Path $windows11SupportedProcessorsListsInInstallFolderScriptsBasePath -ErrorAction Stop | Out-Null

		$latestWindows11SupportedAMDProcessorsListPath = (Get-ChildItem "$windows11SupportedProcessorsListsBasePath\Windows 11 Supported Processors Lists 20*\SupportedProcessorsAMD.txt" -File | Sort-Object -Property CreationTime | Select-Object -Last 1).FullName
		if (Test-Path $latestWindows11SupportedAMDProcessorsListPath) {
			Write-Output "`n  Copying Latest Windows 11 Supported AMD Processors Lists Into Scripts in Install Folder Resources...`n    $latestWindows11SupportedAMDProcessorsListPath"

			Copy-Item $latestWindows11SupportedAMDProcessorsListPath "$windows11SupportedProcessorsListsInInstallFolderScriptsBasePath\SupportedProcessorsAMD.txt" -Force -ErrorAction Stop
		} else {
			Write-Host "`n  NO LATEST WINDOWS 11 SUPPORTED AMD PROCESSORS LIST" -ForegroundColor Yellow
		}

		$latestWindows11SupportedIntelProcessorsListPath = (Get-ChildItem "$windows11SupportedProcessorsListsBasePath\Windows 11 Supported Processors Lists 20*\SupportedProcessorsIntel.txt" -File | Sort-Object -Property CreationTime | Select-Object -Last 1).FullName
		if (Test-Path $latestWindows11SupportedIntelProcessorsListPath) {
			Write-Output "`n  Copying Latest Windows 11 Supported Intel Processors Lists Into Scripts in Install Folder Resources...`n    $latestWindows11SupportedIntelProcessorsListPath"

			Copy-Item $latestWindows11SupportedIntelProcessorsListPath "$windows11SupportedProcessorsListsInInstallFolderScriptsBasePath\SupportedProcessorsIntel.txt" -Force -ErrorAction Stop
		} else {
			Write-Host "`n  NO LATEST WINDOWS 11 SUPPORTED INTEL PROCESSORS LIST" -ForegroundColor Yellow
		}

		$latestWindows11SupportedQualcommProcessorsListPath = (Get-ChildItem "$windows11SupportedProcessorsListsBasePath\Windows 11 Supported Processors Lists 20*\SupportedProcessorsQualcomm.txt" -File | Sort-Object -Property CreationTime | Select-Object -Last 1).FullName
		if (Test-Path $latestWindows11SupportedQualcommProcessorsListPath) {
			Write-Output "`n  Copying Latest Windows 11 Supported Qualcomm Processors Lists Into Scripts in Install Folder Resources...`n    $latestWindows11SupportedQualcommProcessorsListPath"

			Copy-Item $latestWindows11SupportedQualcommProcessorsListPath "$windows11SupportedProcessorsListsInInstallFolderScriptsBasePath\SupportedProcessorsQualcomm.txt" -Force -ErrorAction Stop
		} else {
			Write-Host "`n  NO LATEST WINDOWS 11 SUPPORTED QUALCOMM PROCESSORS LIST" -ForegroundColor Yellow
		}


		$installFolderResourcesToCopy = Get-ChildItem "$PSScriptRoot\Install Folder Resources"

		if ($installFolderResourcesToCopy.Count -gt 0) {
			Write-Output "`n  Copying Install Folder Resources Into $winPEname Image..."

			if (Test-Path "$systemTempDir\mountPE\Install") {
				Remove-Item "$systemTempDir\mountPE\Install" -Recurse -Force -ErrorAction Stop
			}

			New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE\Install" -ErrorAction Stop | Out-Null

			Copy-Item "$PSScriptRoot\Install Folder Resources\*" "$systemTempDir\mountPE\Install" -Recurse -Force -ErrorAction Stop

			Write-Output "    Unarchiving Java in Install Folder in $winPEname Image..."

			if (Test-Path "$systemTempDir\mountPE\Install\QA Helper\java-jre") {
				Remove-Item "$systemTempDir\mountPE\Install\QA Helper\java-jre" -Recurse -Force -ErrorAction Stop
			}

			Expand-Archive "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip" "$systemTempDir\mountPE\Install\QA Helper\" -Force -ErrorAction Stop

			if (Test-Path "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip") {
				Remove-Item "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip" -Force -ErrorAction Stop
			}
		} else {
			Write-Host "`n  NOTHING IN `"Install Folder Resources`" TO COPY" -ForegroundColor Yellow
		}
	} else {
		Write-Host "`n  NO `"Install Folder Resources`" FOLDER" -ForegroundColor Yellow
	}


	if (Test-Path $winPEextraDriversPath) {
		$winPEextraDriverInfPaths = (Get-ChildItem $winPEextraDriversPath -Recurse -File -Include '*.inf').FullName

		if ($winPEextraDriverInfPaths.Count -gt 0) {
			$startDriversDate = Get-Date
			Write-Output "`n  Installing $($winPEextraDriverInfPaths.Count) Extra Drivers Into $winPEname Image at $startDriversDate..."

			$thisDriverIndex = 0
			$installedDriverCount = 0
			foreach ($thisDriverInfPath in $winPEextraDriverInfPaths) {
				$thisDriverIndex ++
				$thisDriverFolderName = (Split-Path (Split-Path $thisDriverInfPath -Parent) -Leaf)

				if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\DriverStore\FileRepository\$thisDriverFolderName")) {
					try {
						Write-Output "    Installing Extra Driver $thisDriverIndex of $($winPEextraDriverInfPaths.Count): $thisDriverFolderName ($([math]::Round(((Get-ChildItem -Path "$winPEextraDriversPath\$thisDriverFolderName" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB), 2)) MB)"
						Add-WindowsDriver -Path "$systemTempDir\mountPE" -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null
						$installedDriverCount ++
					} catch {
						Write-Host "      ERROR INSTALLING EXTRA DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
					}
				} else {
					Write-Output "    ALREADY INSTALLED Extra Driver $thisDriverIndex of $($winPEextraDriverInfPaths.Count): $thisDriverFolderName"
				}
			}

			$endDriversDate = Get-Date
			Write-Output "`n  Finished Installing $installedDriverCount Extra Drivers at $endDriversDate ($([math]::Round(($endDriversDate - $startDriversDate).TotalMinutes, 2)) Minutes)"
		}
	}

	$win11ProImagesSourcePath = "$basePath\Windows 11 Pro $windows11featureVersion"

	if (-not (Test-Path $win11ProImagesSourcePath)) {
		# NOTE: Windows source folders may have a version suffix ("v1", "v2", etc) from the source ISOs,
		# so if the folders are not found check for up to 10 version suffix folder names.

		for ($possibleISOversionSuffix = 10; $possibleISOversionSuffix -ge 1; $possibleISOversionSuffix --) {
			$win11ProImagesSourcePath = "$basePath\Windows 11 Pro $windows11featureVersion v$possibleISOversionSuffix"
			if (Test-Path $win11ProImagesSourcePath) {
				break
			}
		}
	}

	if (Test-Path $win11ProImagesSourcePath) {
		$windows11ExtractedDriversPath = "$win11ProImagesSourcePath\Extracted Network Drivers"
		if (($winPEmajorVersion -eq '11') -and (Test-Path $windows11ExtractedDriversPath)) {
			# NOTE: When using WinPE/WinRE 11 22H2 as the installation environment for both Windows 10 and 11, some network drivers are not available for older systems that don't support Windows 11 (which wasn't an issue with initial WinRE 11 version 21H2/22000).
			# Having the installation environment be able to establish a network connection is critical for downloading QA Helper, as well as connecting to local SMB shares to retrieve the Windows install images.
			# Through testing, I found that extracting all the default network drivers from the full Windows 11 image and installing them into the WinRE 11 image allowed all my test systems to properly make network connections (installing all drivers from WinRE 10 did not work).
			# So, the network drivers will always be extracted from the full Windows images in the "Create Windows Install Image" script, so they can be installed into the WinRE image here.

			$windows11DriverInfPaths = (Get-ChildItem $windows11ExtractedDriversPath -Recurse -File -Include '*.inf').FullName

			if ($windows11DriverInfPaths.Count -gt 0) {
				$startDriversDate = Get-Date
				Write-Output "`n  Installing $($windows11DriverInfPaths.Count) Windows 11 Pro Default Network Drivers Into $winPEname Image at $startDriversDate..."

				$thisDriverIndex = 0
				$installedDriverCount = 0
				foreach ($thisDriverInfPath in $windows11DriverInfPaths) {
					$thisDriverIndex ++
					$thisDriverFolderName = (Split-Path (Split-Path $thisDriverInfPath -Parent) -Leaf)

					if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\DriverStore\FileRepository\$thisDriverFolderName")) {
						try {
							Write-Output "    Installing Windows 11 Pro Default Network Driver $thisDriverIndex of $($windows11DriverInfPaths.Count): $thisDriverFolderName ($([math]::Round(((Get-ChildItem -Path "$windows11ExtractedDriversPath\$thisDriverFolderName" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB), 2)) MB)"
							Add-WindowsDriver -Path "$systemTempDir\mountPE" -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null
							$installedDriverCount ++
						} catch {
							Write-Host "      ERROR INSTALLING WINDOWS 11 PRO DEFAULT NETWORK DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
						}
					} else {
						Write-Output "    ALREADY INSTALLED Windows 11 Pro Default Network Driver $thisDriverIndex of $($windows11DriverInfPaths.Count): $thisDriverFolderName"
					}
				}

				$endDriversDate = Get-Date
				Write-Output "`n  Finished Installing $installedDriverCount Windows 11 Pro Default Network Drivers at $endDriversDate ($([math]::Round(($endDriversDate - $startDriversDate).TotalMinutes, 2)) Minutes)"
			}
		}
	}

	if ($winPEname.EndsWith('-NetDriversForUSB') -and ($winPEoptionalFeatures -contains 'WinPE-WiFi') -and (Test-Path $winREnetDriversPath)) {
		$winREnetDriverInfPaths = (Get-ChildItem $winREnetDriversPath -Recurse -File -Include '*.inf').FullName

		if ($winREnetDriverInfPaths.Count -gt 0) {
			$startDriversDate = Get-Date
			Write-Output "`n  Installing $($winREnetDriverInfPaths.Count) Network Drivers for USB Install Into $winPEname Image at $startDriversDate..."

			$thisDriverIndex = 0
			$installedDriverCount = 0
			foreach ($thisDriverInfPath in $winREnetDriverInfPaths) {
				$thisDriverIndex ++
				$thisDriverFolderName = (Split-Path (Split-Path $thisDriverInfPath -Parent) -Leaf)

				if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\DriverStore\FileRepository\$thisDriverFolderName")) {
					$thisDriverSizeMB = $([math]::Round(((Get-ChildItem -Path "$winREnetDriversPath\$thisDriverFolderName" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB), 2))
					if ($thisDriverSizeMB -lt 10) {
						try {
							Write-Output "    Installing Network Driver for USB Install $thisDriverIndex of $($winREnetDriverInfPaths.Count): $thisDriverFolderName ($thisDriverSizeMB MB)"
							Add-WindowsDriver -Path "$systemTempDir\mountPE" -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null
							$installedDriverCount ++
						} catch {
							Write-Host "      ERROR INSTALLING NETWORK DRIVER FOR USB INSTALL `"$thisDriverFolderName`": $_" -ForegroundColor Red
						}
					} else {
						Write-Output "    SKIPPING LARGE Network Driver for USB Install $thisDriverIndex of $($winREnetDriverInfPaths.Count): $thisDriverFolderName ($thisDriverSizeMB MB)"
					}
				} else {
					Write-Output "    ALREADY INSTALLED Network Driver for USB Install $thisDriverIndex of $($winREnetDriverInfPaths.Count): $thisDriverFolderName"
				}
			}

			$endDriversDate = Get-Date
			Write-Output "`n  Finished Installing $installedDriverCount Network Drivers for USB Install at $endDriversDate ($([math]::Round(($endDriversDate - $startDriversDate).TotalMinutes, 2)) Minutes)"
		}
	}


	Write-Output "`n  Cleaning Up $winPEname Image..."
	# PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
	$dismCleanupExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

	if ($dismCleanupExitCode -eq 0) {
		Write-Output "`n  Unmounting and Saving Updated $winPEname Image..."
		# Dism /Unmount-Image /MountDir:C:\WinPE_amd64_PS\mount /Commit
		Dismount-WindowsImage -Path "$systemTempDir\mountPE" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
		Remove-Item "$systemTempDir\mountPE" -Recurse -Force -ErrorAction Stop
		Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop

		Write-Output "`n  Exporting Compressed $wimImageBaseName Image as `"$winPEname.wim`"..."
		# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-optimize#export-and-then-replace-the-image

		if (Test-Path "$winPEoutputPath\$winPEname.wim") {
			Write-Output "    Deleting Previous $wimImageBaseName Image `"$winPEname.wim`"..."
			Remove-Item "$winPEoutputPath\$winPEname.wim" -Force -ErrorAction Stop
		}

		# "-Setbootable" does not seem to be necessary (USBs will boot without it being set), but it doesn't seem to hurt anything so leaving it in place.
		Export-WindowsImage -SourceImagePath "$winPEoutputPath\media\sources\boot.wim" -SourceIndex 1 -DestinationImagePath "$winPEoutputPath\$winPEname.wim" -CheckIntegrity -CompressionType 'max' -Setbootable -ErrorAction Stop | Out-Null
		Remove-Item "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
		Get-WindowsImage -ImagePath "$winPEoutputPath\$winPEname.wim" -Index 1 -ErrorAction Stop


		Write-Output "`n  Verifying Exported Updated $winPEname Image Contents Against Source $wimImageBaseName Image Contents..."
		# NOTE: See comments in "Create Windows Install Image" about this manual verification of the exported WinPE/WinRE image.

		$verifyingStartDate = Get-Date

		$updatedWinPeWimSizeBytes = (Get-Item "$winPEoutputPath\$winPEname.wim").Length

		if ($updatedWinPeWimSizeBytes -lt $sourceWinPeWimSizeBytes) {
			$updatedWinPeWimSizeBytesDifference = ($sourceWinPeWimSizeBytes - $updatedWinPeWimSizeBytes)
			if ($updateResourcesOnly -and ($updatedWinPeWimSizeBytesDifference -lt 1500000)) {
				Write-Host "`n    NOTICE: UPDATED $winPEname WIM ($updatedWinPeWimSizeBytes) IS *$([math]::Round(($updatedWinPeWimSizeBytesDifference / 1MB), 2)) MB SMALLER THAN* SOURCE $wimImageBaseName WIM ($sourceWinPeWimSizeBytes) - CONTINUING ANYWAY`n" -ForegroundColor Yellow
			} else {
				Write-Host "`n    ERROR: UPDATED $winPEname WIM ($updatedWinPeWimSizeBytes) IS *$([math]::Round(($updatedWinPeWimSizeBytesDifference / 1MB), 2)) MB SMALLER THAN* SOURCE $wimImageBaseName WIM ($sourceWinPeWimSizeBytes) - THIS SHOULD NOT HAVE HAPPENED" -ForegroundColor Red
				exit 1
			}
		}

		$updatedWinPeWimContentPaths = Get-WindowsImageContent -ImagePath "$winPEoutputPath\$winPEname.wim" -Index 1 | Select-String $excludedCompareWinPeWimContentPaths -SimpleMatch -NotMatch
		$filePathsRemovedFromUpdatedWinPeWIM = (Compare-Object -ReferenceObject $sourceWinPeWimContentPaths -DifferenceObject $updatedWinPeWimContentPaths | Where-Object SideIndicator -eq '<=').InputObject # Comparing text lists of paths from within the WIMs is MUCH faster than comparing mounted files via "Get-ChildItem -Recurse".
		if ($filePathsRemovedFromUpdatedWinPeWIM.Count -gt 0) { # For this WIM, there should NEVER be any files removed.
			Write-Host "`n    ERROR: THE FOLLOWING $($filePathsRemovedFromUpdatedWinPeWIM.Count) FILES WERE REMOVED FROM THE UPDATED $winPEname WIM - THIS SHOULD NOT HAVE HAPPENED`n      $($filePathsRemovedFromUpdatedWinPeWIM -Join "`n      ")" -ForegroundColor Red
			exit 1
		}

		$verifyingEndDate = Get-Date
		Write-Output "    Finished Verifying Exported Updated $winPEname Image at $verifyingEndDate ($([math]::Round(($verifyingEndDate - $verifyingStartDate).TotalMinutes, 2)) Minutes)"

		Write-Output "`n  Calculating Checksum for $winPEname.wim..."
		Set-Content "$winPEoutputPath\$winPEname.wim.checksum" (Get-FileHash "$winPEoutputPath\$winPEname.wim" -Algorithm 'SHA256').Hash
		Get-Content "$winPEoutputPath\$winPEname.wim.checksum"

		Write-Output "`n  Overwriting Original $wimImageBaseName Image with Compressed $winPEname for USB Install..."
		# Replace boot.wim in sources folder for MakeWinPEMedia script.
		Copy-Item "$winPEoutputPath\$winPEname.wim" "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
		Copy-Item "$winPEoutputPath\$winPEname.wim.checksum" "$winPEoutputPath\boot.wim.checksum" -Force -ErrorAction Stop
		Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop


		if ($createISO) {
			Write-Output "`n`n  Creating $winPEname ISO...`n"
			# https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-usb-bootable-drive?view=windows-11#create-a-winpe-iso-dvd-or-cd
			$isoName = "$winPEname-$(Get-Date -UFormat '%Y%m%d').iso"
			if (-not $winPEname.EndsWith('-NetDriversForUSB')) {
				$isoName = "$winPEname-NoNetDrivers-$(Get-Date -UFormat '%Y%m%d').iso" # Add "-NoNetDrivers-" so that the filename always sorts AFTER the "-NetDriversForUSB-" ISO (in the boot list when we were momentarily using Ventoy).
			}
			$makeWinPEISOExitCode = (Start-Process '\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\MakeWinPEMedia.cmd' -NoNewWindow -Wait -PassThru -ArgumentList '/ISO', '/F', "`"$winPEoutputPath`"", "`"$winPEoutputPath\$isoName`"").ExitCode

			if ($makeWinPEISOExitCode -ne 0) {
				Write-Host "`n    ERROR: FAILED TO CREATE ISO - EXIT CODE: $makeWinPEISOExitCode" -ForegroundColor Red
				exit $makeWinPEISOExitCode
			}

			Write-Output "`n  Calculating Checksum for $isoName..."
			Set-Content "$winPEoutputPath\$isoName.checksum" (Get-FileHash "$winPEoutputPath\$isoName" -Algorithm 'SHA256').Hash
			Get-Content "$winPEoutputPath\$isoName.checksum"
			Write-Output ''
		}
	} else {
		Write-Host "`n    ERROR: FAILED TO DISM CLEANUP - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
		exit 1
	}
}


Add-WinPECustomizations


if (($wimImageBaseName -eq 'WinRE') -and (-not $winPEname.EndsWith('-NetDriversForUSB')) -and (Test-Path $winREnetDriversPath) -and ((Get-ChildItem $winREnetDriversPath -Recurse -File -Include '*.inf').Count -gt 0)) {
	# $promptCaption = "  Would you like to ALSO create/update WinRE with network drivers for USB installers?"
	# $promptChoices = '&Yes', '&No'

	# $Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
	# $promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 0)
	# Write-Output ''

	# if ($promptResponse -eq 0) {
	if (-not (Test-Path "$winPEoutputPath\media\sources\boot.wim")) {
		Write-Host "`n    ERROR: `"boot.wim`" DOES NOT EXIST - CANNOT ADD NETWORK DRIVERS FOR USB INSTALL - THIS SHOULD NOT HAVE HAPPENED" -ForegroundColor Red
		exit 1
	}

	$winPEname += '-NetDriversForUSB'

	if ($updateResourcesOnly -and (Test-Path "$winPEoutputPath\$winPEname.wim")) {
		Write-Output "`n  Deleting Previous `"boot.wim`" to Update Resources Within `"$winPEname.wim`"..."
		Remove-Item "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop

		Write-Output "  Moving Previous `"$winPEname.wim`" to `"boot.wim`" to Update Resources..."
		Move-Item "$winPEoutputPath\$winPEname.wim" "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
	}

	Add-WinPECustomizations
	# }
}


if ($includeResourcesInUSB) {
	if (Test-Path "$winPEoutputPath\media") {
		Write-Output "`n`n  Updating `"windows-resources`" Folder Contents for USB Install..."

		if (Test-Path "$winPEoutputPath\media\windows-resources") {
			Remove-Item "$winPEoutputPath\media\windows-resources" -Recurse -Force -ErrorAction Stop
		}

		New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources" -ErrorAction Stop | Out-Null


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
						$latestWimFilename = $latestWim.BaseName

						Write-Output "    Copying Latest Windows $thisWindowsMajorVersion $thisWindowsEdition Install Image ($latestWimFilename) Into `"windows-resources\os-images`"..."

						if (-not (Test-Path "$winPEoutputPath\media\windows-resources\os-images")) {
							New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop | Out-Null
						}

						$wimFileSize = $latestWim.Length

						$maxFat32FileSize = 4294967294
						if ($wimFileSize -lt $maxFat32FileSize) {
							Write-Output "      Windows $thisWindowsMajorVersion $thisWindowsEdition Install Image Is Within FAT32 Max File Size ($wimFileSize <= $maxFat32FileSize)"

							Copy-Item $latestWimPath "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop
						} else {
							$splitMBs = 3000
							Write-Host "      Windows $thisWindowsMajorVersion $thisWindowsEdition Install Image Is Bigger Than FAT32 Max File Size ($wimFileSize > $maxFat32FileSize)`n      SPLITTING WINDOWS IMAGE INTO $splitMBs MB SWMs" -ForegroundColor Yellow

							Split-WindowsImage -ImagePath $latestWimPath -SplitImagePath "$winPEoutputPath\media\windows-resources\os-images\$latestWimFilename+.swm" -FileSize $splitMBs -CheckIntegrity -ErrorAction Stop | Out-Null

							Rename-Item "$winPEoutputPath\media\windows-resources\os-images\$latestWimFilename+.swm" "$winPEoutputPath\media\windows-resources\os-images\$latestWimFilename+1.swm"
						}
					} else {
						Write-Host "    NO WINDOWS $thisWindowsMajorVersion $thisWindowsEdition INSTALL IMAGE FILE FOR $wimImageBaseName USB" -ForegroundColor Yellow
					}
				} else {
					Write-Host "    NO WINDOWS $thisWindowsMajorVersion $thisWindowsEdition INSTALL IMAGE FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
				}
			}
		}


		if (Test-Path $setupResourcesSourcePath) {
			Write-Output "    Copying Setup Resources Into `"windows-resources\setup-resources`"..."

			Copy-Item $setupResourcesSourcePath "$winPEoutputPath\media\windows-resources\setup-resources" -Recurse -ErrorAction Stop
		} else {
			Write-Host "    NO SETUP RESOURCES FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
		}


		if (Test-Path $appInstallersSourcePath) {
			Write-Output "    Copying App Installers Into `"windows-resources\app-installers`"..."

			New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources\app-installers" -ErrorAction Stop | Out-Null

			Get-ChildItem $appInstallersSourcePath -Exclude '*.sh', '*.ps1' -ErrorAction Stop | ForEach-Object {
				Copy-Item $_ "$winPEoutputPath\media\windows-resources\app-installers" -Recurse -Force -ErrorAction Stop
			}
		} else {
			Write-Host "    NO APP INSTALLERS FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
		}
	} else {
		Write-Host "`n`n  NO MEDIA FOLDER FOR $wimImageBaseName USB" -ForegroundColor Red
	}
} else {
	Write-Host "`n`n  NOT ADDING RESOURCES TO BOOT FOLDER FOR STANDALONE $wimImageBaseName USB (WILL BE INCLUDED IN SEPARATE USB PARTITION)" -ForegroundColor Yellow
}


$endDate = Get-Date
Write-Output "`n  Finished at $endDate ($([math]::Round(($endDate - $startDate).TotalMinutes, 2)) Minutes)"
