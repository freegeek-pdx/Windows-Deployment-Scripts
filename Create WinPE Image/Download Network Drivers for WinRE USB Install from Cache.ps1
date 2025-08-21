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

$Host.UI.RawUI.WindowTitle = 'Download Network Drivers for WinRE USB Install from Cache'

$basePath = "$HOME\Documents\Free Geek"
if (Test-Path "$HOME\Documents\Free Geek.lnk") {
	$basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Documents\Free Geek.lnk").TargetPath
}

$winREnetDriversOutputPath = "$basePath\WinRE Network Drivers for USB Install"

[xml]$smbCredentialsXML = Get-Content "$PSScriptRoot\Install Folder Resources\Scripts\smb-credentials.xml" -ErrorAction Stop

$smbServerIP = $smbCredentialsXML.smbCredentials.driversReadOnlyShare.ip
$smbShare = "\\$smbServerIP\$($smbCredentialsXML.smbCredentials.driversReadOnlyShare.shareName)"
$smbUsername = $smbCredentialsXML.smbCredentials.driversReadOnlyShare.username # (This is the user that can READ ONLY) domain MUST NOT be prefixed in username.
$smbPassword = $smbCredentialsXML.smbCredentials.driversReadOnlyShare.password

$driversCacheBasePath = "$smbShare\Drivers\Cache"

try {
	Test-Connection $smbServerIP -Count 1 -Quiet -ErrorAction Stop | Out-Null
} catch {
	Write-Host "`n  ERROR CONNECTING TO LOCAL FREE GEEK SERVER: $_" -ForegroundColor Red
	exit 1
}

Write-Host "`n  Mounting SMB Share for Drivers Cache - PLEASE WAIT, THIS MAY TAKE A MOMENT..." -NoNewline

# Try to connect to SMB Share 5 times before stopping to show error to user because sometimes it takes a few attempts, or it sometimes just fails and takes more manual reattempts before it finally works.
for ($smbMountAttempt = 0; $smbMountAttempt -lt 5; $smbMountAttempt ++) {
	try {
		# If we don't get the New-SmbMapping return value it seems to be asynchronous, which results in messages being show out of order result and also result in a failure not being detected.
		$smbMappingStatus = (New-SmbMapping -RemotePath $smbShare -UserName $smbUsername -Password $smbPassword -Persistent $false -ErrorAction Stop).Status

		if ($smbMappingStatus -eq 0) {
			Write-Host "`n`n  Successfully Mounted SMB Share for Drivers Cache" -ForegroundColor Green
		} else {
			throw "SMB Mapping Status $smbMappingStatus"
		}

		break
	} catch {
		if ($smbMountAttempt -lt 4) {
			Write-Host '.' -NoNewline
			Start-Sleep ($smbMountAttempt + 1) # Sleep a little longer after each attempt.
		} else {
			Write-Host "`n`n  ERROR MOUNTING SMB SHARE: $_" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to connect to local Free Geek SMB share `"$smbShare`"." -ForegroundColor Red

			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			Read-Host "`n`n  FAILED TO DOWNLOAD NETWORK DRIVERS FROM CACHE" | Out-Null

			exit 2
		}
	}
}

if (-not (Test-Path $winREnetDriversOutputPath)) {
	New-Item -ItemType 'Directory' -Path $winREnetDriversOutputPath -ErrorAction Stop | Out-Null
}

Write-Output "`n  Downloading WinRE Network Drivers for USB Install from Driver Cache..."

$allCachedDriverPaths = (Get-ChildItem "$driversCacheBasePath\Unique Drivers" -Directory).FullName

$netDriverFolderNames = @()

# This Driver .inf parsing code is based on code written for "Install Windows.ps1"
$thisDriverIndex = 0
$downloadedNetDriversCount = 0
foreach ($thisDriverFolderPath in $allCachedDriverPaths) {
	$thisDriverFolderName = (Split-Path $thisDriverFolderPath -Leaf)

	if ($thisDriverFolderName.Contains('.inf_amd64_')) {
		$thisDriverInfContents = Get-Content "$thisDriverFolderPath\$($thisDriverFolderName.Substring(0, $thisDriverFolderName.LastIndexOf('.'))).inf"

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
						$thisDriverSizeMB = $([math]::Round(((Get-ChildItem -Path $thisDriverFolderPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB), 2))
						if ($thisDriverSizeMB -lt 20) {
							$netDriverFolderNames += $thisDriverFolderName
							if (-not (Test-Path "$winREnetDriversOutputPath\$thisDriverFolderName")) {
								try {
									Write-Output "    $thisDriverIndex) Downloading Network Driver: $thisDriverFolderName ($thisDriverSizeMB MB)..."
									Copy-Item $thisDriverFolderPath $winREnetDriversOutputPath -Recurse -Force -ErrorAction Stop
									$downloadedNetDriversCount ++
								} catch {
									Write-Host "      ERROR DOWNLOADING NETWORK DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
								}
							} else {
								Write-Output "    $thisDriverIndex) ALREADY DOWNLOADED NETWORK DRIVER: $thisDriverFolderName ($thisDriverSizeMB MB)"
							}
						} else {
							Write-Output "    $thisDriverIndex) SKIPPING LARGE NETWORK DRIVER: $thisDriverFolderName ($thisDriverSizeMB MB)"
						}
					}

					break
				}
			}
		}
	}
}

Remove-SmbMapping -RemotePath $smbShare -Force -UpdateProfile -ErrorAction SilentlyContinue # Done with SMB Share now, so remove it.

Write-Host "`n  Downloaded $downloadedNetDriversCount Network Drivers from Cache" -ForegroundColor Green

try {
	Write-Output "`n`n  Checking Downloaded Network Drivers for Stray (No Longer Cached) Drivers to Delete..."

	$deletedStrayDownloadedNetDriversCount = 0

	Get-ChildItem "$winREnetDriversOutputPath" -ErrorAction Stop | ForEach-Object {
		if (-not $netDriverFolderNames.Contains($_.Name)) {
			$deletedStrayDownloadedNetDriversCount ++
			Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
		}
	}

	if ($deletedStrayDownloadedNetDriversCount -eq 0) {
		Write-Host "`n  Checked Downloaded Network Drivers and Found No Strays to Delete" -ForegroundColor Green
	} else {
		Write-Host "`n  Deleted $deletedStrayDownloadedNetDriversCount Strays From Downloaded Network Drivers" -ForegroundColor Green
	}
} catch {
	Write-Host "`n  ERROR DELETED STRAY DOWNLOADED NETWORK DRIVERS: $_" -ForegroundColor Red
	Write-Host "`n  ERROR: Failed to check for or delete stray downloaded network drivers." -ForegroundColor Red
}

$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
Read-Host "`n`n  DONE DOWNLOADING NETWORK DRIVERS FROM CACHE" | Out-Null
