###########################################################################
##                                                                       ##
##   TO RUN THIS SCRIPT, LAUNCH "Run Create Windows Install Image.cmd"   ##
##                                                                       ##
###########################################################################

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

# Requires Latest Windows ISOs: https://www.microsoft.com/software-download/windows10 & https://www.microsoft.com/software-download/windows11
# When the Windows 10 download page is viewed on Mac or Linux, you have the option to download the ISO directly, but when viewed on Windows you can only download the Media Creation Tool (instead of direct ISO download) which can then be used to export an ISO.
# Instead of using the Media Creation Tool on Windows, a workaround to be able to download the ISO directly on Windows is to use the Developer Tools options in Chrome or Firefox to change the User Agent or use Responsive Design Mode and then reload the page.
# Or, use the Fido script (https://github.com/pbatard/Fido) built into Rufus: https://rufus.ie/en/

# Reference (Modify a WIM): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/mount-and-modify-a-windows-image-using-dism
# Reference (Reduce Size of WIM): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/reduce-the-size-of-the-component-store-in-an-offline-windows-image

# IMPORTANT: "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat" is run from within the CMD launcher file first for latest "DISM" from the ADK to be used.

# NOTE: There is at least one monthly Cumulative Update that would be time consuming during the setup process, so this script should be run monthly or so to create an updated WIM for the installation process to use instead of needing to rely on Windows Update as much during setup.
# This script will always install updates on top of the original source image directly from the ISO.
# Updates ARE NOT added on top of to the last updated WIM because it is not necessary and may just unnecessarily bloat the WIM (but DISM's /Cleanup-Image /StartComponentCleanup /ResetBase and then exporting a new compressed image should take care of any bloat anyway).
# Previous WIMs (with the updated date in the filename) will be left in the $wimOutputPath folder when newly updated WIMs are created to be deleted at your discretion. I generally keep one previous WIM for quick rollback if necessary and manually delete anything older than that.

$Host.UI.RawUI.WindowTitle = 'Create Windows Install Image'

$basePath = "$HOME\Documents\Free Geek"
if (Test-Path "$HOME\Documents\Free Geek.lnk") {
	$basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Documents\Free Geek.lnk").TargetPath
}

$windowsMajorVersions = @('11', '10')
$windowsEditions = @('Pro', 'Home')

if ($windowsMajorVersions.Count -gt 1) {
	$promptCaption = '  Which Windows version do you want to create/update?'
	$promptChoices = '1&1', '1&0', '&Both', 'E&xit'

	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
	$promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 2)
	Write-Output ''

	if ($promptResponse -eq 3) {
		exit 0
	} elseif ($promptResponse -eq 0) {
		$windowsMajorVersions = @('11')
	} elseif ($promptResponse -eq 1) {
		$windowsMajorVersions = @('10')
	}
}

$promptCaption = "  Which Windows $($windowsMajorVersions -Join ', ') edition do you want to create/update?"
$promptChoices = '&Pro', '&Home', '&Both', '&Exit'

$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
$promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 2)
Write-Output ''

if ($promptResponse -eq 3) {
	exit 0
} elseif ($promptResponse -eq 0) {
	$windowsEditions = @('Pro')
} elseif ($promptResponse -eq 1) {
	$windowsEditions = @('Home')
}

$startDate = Get-Date
Write-Output "`n  Starting at $startDate..."

