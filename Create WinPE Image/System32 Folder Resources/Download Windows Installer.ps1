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

# THIS WAS ONLY USED DURING TESTING. LEAVING IT IN PLACE IN CASE IT COMES IN HANDY IN THE FUTURE.

# PowerShell must be installed in WinPE to run this script:
# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe

$Host.UI.RawUI.WindowTitle = 'Download Windows Installer'

if (((-not (Test-Path '\Windows\System32\startnet.cmd')) -and (-not (Test-Path '\Windows\System32\winpeshl.ini'))) -or (-not (Get-ItemProperty 'HKLM:\SYSTEM\Setup').FactoryPreInstallInProgress)) {
	Write-Host "`n  ERROR: `"Download Windows Installer`" Can Only Run In Windows Preinstallation Environment`n`n  EXITING IN 5 SECONDS..." -ForegroundColor Red
	Start-Sleep 5
	exit 1
}

Write-Output "`n  Initializing Windows Preinstallation Environment..."
# WinPE Initialization Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize#highperformance
Start-Process 'Wpeinit' -NoNewWindow -Wait
Start-Process 'powercfg' -NoNewWindow -Wait -ArgumentList '/s', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

$didDownloadInstallWindowsScript = $false

for ( ; ; ) {
	Clear-Host
	Write-Output "`n  Downloading Windows Installation Script...`n`n`n`n`n  IMPORTANT: Internet Is Required During Installation Process" # Add empty lines for PowerShell progress UI

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3

	for ($downloadAttempt = 0; $downloadAttempt -lt 5; $downloadAttempt ++) {
		try {
			$installWindowsScriptContent = Invoke-RestMethod -Uri 'https://apps.freegeek.org/windows/scripts/InstallWindows.ps1' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
			if ($installWindowsScriptContent.Contains('Expand-WindowsImage')) {
				$installWindowsScriptBlock = [ScriptBlock]::Create($installWindowsScriptContent)
				Invoke-Command $installWindowsScriptBlock -ArgumentList 'Downloaded' -ErrorAction Stop
				$didDownloadInstallWindowsScript = $true
				break
			} else {
				throw 'Invalid Windows Installation Script Contents'
			}
		} catch {
			Write-Host "`n  ERROR LOADING WINDOWS INSTALLATION SCRIPT: $_" -ForegroundColor Red
			Write-Host '  IMPORTANT: Internet Is Required During Installation Process' -ForegroundColor Red

			if ($downloadAttempt -lt 4) {
				Write-Host "  Download Windows Installation Script Attempt $($downloadAttempt + 1) of 5 - TRYING AGAIN..." -ForegroundColor Yellow
				Start-Sleep ($downloadAttempt + 1) # Sleep a little longer after each attempt.
			} else {
				Write-Host '  Failed to Download Windows Installation Script After 5 Attempts' -ForegroundColor Yellow
			}
		}
	}

	if ($didDownloadInstallWindowsScript) {
		break
	} else {
		Write-Host "`n`n  IMPORTANT: Make sure Ethernet cable is plugged securely and try again." -ForegroundColor Red
		Write-Host "`n`n  If this issue continues, please inform Free Geek I.T.`n" -ForegroundColor Red
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		Read-Host '  Press ENTER to Try Again or Press "Control + C" (or Close This Window) to Cancel and Reboot' | Out-Null
	}
}
