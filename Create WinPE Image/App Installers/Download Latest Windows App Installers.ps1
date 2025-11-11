#
# MIT License
#
# Copyright (c) 2023 Free Geek
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

Write-Output "`nDownload Latest Windows App Installers"
$Host.UI.RawUI.WindowTitle = 'Download Latest Windows App Installers'

$ProgressPreference = 'SilentlyContinue' # Not showing progress makes "Invoke-WebRequest" downloads MUCH faster: https://stackoverflow.com/a/43477248

function DownloadAppInstaller {
	Param(
		[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$AppName,
		[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InstallerExtension,
		[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$LatestVersion,
		[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DownloadURL,
		[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DownloadFolderPath
	)

	Write-Output "Latest $AppName Version: $LatestVersion"

	$downloadedVersion = 'N/A'
	$downloadedInstallers = Get-ChildItem "$DownloadFolderPath\${AppName}_*"
	if (($null -ne $downloadedInstallers) -and ($downloadedInstallers.Count -gt 0)) {
		$downloadedInstallerNameParts = $downloadedInstallers[0].BaseName.Split('_')
		if (($downloadedInstallerNameParts.Count -gt 1) -and ($downloadedInstallerNameParts[1] -Match '^\d[.\d]*$')) {
			$downloadedVersion = $downloadedInstallerNameParts[1]
		}
	}

	Write-Output "Downloaded $AppName Installer: $downloadedVersion"

	if ($LatestVersion -Match '^\d[.\d]*$') {
		$installerFileName = "${AppName}_${LatestVersion}_Installer.$InstallerExtension"
		$installerPath = "$DownloadFolderPath\$installerFileName"

		if (-not (Test-Path $installerPath)) {
			Write-Output "Downloading Latest $AppName Installer..."

			$systemTempDir = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine') # Get SYSTEM (not user) temporary directory, which should be "\Windows\Temp".
			if (-not (Test-Path $systemTempDir)) {
				$systemTempDir = "$Env:SystemRoot\Temp"
			}

			if (Test-Path "$systemTempDir\$installerFileName-download") {
				Remove-Item "$systemTempDir\$installerFileName-download" -Force -ErrorAction Stop
			}

			Invoke-WebRequest -UserAgent 'curl' -Uri $DownloadURL -OutFile "$systemTempDir\$installerFileName-download" -ErrorAction Stop
			# NOTE: If the default PowerShell user agent string is used, the VLC download URL goes to a website which starts the download as if it was accessed in the browser, but with the "curl" user agent string the Windows installers is properly downloaded.
			# Also, without changing the user agent string the Dropbox URL would redirect to the Mac version when run via "pwsh" on macOS even though "os=win" is specified in the URL.
			# Finally, changing the user agent string to "curl" doesn't break any of the other download URLs even though it isn't necessary for them.

			Remove-Item "$DownloadFolderPath\${AppName}_*" -Force -ErrorAction Stop

			Move-Item "$systemTempDir\$installerFileName-download" $installerPath -Force -ErrorAction Stop

			if (Test-Path $installerPath) {
				Write-Output "Downloaded Latest $AppName Installer"
			} else {
				Write-Output "ERROR DOWNLOADING LATEST $AppName INSTALLER"
			}
		} else {
			Write-Output "Latest $AppName Installer Already Downloaded"
		}
	} else {
		Write-Output 'INVALID Latest $AppName Version'
	}

	Write-Output '----------'
}


Write-Output "`n`nDownloading Standard App Installers..."

$installersDownloadFolderPath = "$PSScriptRoot\Standard"

if (-not (Test-Path $installersDownloadFolderPath)) {
	New-Item -ItemType 'Directory' -Path $installersDownloadFolderPath -ErrorAction Stop | Out-Null
}

Write-Output '----------'

# NOTE: In Windows 10 20H2, using the Firefox and VLC MSI installers were both causing a "default browser reset" notification, so I switched to the EXE installers for those apps which did not cause that notification.
# I re-tested the Firefox and VLC MSI installers in Windows 10 22H2 and Windows 11 22H2 and did not see the "default browser reset" notification anymore, so I've switched back to the MSI installers.
# But, this is something to keep an eye on into the future in case these MSIs need to be switched back to their EXE alternatives.

$latestFirefoxDownloadURL = 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US'
$latestFirefoxVersion = [System.Net.HttpWebRequest]::Create($latestFirefoxDownloadURL).GetResponse().ResponseUri.AbsoluteUri.Split('/')[6] # https://stackoverflow.com/a/45593554
DownloadAppInstaller -AppName 'Firefox' -InstallerExtension 'msi' -LatestVersion $latestFirefoxVersion -DownloadURL $latestFirefoxDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latestLibreOfficeVersion = ((Invoke-WebRequest -TimeoutSec 10 -Uri 'https://download.documentfoundation.org/libreoffice/stable/').Links.href | Select-String '^(\d[.\d]*)/$').Matches[-1].Groups[1].Value # Seen this one sometimes timeout after 5 seconds, so give it 10 seconds.
$latestLibreOfficeDownloadURL = "https://download.documentfoundation.org/libreoffice/stable/$latestLibreOfficeVersion/win/x86_64/LibreOffice_${latestLibreOfficeVersion}_Win_x86-64.msi"
DownloadAppInstaller -AppName 'LibreOffice' -InstallerExtension 'msi' -LatestVersion $latestLibreOfficeVersion -DownloadURL $latestLibreOfficeDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latestVLCVersion = ((Invoke-WebRequest -TimeoutSec 5 -Uri 'https://get.videolan.org/vlc/last/win64/').Links.href | Select-String '^vlc-(\d[.\d]*)-win64\.msi$').Matches[0].Groups[1].Value
if ($null -eq $latestVLCVersion) { $latestVLCVersion = '3.0.20' } # MSI for VLC 3.0.21 is being skipped: https://code.videolan.org/videolan/vlc/-/issues/28677#note_461571
$latestVLCDownloadURL = "https://get.videolan.org/vlc/$latestVLCVersion/win64/vlc-$latestVLCVersion-win64.msi"
DownloadAppInstaller -AppName 'VLC' -InstallerExtension 'msi' -LatestVersion $latestVLCVersion -DownloadURL $latestVLCDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latest7ZipVersion = ((Invoke-WebRequest -TimeoutSec 5 -Uri 'https://www.7-zip.org/download.html').Content | Select-String '<P><B>Download 7-Zip (\d[.\d]*) ').Matches[0].Groups[1].Value
$latest7ZipDownloadURL = "https://www.7-zip.org/$(((Invoke-WebRequest -TimeoutSec 5 -Uri 'https://www.7-zip.org/download.html').Links.href | Select-String '^.*-x64\.msi$').Matches[0].Value)"
DownloadAppInstaller -AppName '7-Zip' -InstallerExtension 'msi' -LatestVersion $latest7ZipVersion -DownloadURL $latest7ZipDownloadURL -DownloadFolderPath $installersDownloadFolderPath


Write-Output "`n`nDownloading Extra App Installers..."

$installersDownloadFolderPath = "$PSScriptRoot\Extra"

if (-not (Test-Path $installersDownloadFolderPath)) {
	New-Item -ItemType 'Directory' -Path $installersDownloadFolderPath -ErrorAction Stop | Out-Null
}

Write-Output '----------'

$latestChromeVersion = (Invoke-RestMethod -Uri 'https://versionhistory.googleapis.com/v1/chrome/platforms/win64/channels/stable/versions/all/releases?filter=fraction=1').releases[0].version # https://developer.chrome.com/docs/web-platform/versionhistory/examples#release & https://developer.chrome.com/docs/web-platform/versionhistory/reference#filter & https://macadmins.slack.com/archives/C013HFTFQ13/p1701811746942389?thread_ts=1701685863.377489&cid=C013HFTFQ13
$latestChromeDownloadURL = 'https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi'
# NOTE: It's important to download the offline MSI installer since the EXE installer would require internet when run, which we don't want to require for USB installations.
DownloadAppInstaller -AppName 'Google Chrome' -InstallerExtension 'msi' -LatestVersion $latestChromeVersion -DownloadURL $latestChromeDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latestZoomDownloadURL = 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'
$latestZoomVersion = [System.Net.HttpWebRequest]::Create($latestZoomDownloadURL).GetResponse().ResponseUri.AbsoluteUri.Split('/')[4] # https://stackoverflow.com/a/45593554
DownloadAppInstaller -AppName 'Zoom' -InstallerExtension 'msi' -LatestVersion $latestZoomVersion -DownloadURL $latestZoomDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latestTeamViewerVersion = ((Invoke-WebRequest -TimeoutSec 5 -Uri 'https://www.teamviewer.com/download/portal/windows/').Content | Select-String 'Current version: .+>(\d[.\d]*)<.+').Matches[0].Groups[1].Value
$latestTeamViewerDownloadURL = 'https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe'
DownloadAppInstaller -AppName 'TeamViewer' -InstallerExtension 'exe' -LatestVersion $latestTeamViewerVersion -DownloadURL $latestTeamViewerDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$latestDropboxDownloadURL = 'https://www.dropbox.com/download?full=1&os=win'
$latestDropboxVersion = ([System.Net.HttpWebRequest]::Create($latestDropboxDownloadURL).GetResponse().ResponseUri.AbsoluteUri -Split ('%20'))[1] # https://stackoverflow.com/a/45593554
DownloadAppInstaller -AppName 'Dropbox' -InstallerExtension 'exe' -LatestVersion $latestDropboxVersion -DownloadURL $latestDropboxDownloadURL -DownloadFolderPath $installersDownloadFolderPath


Write-Output "`n`nDownloading Installers for Intel Systems..."

$installersDownloadFolderPath = "$PSScriptRoot\Intel"

if (-not (Test-Path $installersDownloadFolderPath)) {
	New-Item -ItemType 'Directory' -Path $installersDownloadFolderPath -ErrorAction Stop | Out-Null
}

Write-Output '----------'

$latestIntelProcessorDiagnosticToolDownloadURL = ((Invoke-WebRequest -UserAgent 'curl' -TimeoutSec 5 -Uri 'https://www.intel.com/content/www/us/en/download/15951/intel-processor-diagnostic-tool.html').Content | Select-String 'data-href="(.+_64bit\.msi)"').Matches[0].Groups[1].Value
# NOTE: Oddly, accessing this URL with no custom "User-Agent" (using the PowerShell user agent string), or even using a generic "Mozilla/5.0" user agent string errors with an "Access Denied", but using a generic "curl" user agent string works.
$latestIntelProcessorDiagnosticToolVersion = $latestIntelProcessorDiagnosticToolDownloadURL.Split('_')[2]
DownloadAppInstaller -AppName 'Intel Processor Diagnostic Tool' -InstallerExtension 'msi' -LatestVersion $latestIntelProcessorDiagnosticToolVersion -DownloadURL $latestIntelProcessorDiagnosticToolDownloadURL -DownloadFolderPath $installersDownloadFolderPath


Write-Output "`n`nDownloading Installers for Lenovo Systems..."

$installersDownloadFolderPath = "$PSScriptRoot\Lenovo"

if (-not (Test-Path $installersDownloadFolderPath)) {
	New-Item -ItemType 'Directory' -Path $installersDownloadFolderPath -ErrorAction Stop | Out-Null
}

Write-Output '----------'

# Could not figure out how to get latest version dymanically from https://support.lenovo.com/downloads/DS012808 since it's all loaded with JavaScript.
# But luckily found that the download link is also listed on https://support.lenovo.com/us/en/solutions/ht037099 and was able to retrieve the latest version from there.
# At some point between August 9th, 2021 and September 2nd, 2021 https://support.lenovo.com/us/en/solutions/ht037099 has changed to be all loaded with JavaScript as well, but I was able to find the download link within the JavaScript source.
# NOTE: As of sometime around October 2024, these "Invoke-WebRequest" methods to the "support.lenovo.com" URLs will timeout unless we change the "User-Agent" string, and just using "curl" works fine (which I tried since using "curl" itself wasn't timing out).
# Sometime in early 2025, this URL stopped returning anything and times out even with the 'curl' User-Agent string, presumably because of intentionally blocked User-Agent strings.
# This can be worked around by setting an empty User-Agent.

$latestLenovoSystemUpdateVersion = ((Invoke-WebRequest -UserAgent '' -TimeoutSec 5 -Uri "https://support.lenovo.com$(((Invoke-WebRequest -UserAgent '' -TimeoutSec 5 -Uri 'https://support.lenovo.com/us/en/solutions/ht037099').Content | Select-String ' src="(/us/en/api/v4/contents/cdn/.+\.js)"').Matches[0].Groups[1].Value)").Links.outerHTML | Select-String 'https://download\.lenovo\.com/pccbbs/thinkvantage_en/system_update_(\d[.\d]*)\.exe').Matches[0].Groups[1].Value
$latestLenovoSystemUpdateDownloadURL = "https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_$latestLenovoSystemUpdateVersion.exe"
DownloadAppInstaller -AppName 'Lenovo System Update' -InstallerExtension 'exe' -LatestVersion $latestLenovoSystemUpdateVersion -DownloadURL $latestLenovoSystemUpdateDownloadURL -DownloadFolderPath $installersDownloadFolderPath

$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
Read-Host "`n`nDONE DOWNLOADING LATEST WINDOWS APP INSTALLERS" | Out-Null