foreach ($thisWindowsMajorVersion in $windowsMajorVersions) {
	$windowsFeatureVersions = @()
	if ($thisWindowsMajorVersion -eq '10') {
		$windowsFeatureVersions += '22H2' # 22H2 is the FINAL feature update for Windows 10: https://techcommunity.microsoft.com/t5/windows-it-pro-blog/windows-client-roadmap-update/ba-p/3805227
	} else {
		# $windowsFeatureVersions += '23H2' # https://www.reddit.com/r/WindowsHelp/comments/1ga0e8h/comment/mcplrzl & https://archive.org/details/win11_23h2_english_x64v2_202409
		$windowsFeatureVersions += '24H2'
	}

	foreach ($thisWindowsFeatureVersion in $windowsFeatureVersions) {
		foreach ($thisWindowsEdition in $windowsEditions) {
			$thisStartDate = Get-Date

			$wimName = "Windows-$thisWindowsMajorVersion-$thisWindowsEdition-$thisWindowsFeatureVersion-Updated-$(Get-Date -UFormat '%Y%m%d')"
			$winREwimName = "WinRE-$thisWindowsMajorVersion-$thisWindowsEdition-$thisWindowsFeatureVersion-Updated-$(Get-Date -UFormat '%Y%m%d')"
			$wimOutputPath = "$basePath\Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion"

			$sourceISOname = "Win$($thisWindowsMajorVersion)_$($thisWindowsFeatureVersion)_English_x64.iso" # This is the default ISO name when downloaded directly, but when the using with the Media Creation Tool (instead of direct ISO download) the default name is "Windows.iso" when exporting an ISO.
			$sourceISOpath = "$basePath\$sourceISOname"

			if (-not (Test-Path $sourceISOpath)) {
				# NOTE: Windows ISOs are updated periodically to include recent cumulative updates.
				# When updated versions are released, they will have "v1", "v2", etc included at the end of the filename.
				# So, if the source ISO is not found check for up to 10 version suffix ISO names.

				for ($possibleISOversionSuffix = 10; $possibleISOversionSuffix -ge 1; $possibleISOversionSuffix --) {
					if (Test-Path "$basePath\$($sourceISOname.Replace('.iso', "v$possibleISOversionSuffix.iso"))") {
						$sourceISOversionSuffix = "v$possibleISOversionSuffix"
						$sourceISOname = $sourceISOname.Replace('.iso', "$sourceISOversionSuffix.iso")
						$sourceISOpath = "$basePath\$sourceISOname"
						$wimOutputPath += " $sourceISOversionSuffix"
						break
					}
				}
			}

			$sourceWIMpath = "$wimOutputPath\Windows-$thisWindowsMajorVersion-$thisWindowsEdition-$thisWindowsFeatureVersion-ISO$sourceISOversionSuffix-Source.wim"

			Write-Output "`n  Creating Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image at $thisStartDate..."

			if (Test-Path $sourceISOpath) {
				while ($previousMountedDiskImage = Get-DiskImage $sourceISOpath | Get-Volume) {
					Write-Output "`n  Unmounting Previously Mounted $sourceISOname at $($previousMountedDiskImage.DriveLetter):\..."
					Dismount-DiskImage $sourceISOpath -ErrorAction Stop | Out-Null
				}
			}

			$systemTempDir = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine') # Get SYSTEM (not user) temporary directory, which should be "\Windows\Temp".
			if (-not (Test-Path $systemTempDir)) {
				$systemTempDir = '\Windows\Temp'

				# NOTE ABOUT MOUNTING ALL WIM IMAGES IN THE TEMP DIR:
				# Previously, Windows 11 Cumulative Update KB5010795 (2022-01) and older would install fine, but any newer Cumulative Updates would all fail with with 0x8007007a (ERROR_INSUFFICIENT_BUFFER) and then 0x800f0988 (PSFX_E_INVALID_DELTA_COMBINATION).
				# At first I thought something was funky with the Cumulative Updates and maybe some pre-requisite was missing, but even installing the working Cumulative Update before the next one would result in the same error.
				# This same error also happened regardless of using the regular Cumulative Update MSU file or the Dynamic Cumulative Update CAB file.
				# But, installing newer Cumulative Updates into *WinRE* from Win 11 21H2 works fine, which is kind of odd that this issue only affects the full Windows image and not WinRE.
				# Then I thought that maybe this was an issue because of trying to update a Win 11 21H2 image on Windows 10, but I got the same exact error when updating the Win 11 21H2 image from within Win 11 21H2 as well.
				# From more closely examinining the DISM error log, it started to look like is was possibly an issue with path lengths being too long, so I enabled Long Paths on my system, but that also didn't solve the issue and the same error happened.
				# But, it still seemed like possibly a path issue because some files were copying correctly and then some weren't, so I decided to try mounting the WIM at the root of the drive instead of all the way into the home folder at $basePath.
				# AND THAT WORKED! I don't quite understand why this worked since if it was a path length issue, enabling Long Paths should have solved it.
				# Since enabling Long Paths didn't help, I disabled Long Paths again and the latest Cumulative Updates still worked then the WIM was mounted at the root of the drive!
				# Since mounting at the root of the drive felt a bit sloppy, I decided to try mounting the WIM within the system temporary directory at "\Windows\Temp\" hoping that would not trigger the same path length issue (or whatever it was), and that also worked!
				# So, I switched all WIM mounting to be within the system temporary directory and now all Cumulative Updates appear to be installing for all WIMs (including Win 10).
			}

			if ((Test-Path "$systemTempDir\mountOS") -and ((Get-ChildItem "$systemTempDir\mountOS").Count -gt 0)) {
				Write-Output "`n  Unmounting Previously Mounted Windows Install Image..."
				Dismount-WindowsImage -Path "$systemTempDir\mountOS" -Discard -ErrorAction Stop | Out-Null
				Remove-Item "$systemTempDir\mountOS" -Recurse -Force -ErrorAction Stop
			}

			if ((Test-Path "$systemTempDir\mountRE") -and ((Get-ChildItem "$systemTempDir\mountRE").Count -gt 0)) {
				Write-Output "`n  Unmounting Previously Mounted WinRE Image..."
				Dismount-WindowsImage -Path "$systemTempDir\mountRE" -Discard -ErrorAction Stop | Out-Null
				Remove-Item "$systemTempDir\mountRE" -Recurse -Force -ErrorAction Stop
			}

			if (($thisWindowsMajorVersion -eq '11') -and ($thisWindowsFeatureVersion -eq "$((Get-Date).AddYears(-1).ToString('yy'))H2")) {
				$latestWindows11featureVersion = ((Invoke-WebRequest -TimeoutSec 5 -Uri 'https://www.microsoft.com/software-download/windows11').Content | Select-String '\(Current release: Windows 11 202\d Update l Version (2\dH2)\)').Matches[0].Groups[1].Value
				if ($latestWindows11featureVersion -ne $thisWindowsFeatureVersion) {
					if (($null -eq $latestWindows11featureVersion) -or ($latestWindows11featureVersion -eq '')) {
						$latestWindows11featureVersion = 'UNKNOWN'
					}

					$win11updatePromptCaption = "`n  Windows $thisWindowsMajorVersion $thisWindowsEdition $latestWindows11featureVersion is now available.`n  Create a new Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image anyway?"
					$win11updatePromptChoices = '&Yes', '&No'

					$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
					$win11updatePromptResponse = $Host.UI.PromptForChoice($win11updatePromptCaption, "`n", $win11updatePromptChoices, 1)
					Write-Output ''

					if ($win11updatePromptResponse -eq 1) {
						Start-Process 'https://www.microsoft.com/software-download/windows11'
						continue # Go to next Windows version in loop, if multiple have been selected.
					}
				}
			}

			if (Test-Path "$Env:WINDIR\Logs\DISM\dism.log") {
				# Delete past DISM log to make it easier to find errors in the log for this run if something goes wrong.
				Remove-Item "$Env:WINDIR\Logs\DISM\dism.log" -Force -ErrorAction Stop
			}

			if ((Test-Path $sourceISOpath) -and (-not (Test-Path $sourceWIMpath))) {
				Write-Output "`n  Mounting $sourceISOname..."

				$mountedDiskImageDriveLetter = (Mount-DiskImage $sourceISOpath -ErrorAction Stop | Get-Volume -ErrorAction Stop).DriveLetter

				Write-Output "    Mounted to $($mountedDiskImageDriveLetter):\"

				if (-not (Test-Path $wimOutputPath)) {
					New-Item -ItemType 'Directory' -Path $wimOutputPath -ErrorAction Stop | Out-Null
				}

				Write-Output "`n  Exporting Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image from $sourceISOname..."
				$isoInstallWimName = "$($mountedDiskImageDriveLetter):\sources\install.esd" # If the ISO is exported by the Media Creation Tool, the install file will be called "install.esd"
				if (-not (Test-Path $isoInstallWimName)) {
					$isoInstallWimName = "$($mountedDiskImageDriveLetter):\sources\install.wim" # If the ISO is downloaded directly, the install file will be called "install.wim"
				}
				Export-WindowsImage -SourceImagePath $isoInstallWimName -SourceName "Windows $thisWindowsMajorVersion $thisWindowsEdition" -DestinationImagePath $sourceWIMpath -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
				Get-WindowsImage -ImagePath $sourceWIMpath -Index 1 -ErrorAction Stop

				while ($previousMountedDiskImage = Get-DiskImage $sourceISOpath | Get-Volume) {
					Write-Output "`n  Unmounting $sourceISOname at $($previousMountedDiskImage.DriveLetter):\..."
					Dismount-DiskImage $sourceISOpath -ErrorAction Stop | Out-Null
				}
			}

			if (Test-Path "$wimOutputPath\$wimName-TEMP.wim") {
				Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop
			}

			if (Test-Path "$wimOutputPath\$winREwimName-TEMP.wim") {
				Remove-Item "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop
			}


			if (-not (Test-Path $sourceWIMpath)) {
				if (-not (Test-Path $sourceISOpath)) {
					Write-Host "`n  SOURCE ISO NOT FOUND AT `"$sourceISOpath`"" -ForegroundColor Red
				} else {
					Write-Host "`n  EXTRACTED SOURCE WIM NOT FOUND AT `"$sourceWIMpath`"" -ForegroundColor Red
				}

				exit 1
			}

			$downloadUpdatesStartDate = Get-Date
			Write-Output "`n  Downloading Latest Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Updates at $downloadUpdatesStartDate..."

			# Searching and downloading the regular monthly Cumulative Updates is automated by this script.
			# IMPORTANT NOTE: Only ".msu" and ".cab" files can be pre-installed into the WIM. Any ".exe" updates (such as anti-virus updates) will have to be done by Windows Update after installation, which is fine because they are usually very small and quick and also get updated frequently.

			# The following automated update search/download uses template strings like "[YYYY-MM] Cumulative Update for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64" and the following code searches for the newest available update until one is found.
			# These template strings are stored in the "$windowsUpdatesSearchTemplates" array below, and can be set for all versions of Windows, or can be conditionally appended only for a specific version of Windows.
			# For example, if it is January 2024, that template string will result in the following searches being performed for Windows 10 22H2 in order until one is found:
				# 2024-01 Cumulative Update Preview for Windows 10 Version 22H2 for x64
				# 2024-01 Cumulative Update for Windows 10 Version 22H2 for x64
				# 2023-12 Cumulative Update Preview for Windows 10 Version 22H2 for x64
				# 2023-12 Cumulative Update for Windows 10 Version 22H2 for x64
			# This works by replacing the "[YYYY-MM]" portion of the template string first with the current month, and then with the previous month, and then even older months if necessary
			# Also, any instance of "Cumulative Update" in the template string will be replaced with "Cumulative Update Preview" to peform those searches in order as well.
			# This same template string would also perform the same monthly searches for Windows 11 23H2 by replacing the "[MAJOR VERSION]" and "[FEATURE VERSION]" portions of the template string.

			$osUpdatesToInstallPath = "$wimOutputPath\OS Updates to Install"
			if (-not (Test-Path $osUpdatesToInstallPath)) {
				New-Item -ItemType 'Directory' -Path $osUpdatesToInstallPath -ErrorAction Stop | Out-Null
			}

			$windowsUpdatesChangedSinceLastBuild = $false

			$windowsUpdatesSearchTemplates = @(
				'[YYYY-MM] Cumulative Update for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64'
				'[YYYY-MM] Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64'
			)

			if ($thisWindowsMajorVersion -eq '10') {
				$windowsUpdatesSearchTemplates += @(
					'2023-10 Servicing Stack Update for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64'
					'Microsoft .NET Framework 4.8.1 for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64'
					# In June 2023, Microsoft started releasing .NET 4.8.1 to all systems via Windows Update, so pre-install this package: https://devblogs.microsoft.com/dotnet/upcoming-availability-of-net-framework-4-8-1-on-windows-update-and-catalog/
					# When this .NET 4.8.1 package (https://support.microsoft.com/kb/5011048) is pre-installed on Windows 10, the .NET 4.8 monthly Cumulative Updates are no longer needed and only the .NET 4.8.1 updates are needed.
				)
			}

			# Sometimes trying to install only the latest Cumulative Update will result in error 0x800f0823 (CBS_E_NEW_SERVICING_STACK_REQUIRED).
			# The solution for this error is to include a past Servicing Stack Update which will be installed before the latest and resolve this incompatibility.
			# Updates are installed in order by filename, which always includes the KB# making older updates install before newer ones and Servicing Stack Updates start with "ssu" which makes them correctly install before other updates which start with "windows".
			# To find the required Servicing Stack Update for a specific Cumulative Update, check the "Prerequisite" section (in the "How to get this update" section) of the Support pages for the specific Cumulative Update, such as:
			# https://support.microsoft.com/en-us/topic/may-29-2024-kb5037849-os-build-19045-4474-preview-cda7ed71-6202-45ed-a649-63b11fedabfe
			# (Use the Table of Contents navigation on the left of that page to navigate to the correct KB# for the Cumulative Update you are installing.)
			# When an error occurs, the DISM log will be opened in Notepad and there can also be useful information about what requirement is missing if you scroll to where the error occurred.
			# Once you have located the correct SSU, search it's KB# in the Microsoft Update Catalog (https://www.catalog.update.microsoft.com/Home.aspx), such as https://www.catalog.update.microsoft.com/Search.aspx?q=KB5031539
			# and find the correct name for the Windows version, such as "2023-10 Servicing Stack Update for Windows 10 Version 22H2 for x64-based Systems" and add that exact name to the list above to be installed conditionally for the correct Windows version.
			# NOTE: Any SSU added for a cumulative update should be removed if/when it is no longer needed, such as when an updated ISO has been released which pre-includes the newer updates.

			# For WinRE, some Cumulative Updates will fail with error 0x8007007e (ERROR_MOD_NOT_FOUND) even when the proper Servicing Stack Update is included, and I'm not certain why.
			# When this happens, the solution is to find the newest *previous* Cumulative Update or Cumulative Update Preview that works.
			# For example, CU KB5005565 (2021-09) + SSU KB5005260 (19041.1161) errors for WinRE, but using the previous CU KB5005101 (2021-08 Preview) + SSU KB5005260 (19041.1161) works fine.
			# So, in these cases, seperate older working updates for WinRE can be supplied in a "$wimOutputPath\WinRE Updates to Install" folder which can be manually created and filled and will not be overwritten by this automated update code.
			# See "PAST NOTES ABOUT MANUALLY DOWNLOADING UPDATES" below about how to manually search/download specific Cumulative Updates in the Microsoft Update Catalog.
			# NOTE: The "$wimOutputPath\WinRE Updates to Install" folder should be removed if/when those separate updates are no longer needed.

			# PAST NOTES ABOUT MANUALLY DOWNLOADING UPDATES:
			# IN THE PAST, to find the latest updates to be pre-installed, I just run a Windows installation and take note of any KB#'s that get installed by Windows Update during setup process and pre-install them into an updated WIM using this script instead of leaving Windows Update to do them (to save install/setup time).
			# To manually find the update files, I would perform searches of the Microsoft Update Catalog (https://www.catalog.update.microsoft.com/Home.aspx) for the update files like this: KB5011048 "Windows 10 Version 22H2 for x64" - Explanation: KB5011048 (the specific ID of the update you want) + "Windows 10 Version 22H2 for x64" in quotes to match only the exact windows version and architecture we want.
			# Link to the previous example search: https://www.catalog.update.microsoft.com/Search.aspx?q=KB5011048%20%22Windows%2010%20Version%2022H2%20for%20x64%22
			# ALSO, if you don't know the KB IDs, you can at least find the latest Cumulative Updates (for Windows and .NET including Cumulative Preview updates) by searching: "2023-10" Cumulative "Windows 10 Version 22H2 for x64" - Explanation: Same as above except filtering for only "Cumulative" Updates for the specified year and month *in quotes* like "YYYY-MM" to only match that exact update (obviously, set the year and month to the current or previous month for the latest updates).
			# Link to the previous example search: https://www.catalog.update.microsoft.com/Search.aspx?q=%222023-10%22%20Cumulative%20%22Windows%2010%20Version%2022H2%20for%20x64%22
			# And for Windows 11: "2023-10" Cumulative "Windows 11 Version 22H2 for x64": https://www.catalog.update.microsoft.com/Search.aspx?q=%222023-10%22%20Cumulative%20%22Windows%2011%20Version%2022H2%20for%20x64%22
			# After downloading desired update files, they would be put into the "$wimOutputPath\OS Updates to Install" folder to be installed by this script.
			# Also, (usually) only the latest updates need to be installed. For example, a previous Cumulative update file should be remove after a new Cumulative update is added so that both are not unnecessarily installed.

			# IMPORTANT NOTE *FROM THE PAST* ABOUT UPDATING WINRE IN WINDOWS 10 21H2 (IN REGARDS TO TPM VERSION DETECTION):
			# Something changed or broke in a Cumulative Update for WinRE in Win 10 21H2 that makes WinRE not be able to detect the TPM version to determine Windows 11 support. (But, all updates I've tried seem to function properly in WinRE in Win 10 21H2 other than TPM detection.)
			# TPM detection WORKS PROPERLY in the un-updated WinRE in Win 10 21H2 and ALSO WORKS PROPERLY with the KB5007186 (2021-11) Cumulative Update applied to WinRE in Win 10 21H2.
			# BUT, TPM detection FAILS when any newer Cumulative Update is installed so far (as of March 2022), including KB5007253 (2021-11 Preview), KB5008212 (2021-12), and KB5009543 (2022-01), KB5010793 (Also 2022-01), KB5010342 (2022-02), KB5010415 (2022-02 Preview), and KB5011487 (2022-03)
			# So, can use the "WinRE Updates to Install" folder to keep installing KB5007186 (2021-11) along with the latest .NET update for WinRE, while still installing the latest Cumulative and .NET updates into the full OS using the separate "OS Updates to Install" folder.
			# I submitted a report to Microsoft about this issue through Feedback Hub on 01/14/22 and have not got any response as of 03/28/22.
			# PS. These same exact Cumulative Updates also cause the same issue on WinRE in Win 10 21H1. So it's not a WinRE 21H2 issue specifically, but an issue with the Cumulative Updates themselves.
			# PPS. This issue does NOT appear to affect WinRE from Win 11 21H2 as at least the Win 11 KB5011493 (2022-03) Cumulative Update can be installed and TPM can still be detected in a fully updated WinRE from Win 11 21H2.
			# CONCLUSION: I started using WinRE from Win 11 21H2 as our installation environment and not worry about this TPM detection issue in WinRE from Win 10 anymore since a fully updated WinRE from Win 11 21H2 gets the job done.

			$latestUpdateNames = @()
			foreach ($thisUpdateSearchTemplate in $windowsUpdatesSearchTemplates) {
				$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Replace('[MAJOR VERSION]', $thisWindowsMajorVersion)
				$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Replace('[FEATURE VERSION]', $thisWindowsFeatureVersion)
				$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Replace(',', ' ')
				# NOTE: Replace any commas with spaces since they just treated as a word separator (even when quoted) by "https://www.catalog.update.microsoft.com" in the initial search anyways (which is also case-insensitive),
				# and will also be manually removed from the search results below when matching the exact result row so that a comma existing or not existing doesn't break the match.
				# This is so that a template like "[YYYY-MM] Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows [MAJOR VERSION] Version [FEATURE VERSION] for x64" can match both of the following results (as exact matches are explicitly case-insensitive):
					# 2023-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 10 Version 22H2 for x64
					# 2023-10 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11, version 22H2 for x64
				$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Trim() -Replace '\s+', ' ' # Finally, normalize all spaces.

				$isSearchingCumulativeUpdate = $thisUpdateSearchTemplate.StartsWith('[YYYY-MM] Cumulative Update')
				$isSearchingCumulativeUpdatePreview = $isSearchingCumulativeUpdate
				$relativeCumulativeUpdateSearchMonth = 0

				$thisUpdateToSearch = $thisUpdateSearchTemplate

				for (;;) {
					if ($isSearchingCumulativeUpdate) {
						$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Replace('Cumulative Update Preview for', 'Cumulative Update for')
						
						if ($isSearchingCumulativeUpdatePreview) {
							$thisUpdateSearchTemplate = $thisUpdateSearchTemplate.Replace('Cumulative Update for', 'Cumulative Update Preview for')
						}

						$thisUpdateToSearch = $thisUpdateSearchTemplate.Replace('[YYYY-MM]', (Get-Date).AddMonths($relativeCumulativeUpdateSearchMonth).ToString('yyyy-MM'))
					}

					Write-Output "`n    Searching for Windows Update `"$thisUpdateToSearch`"..."
					$thisTruncatedUpdateToSearch = $thisUpdateToSearch
					while ($thisTruncatedUpdateToSearch.Length -gt 98) {
						$thisTruncatedUpdateToSearch = $thisTruncatedUpdateToSearch.Substring(0, $thisTruncatedUpdateToSearch.LastIndexOf(' '))
						# NOTE: There is a 100 character limit for search strings on "https://www.catalog.update.microsoft.com" and any anything longer gets truncated, which means the exact quoted value may not get searched if the closing quote gets truncated off.
						# To make sure an exact quoted string is always searched for, manually truncate off the trailing WORDS until the string is equal to or less that 100 character (including the quotes).
						# This truncation is done at whole words because if it's done by character in the middle of a word an exact match may not be found with how the search will look for only that partial word.
						# This means our initial search may not be as precise as intended, but the following code will then scrape the page contents for the exact un-truncated search string so the exact update name will always be matched.
						# The one exception would be if there were over 25 results which would get paginated and the search string we're looking for is not on the first page, but that is not the case with any of our search string and is unlikely with any long quoted string.
					}

					if ($thisTruncatedUpdateToSearch -ne $thisUpdateToSearch) {
						Write-Output "      Truncated Search String for 100 Character Limit: `"$thisTruncatedUpdateToSearch`""
					}

					$theseUpdateSearchSource = Invoke-WebRequest -TimeoutSec 5 -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=%22$($thisTruncatedUpdateToSearch.Replace(' ', '%20'))%22" -ErrorAction Stop
					$theseUpdateSearchLinks = $theseUpdateSearchSource.Links

					$thisUpdateID = $null
					$thisUpdateFullName = $thisUpdateToSearch
					$thisUpdateSize = 'UNKNOWN SIZE'
					foreach ($thisUpdateSearchLink in $theseUpdateSearchLinks) {
						$thisUpdateSearchLinkNormalizedOuterHTML = $thisUpdateSearchLink.outerHTML.Replace(',', ' ').Trim() -Replace '\s+', ' ' # Replace commas with spaces and normalize all spaces in link (see comments above about removing commas).
						if ($thisUpdateSearchLinkNormalizedOuterHTML.ToLower().Contains($thisUpdateToSearch.ToLower())) { # NOTE: Using ".ToLower()" for a case-INSENSITIVE match.
							$thisUpdateID = $thisUpdateSearchLink.id.Split('_')[0]
							$thisUpdateFullName = ($thisUpdateSearchLink.outerHTML -Split ('>|<'))[2].Trim()
							$updateSizeMatches = ($theseUpdateSearchSource.Content | Select-String "<span id=`"$($thisUpdateID)_size`">(.+)</span>").Matches
							if ($updateSizeMatches.Count -gt 0) {
								$thisUpdateSize = $updateSizeMatches[0].Groups[1].Value.Trim()
							}
							break
						}
					}

					if ($null -ne $thisUpdateID) {
						Write-Output "      Found Windows Update ID $($thisUpdateID):`n      $thisUpdateFullName"

						$downloadPageContent = (Invoke-WebRequest -TimeoutSec 5 -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method 'POST' -Body @{updateIDs = "[$(@{updateID = $thisUpdateID} | ConvertTo-Json -Compress)]"} -ErrorAction Stop).Content
						# Initially, I couldn't figure out on my own what exactly the "Download" button within the "Search.aspx" results was POSTing to the "DownloadDialog.aspx"
						# page to have it show the correct update download resulst, but after some searching I found this helpful example: 
						# https://github.com/potatoqualitee/kbupdate/blob/0dcc43ff15ec9275fbbd850af56a307e2fbc438f/public/Get-KbUpdate.ps1#L596-L598

						$updateURLMatches = ($downloadPageContent | Select-String "url = '(.+)'" -AllMatches).Matches
						if ($updateURLMatches.Count -eq 0) {
							Write-Host "        ERROR: NO DOWNLOAD URLS FOUND FOR UPDATE ID `"$thisUpdateID`"" -ForegroundColor Red
						} else {
							foreach ($thisUpdateURLMatch in $updateURLMatches) {
								$thisUpdateDownloadURL = $thisUpdateURLMatch.Groups[1].Value
								if ($thisUpdateDownloadURL.EndsWith('.cab') -or $thisUpdateDownloadURL.EndsWith('.msu')) {
									$thisUpdateFilename = ([uri]$thisUpdateDownloadURL).Segments[-1]

									$thisUpdateName = $thisUpdateFilename
									if ($thisUpdateFilename.Contains('-kb')) {
										$thisUpdateName = "KB$(($thisUpdateFilename -Split ('-kb'))[1].Split('-')[0])"
									} elseif ($thisUpdateFilename.Contains('ssu-')) {
										$thisUpdateName = "SSU $(($thisUpdateFilename -Split ('ssu-'))[1].Split('-')[0])"
									} elseif ($thisUpdateFilename.Contains('_')) {
										$thisUpdateName = ($thisUpdateFilename -Split ('_'))[0]
									}

									$thisUpdateName += " - $thisUpdateToSearch"
									$thisUpdateDownloadPath = "$osUpdatesToInstallPath\$thisUpdateName\$thisUpdateFilename"
									# Starting with Cumulative Update 2025-04/KB5055523, installing the companion KB5043080 (which has been included with Windows 11 24H2 Cumulative Updates since 2024-09) started failing with 0x80070228.
									# By examining the logs, I found the following entries which made it appear as though the full Cumulative Update file (KB5058499 in the logs below) was being checked when the KB5043080 file was being installed by itself BEFORE the full Cumulative Update.

									# Info Loading database: \\?\C:\Windows\TEMP\mountRE\Windows\Temp\########-####-####-####-############\metadata\LCUCompDB_KB5043080.xml
									# Info Loading database: \\?\C:\Windows\TEMP\mountRE\Windows\Temp\########-####-####-####-############\metadata\SSUCompDB_KB5043113.xml
									# Info Processing metadata source C:\PATH\TO\windows11.0-kb5058499-x64_f633db6acc14132bf74cc1461bd77b8941819d5f.msu.
									# ... about 30 lines later ...
									# Info Loading database: \\?\C:\Windows\TEMP\mountRE\Windows\Temp\########-####-####-####-############\metadata\SessionCompDBs\LCUCompDB_KB5058499.xml
									# ... about 50 lines later ...
									# Error DISM DISM Package Manager: PID=#### TID=#### Failed to install UUP package. - CMsuPackage::DoInstall(hr:0x80070228)
									# Error DISM DISM Package Manager: PID=#### TID=#### Failed to execute the install in expanded MSU folder C:\Windows\TEMP\mountRE\Windows\Temp\########-####-####-####-############. - CMsuPackage::ProcessMsu(hr:0x80070228)
									# Error DISM DISM Package Manager: PID=#### TID=#### Failed to apply the MSU unattend file to the image. - CMsuPackage::Install(hr:0x80070228)
									# Error DISM API: PID=#### TID=#### Failed to install msu package C:\PATH\TO\windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu - CAddPackageCommandObject::InternalExecute(hr:0x80070228)
									# Error DISM API: PID=#### TID=#### InternalExecute failed - CBaseCommandObject::Execute(hr:0x80070228)
									# Error DISM API: PID=#### TID=#### CAddPackageCommandObject internal execution failed - DismAddPackageInternal(hr:0x80070228)

									# This was odd and confusing because KB5043080 would install properly with Cumulative Updates 2024-09 through 2025-03 with no error.
									# In an attempt to isolate each update file, I put them in their own subfolders, and that ended up solving the problem.
									# I don't fully understand why a separate MSU file (KB5058499 in the logs above) is getting checked when a command is run to only install KB5043080, but this workaround allowed all MSU files to be installed properly.

									while ("$($thisUpdateDownloadPath).download".Length -gt 248) { # MAX_PATH (260) minus 12 (248) seems to be the safest path length: https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
										$thisUpdateName = $thisUpdateName.Substring(0, $thisUpdateName.LastIndexOf(' '))
										$thisUpdateDownloadPath = "$osUpdatesToInstallPath\$thisUpdateName\$thisUpdateFilename"
									}

									$latestUpdateNames += $thisUpdateName

									if (Test-Path $thisUpdateDownloadPath) {
										Write-Output "        Windows Update Already Downloaded `"$thisUpdateFilename`" ($thisUpdateSize)"
									} else {
										if (Test-Path "$osUpdatesToInstallPath\$thisUpdateName") {
											Remove-Item "$osUpdatesToInstallPath\$thisUpdateName" -Recurse -Force -ErrorAction Stop
										}

										New-Item -ItemType 'Directory' -Path "$osUpdatesToInstallPath\$thisUpdateName" -ErrorAction Stop | Out-Null

										$alternateWindowsEdition = 'Pro'
										if ($thisWindowsEdition -eq 'Pro') {
											$alternateWindowsEdition = 'Home'
										}

										$alternateWindowsEditionVersionString = "Windows $thisWindowsMajorVersion $alternateWindowsEdition $thisWindowsFeatureVersion"

										$thisUpdateDownloadPathFromAlternateWindowsEdition = $thisUpdateDownloadPath.Replace("Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion", $alternateWindowsEditionVersionString)
										if (Test-Path $thisUpdateDownloadPathFromAlternateWindowsEdition) {
											Write-Output "        Copying Windows Update `"$thisUpdateFilename`" ($thisUpdateSize) from $alternateWindowsEditionVersionString Updates..."

											Copy-Item $thisUpdateDownloadPathFromAlternateWindowsEdition $thisUpdateDownloadPath -Force -ErrorAction Stop

											Write-Output "          Copied Windows Update `"$thisUpdateFilename`" from $alternateWindowsEditionVersionString Updates"
										} else {
											Write-Output "        Downloading Windows Update `"$thisUpdateFilename`" ($thisUpdateSize)..."

											Invoke-WebRequest $thisUpdateDownloadURL -OutFile "$($thisUpdateDownloadPath).download" -ErrorAction Stop

											Move-Item "$($thisUpdateDownloadPath).download" "$thisUpdateDownloadPath" -Force -ErrorAction Stop

											Write-Output "          Downloaded Windows Update `"$thisUpdateFilename`""
										}

										$windowsUpdatesChangedSinceLastBuild = $true
									}
								} else {
									Write-Host "        WARNING: CAN ONLY PRE-INSALL `".cab`" OR `".msu`" UPDATES (IGNORING $thisUpdateDownloadURL)" -ForegroundColor Yellow
								}
							}
						}

						break
					} else {
						Write-Host "      DID NOT FIND WINDOWS UPDATE FOR `"$thisUpdateToSearch`"" -ForegroundColor Yellow

						if ($isSearchingCumulativeUpdate) {
							if (-not $isSearchingCumulativeUpdatePreview) {
								$relativeCumulativeUpdateSearchMonth --
							}

							$isSearchingCumulativeUpdatePreview = (-not $isSearchingCumulativeUpdatePreview)
						} else {
							break
						}
					}
				}
			}

			if ($latestUpdateNames.Count -eq 0) {
				Write-Host "`n    FAILED TO FIND ANY WINDOWS UPDATES - MAKE SURE INTERNET IS CONNECTED AND TRY AGAIN" -ForegroundColor Red
				exit 1
			}

			Write-Output "`n    Checking for Outdated Previously Downloaded Windows Updates to Delete..."

			$deletedOutdatedUpdatesCount = 0

			Get-ChildItem "$osUpdatesToInstallPath" -ErrorAction Stop | ForEach-Object {
				if (-not $latestUpdateNames.Contains($_.Name)) {
					Write-Output "      Deleting Outdated Windows Update: $($_.Name)"
					Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
					$deletedOutdatedUpdatesCount ++
				}
			}

			if ($deletedOutdatedUpdatesCount -eq 0) {
				Write-Output '      No Outdated Previously Downloaded Windows Updates to Delete'
			} else {
				Write-Output "      Deleted $deletedOutdatedUpdatesCount Outdated Previously Downloaded Windows Updates"
				$windowsUpdatesChangedSinceLastBuild = $true
			}

			$downloadUpdatesEndDate = Get-Date
			Write-Output "`n  Finished Downloading Latest Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Updates at $downloadUpdatesEndDate ($([math]::Round(($downloadUpdatesEndDate - $downloadUpdatesStartDate).TotalMinutes, 2)) Minutes)"

			if (-not $windowsUpdatesChangedSinceLastBuild) {
				$noNewUpdatesPromptCaption = "`n  No new Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion updates have been downloaded since the last run.`n  Create a new Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image anyway?"
				$noNewUpdatesPromptChoices = '&Yes', '&No'

				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$noNewUpdatesPromptResponse = $Host.UI.PromptForChoice($noNewUpdatesPromptCaption, "`n", $noNewUpdatesPromptChoices, 1)
				Write-Output ''

				if ($noNewUpdatesPromptResponse -eq 1) {
					continue # Go to next Windows version in loop, if multiple have been selected.
				}
			}


			$updatesToInstallIntoWIM = @()
			if (Test-Path $osUpdatesToInstallPath) {
				$updatesToInstallIntoWIM = Get-ChildItem "$osUpdatesToInstallPath" -Recurse -File -Include '*.msu', '*.cab' | Sort-Object -Property BaseName # Make sure the update files are sorted by file name, not the parent folder name (so that SSUs are always first).
			}

			$updatesToInstallIntoWinRE = @()
			if (Test-Path "$wimOutputPath\WinRE Updates to Install") {
				$updatesToInstallIntoWinRE = Get-ChildItem "$wimOutputPath\WinRE Updates to Install" -Recurse -File -Include '*.msu', '*.cab' | Sort-Object -Property BaseName
			} else {
				$updatesToInstallIntoWinRE = $updatesToInstallIntoWIM
			}


			if (($updatesToInstallIntoWinRE.Count -gt 0) -or ($updatesToInstallIntoWIM.Count -gt 0) -or (-not (Test-Path "$wimOutputPath\$winREwimName.wim"))<# -or (-not (Test-Path "$wimOutputPath\Wi-Fi Drivers"))#>) {
				Write-Output "`n  Mounting Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."

				Copy-Item $sourceWIMpath "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop

				if (-not (Test-Path "$systemTempDir\mountOS")) {
					New-Item -ItemType 'Directory' -Path "$systemTempDir\mountOS" -ErrorAction Stop | Out-Null
				}

				Mount-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -Path "$systemTempDir\mountOS" -CheckIntegrity -ErrorAction Stop | Out-Null
			}


			if (Test-Path "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim") {
				Write-Output "`n  Extracting WinRE from Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."

				Copy-Item "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim" "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop
			} else {
				Write-Host "`n  WINRE NOT FOUND" -ForegroundColor Red
				break
			}


			# NOTE: When using WinPE/WinRE 11 22H2 as the installation environment for both Windows 10 and 11, some network drivers are not available for older systems that don't support Windows 11 (which wasn't an issue with initial WinRE 11 version 21H2/22000).
			# Having the installation environment be able to establish a network connection is critical for downloading QA Helper, as well as connecting to local SMB shares to retrieve the Windows install images.
			# Through testing, I found that extracting all the default network drivers from the full Windows 11 image and installing them into the WinRE 11 image allowed all my test systems to properly make network connections (installing all drivers from WinRE 10 did not work).
			# So, the network drivers will always be extracted from the full Windows images in this script and then installed into the WinRE image when creating the installation image in the "Create WinPE Image" script.
			$extractedNetworkDriversPath = "$wimOutputPath\Extracted Network Drivers"
			if (-not (Test-Path $extractedNetworkDriversPath)) {
				Write-Output "`n  Extracting Network Drivers from Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."

				New-Item -ItemType 'Directory' -Path $extractedNetworkDriversPath -ErrorAction Stop | Out-Null

				$allPreInstalledDriverInfPaths = (Get-ChildItem "$systemTempDir\mountOS\Windows\System32\DriverStore\FileRepository" -Recurse -File -Include '*.inf').FullName

				# This Driver .inf parsing code is based on code written for "Install Windows.ps1"
				$thisDriverIndex = 0
				foreach ($thisDriverInfPath in $allPreInstalledDriverInfPaths) {
					$thisDriverFolderPath = (Split-Path $thisDriverInfPath -Parent)
					$thisDriverFolderName = (Split-Path $thisDriverFolderPath -Leaf)

					$thisDriverInfContents = Get-Content $thisDriverInfPath

					foreach ($thisDriverInfLine in $thisDriverInfContents) {
						if (($lineCommentIndex = $thisDriverInfLine.IndexOf(';')) -gt -1) { # Remove .inf comments from each line before any parsing to avoid matching any text within comments.
							$thisDriverInfLine = $thisDriverInfLine.Substring(0, $lineCommentIndex)
						}

						$thisDriverInfLine = $thisDriverInfLine.Trim()

						if ($thisDriverInfLine -ne '') {
							$thisDriverInfLineUPPER = $thisDriverInfLine.ToUpper()

							if ($thisDriverInfLine.StartsWith('[')) {
								# https://docs.microsoft.com/en-us/windows-hardware/drivers/install/inf-version-section
								$wasInfVersionSection = $isInfVersionSection
								$isInfVersionSection = ($thisDriverInfLineUPPER -eq '[VERSION]')

								if ($wasInfVersionSection -and (-not $isInfVersionSection)) {
									# If passed Version section and didn't already break from getting a NET class, then we can stop reading lines because we don't want this driver.
									break
								}
							} elseif ($isInfVersionSection -and (($lineEqualsIndex = $thisDriverInfLine.IndexOf('=')) -gt -1) -and $thisDriverInfLineUPPER.Contains('CLASS') -and (-not $thisDriverInfLineUPPER.Contains('CLASSGUID'))) {
								$thisDriverClass = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Trim().ToUpper() # It appears that the Class Names will never be in quotes or be variables that need to be translated.

								if ($thisDriverClass -eq 'NET') {
									$thisDriverIndex ++
									try {
										Write-Output "    Extracting Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Network Driver $($thisDriverIndex): $thisDriverFolderName"
										Copy-Item $thisDriverFolderPath $extractedNetworkDriversPath -Recurse -Force -ErrorAction Stop
									} catch {
										Write-Host "      ERROR EXTRACTING WINDOWS $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion NETWORK DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
									}
								}

								break
							}
						}
					}
				}
			} else {
				Write-Host "`n  WINDOWS $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion NETWORK DRIVERS ALREADY EXTRACTED" -ForegroundColor Yellow
			}


			if ($updatesToInstallIntoWinRE.Count -gt 0) {
				Write-Output "`n  Mounting WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion for Updates..."

				if (-not (Test-Path "$systemTempDir\mountRE")) {
					New-Item -ItemType 'Directory' -Path "$systemTempDir\mountRE" -ErrorAction Stop | Out-Null
				}

				Mount-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -Path "$systemTempDir\mountRE" -CheckIntegrity -ErrorAction Stop | Out-Null


				<#
				# NOTE: When testing the network driver issues with WinRE 11 22H2 (described above), I also extracted WinRE network drivers to be able to easily compare the driver sets to see what as not included vs the full Windows images as well as between WinRE 10 and 11.
				# In the end, this code was not needed since only the network drivers from the full Windows image are used, but leaving this code in place but commented out in case it's useful for future needs or just testing or reference.
				$extractedNetworkDriversPath = "$wimOutputPath\WinRE Extracted Network Drivers"
				if (-not (Test-Path $extractedNetworkDriversPath)) {
					Write-Output "`n  Extracting WinRE Network Drivers from Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."

					New-Item -ItemType 'Directory' -Path $extractedNetworkDriversPath -ErrorAction Stop | Out-Null

					$allPreInstalledDriverInfPaths = (Get-ChildItem "$systemTempDir\mountRE\Windows\System32\DriverStore\FileRepository" -Recurse -File -Include '*.inf').FullName

					# This Driver .inf parsing code is based on code written for "Install Windows.ps1"
					$thisDriverIndex = 0
					foreach ($thisDriverInfPath in $allPreInstalledDriverInfPaths) {
						$thisDriverFolderPath = (Split-Path $thisDriverInfPath -Parent)
						$thisDriverFolderName = (Split-Path $thisDriverFolderPath -Leaf)

						$thisDriverInfContents = Get-Content $thisDriverInfPath

						foreach ($thisDriverInfLine in $thisDriverInfContents) {
							if (($lineCommentIndex = $thisDriverInfLine.IndexOf(';')) -gt -1) { # Remove .inf comments from each line before any parsing to avoid matching any text within comments.
								$thisDriverInfLine = $thisDriverInfLine.Substring(0, $lineCommentIndex)
							}

							$thisDriverInfLine = $thisDriverInfLine.Trim()

							if ($thisDriverInfLine -ne '') {
								$thisDriverInfLineUPPER = $thisDriverInfLine.ToUpper()

								if ($thisDriverInfLine.StartsWith('[')) {
									# https://docs.microsoft.com/en-us/windows-hardware/drivers/install/inf-version-section
									$wasInfVersionSection = $isInfVersionSection
									$isInfVersionSection = ($thisDriverInfLineUPPER -eq '[VERSION]')

									if ($wasInfVersionSection -and (-not $isInfVersionSection)) {
										# If passed Version section and didn't already break from getting a NET class, then we can stop reading lines because we don't want this driver.
										break
									}
								} elseif ($isInfVersionSection -and (($lineEqualsIndex = $thisDriverInfLine.IndexOf('=')) -gt -1) -and $thisDriverInfLineUPPER.Contains('CLASS') -and (-not $thisDriverInfLineUPPER.Contains('CLASSGUID'))) {
									$thisDriverClass = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Trim().ToUpper() # It appears that the Class Names will never be in quotes or be variables that need to be translated.

									if ($thisDriverClass -eq 'NET') {
										$thisDriverIndex ++
										try {
											Write-Output "    Extracting WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Network Driver $($thisDriverIndex): $thisDriverFolderName"
											Copy-Item $thisDriverFolderPath $extractedNetworkDriversPath -Recurse -Force -ErrorAction Stop
										} catch {
											Write-Host "      ERROR EXTRACTING WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion NETWORK DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
										}
									}

									break
								}
							}
						}
					}
				} else {
					Write-Host "`n  WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion NETWORK DRIVERS ALREADY EXTRACTED" -ForegroundColor Yellow
				}
				#>


				Write-Output "`n  Increasing WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Scratch Space..."
				# Increase WinRE Scratch Space: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-winre-part-1
				# If too manu GUI apps get launched during testing it appears the limited default of 32 MB of scratch space can get used up and then other stuff can fail to load such as required DISM PowerShell modules.

				Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountRE`"", '/Get-ScratchSpace'

				# PowerShell equivalent of DISM's "/Set-ScratchSpace" does not seem to exist.
				$dismSetScratchSpaceExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountRE`"", '/Set-ScratchSpace:512').ExitCode

				if ($dismSetScratchSpaceExitCode -ne 0) {
					Write-Host "`n    ERROR: FAILED TO INCREASE WINRE SCRATCH SPACE - EXIT CODE: $dismSetScratchSpaceExitCode" -ForegroundColor Red
					break
				}

				Write-Output "`n  WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image Info Before Updates:"
				Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -ErrorAction Stop

				Write-Output "`n  Installing $($updatesToInstallIntoWinRE.Count) Updates Into WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image..."
				# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#add-update-packages-to-winre

				foreach ($thisUpdateToInstallIntoWinRE in $updatesToInstallIntoWinRE) {
					$updateStartDate = Get-Date

					$updateName = $thisUpdateToInstallIntoWinRE.Name
					if ($thisUpdateToInstallIntoWinRE.Name.Contains('-kb')) {
						$updateName = "KB$(($thisUpdateToInstallIntoWinRE.Name -Split ('-kb'))[1].Split('-')[0])"
					} elseif ($thisUpdateToInstallIntoWinRE.Name.Contains('ssu-')) {
						$updateName = "SSU $(($thisUpdateToInstallIntoWinRE.Name -Split ('ssu-'))[1].Split('-')[0])"
					} elseif ($thisUpdateToInstallIntoWinRE.Name.Contains('_')) {
						$updateName = ($thisUpdateToInstallIntoWinRE.Name -Split ('_'))[0]
					}

					Write-Output "    Installing $updateName ($([math]::Round(($thisUpdateToInstallIntoWinRE.Length / 1MB), 2)) MB) Into WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image at $updateStartDate..."
					try {
						Add-WindowsPackage -Path "$systemTempDir\mountRE" -PackagePath $thisUpdateToInstallIntoWinRE.FullName -WarningAction Stop -ErrorAction Stop | Out-Null
					} catch {
						notepad.exe "$Env:WINDIR\Logs\DISM\dism.log"
						throw $_
					}
					$updateEndDate = Get-Date
					Write-Output "      Finished Installing at $updateEndDate ($([math]::Round(($updateEndDate - $updateStartDate).TotalMinutes, 2)) Minutes)"
				}

				Write-Output "`n  Superseded Packages in WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image After Updates:"
				Get-WindowsPackage -Path "$systemTempDir\mountRE" | Where-Object -Property PackageState -Eq -Value Superseded


				# NOTHING EXCEPT UPDATES SHOULD BE PRE-INSTALLED OR ADDED INTO THE WINRE WIM!


				Write-Output "`n  Cleaning Up WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image After Updates..."
				# PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
				$dismCleanupREexitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountRE`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

				if ($dismCleanupREexitCode -eq 0) {
					Write-Output "`n  Superseded Packages for WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image After Cleanup (Nothing Should Be Listed This Time):"
					Get-WindowsPackage -Path "$systemTempDir\mountRE" | Where-Object -Property PackageState -Eq -Value Superseded


					Write-Output "`n  Unmounting and Saving Updated WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image..."
					# Dism /Unmount-Image /MountDir:C:\test\offline /Commit
					Dismount-WindowsImage -Path "$systemTempDir\mountRE" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
					Remove-Item "$systemTempDir\mountRE" -Recurse -Force -ErrorAction Stop
					Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -ErrorAction Stop

					if (Test-Path "$wimOutputPath\$winREwimName.wim") {
						Write-Output "`n  Deleting Previous WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image With The Same Name ($winREwimName.wim)..."
						Remove-Item "$wimOutputPath\$winREwimName.wim" -Force -ErrorAction Stop
					}


					Write-Output "`n  Exporting Compressed WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image as `"$winREwimName.wim`"..."
					# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-final-image
					Export-WindowsImage -SourceImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -SourceIndex 1 -DestinationImagePath "$wimOutputPath\$winREwimName.wim" -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
					Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName.wim" -Index 1 -ErrorAction Stop

					# Delete the TEMP WIM which can be considerably larger than the exported compressed WIM.
					# This is because the TEMP WIM will have a "[DELETED]" folder within it with all the old junk from the update process. This "[DELETED]" folder is not included when exporting a WIM.
					Remove-Item "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop

					Write-Output "`n  Verifying Exported Updated WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image Contents Against Source WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image Contents..."
					# IMPORTANT: When creating WinRE 10 22H2 images (from Windows 10 22H2), I ran into an issue I had never run into before where critical system files could end up being removed from the final exported WinRE/Windows images.
					# I am not sure exactly how or why this happened, and it only happened rarely, but I was able to reproduce the issue after many reattempts of creating the updated Windows 10 images.
					# In all my testing, this issue never seemed to happen to Windows 11 images, but since it is so inconsistent/rare I'm not sure that it couldn't happen on Windows 11 images as well, so they will also be verified.
					# Also, I was previously using the older built-in version of DISM located at "/Windows/System32/Dism.exe" rather than the latest version of DISM from the ADK (https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install#choose-the-right-adk-for-your-scenario), which is now being used by running "DandISetEnv.bat" before this script is launched.
					# Since switching to the using the latest DISM in the latest Window 11 22H2 ADK I have not seen this issue, but since it was so inconsistent I'm unsure whether or not using the latest DISM actually avoids the issue.
					# I'm also unsure whether using the latest DISM from the ADK affects the PowerShell cmdlets such as "Export-WindowsImage", but I'm also unsure whether the issue happened at that step or before that at the "DISM /Cleanup-Image /StartComponentCleanup /ResetBase" step.
					# It's possible the files were being removed because they became corrupted, which may actually indicate some issue with my SSD and not with any of the software being used, but that is just speculation since my SSD appears to be perfectly healthy when checked with "Hard Disk Sentinel".
					# Since I'm unsure exactly where or why the issue was actually happening, I decided to just manually verify the exported images contents to make sure they contain all the expected system files that are present in the original image.
					# I also noticed that when this happened usually many files were removed resulting in the exported image being smaller than the source image, so the file sizes are compared first as an initial fast way to detect the issue without having to do the longer file comparison.
					# If the exported image is larger than the source image, the system file lists are still compared, excluding all the paths that are expected to be different.
					# Excluding the paths that are expected to be different makes the file path comparison much faster, and still ensures that all the critical System32 contents (etc) are present in the exported image.
					# Since it could be possible that some files are removed from the paths that are expected to be different (which aren't being checked), this verification should not be considered to be 100% thorough,
					# but in my testing when the issue happens many files get removed and this verification was able to detect the issue to stop the process and alert that the exported image should not be used.
					# If this verification fails, there is no way to correct the problem from this point and the script should just be run again to re-create the updated images from scrach, which should usually work fine the next time.

					$verifyingStartDate = Get-Date

					$sourceWinReWimSizeBytes = (Get-Item "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim").Length
					$updatedWinReWimSizeBytes = (Get-Item "$wimOutputPath\$winREwimName.wim").Length

					if ($updatedWinReWimSizeBytes -lt $sourceWinReWimSizeBytes) {
						$updatedWinReWimSizeBytesDifference = ($sourceWinReWimSizeBytes - $updatedWinReWimSizeBytes)
						if ($updatedWinReWimSizeBytesDifference -ge 1000000) {
							Write-Host "`n    ERROR: UPDATED WINRE WIM ($updatedWinReWimSizeBytes) IS *$([math]::Round(($updatedWinReWimSizeBytesDifference / 1MB), 2)) MB SMALLER THAN* SOURCE WINRE WIM ($sourceWinReWimSizeBytes) - THIS SHOULD NOT NORMALLY HAPPENED" -ForegroundColor Red

							$smallerUpdatedWinReWimPromptCaption = '    Continue anyway?'
							$smallerUpdatedWinReWimPromptChoices = '&No', '&Yes'

							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							$smallerUpdatedWinReWimPromptResponse = $Host.UI.PromptForChoice($smallerUpdatedWinReWimPromptCaption, "`n", $smallerUpdatedWinReWimPromptChoices, 0)
							Write-Output ''

							if ($smallerUpdatedWinReWimPromptResponse -eq 0) {
								break
							}
						} else {
							Write-Host "`n    NOTICE: UPDATED WINRE WIM ($updatedWinReWimSizeBytes) IS *$([math]::Round(($updatedWinReWimSizeBytesDifference / 1MB), 2)) MB SMALLER THAN* SOURCE WINRE WIM ($sourceWinReWimSizeBytes) - CONTINUING ANYWAY`n" -ForegroundColor Yellow
						}
					}

					$excludedCompareWinReWimContentPaths = @('\Windows\servicing\', '\Windows\System32\CatRoot\', '\Windows\System32\DriverStore\FileRepository\', '\Windows\WinSxS\') # Exclude these paths from the difference comparison because these are the paths we expect to be different.
					if (($thisWindowsMajorVersion -eq '10') -and ($thisWindowsFeatureVersion -eq '22H2')) { # NOTE: The following added exclusions are only relevant to each feature version since a new feature version will not contain stuff remove in previous cumulative updates to the prior feature version.
						$excludedCompareWinReWimContentPaths += '\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Accessories\' # This one folder outside of the previously excluded paths will be moved to "\ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\" within the updated WinRE 10 image (but not the WinRE 11 image), so don't error when it doesn't exist.
					}

					$sourceWinReWimContentPaths = Get-WindowsImageContent -ImagePath "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim" -Index 1 | Select-String $excludedCompareWinReWimContentPaths -SimpleMatch -NotMatch # Exclude paths from the source lists since it's more efficient than letting them be compared and ignoring them from the results.
					$updatedWinReWimContentPaths = Get-WindowsImageContent -ImagePath "$wimOutputPath\$winREwimName.wim" -Index 1 | Select-String $excludedCompareWinReWimContentPaths -SimpleMatch -NotMatch
					$filePathsRemovedFromUpdatedWinReWIM = (Compare-Object -ReferenceObject $sourceWinReWimContentPaths -DifferenceObject $updatedWinReWimContentPaths | Where-Object SideIndicator -eq '<=').InputObject # Comparing text lists of paths from within the WIMs is MUCH faster than comparing mounted files via "Get-ChildItem -Recurse".
					$verifyingEndDate = Get-Date

					if ($filePathsRemovedFromUpdatedWinReWIM.Count -gt 0) { # It is NOT COMMON for ANY files to be removed by an update for WinPE/RE, but still make it a prompt (defaulting to "No") just in case that changes in the future.
						Write-Host "`n    ERROR: THE FOLLOWING $($filePathsRemovedFromUpdatedWinReWIM.Count) FILES WERE REMOVED FROM THE UPDATED WINRE WIM`n      $($filePathsRemovedFromUpdatedWinReWIM -Join "`n      ")" -ForegroundColor Red

						$filePathsRemovedFromUpdatedWinReWimPromptCaption = '    Continue anyway?'
						$filePathsRemovedFromUpdatedWinReWimPromptChoices = '&No', '&Yes'

						$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
						$filePathsRemovedFromUpdatedWinReWimPromptResponse = $Host.UI.PromptForChoice($filePathsRemovedFromUpdatedWinReWimPromptCaption, "`n", $filePathsRemovedFromUpdatedWinReWimPromptChoices, 0)
						Write-Output ''

						if ($filePathsRemovedFromUpdatedWinReWimPromptResponse -eq 0) {
							break
						}
					}

					Write-Output "    Finished Verifying Exported Updated WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image at $verifyingEndDate ($([math]::Round(($verifyingEndDate - $verifyingStartDate).TotalMinutes, 2)) Minutes)"

					Write-Output "`n  Replacing Original WinRE with Updated WinRE in Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."
					Remove-Item "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim" -Force -ErrorAction Stop
					Copy-Item "$wimOutputPath\$winREwimName.wim" "$systemTempDir\mountOS\Windows\System32\Recovery\Winre.wim" -Force -ErrorAction Stop
				} else {
					Write-Host "`n    ERROR: FAILED TO DISM CLEANUP FOR WINRE - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
					break
				}
			} else {
				Write-Host "`n  NO UPDATE FILES (IN `"WinRE Updates to Install`" FOLDER) TO INSTALL" -ForegroundColor Yellow

				if (Test-Path "$systemTempDir\mountRE") {
					Write-Output "`n  Unmounting and Discarding Un-Updated WinRE $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image..."
					Dismount-WindowsImage -Path "$systemTempDir\mountRE" -Discard -ErrorAction Stop | Out-Null
					Remove-Item "$systemTempDir\mountRE" -Recurse -Force -ErrorAction Stop
				}

				if (Test-Path "$wimOutputPath\$winREwimName-TEMP.wim") {
					Move-Item "$wimOutputPath\$winREwimName-TEMP.wim" "$wimOutputPath\WinRE-$thisWindowsMajorVersion-$thisWindowsFeatureVersion-ISO$sourceISOversionSuffix-Source.wim" -Force -ErrorAction Stop
				}
			}


			if ($updatesToInstallIntoWIM.Count -gt 0) {
				Write-Output "`n  Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Image Info Before Updates:"
				Get-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -ErrorAction Stop

				Write-Output "`n  Installing $($updatesToInstallIntoWIM.Count) Updates Into Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."
				# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#add-windows-updates-to-your-image
				# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-desktop-editions#add-windows-updates-to-your-image

				$installedUpdateNames = @()

				foreach ($thisUpdateToInstallIntoWIM in $updatesToInstallIntoWIM) {
					$updateStartDate = Get-Date

					$updateName = $thisUpdateToInstallIntoWIM.Name
					if ($thisUpdateToInstallIntoWIM.Name.Contains('-kb')) {
						$updateName = "KB$(($thisUpdateToInstallIntoWIM.Name -Split ('-kb'))[1].Split('-')[0])"
					} elseif ($thisUpdateToInstallIntoWIM.Name.Contains('ssu-')) {
						$updateName = "SSU $(($thisUpdateToInstallIntoWIM.Name -Split ('ssu-'))[1].Split('-')[0])"
					} elseif ($thisUpdateToInstallIntoWIM.Name.Contains('_')) {
						$updateName = ($thisUpdateToInstallIntoWIM.Name -Split ('_'))[0]
					}

					$installedUpdateNames += $updateName

					Write-Output "    Installing $updateName ($([math]::Round(($thisUpdateToInstallIntoWIM.Length / 1MB), 2)) MB) Into Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image at $updateStartDate..."
					# Dism /Image:C:\test\offline /Add-Package /PackagePath:C:\packages\package1.cab (https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-or-remove-packages-offline-using-dism)
					try {
						Add-WindowsPackage -Path "$systemTempDir\mountOS" -PackagePath $thisUpdateToInstallIntoWIM.FullName -WarningAction Stop -ErrorAction Stop | Out-Null
					} catch {
						notepad.exe "$Env:WINDIR\Logs\DISM\dism.log"
						throw $_
					}
					$updateEndDate = Get-Date
					Write-Output "      Finished Installing at $updateEndDate ($([math]::Round(($updateEndDate - $updateStartDate).TotalMinutes, 2)) Minutes)"
				}

				Write-Output "`n  Superseded Packages in Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image After Updates:"
				Get-WindowsPackage -Path "$systemTempDir\mountOS" | Where-Object -Property PackageState -Eq -Value Superseded


				# NOTHING EXCEPT UPDATES SHOULD BE PRE-INSTALLED OR ADDED INTO THE WINDOWS INSTALL WIM!
				# ALL NECESSARY WINDOWS INSTALL SETUP FILES ARE ADDED FROM SERVER OR USB DURING THE INSTALLATION PROCESS.


				Write-Output "`n  Cleaning Up Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image After Updates..."
				# PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
				$dismCleanupOSexitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountOS`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

				if ($dismCleanupOSexitCode -eq 0) {
					Write-Output "`n  Superseded Packages for Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image After Cleanup (Nothing Should Be Listed This Time):"
					Get-WindowsPackage -Path "$systemTempDir\mountOS" | Where-Object -Property PackageState -Eq -Value Superseded


					Write-Output "`n  Unmounting and Saving Updated Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."
					# Dism /Unmount-Image /MountDir:C:\test\offline /Commit
					Dismount-WindowsImage -Path "$systemTempDir\mountOS" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
					Remove-Item "$systemTempDir\mountOS" -Recurse -Force -ErrorAction Stop
					Get-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -ErrorAction Stop

					if (Test-Path "$wimOutputPath\$wimName.wim") {
						Write-Output "`n  Deleting Previous Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image With The Same Name ($wimName.wim)..."
						Remove-Item "$wimOutputPath\$wimName.wim" -Force -ErrorAction Stop
					}


					Write-Output "`n  Exporting Compressed Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image as `"$wimName.wim`"..."
					# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-final-image
					Export-WindowsImage -SourceImagePath "$wimOutputPath\$wimName-TEMP.wim" -SourceIndex 1 -DestinationImagePath "$wimOutputPath\$wimName.wim" -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
					Get-WindowsImage -ImagePath "$wimOutputPath\$wimName.wim" -Index 1 -ErrorAction Stop

					# Delete the TEMP WIM which can be considerably larger than the exported compressed WIM.
					# This is because the TEMP WIM will have a "[DELETED]" folder within it with all the old junk from the update process. This "[DELETED]" folder is not included when exporting a WIM.
					Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop


					Write-Output "`n  Verifying Exported Updated Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image Contents Against Source Windows Image Contents..."
					# NOTE: See comments above when verifying the WinRE image which also apply to this manual verification of the exported Windows image.

					$verifyingStartDate = Get-Date

					$sourceWinInstallWimSizeBytes = (Get-Item $sourceWIMpath).Length
					$updatedWinInstallWimSizeBytes = (Get-Item "$wimOutputPath\$wimName.wim").Length

					if ($updatedWinInstallWimSizeBytes -lt $sourceWinInstallWimSizeBytes) {
						Write-Host "`n    ERROR: UPDATED WINDOWS INSTALL WIM ($updatedWinInstallWimSizeBytes) IS *$([math]::Round((($sourceWinInstallWimSizeBytes - $updatedWinInstallWimSizeBytes) / 1MB), 2)) MB SMALLER THAN* SOURCE WINDOWS INSTALL WIM ($sourceWinInstallWimSizeBytes) - THIS SHOULD NOT HAVE HAPPENED`n    $($filePathsRemovedFromUpdatedWinInstallWIM -Join "`n    ")" -ForegroundColor Red
						break
					}

					$excludedCompareWinInstallWimContentPaths = @('\Windows\servicing\', '\Windows\System32\CatRoot\', '\Windows\System32\DriverStore\FileRepository\', '\Windows\WinSxS\') # Exclude these paths from the difference comparison because these are the paths we expect to be different.

					$winInstallWimFilesRemovedByUpdatesFilePath = "$wimOutputPath\Windows Files Removed By Updates.txt"
					if (Test-Path $winInstallWimFilesRemovedByUpdatesFilePath) {
						# When Cumulative updates are installed, files can be removed by the update.
						# To not prompt about these past removals with each new update, a list of approved removals is saved to ignore for future updates.
						# So, read this list and add it to the excludedCompareWinInstallWimContentPaths variable to ignore these already approved removed files.

						$excludedCompareWinInstallWimContentPaths += Get-Content $winInstallWimFilesRemovedByUpdatesFilePath | Select-String '\' -SimpleMatch
					}

					$sourceWinInstallWimContentPaths = Get-WindowsImageContent -ImagePath $sourceWIMpath -Index 1 | Select-String $excludedCompareWinInstallWimContentPaths -SimpleMatch -NotMatch # Exclude paths from the source lists since it's more efficient than letting them be compared and ignoring them from the results.
					$updatedWinInstallWimContentPaths = Get-WindowsImageContent -ImagePath "$wimOutputPath\$wimName.wim" -Index 1 | Select-String $excludedCompareWinInstallWimContentPaths -SimpleMatch -NotMatch
					$filePathsRemovedFromUpdatedWinInstallWIM = (Compare-Object -ReferenceObject $sourceWinInstallWimContentPaths -DifferenceObject $updatedWinInstallWimContentPaths | Where-Object SideIndicator -eq '<=').InputObject # Comparing text lists of paths from within the WIMs is MUCH faster than comparing mounted files via "Get-ChildItem -Recurse".
					$verifyingEndDate = Get-Date

					if ($filePathsRemovedFromUpdatedWinInstallWIM.Count -gt 0) {
						Write-Host "`n    ERROR: THE FOLLOWING $($filePathsRemovedFromUpdatedWinInstallWIM.Count) FILES WERE REMOVED FROM THE UPDATED WINDOWS INSTALL WIM`n    $($filePathsRemovedFromUpdatedWinInstallWIM -Join "`n    ")" -ForegroundColor Red

						$filePathsRemovedFromUpdatedWinInstallWimPromptCaption = '    Continue anyway?'
						$filePathsRemovedFromUpdatedWinInstallWimPromptMessage = "`n    If you continue, these removed files will be added to a list of files to ignore during future updates so you will not be prompted about them again.`n`n"
						$filePathsRemovedFromUpdatedWinInstallWimPromptChoices = '&No', '&Yes'

						$filePathsRemovedFromUpdatedWinInstallWimPromptChoicesDefaultOption = 1
						if ($filePathsRemovedFromUpdatedWinInstallWIM.Count -gt 10) { # It is not uncommon for 10 or so files to be removed by an update, but any more is likely an issue.
							$filePathsRemovedFromUpdatedWinInstallWimPromptChoicesDefaultOption = 0
						}

						$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
						$filePathsRemovedFromUpdatedWinInstallWimPromptResponse = $Host.UI.PromptForChoice($filePathsRemovedFromUpdatedWinInstallWimPromptCaption, $filePathsRemovedFromUpdatedWinInstallWimPromptMessage, $filePathsRemovedFromUpdatedWinInstallWimPromptChoices, $filePathsRemovedFromUpdatedWinInstallWimPromptChoicesDefaultOption)
						Write-Output ''

						if ($filePathsRemovedFromUpdatedWinInstallWimPromptResponse -eq 0) {
							break
						} else {
							Add-Content $winInstallWimFilesRemovedByUpdatesFilePath "Removed By $($installedUpdateNames -Join ' + '):"
							Add-Content $winInstallWimFilesRemovedByUpdatesFilePath $filePathsRemovedFromUpdatedWinInstallWIM
						}
					}

					Write-Output "    Finished Verifying Exported Updated Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image at $verifyingEndDate ($([math]::Round(($verifyingEndDate - $verifyingStartDate).TotalMinutes, 2)) Minutes)"

					Write-Output "`n  Calculating Checksum for $wimName.wim..."
					Set-Content "$wimOutputPath\$wimName.wim.checksum" (Get-FileHash "$wimOutputPath\$wimName.wim" -Algorithm 'SHA256').Hash
					Get-Content "$wimOutputPath\$wimName.wim.checksum"
				} else {
					Write-Host "`n    ERROR: FAILED TO DISM CLEANUP FOR OS - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
					break
				}
			} else {
				Write-Host "`n  NO UPDATE FILES (IN `"OS Updates to Install`" FOLDER) TO INSTALL" -ForegroundColor Yellow

				if (Test-Path "$systemTempDir\mountOS") {
					Write-Output "`n  Unmounting and Discarding Un-Updated Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion Install Image..."
					Dismount-WindowsImage -Path "$systemTempDir\mountOS" -Discard -ErrorAction Stop | Out-Null
					Remove-Item "$systemTempDir\mountOS" -Recurse -Force -ErrorAction Stop
					Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop
				}
			}

			$thisEndDate = Get-Date
			Write-Output "`n  Finished Windows $thisWindowsMajorVersion $thisWindowsEdition $thisWindowsFeatureVersion at $thisEndDate ($([math]::Round(($thisEndDate - $thisStartDate).TotalMinutes, 2)) Minutes)"
		}
	}
}

$endDate = Get-Date
Write-Output "`n  Finished at $endDate ($([math]::Round(($endDate - $startDate).TotalMinutes, 2)) Minutes)"
