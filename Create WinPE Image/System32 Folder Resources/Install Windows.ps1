#
# By Pico Mitchell for Free Geek
# Originally written and tested in September 2020 for Windows 10, version 2004
# Tested in November 2022 for Windows 10, version 22H2
# AND Tested in November 2022 for Windows 11, version 22H2
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

# Version: 2022.11.5-1

# PowerShell must be installed in WinPE to run this script (which will be taken care of automatically if WinPE is built with "Create WinPE Image.ps1"):
# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe

$Host.UI.RawUI.WindowTitle = 'Install Windows'

if (((-not (Test-Path '\Windows\System32\startnet.cmd')) -and (-not (Test-Path '\Windows\System32\winpeshl.ini'))) -or (-not (Get-ItemProperty 'HKLM:\SYSTEM\Setup').FactoryPreInstallInProgress)) {
	Write-Host "`n  ERROR: `"Install Windows`" Can Only Run In Windows Preinstallation Environment`n`n  EXITING IN 5 SECONDS..." -ForegroundColor Red
	Start-Sleep 5
	exit 1
}

$focusWindowFunctionTypes = Add-Type -PassThru -Name FocusWindow -MemberDefinition @'
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
'@

function FocusScriptWindow {
	# Based On: https://stackoverflow.com/a/58548853
	
	$scriptWindowHandle = (Get-Process -Id $PID).MainWindowHandle
	
	if ($scriptWindowHandle) {
		$focusWindowFunctionTypes::SetForegroundWindow($scriptWindowHandle) | Out-Null
		if ($focusWindowFunctionTypes::IsIconic($scriptWindowHandle)) {
			$focusWindowFunctionTypes::ShowWindow($scriptWindowHandle, 9) | Out-Null
		}
	}
	
	(New-Object -ComObject Wscript.Shell).AppActivate($Host.UI.RawUI.WindowTitle) | Out-Null # Also try "AppActivate" since "SetForegroundWindow" seems to maybe not work as well on Windows 11.
}

$testMode = (Test-Path '\Windows\System32\TESTING') # Use System32 folder so that test mode can be set dynamically by iPXE without needing separate WinPE images.

FocusScriptWindow

# WinPE Initialization Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize#highperformance

$requiredModulesToPreImport = @('CimCmdlets', 'Dism', 'Microsoft.PowerShell.Archive', 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility', 'SmbShare', 'Storage')

try {
	Write-Output "`n  Initializing Windows Preinstallation Environment..."

	Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

	$wpeinitExitCode = (Start-Process 'Wpeinit.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-Wpeinit-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-Wpeinit-Error.txt" -ErrorAction Stop).ExitCode
	$wpeinitError = Get-Content -Raw "$Env:TEMP\fgInstall-Wpeinit-Error.txt"

	if (($wpeinitExitCode -eq 0) -and ($null -eq $wpeinitError)) {
		# IMPORTANT: Also manually import required modules first thing (rather than letting the load dynamically when their commands are called later) so that they are always loaded before any other GUI apps.
		# If these modules are not loaded first, they may fail to load later since it seems that after loading GUI apps, resources can get used up (maybe scratch space) and cause modules (such as Dism) to fail to load when their commands are called.
		# These failures would not tend to happen if only QA Helper was run, but were more likely to happen if other apps like Disk Check PE and/or Web Browser PE were also launched during testing.
		
		if ($testMode) {
			Write-Host "`n    LOADED MODULES (SHOULD BE Microsoft.PowerShell.Management Microsoft.PowerShell.Utility):`n      $($(Get-Module).Name -Join "`n      ")" -ForegroundColor Yellow
		}

		$previousErrorActionPreference = $ErrorActionPreference
		$ErrorActionPreference = 'SilentlyContinue' # Set default ErrorAction since "Import-LocalizedData" (sub-called by "Import-Module") will error when importing "Microsoft.PowerShell.Archive", but the module itself will import properly and we just want to hide that sub-error. 

		foreach ($thisModuleToImport in $requiredModulesToPreImport) {
			Import-Module $thisModuleToImport -ErrorAction Stop # Manually setting "-ErrorAction Stop" (even with "$ErrorActionPreference = 'SilentlyContinue'") means this will still throw an error if an module actually fails to import.
		}

		$ErrorActionPreference = $previousErrorActionPreference # Set back to previous ErrorAction.

		if ($testMode) {
			Write-Host "`n    LOADED MODULES (SHOULD BE $requiredModulesToPreImport):`n      $($(Get-Module).Name -Join "`n      ")" -ForegroundColor Yellow
		}

		Write-Host "`n  Successfully Initialized Windows Preinstallation Environment" -ForegroundColor Green
	} else {
		if ($null -eq $wpeinitError) {
			$wpeinitError = Get-Content -Raw "$Env:TEMP\fgInstall-Wpeinit-Output.txt"
		}
		
		Write-Host "`n  ERROR RUNNING WPEINIT: $wpeinitError" -ForegroundColor Red
		Write-Host "`n  ERROR: Failed to initialize Windows Preinstallation Environment (Wpeinit Exit Code = $wpeinitExitCode)." -ForegroundColor Red
		
		Write-Host "`n`n  !!! THIS SHOULD NOT HAVE HAPPENED !!!`n`n  If this issue continues, please inform Free Geek I.T.`n`n  Rebooting This Computer in 30 Seconds..." -ForegroundColor Red
		Start-Sleep 30
		exit 2
	}
} catch {
	Write-Host "`n  ERROR STARTING WPEINIT: $_" -ForegroundColor Red
	Write-Host "`n  ERROR: Failed to initialize Windows Preinstallation Environment." -ForegroundColor Red
	
	Write-Host "`n`n  !!! THIS SHOULD NOT HAVE HAPPENED !!!`n`n  If this issue continues, please inform Free Geek I.T.`n`n  Rebooting This Computer in 30 Seconds..." -ForegroundColor Red
	Start-Sleep 30
	exit 3
}


$didSetPowerPlan = $false

try {
	Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

	# "Get-CimInstance Win32_PowerPlan -Namespace ROOT\CIMV2\power" is not available in WinPE.
	$powercfgGetactiveschemeExitCode = (Start-Process 'powercfg.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-powercfg-getactivescheme-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-powercfg-getactivescheme-Error.txt" -ArgumentList '/getactivescheme' -ErrorAction Stop).ExitCode
	$powercfgGetactiveschemeOutput = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-getactivescheme-Output.txt"
	$powercfgGetactiveschemeError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-getactivescheme-Error.txt"

	if (($powercfgGetactiveschemeExitCode -eq 0) -and ($null -eq $powercfgGetactiveschemeError) -and ($null -ne $powercfgGetactiveschemeOutput) -and (-not $powercfgGetactiveschemeOutput.Contains('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'))) {
		Write-Output "`n`n  Setting High Performance Power Plan and Disabling Screen Sleep..."

		$powercfgSetactiveExitCode = (Start-Process 'powercfg.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-powercfg-setactive-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-powercfg-setactive-Error.txt" -ArgumentList '/setactive', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -ErrorAction Stop).ExitCode
		$powercfgSetactiveError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-setactive-Error.txt"

		if (($powercfgSetactiveExitCode -eq 0) -and ($null -eq $powercfgSetactiveError)) {
			$powercfgChangeAcExitCode = (Start-Process 'powercfg.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-powercfg-change-ac-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-powercfg-change-ac-Error.txt" -ArgumentList '/change', 'monitor-timeout-ac', '0' -ErrorAction Stop).ExitCode
			$powercfgChangeAcError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-change-ac-Error.txt"

			if (($powercfgChangeAcExitCode -eq 0) -and ($null -eq $powercfgChangeAcError)) {
				$powercfgChangeDcExitCode = (Start-Process 'powercfg.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-powercfg-change-dc-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-powercfg-change-dc-Error.txt" -ArgumentList '/change', 'monitor-timeout-dc', '0' -ErrorAction Stop).ExitCode
				$powercfgChangeDcError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-change-dc-Error.txt"
			
				if (($powercfgChangeDcExitCode -eq 0) -and ($null -eq $powercfgChangeDcError)) {
					Write-Host "`n  Successfully Set High Performance Power Plan and Disabled Screen Sleep" -ForegroundColor Green
					
					$didSetPowerPlan = $true
				} else {
					if ($null -eq $powercfgChangeDcError) {
						$powercfgChangeDcError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-change-dc-Output.txt"
					}

					Write-Host "`n  ERROR CHANGING DC POWERCFG: $powercfgChangeDcError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to disable screen sleep on DC power (powercfg Exit Code = $powercfgChangeDcExitCode)." -ForegroundColor Red
				}
			} else {
				if ($null -eq $powercfgChangeAcError) {
					$powercfgChangeAcError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-change-ac-Output.txt"
				}
				
				Write-Host "`n  ERROR CHANGING AC POWERCFG: $powercfgChangeAcError" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to disable screen sleep on AC power (powercfg Exit Code = $powercfgChangeAcExitCode)." -ForegroundColor Red
			}
		} else {
			if ($null -eq $powercfgSetactiveError) {
				$powercfgSetactiveError = Get-Content -Raw "$Env:TEMP\fgInstall-powercfg-setactive-Output.txt"
			}

			Write-Host "`n  ERROR SETTING POWERCFG: $powercfgSetactiveError" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to set High Performance power plan (powercfg Exit Code = $powercfgSetactiveExitCode)." -ForegroundColor Red
		}
	} else {
		$didSetPowerPlan = $true
	}
} catch {
	Write-Host "`n  ERROR STARTING POWERCFG: $_" -ForegroundColor Red
}

if (-not $didSetPowerPlan) {
	Write-Host "`n  Computer or Screen May Sleep During Installation - CONTINUING ANYWAY" -ForegroundColor Yellow
	Start-Sleep 3
}


if ((Test-Path '\Install\Scripts\Wi-Fi Profiles\') -and (Test-Path '\sources\recovery\RecEnv.exe')) {
	# Wi-Fi *IS NOT* supported in a regular WinPE image, but we are now using a WinRE-based image, which can support Wi-Fi when the necessary drivers are pre-installed: https://msendpointmgr.com/2018/03/06/build-a-winpe-with-wireless-support/

	# Wi-Fi Profiles must be exported with: netsh wlan export profile name="Name" key=clear folder="C:\Path\"
	# The "key=clear" argument is very important because it seems that while the profile with an encrypted password (key) can be successfully imported on another computer,
	# the encrypted password will not actually work and the computer will not connect to the Wi-Fi network.

	$wiFiProfileFiles = Get-ChildItem '\Install\Scripts\Wi-Fi Profiles\*' -Include '*.xml' -ErrorAction SilentlyContinue

	if (($null -ne $wiFiProfileFiles) -and ($wiFiProfileFiles.Count -gt 0)) {
		Write-Output "`n`n  Adding Wi-Fi Network Profiles...`n"

		try {
			Start-Service 'wlansvc' -ErrorAction Stop # Make sure Wireless AutoConfig Service (wlansvc) is running before trying to add profiles since they will fail if it's not started yet.
		} catch {
			Write-Host "    Error Starting Wireless AutoConfig Service (wlansvc): $_`n" -ForegroundColor Yellow
		}

		foreach ($thisWiFiProfileFile in $wiFiProfileFiles) {
			$thisWiFiProfileName = $thisWiFiProfileFile.BaseName
			if ($thisWiFiProfileName.StartsWith('Wi-Fi-')) {
				$thisWiFiProfileName = $thisWiFiProfileName.Substring(6)
			}

			Write-Host "    Adding Wi-Fi Network Profile: $thisWiFiProfileName..." -NoNewline
			
			Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue
			
			try {
				$netshWlanAddProfileExitCode = (Start-Process 'netsh.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-netsh-wlan-add-profile-$thisWiFiProfileName-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-netsh-wlan-add-profile-$thisWiFiProfileName-Error.txt" -ArgumentList 'wlan', 'add', 'profile', "filename=`"$($thisWiFiProfileFile.FullName)`"" -ErrorAction Stop).ExitCode
				$netshWlanAddProfileError = Get-Content -Raw "$Env:TEMP\fgInstall-netsh-wlan-add-profile-$thisWiFiProfileName-Error.txt"
				
				if (($netshWlanAddProfileExitCode -eq 0) -and ($null -eq $netshWlanAddProfileError)) {
					Write-Host ' ADDED' -ForegroundColor Green
				} else {
					Write-Host ' FAILED' -NoNewline -ForegroundColor Red
					Write-Host ' (CONTINUING ANYWAY)' -ForegroundColor Yellow

					if ($null -eq $netshWlanAddProfileError) {
						$netshWlanAddProfileError = Get-Content -Raw "$Env:TEMP\fgInstall-netsh-wlan-add-profile-$thisWiFiProfileName-Output.txt"
					}

					if ($null -ne $netshWlanAddProfileError) {
						$netshWlanAddProfileError = $netshWlanAddProfileError.Trim()
					}

					Write-Host "      ERROR ADDING PROFILE (Code $netshWlanAddProfileExitCode): $netshWlanAddProfileError" -ForegroundColor Red
				}
			} catch {
				Write-Host ' FAILED' -NoNewline -ForegroundColor Red
				Write-Host ' (CONTINUING ANYWAY)' -ForegroundColor Yellow
				Write-Host "      ERROR STARTING NETSH: $_" -ForegroundColor Red
			}
		}

		Write-Host "`n  Finished Adding Wi-Fi Network Profiles" -ForegroundColor Green
	}
}


$didSyncSystemTime = $false

Write-Output "`n`n  Syncing System Time..."
# W32tm.exe is not included in WinPE by default, but "Create WinPE Image.ps1" will install it and then time can be synced in WinPE (to be sure QA Helper can be installed since if time is far off HTTPS will fail).

if (Test-Path '\Windows\System32\W32tm.exe') {
	try {
		Start-Service 'W32Time' -ErrorAction Stop # This DOES work in WinPE by default even though W32tm.exe is not included by default.

		Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

		$w32tmResyncExitCode = (Start-Process 'W32tm' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-W32tm-resync-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-W32tm-resync-Error.txt" -ArgumentList '/resync', '/force' -ErrorAction Stop).ExitCode
		$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgInstall-W32tm-resync-Error.txt"
		
		if (($w32tmResyncExitCode -eq 0) -and ($null -eq $w32tmResyncError)) {
			Write-Host "`n  Successfully Synced System Time" -ForegroundColor Green

			$didSyncSystemTime = $true
		} else {
			if ($null -eq $w32tmResyncError) {
				$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgInstall-W32tm-resync-Output.txt"
			}

			Write-Host "`n  ERROR SYNCING SYSTEM TIME: $w32tmResyncError" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to sync system time (W32tm Exit Code = $w32tmResyncExitCode)." -ForegroundColor Red
		}
	} catch {
		Write-Host "`n  ERROR STARTING TIME SERVICE OR W32TM: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: Failed to start system time service." -ForegroundColor Red
	}
} else {
	Write-Host "`n  ERROR: W32tm.exe is not installed into WinPE." -ForegroundColor Red
}

if (-not $didSyncSystemTime) {
	Write-Host "`n  System Time May Be Incorrect - CONTINUING ANYWAY" -ForegroundColor Yellow
}

$didDetectExistingDPK = $false

Write-Output "`n`n  Checking for Existing Digital Product Key (DPK) in SMBIOS..."

if (Test-Path '\Install\DPK\oa3tool.exe') {
	try {
		Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

		$oa3toolValidateExitCode = (Start-Process '\Install\DPK\oa3tool.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-oa3tool-Validate-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-oa3tool-Validate-Error.txt" -ArgumentList '/Validate' -ErrorAction Stop).ExitCode
		$oa3toolValidateError = Get-Content -Raw "$Env:TEMP\fgInstall-oa3tool-Validate-Error.txt"

		if (($oa3toolValidateExitCode -eq 0) -and ($null -eq $oa3toolValidateError)) {
			$oa3toolValidateOutput = Get-Content -Raw "$Env:TEMP\fgInstall-oa3tool-Validate-Output.txt"

			if ($oa3toolValidateOutput.Contains('ACPI MSDM table payload:') -and $oa3toolValidateOutput.Contains('Partial Product Key:')) {
				Write-Host "`n  Successfully Detected DPK in SMBIOS" -ForegroundColor Green

				$didDetectExistingDPK = $true
			}
		} else {
			if ($null -eq $oa3toolValidateError) {
				$oa3toolValidateError = Get-Content -Raw "$Env:TEMP\fgInstall-oa3tool-Validate-Output.txt"
			}

			if (!$oa3toolValidateError.Contains('failed to find the ACPI MSDM table')) { # Only the yellow "Failed to Detect DPK in SMBIOS" message below will be displayed for this expected failure state.
				Write-Host "`n  ERROR RUNNING OA3TOOL VALIDATE: $oa3toolValidateError" -ForegroundColor Red
				Write-Host "`n  ERROR: OEM Activation Tool 3.0 (oa3tool.exe) validation failed (oa3tool Exit Code = $oa3toolValidateExitCode)." -ForegroundColor Red
			}
		}
	} catch {
		Write-Host "`n  ERROR STARTING OA3TOOL: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: Failed to start OEM Activation Tool 3.0 (oa3tool.exe)." -ForegroundColor Red
	}
} else {
	Write-Host "`n  ERROR: OEM Activation Tool 3.0 (oa3tool.exe) was not found at `"\Install\DPK\oa3tool.exe`"." -ForegroundColor Red
}

if (-not $didDetectExistingDPK) {
	Write-Host "`n  Failed to Detect DPK in SMBIOS - CONTINUING ANYWAY - MUST MANUALLY CONFIRM COA OR GML" -ForegroundColor Yellow
}

Start-Sleep 3

if (-not $didDetectExistingDPK) {
	$lastConfirmExistingWindowsError = ''

	for ( ; ; ) {
		Clear-Host
		Write-Host "`n  Windows can only be installed and licensed with a Refurbished DPK on computers that originally shipped with Windows.`n  You must manually verify that a COA or GML sticker is on this computer since a DPK was not detected in SMBIOS." -ForegroundColor Yellow

		Write-Output "`n`n  Does this computer have a Certificate of Authenticity (COA) or Genuine Microsoft Label (GML) sticker`n  for any of the following Windows versions anywhere on its case?"
		Write-Host "`n  Windows XP, Windows Vista, Windows 7 (Starter, Home Basic, Home Premium, Pro, or Ultimate),`n  Windows 8 or 8.1 (Home or Pro), Windows 10 (Home or Pro), or Windows 11 (Home or Pro)`n" -ForegroundColor Blue

		if ($lastConfirmExistingWindowsError -ne '') {
			Write-Host $lastConfirmExistingWindowsError -ForegroundColor Red
		}

		Write-Host "`n    Y: Yes, Continue Installing Windows" -ForegroundColor Cyan
		Write-Host "`n    N: No, Cancel Windows Installation and Shut Down This Computer" -ForegroundColor Cyan

		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		$actionChoice = Read-Host "`n`n  Enter the Letter of Your Answer"

		if ($actionChoice.ToUpper() -eq 'Y') {
			break
		} elseif ($actionChoice.ToUpper() -eq 'N') {
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$confirmShutDown = Read-Host "`n  Enter `"N`" Again to Confirm Canceling Windows Installation and Shutting Down This Computer"

			if ($confirmShutDown.ToUpper() -eq 'N') {
				Clear-Host
				Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Shutting Down This Computer in 5 Seconds..." -ForegroundColor Yellow
				Start-Sleep 5
				Stop-Computer
				Start-Sleep 60 # Sleep for 1 minute after executing "Stop-Computer" because if the script exits before "Stop-Computer" shut's down, the computer will be rebooted instead.
				
				exit 4
			} else {
				$lastConfirmExistingWindowsError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Shutting Down This Computer - CHOOSE AGAIN`n"
			}
		} else {
			if ($actionChoice) {
				$lastConfirmExistingWindowsError = "`n    ERROR: `"$actionChoice`" Is Not a Valid Choice - CHOOSE AGAIN`n"
			} else {
				$lastConfirmExistingWindowsError = ''
			}
		}
	}
}

if ($testMode) {
	Start-Process 'cmd.exe' -WindowStyle Minimized -ErrorAction SilentlyContinue
}

$installDriveID = $null
$installDriveName = $null

for ( ; ; ) {
	Clear-Host
	Write-Output "`n  Preparing to Install QA Helper...`n`n`n`n`n" # Add empty lines for PowerShell progress UI

	$qaHelperInstallMode = 'update' # Use update mode to always re-download the latest version when re-opening QA Helper.

	if ($testMode) {
		$qaHelperInstallMode = 'test'
	}

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3

	for ($downloadAttempt = 0; $downloadAttempt -lt 5; $downloadAttempt ++) {
		try {
			$actuallyInstallScriptContent = Invoke-RestMethod -Uri 'https://apps.freegeek.org/qa-helper/download/actually-install-qa-helper.ps1' -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
			if ($actuallyInstallScriptContent.Contains('qa-helper')) {
				$actuallyInstallScriptBlock = [ScriptBlock]::Create($actuallyInstallScriptContent)
				Invoke-Command $actuallyInstallScriptBlock -ArgumentList $qaHelperInstallMode -ErrorAction Stop
				break
			} else {
				throw 'Invalid Installer Script Contents'
			}
		} catch {
			Write-Host "`n  ERROR LOADING QA HELPER INSTALLER: $_" -ForegroundColor Red
			Write-Host '  IMPORTANT: Internet Is Required to Load QA Helper' -ForegroundColor Red
			
			if ($downloadAttempt -lt 4) {
				Write-Host "  Load Installer Attempt $($downloadAttempt + 1) of 5 - TRYING AGAIN..." -ForegroundColor Yellow
				Start-Sleep ($downloadAttempt + 1) # Sleep a little longer after each attempt.
			} else {
				Write-Host '  Failed to Load QA Helper Installer After 5 Attempts' -ForegroundColor Yellow
			}
		}
	}

	$javaPath = '\Install\QA Helper\java-jre\bin\javaw.exe'

	if ($testMode) {
		$javaPath = '\Install\QA Helper\java-jre\bin\java.exe' # This java executable with log output when in test mode.
	}

	if ((Test-Path $javaPath) -and (Test-Path '\Install\QA Helper\QA_Helper.jar')) {
		Write-Output "`n`n  Launching QA Helper - PLEASE WAIT, THIS MAY TAKE A MOMENT..."

		# To be able to run Java in WinPE, a handful of missing DLLs must be added into WinPE.
		# Create the WinPE image with the "SetupWinPE.ps1" script to deal with this automatically.
		# See "SetupWinPE.ps1" source for info about using Process Explorer to find missing DLLs for an executable (such as javaw.exe).
		
		Start-Process $javaPath -NoNewWindow -ArgumentList '-jar', '"\Install\QA Helper\QA_Helper.jar"' -ErrorAction SilentlyContinue

		# Don't use "-Wait" in Start-Process because there's like a 5 second or so lag before continuing after closing the QA Helper window.
		# Instead, manually detect if the QA Helper window is visible and continue after it's closed for a quicker response time.

		# Since QA Helper's Loading window may take a moment to appear, wait up to 60 seconds for the Loading window before continuing anyway.	
		for ($waitForWindowAttempt = 0; $waitForWindowAttempt -lt 60; $waitForWindowAttempt ++) {
			if (Get-Process | Where-Object { $_.MainWindowTitle.Contains('QA Helper') }) {
				Clear-Host
				Write-Host "`n  Close QA Helper (or Click `"Install OS`") to Continue and Choose Drive to Install Windows Onto..." -ForegroundColor Cyan
				break
			} else {
				Start-Sleep 1
			}
		}

		while (Get-Process | Where-Object { $_.MainWindowTitle.Contains('QA Helper') }) {
			Start-Sleep 1
		}
	} else {
		Write-Host "`n  ERROR: Failed to install QA Helper." -ForegroundColor Red
		Write-Host "`n`n  CONTINUING TO CHOOSE DRIVE TO INSTALL WINDOWS ONTO IN 3 SECONDS..." -ForegroundColor Yellow
		Start-Sleep 3
	}

	$lastChooseInstallDriveError = ''

	for ( ; ; ) {
		Clear-Host
		Write-Output "`n  Choose Drive to Install Windows Onto (or Other Action)...`n"
		
		if ($lastChooseInstallDriveError -ne '') {
			Write-Host $lastChooseInstallDriveError -ForegroundColor Red
		}

		$installDriveOptions = Get-PhysicalDisk | Where-Object { ($_.BusType -eq 'SATA') -or ($_.BusType -eq 'ATA') -or ($_.BusType -eq 'NVMe') -or ($_.BusType -eq 'RAID') } | Sort-Object -Property 'DeviceId'
		
		if ($installDriveOptions.DeviceId.Count -gt 0) {
			$installDriveOptions | ForEach-Object {
				$thisDriveMediaType = $_.MediaType

				if ($thisDriveMediaType -eq 'Unspecified') {
					$thisDriveMediaType = 'HD' # Just show as "HD" (not "HDD" or "SSD") if MediaType is "Unspecified"
				}

				Write-Host "`n    $($_.DeviceId): ERASE and INSTALL Windows Onto $([math]::Round($_.Size / 1000 / 1000 / 1000)) GB $($_.BusType) $thisDriveMediaType `"$($_.Model)`"" -ForegroundColor Cyan
			}
		} else {
			Write-Host "`n    No Internal Drives Detected`n" -ForegroundColor Yellow
		}
		
		Write-Host "`n    H: Re-Open QA Helper" -ForegroundColor Cyan
		Write-Host "`n    C: Cancel Windows Installation and Reboot This Computer" -ForegroundColor Cyan
		Write-Host "`n    X: Cancel Windows Installation and Shut Down This Computer" -ForegroundColor Cyan

		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		$actionChoice = Read-Host "`n`n  Enter the Number or Letter of an Action to Perform"

		if ($actionChoice.ToUpper() -eq 'H') {
			break
		} elseif ($actionChoice.ToUpper() -eq 'C') {
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$confirmQuit = Read-Host "`n  Enter `"C`" Again to Confirm Canceling Windows Installation and Rebooting This Computer"

			if ($confirmQuit.ToUpper() -eq 'C') {
				Clear-Host
				Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Rebooting This Computer in 5 Seconds..." -ForegroundColor Yellow
				Start-Sleep 5

				exit 5
			} else {
				$lastChooseInstallDriveError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Rebooting This Computer - CHOOSE AGAIN`n"
			}
		} elseif ($actionChoice.ToUpper() -eq 'X') {
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$confirmShutDown = Read-Host "`n  Enter `"X`" Again to Confirm Canceling Windows Installation and Shutting Down This Computer"

			if ($confirmShutDown.ToUpper() -eq 'X') {
				Clear-Host
				Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Shutting Down This Computer in 5 Seconds..." -ForegroundColor Yellow
				Start-Sleep 5
				Stop-Computer
				Start-Sleep 60 # Sleep for 1 minute after executing "Stop-Computer" because if the script exits before "Stop-Computer" shut's down, the computer will be rebooted instead.
						
				exit 6
			} else {
				$lastChooseInstallDriveError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Shutting Down This Computer - CHOOSE AGAIN`n"
			}
		} else {
			$possibleInstallDriveID = $actionChoice -Replace '\D+', ''
			
			if ($possibleInstallDrive = $installDriveOptions | Where-Object DeviceId -eq $possibleInstallDriveID) {
				$possibleInstallDriveName = "$([math]::Round($possibleInstallDrive.Size / 1000 / 1000 / 1000)) GB $($possibleInstallDrive.BusType) $($possibleInstallDrive.MediaType) `"$($possibleInstallDrive.Model)`""
				
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$confirmDriveID = Read-Host "`n  Enter `"$possibleInstallDriveID`" Again to Confirm COMPLETELY ERASING and INSTALLING Windows`n  Onto $possibleInstallDriveName"
				$confirmDriveID = $confirmDriveID -Replace '\D+', ''
				
				if ($possibleInstallDriveID -eq $confirmDriveID) {
					$installDriveID = $possibleInstallDriveID
					$installDriveName = $possibleInstallDriveName
					
					break
				} else {
					$lastChooseInstallDriveError = "`n    ERROR: Did Not Confirm Drive ID `"$possibleInstallDriveID`" - CHOOSE AGAIN`n"
				}
			} else {
				if ($actionChoice) {
					$lastChooseInstallDriveError = "`n    ERROR: `"$actionChoice`" Is Not a Valid Choice - CHOOSE AGAIN`n"
				} else {
					$lastChooseInstallDriveError = ''
				}
			}
		}
	}

	if (($null -ne $installDriveID) -and ($null -ne $installDriveName)) {
		break
	}
}


if (($null -eq $installDriveID) -or ($null -eq $installDriveName)) {
	Write-Host "`n  ERROR: No Install Drive Selected`n`n  !!! THIS SHOULD NOT HAVE HAPPENED !!!`n`n  Rebooting This Computer in 15 Seconds..." -ForegroundColor Red
	Start-Sleep 15
} else {
	$isBaseInstall = $false

	if ($testMode) {
		$lastChooseInstallTypeError = ''

		for ( ; ; ) {
			Clear-Host
			Write-Output "`n  Choose Windows Installation Type for $installDriveName...`n"

			if ($lastChooseInstallTypeError -ne '') {
				Write-Host $lastChooseInstallTypeError -ForegroundColor Red
			}

			Write-Host "`n    S: Standard Install with Apps and Testing (Boot Into Audit Mode After Install)" -ForegroundColor Cyan
			Write-Host "`n    B: Base Install With NO Apps and NO Testing (Boot Into Windows Setup After Install)" -ForegroundColor Cyan
			Write-Host "`n    C: Cancel Windows Installation and Reboot This Computer" -ForegroundColor Cyan
			Write-Host "`n    X: Cancel Windows Installation and Shut Down This Computer" -ForegroundColor Cyan

			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$installationTypeChoice = Read-Host "`n`n  Enter the Letter for Desired Windows Installation Type"

			if ($installationTypeChoice.ToUpper() -eq 'S') {
				Write-Host "`n  Standard Windows Installation Will Be Performed..." -ForegroundColor Green
				
				Start-Sleep 2
				break
			} elseif ($installationTypeChoice.ToUpper() -eq 'B') {
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$confirmBaseInstall = Read-Host "`n  Enter `"B`" Again to Confirm Performing Base Windows Installation With NO Apps and NO Testing"

				if ($confirmBaseInstall.ToUpper() -eq 'B') {
					Write-Host "`n  Base Windows Installation Will Be Performed..." -ForegroundColor Green

					$isBaseInstall = $true

					Start-Sleep 2
					break
				} else {
					$lastChooseInstallTypeError = "`n    ERROR: Did Not Confirm Performing Base Windows Installation - CHOOSE AGAIN`n"
				}
			} elseif ($installationTypeChoice.ToUpper() -eq 'C') {
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$confirmQuit = Read-Host "`n  Enter `"C`" Again to Confirm Canceling Windows Installation and Rebooting This Computer"

				if ($confirmQuit.ToUpper() -eq 'C') {
					Clear-Host
					Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Rebooting This Computer in 5 Seconds..." -ForegroundColor Yellow
					Start-Sleep 5

					exit 7
				} else {
					$lastChooseInstallTypeError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Rebooting This Computer - CHOOSE AGAIN`n"
				}
			} elseif ($installationTypeChoice.ToUpper() -eq 'X') {
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$confirmShutDown = Read-Host "`n  Enter `"X`" Again to Confirm Canceling Windows Installation and Shutting Down This Computer"
	
				if ($confirmShutDown.ToUpper() -eq 'X') {
					Clear-Host
					Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Shutting Down This Computer in 5 Seconds..." -ForegroundColor Yellow
					Start-Sleep 5
					Stop-Computer
					Start-Sleep 60 # Sleep for 1 minute after executing "Stop-Computer" because if the script exits before "Stop-Computer" shut's down, the computer will be rebooted instead.

					exit 8
				} else {
					$lastChooseInstallTypeError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Shutting Down This Computer - CHOOSE AGAIN`n"
				}
			} else {
				if ($installationTypeChoice) {
					$lastChooseInstallTypeError = "`n    ERROR: `"$installationTypeChoice`" Is Not a Valid Choice - CHOOSE AGAIN`n"
				} else {
					$lastChooseInstallTypeError = ''
				}
			}
		}
	}

	# SMB Shares in WinPE Notes:
	# To connect to a guest/anonymous SMB Share in WinPE, a dummy username and password must be supplied or the connection will always fail. This is only an issue in WinPE, not in a full Windows installation.
	# Although, even with a dummy username and password, WinPE seemed to fail more often when connecting to a guest/anonymous SMB Share, so using a password protected SMB Share in WinPE is recommended.
	
	[xml]$smbCredentialsXML = $null

	try {
		[xml]$smbCredentialsXML = Get-Content '\Install\Scripts\smb-credentials.xml' -ErrorAction Stop

		if ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.ip) {
			throw 'NO RESOURCES SHARE IP'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.shareName) {
			throw 'NO RESOURCES SHARE NAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.username) {
			throw 'NO RESOURCES SHARE USERNAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.password) {
			throw 'NO RESOURCES SHARE PASSWORD'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadOnlyShare.ip) {
			throw 'NO DRIVERS SHARE IP'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadOnlyShare.shareName) {
			throw 'NO DRIVERS SHARE NAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadOnlyShare.username) {
			throw 'NO DRIVERS SHARE USERNAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadOnlyShare.password) {
			throw 'NO DRIVERS SHARE PASSWORD'
		}
	} catch {
		Write-Host "`n`n  ERROR RETRIEVING SMB CREDENTIALS: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: REQUIRED `"smb-credentials.xml`" DOES NOT EXISTS OR HAS INVALID CONTENTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		Read-Host '  Press ENTER to Exit' | Out-Null

		exit 9
	}

	$smbServerIP = $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.ip
	$smbShare = "\\$smbServerIP\$($smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.shareName)"
	$smbUsername = "$smbServerIP\$($smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.username)" # Domain must be prefixed in any username.
	$smbPassword = $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.password

	$smbWdsServerIP = $smbCredentialsXML.smbCredentials.driversReadOnlyShare.ip
	$smbWdsShare = "\\$smbWdsServerIP\$($smbCredentialsXML.smbCredentials.driversReadOnlyShare.shareName)"
	$smbWdsUsername = "user\$($smbCredentialsXML.smbCredentials.driversReadOnlyShare.username)" # (This is the user that can READ ONLY) For some strange reason, in WinPE the username must be prefixed, but with anything EXCEPT the server name.
	$smbWdsPassword = $smbCredentialsXML.smbCredentials.driversReadOnlyShare.password
	
	$driversCacheBasePath = "$smbWdsShare\Drivers\Cache"
	$driverPacksBasePath = "$smbWdsShare\Drivers\Packs"
	
	$osImagesSMBbasePath = "$smbShare\windows-resources\os-images"
	$setupResourcesSMBbasePath = "$smbShare\windows-resources\setup-resources"
	
	$osImagesPath = "$osImagesSMBbasePath\production"
	$setupResourcesPath = "$setupResourcesSMBbasePath\production"
	
	# When in test mode (and is not USB install), $osImagesSMBtestingPath will be checked first and $setupResourcesPath will be fallen back on if no test image is found.
	# This way, we do not need to always store 2 duplicate os image files when no test image is needed. 
	$osImagesSMBtestingPath = "$osImagesSMBbasePath\testing"

	# When in test mode (and is not USB install), all $setupResourcesPath files will be installed first and then anything in $setupResourcesSMBtestingPath will add to or overwrite those file.
	# This way, only modified or added files need to exist in $setupResourcesSMBtestingPath rather than a full duplicate of all required files.
	$setupResourcesSMBtestingPath = "$setupResourcesSMBbasePath\testing"
	
	$didInstallWindowsImage = $false # Keep track of if Windows Image was successfully installed in a previous loop to know whether the drive needs to be reformatted and the install re-attempted.
	$didInstallDrivers = $false # Keep track of if drivers were successfully installed in a previous loop to not unnecessarily reinstall them.

	$didCreateRecoveryPartition = $false # Keep track of if Recovery was successfully created and setup in a previous
	$didSetUpRecovery = $false # loop to not unnecessarily do it again (which seems to fail on subsequent attempts).

	$biosOrUEFI = $null

	for ( ; ; ) {
		Clear-Host
		FocusScriptWindow

		if ($didInstallWindowsImage) {
			Write-Output "`n  Preparing to Finish Windows Installation On $installDriveName..."
		} else {
			Write-Output "`n  Preparing to Install Windows Onto $installDriveName..."
		}

		$osImagesUSBpath = $null
		$setupResourcesUSBpath = $null
		# Check all removable drives for "windows-resources" folder (a better version of https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-identify-drive-letters)
		# Do these checks within the loop because it seems that sometimes the USB isn't mounted on boot and needs to be unplugged and replugged and the technician needs to be able to try again.
		$removableDrives = Get-Volume | Where-Object DriveType -eq Removable
		foreach ($thisRemovableDrive in $removableDrives) {
			$thisPossibleOSimagesUSBpath = "$($thisRemovableDrive.DriveLetter):\windows-resources\os-images"
			$thisPossibleSetupResourcesUSBpath = "$($thisRemovableDrive.DriveLetter):\windows-resources\setup-resources"

			if ((Test-Path $thisPossibleOSimagesUSBpath) -and (Test-Path $thisPossibleSetupResourcesUSBpath) -and ((Get-ChildItem "$thisPossibleOSimagesUSBpath\*" -Include 'Windows-10-*.wim', 'Windows-10-*+1.swm').Count -gt 0)) {
				$osImagesUSBpath = $thisPossibleOSimagesUSBpath
				$setupResourcesUSBpath = $thisPossibleSetupResourcesUSBpath

				break
			}
		}

		$isUSBinstall = $false # Will set to USB install mode if fails to connect to $smbServerIP AND both $osImagesUSBpath and $setupResourcesUSBpath are not null.

		$lastTaskSucceeded = $true

		$didConnectToServer = $false

		try {
			$didConnectToServer = (Test-Connection $smbServerIP -Count 1 -Quiet -ErrorAction Stop)
		} catch {
			Write-Host "`n  ERROR CONNECTING TO LOCAL FREE GEEK SERVER: $_" -ForegroundColor Red
		}

		if ($didConnectToServer) {
			Write-Host "`n  Successfully Connected to Local Free Geek Server" -ForegroundColor Green
		} elseif (($null -ne $osImagesUSBpath) -and ($null -ne $setupResourcesUSBpath)) {
			Write-Host "`n  Installing Windows via USB" -NoNewline -ForegroundColor Green
			Write-Host " (Local Free Geek Server Unavailable)" -ForegroundColor Yellow

			$osImagesPath = $osImagesUSBpath
			$setupResourcesPath = $setupResourcesUSBpath

			$isUSBinstall = $true
		} else {
			Write-Host "`n  ERROR: Failed to connect to local Free Geek server `"$smbServerIP`"." -ForegroundColor Red

			$lastTaskSucceeded = $false
		}

		if ($lastTaskSucceeded -and (-not $isUSBinstall)) {
			Write-Host "`n`n  Mounting SMB Share for Windows Installation Image - PLEASE WAIT, THIS MAY TAKE A MOMENT..." -NoNewline
			
			# Try to connect to SMB Share 5 times before stopping to show error to user because sometimes it takes a few attempts, or it sometimes just fails and takes more manual reattempts before it finally works.
			# These failures seemed to happen more often when using a guest/anonymous SMS Share in WinPE. I think WinPE just has issues with guest/anonymous SMB Shares, so we're using a password protected one instead.
			for ($smbMountAttempt = 0; $smbMountAttempt -lt 5; $smbMountAttempt ++) {
				try {
					# If we don't get the New-SmbMapping return value it seems to be asynchronous, which results in messages being show out of order result and also result in a failure not being detected.
					$smbMappingStatus = (New-SmbMapping -RemotePath $smbShare -UserName $smbUsername -Password $smbPassword -Persistent $false -ErrorAction Stop).Status
					$smbWdsMappingStatus = (New-SmbMapping -RemotePath $smbWdsShare -UserName $smbWdsUsername -Password $smbWdsPassword -Persistent $false -ErrorAction Stop).Status
					
					if (($smbMappingStatus -eq 0) -and ($smbWdsMappingStatus -eq 0)) {
						Write-Host "`n`n  Successfully Mounted SMB Share for Windows Installation Image" -ForegroundColor Green
					} else {
						throw "SMB Mapping Status $smbMappingStatus + $smbWdsMappingStatus"
					}

					break
				} catch {
					if ($smbMountAttempt -lt 4) {
						Write-Host '.' -NoNewline
						Start-Sleep ($smbMountAttempt + 1) # Sleep a little longer after each attempt.
					} else {
						Write-Host "`n`n  ERROR MOUNTING SMB SHARE: $_" -ForegroundColor Red
						Write-Host "`n  ERROR: Failed to connect to local Free Geek SMB share `"$smbShare`" or `"$smbWdsShare`"." -ForegroundColor Red
						
						$lastTaskSucceeded = $false
					}
				}
			}
		}

		if (-not $lastTaskSucceeded) {
			Write-Host "`n`n  IMPORTANT: Make sure Ethernet cable is plugged securely and try again." -ForegroundColor Red
			Write-Host "`n  ALSO IMPORTANT: If you are doing a USB install, unplug and re-plug the USB drive and try again." -ForegroundColor Yellow
		}
		
		if (-not $didInstallWindowsImage) {
			$latestWimPath = $null
			$latestWimDisplayName = $null

			if ($lastTaskSucceeded) {
				Write-Output "`n`n  Locating Latest Windows 10 Installation Image..."

				$latestWin10wim = $null

				if ($testMode -and (-not $isUSBinstall)) {
					$latestWin10wim = Get-ChildItem "$osImagesSMBtestingPath\*" -Include 'Windows-10-*.wim', 'Windows-10-*+1.swm' | Sort-Object -Property 'LastWriteTime' | Select-Object -Last 1
				}

				if ($null -eq $latestWin10wim) {
					$latestWin10wim = Get-ChildItem "$osImagesPath\*" -Include 'Windows-10-*.wim', 'Windows-10-*+1.swm' | Sort-Object -Property 'LastWriteTime' | Select-Object -Last 1
					
					if (($null -ne $latestWin10wim) -and $testMode -and (-not $isUSBinstall)) {
						Write-Host '    NO WIM IN TESTING OS IMAGES - USING WIM IN PRODUCTION OS IMAGES' -ForegroundColor Yellow
					}
				} else {
					Write-Host '    FOUND WIM IN TESTING OS IMAGES' -ForegroundColor Yellow
				}

				if ($null -ne $latestWin10wim) {
					$latestWimPath = $latestWin10wim.FullName
					$latestWimDisplayName = $latestWin10wim.BaseName
					
					if ($latestWimDisplayName.EndsWith('+1')) {
						$latestWimDisplayName = $latestWin10wim.Name.Replace('+1.swm', ' (Split Image)')
					}

					$latestWimDisplayName = $latestWimDisplayName.Replace('-', ' ')

					Write-Host "`n  Successfully Located Windows 10 Image: $latestWimDisplayName" -ForegroundColor Green
				} else {
					Write-Host "`n  ERROR: Failed to locate any Windows 10 installation images in `"$osImagesPath`"." -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			}

			$latestWin11wimPath = $null
			$latestWin11WimDisplayName = $null

			if ($lastTaskSucceeded) {
				Write-Output "`n`n  Locating Latest Windows 11 Installation Image..."

				$latestWin11wim = $null

				if ($testMode -and (-not $isUSBinstall)) {
					$latestWin11wim = Get-ChildItem "$osImagesSMBtestingPath\*" -Include 'Windows-11-*.wim', 'Windows-11-*+1.swm' | Sort-Object -Property 'LastWriteTime' | Select-Object -Last 1
				}

				if ($null -eq $latestWin11wim) {
					$latestWin11wim = Get-ChildItem "$osImagesPath\*" -Include 'Windows-11-*.wim', 'Windows-11-*+1.swm' | Sort-Object -Property 'LastWriteTime' | Select-Object -Last 1
					
					if (($null -ne $latestWin11wim) -and $testMode -and (-not $isUSBinstall)) {
						Write-Host '    NO WIM IN TESTING OS IMAGES - USING WIM IN PRODUCTION OS IMAGES' -ForegroundColor Yellow
					}
				} else {
					Write-Host '    FOUND WIM IN TESTING OS IMAGES' -ForegroundColor Yellow
				}

				if ($null -ne $latestWin11wim) {
					$latestWin11wimPath = $latestWin11wim.FullName
					$latestWin11WimDisplayName = $latestWin11wim.BaseName
					
					if ($latestWin11WimDisplayName.EndsWith('+1')) {
						$latestWin11WimDisplayName = $latestWin11wim.Name.Replace('+1.swm', ' (Split Image)')
					}

					$latestWin11WimDisplayName = $latestWin11WimDisplayName.Replace('-', ' ')

					Write-Host "`n  Successfully Located Windows 11 Image: $latestWin11WimDisplayName" -ForegroundColor Green
				} else {
					Write-Host "`n  No Windows 11 Installation Image Found - CONTINUING ANYWAY" -ForegroundColor Yellow # Do not error and stop installation if a Windows 11 WIM was not found but a Windows 10 WIM was.
				}
			}

			if ($lastTaskSucceeded) {
				Write-Output "`n`n  Detecting Whether This Computer Is Booted in Legacy BIOS or UEFI Mode..."
				
				try {
					# Windows Deployment Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-deployment-sample-scripts-sxs#-applyimagebat
					
					Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

					# Run "Wpeutil UpdateBootInfo" before checking PEFirmwareType (seems unnecessary in testing, but sample code does it and doesn't hurt).
					Start-Process 'Wpeutil.exe' -NoNewWindow -Wait -RedirectStandardOutput "$Env:TEMP\fgInstall-Wpeutil-UpdateBootInfo-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-Wpeutil-UpdateBootInfo-Error.txt" -ArgumentList 'UpdateBootInfo' -ErrorAction Stop # RedirectStandardOutput just so it doesn't show in window. 
					$wpeutilUpdateBootInfoError = Get-Content -Raw "$Env:TEMP\fgInstall-Wpeutil-UpdateBootInfo-Error.txt"
					
					$peFirmwareType = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').PEFirmwareType
					if ($peFirmwareType -eq 1) {
						$biosOrUEFI = 'Legacy BIOS'
					} elseif ($peFirmwareType -eq 2) {
						$biosOrUEFI = 'UEFI'
					}
					
					if (($null -ne $biosOrUEFI) -and ($null -eq $wpeutilUpdateBootInfoError)) {
						Write-Host "`n  This Computer Is Booted in $biosOrUEFI Mode" -ForegroundColor Green
					} else {
						if ($null -eq $wpeutilUpdateBootInfoError) {
							$wpeutilUpdateBootInfoError = Get-Content -Raw "$Env:TEMP\fgInstall-Wpeutil-UpdateBootInfo-Output.txt"
						}
						
						Write-Host "`n  ERROR LOADING BOOT INFO: $wpeutilUpdateBootInfoError" -ForegroundColor Red
						Write-Host "`n  ERROR: Failed to detect whether this computer is booted in Legacy BIOS or UEFI mode (PEFirmwareType = $peFirmwareType)." -ForegroundColor Red
						
						$lastTaskSucceeded = $false
					}
				} catch {
					Write-Host "`n  ERROR STARTING WPEUTIL FOR BOOT INFO: $_" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to detect whether this computer is booted in Legacy BIOS or UEFI mode." -ForegroundColor Red
					
					$lastTaskSucceeded = $false
				}
			}

			if ($lastTaskSucceeded) {
				Start-Sleep 3 # Sleep for a few seconds to be able to see last results before clearing screen.

				$lastChooseWindowsVersionError = ''
				
				$shouldQuit = $false
				$shouldShutDown = $false

				for ( ; ; ) {
					Clear-Host
					Write-Output "`n  Detecting If This Computer Supports Windows 11...`n" # https://www.microsoft.com/en-us/windows/windows-11-specifications

					$tpmSpecVersionString = (Get-CimInstance Win32_TPM -Namespace 'ROOT\CIMV2\Security\MicrosoftTPM' -ErrorAction SilentlyContinue).SpecVersion
					$win11compatibleTPM = $false
					
					if ($null -ne $tpmSpecVersionString) {
						$tpmSpecVersionString = $tpmSpecVersionString.Split(',')[0] # Use the first value in the "SpecVersion" comma separated string instead of "PhysicalPresenseVersionInfo" since the latter can be inaccurate when the former is correct.
						$win11compatibleTPM = ((($tpmSpecVersionString -Replace '[^0-9.]', '') -as [double]) -ge 2.0)
					} else {
						$tpmSpecVersionString = 'UNKNOWN'
					}

					if (Test-Path '\Install\Diagnostic Tools\WhyNotWin11.exe') { # Use WhyNotWin11 to help detect if the exact CPU model is compatible and more: https://github.com/rcmaehl/WhyNotWin11
						Remove-Item '\Install\WhyNotWin11 Log.csv' -Force -ErrorAction SilentlyContinue
						Start-Process '\Install\Diagnostic Tools\WhyNotWin11.exe' -NoNewWindow -Wait -ArgumentList '/export', 'CSV', '"X:\Install\WhyNotWin11 Log.csv"', '/silent', '/force' -ErrorAction SilentlyContinue
					}

					$win11compatibleArchitecture = $false
					$win11compatibleBootMethod = $false
					$win11compatibleCPUmodel = $false
					$win11compatibleCPUcores = $false
					$win11compatibleCPUspeed = $false
					$win11compatibleRAM = $false
					$win11compatibleSecureBoot = $false
					$win11compatibleTPMfromWhyNotWin11 = $false
					$checkedWithWhyNotWin11 = $false

					if (Test-Path '\Install\WhyNotWin11 Log.csv') {
						$whyNotWin11LogLastLine = Get-Content '\Install\WhyNotWin11 Log.csv' -Last 1

						if ($null -ne $whyNotWin11LogLastLine) {
							$whyNotWin11LogValues = $whyNotWin11LogLastLine.Split(',')

							if ($whyNotWin11LogValues.Count -eq 12) {
								# Index 0 is "Hostname" which is not useful for these Windows 11 compatibility checks.
								$win11compatibleArchitecture = ($whyNotWin11LogValues[1] -eq 'True')
								$win11compatibleBootMethod = ($whyNotWin11LogValues[2] -eq 'True')
								$win11compatibleCPUmodel = ($whyNotWin11LogValues[3] -eq 'True')
								$win11compatibleCPUcores = ($whyNotWin11LogValues[4] -eq 'True')
								$win11compatibleCPUspeed = ($whyNotWin11LogValues[5] -eq 'True')
								# Index 6 is "DirectX + WDDM2" which is undetectable in WinPE and will always fail since it requires drivers, but we can pretty safely assume compatibility if everything else passes.
								# Index 7 is "Disk Partition Type" which will be inaccurate since will be checking the partition type of the booted RAM disk, but the drive formatting in this script will only ever create compatible GPT partitions when in UEFI mode.
								$win11compatibleRAM = ($whyNotWin11LogValues[8] -eq 'True')
								$win11compatibleSecureBoot = ($whyNotWin11LogValues[9] -eq 'True')
								# Index 10 is "Storage Available" which will be inaccurate since will be checking the storage of the booted RAM disk, but the install drive size will be checked manually to be sure it's 64 GB or more. (WhyNotWin11 2.4.3.2 does add a way to specify a different Drive Letter to check, but that doesn't help since the install drive may not be formatted yet.)
								$win11compatibleTPMfromWhyNotWin11 = ($whyNotWin11LogValues[11] -eq 'True') # We already manually checked TPM version, but doesn't hurt to confirm that WinNotWin11 agrees.

								$checkedWithWhyNotWin11 = $true
							}
						}
					}

					if ($checkedWithWhyNotWin11) {
						Write-Host '    CPU Compatible: ' -NoNewline
						if (-not $win11compatibleCPUspeed) {
							Write-Host 'NO (At Least 1 GHz Speed REQUIRED)' -ForegroundColor Red
						} elseif (-not $win11compatibleCPUcores) {
							Write-Host 'NO (At Least Dual-Core REQUIRED)' -ForegroundColor Red
						} elseif (-not $win11compatibleArchitecture) {
							# This incompatibility should never happen since we only refurbish 64-bit processors and only have 64-bit Windows installers.
							Write-Host 'NO (64-bit REQUIRED)' -ForegroundColor Red
						} elseif (-not $win11compatibleCPUmodel) {
							Write-Host 'NO (Model NOT Supported)' -ForegroundColor Red
						} else {
							Write-Host 'YES' -ForegroundColor Green
						}

						Write-Host '    RAM 4 GB or More: ' -NoNewline
						if ($win11compatibleRAM) {
							Write-Host 'YES' -ForegroundColor Green
						} else {
							Write-Host 'NO (At Least 4 GB REQUIRED)' -ForegroundColor Red
							Write-Host '      YOU MAY BE ABLE TO REPLACE OR ADD MORE RAM' -ForegroundColor Yellow
						}
					} else {
						Write-Host '    CPU Compatible: ' -NoNewline
						Write-Host 'UNKNOWN' -ForegroundColor Red
						Write-Host '      WhyNotWin11 CHECK FAILED - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.' -ForegroundColor Red

						Write-Host '    RAM 4 GB or More: ' -NoNewline
						Write-Host 'UNKNOWN' -ForegroundColor Red
						Write-Host '      WhyNotWin11 CHECK FAILED - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.' -ForegroundColor Red
					}

					$win11compatibleStorage = $false
					Write-Host '    Storage 64 GB or More: ' -NoNewline
					if ((Get-Disk $installDriveID -ErrorAction SilentlyContinue).Size -ge 64GB) {
						$win11compatibleStorage = $true
						Write-Host 'YES' -ForegroundColor Green
					} else {
						Write-Host 'NO (At Least 64 GB REQUIRED)' -ForegroundColor Red
						Write-Host '      YOU MAY BE ABLE TO REPLACE THIS WITH A LARGER DRIVE' -ForegroundColor Yellow
					}

					Write-Host '    GPU Compatible: ' -NoNewline
					Write-Host 'WILL DETECT AFTER INSTALLATION' -ForegroundColor Yellow
					Write-Host '      DIRECTX 12 OR LATER WITH WDDM 2.0 DRIVER IS REQUIRED' -ForegroundColor Yellow
					Write-Host '      BUT CANNOT DETECT THAT UNTIL GPU DRIVERS ARE INSTALLED' -ForegroundColor Yellow

					Write-Host '    UEFI Enabled: ' -NoNewline
					if ($biosOrUEFI -ne 'UEFI') {
						Write-Host 'NO (Booted in Legacy BIOS Mode)' -ForegroundColor Red
						Write-Host '      YOU MAY BE ABLE TO ENABLE UEFI BOOTING IN THE UEFI/BIOS SETUP' -ForegroundColor Yellow
					} elseif (-not $win11compatibleSecureBoot) {
						# Secure Boot DOES NOT need to be enabled, the computer just needs to be Secure Boot capable: https://support.microsoft.com/en-us/windows/windows-11-and-secure-boot-a8ff1202-c0d9-42f5-940f-843abef64fad
						# And WhyNotWin11 only verifies that the computer is Secure Boot capable, not that it is enabled: https://github.com/rcmaehl/WhyNotWin11/blob/16123e4e891e9ba90c23cffccd5876d7ab2cfef3/includes/_Checks.au3#L219 & https://github.com/rcmaehl/WhyNotWin11/blob/1a2459a8cfc754644af7e94f33762eaaca544a07/includes/WhyNotWin11_accessibility.au3#L223
						Write-Host 'NO (NOT Secure Boot Capable)' -ForegroundColor Red
						Write-Host '      YOU MAY BE ABLE TO ENABLE SECURE BOOT CAPABILITY IN THE UEFI/BIOS SETUP' -ForegroundColor Yellow
					} else {
						Write-Host 'YES' -ForegroundColor Green

						if ($checkedWithWhyNotWin11 -and (-not $win11compatibleBootMethod)) {
							Write-Host '      BUT, WhyNotWin11 REPORTED INCOMPATIBLE BOOT METHOD - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.' -ForegroundColor Red
						}
					}

					Write-Host '    TPM 2.0 Enabled: ' -NoNewline
					if ($win11compatibleTPM) {
						Write-Host 'YES' -ForegroundColor Green

						if ($checkedWithWhyNotWin11 -and (-not $win11compatibleTPMfromWhyNotWin11)) {
							Write-Host '      BUT, WhyNotWin11 REPORTED INCOMPATIBLE TPM - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.' -ForegroundColor Red
						}
					} elseif (($tpmSpecVersionString -eq 'UNKNOWN') -or ($tpmSpecVersionString -eq 'Not Supported')) {
						Write-Host 'NO (Not Detected)' -ForegroundColor Red
						Write-Host '      YOU MAY BE ABLE TO ENABLE TPM IN THE UEFI/BIOS SETUP' -ForegroundColor Yellow
					} else {
						Write-Host "NO (Version $tpmSpecVersionString)" -ForegroundColor Red
						Write-Host '      SOME COMPUTERS HAVE MULTIPLE TPM VERSION OPTIONS IN THE UEFI/BIOS SETUP' -ForegroundColor Yellow
					}

					if ($testMode -or ($checkedWithWhyNotWin11 -and $win11compatibleCPUmodel -and $win11compatibleArchitecture -and $win11compatibleCPUcores -and $win11compatibleCPUspeed -and $win11compatibleRAM -and $win11compatibleStorage -and ($biosOrUEFI -eq 'UEFI') -and $win11compatibleBootMethod -and $win11compatibleSecureBoot -and $win11compatibleTPM -and $win11compatibleTPMfromWhyNotWin11)) {
						if ($testMode) {
							Write-Host "`n  WINDOWS 11 COMPATIBILITY CHECKS ARE OVERRIDDEN IN TEST MODE" -ForegroundColor Yellow
						}

						if (($null -ne $latestWin11wimPath) -and (Test-Path $latestWin11wimPath)) {
							Write-Host "`n  This Computer Is Compatible With Window 11" -ForegroundColor Green	

							Write-Output "`n`n  Choose Windows Version for $installDriveName...`n"

							if ($lastChooseWindowsVersionError -ne '') {
								Write-Host $lastChooseWindowsVersionError -ForegroundColor Red
							}

							Write-Host "`n    1: Install Windows 11" -ForegroundColor Cyan
							Write-Host "`n    0: Install Windows 10" -ForegroundColor Cyan
							Write-Host "`n    C: Cancel Windows Installation and Reboot This Computer" -ForegroundColor Cyan
							Write-Host "`n    X: Cancel Windows Installation and Shut Down This Computer" -ForegroundColor Cyan

							FocusScriptWindow
							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							$windowsVersionChoice = Read-Host "`n`n  Enter the Number or Letter of an Action to Perform"

							if ($windowsVersionChoice -eq '1') {
								FocusScriptWindow
								$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
								$confirmWin11 = Read-Host "`n  Enter `"1`" Again to Confirm Installing Windows 11"

								if ($confirmWin11 -eq '1') {
									Write-Host "`n  Windows 11 Will Be Installed..." -ForegroundColor Green
								
									$latestWimPath = $latestWin11wimPath
									$latestWimDisplayName = $latestWin11WimDisplayName

									Start-Sleep 2
									break
								} else {
									$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Installing Windows 11 - CHOOSE AGAIN`n"
								}
							} elseif ($windowsVersionChoice -eq '0') {
								FocusScriptWindow
								$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
								$confirmWin11 = Read-Host "`n  Enter `"0`" Again to Confirm Installing Windows 10"

								if ($confirmWin11 -eq '0') {
									Write-Host "`n  Windows 10 Will Be Installed..." -ForegroundColor Yellow

									Start-Sleep 2
									break
								} else {
									$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Installing Windows 10 - CHOOSE AGAIN`n"
								}
							} elseif ($windowsVersionChoice.ToUpper() -eq 'C') {
								FocusScriptWindow
								$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
								$confirmQuit = Read-Host "`n  Enter `"C`" Again to Confirm Canceling Windows Installation and Rebooting This Computer"

								if ($confirmQuit.ToUpper() -eq 'C') {
									$shouldQuit = $true
									break
								} else {
									$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Rebooting This Computer - CHOOSE AGAIN`n"
								}
							} elseif ($windowsVersionChoice.ToUpper() -eq 'X') {
								FocusScriptWindow
								$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
								$confirmShutDown = Read-Host "`n  Enter `"X`" Again to Confirm Canceling Windows Installation and Shutting Down This Computer"
					
								if ($confirmShutDown.ToUpper() -eq 'X') {
									$shouldShutDown = $true
									break
								} else {
									$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Shutting Down This Computer - CHOOSE AGAIN`n"
								}
							} else {
								if ($windowsVersionChoice) {
									$lastChooseWindowsVersionError = "`n    ERROR: `"$windowsVersionChoice`" Is Not a Valid Choice - CHOOSE AGAIN`n"
								} else {
									$lastChooseWindowsVersionError = ''
								}
							}
						} else {
							Write-Host "`n  This Computer Is Compatible With Window 11" -ForegroundColor Green
							Write-Host "`n  But, No Windows 11 Installation Image Found - WINDOWS 10 WILL BE INSTALLED INSTEAD..." -ForegroundColor Yellow
							Start-Sleep 3 # Sleep for a few seconds to be able to see Windows 11 compatibility notes before clearing screen.

							break
						}
					} elseif (((-not $checkedWithWhyNotWin11) -or ($win11compatibleCPUmodel -and $win11compatibleArchitecture -and $win11compatibleCPUcores -and $win11compatibleCPUspeed)) -and ((-not $win11compatibleRAM) -or (-not $win11compatibleStorage) -or (-not $win11compatibleTPM) -or (-not $win11compatibleTPMfromWhyNotWin11) -or ($biosOrUEFI -ne 'UEFI') -or (-not $win11compatibleBootMethod) -or (-not $win11compatibleSecureBoot))) {
						Write-Host "`n  This Computer Is NOT Currently Compatible With Window 11" -ForegroundColor Red
						Write-Host "`n  But, some of the compatibilty issues listed above may be fixable.`n  You could cancel the installation and try to fix them instead of installing Windows 10." -ForegroundColor Yellow

						Write-Output "`n`n  Confirm Windows Version for $installDriveName...`n"

						if ($lastChooseWindowsVersionError -ne '') {
							Write-Host $lastChooseWindowsVersionError -ForegroundColor Red
						}

						Write-Host "`n    0: Install Windows 10" -ForegroundColor Cyan
						Write-Host "`n    C: Cancel Windows Installation and Reboot This Computer" -ForegroundColor Cyan
						Write-Host "`n    X: Cancel Windows Installation and Shut Down This Computer" -ForegroundColor Cyan

						FocusScriptWindow
						$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
						$windowsVersionChoice = Read-Host "`n`n  Enter the Number or Letter of an Action to Perform"

						if ($windowsVersionChoice -eq '0') {
							Write-Host "`n  Windows 10 Will Be Installed..." -ForegroundColor Green

							Start-Sleep 2
							break
						} elseif ($windowsVersionChoice.ToUpper() -eq 'C') {
							FocusScriptWindow
							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							$confirmQuit = Read-Host "`n  Enter `"C`" Again to Confirm Canceling Windows Installation and Rebooting This Computer"

							if ($confirmQuit.ToUpper() -eq 'C') {
								$shouldQuit = $true
								break
							} else {
								$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Rebooting This Computer - CHOOSE AGAIN`n"
							}
						} elseif ($windowsVersionChoice.ToUpper() -eq 'X') {
							FocusScriptWindow
							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							$confirmShutDown = Read-Host "`n  Enter `"X`" Again to Confirm Canceling Windows Installation and Shutting Down This Computer"
				
							if ($confirmShutDown.ToUpper() -eq 'X') {
								$shouldShutDown = $true
								break
							} else {
								$lastChooseWindowsVersionError = "`n    ERROR: Did Not Confirm Canceling Windows Installation and Shutting Down This Computer - CHOOSE AGAIN`n"
							}
						} else {
							if ($windowsVersionChoice) {
								$lastChooseWindowsVersionError = "`n    ERROR: `"$windowsVersionChoice`" Is Not a Valid Choice - CHOOSE AGAIN`n"
							} else {
								$lastChooseWindowsVersionError = ''
							}
						}
					} else {
						Write-Host "`n  This Computer Is NOT Compatible With Window 11" -ForegroundColor Yellow
						Write-Host "`n  Windows 10 Will Be Installed..." -ForegroundColor Green
						Start-Sleep 3 # Sleep for a few seconds to be able to see Windows 11 compatibility notes before clearing screen.

						break
					}
				}

				if ($shouldQuit) {
					Clear-Host
					Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Rebooting This Computer in 5 Seconds..." -ForegroundColor Yellow
					Start-Sleep 5

					exit 10
				} elseif ($shouldShutDown) {
					Clear-Host
					Write-Host "`n  CANCELED WINDOWS INSTALLATION`n`n  Shutting Down This Computer in 5 Seconds..." -ForegroundColor Yellow
					Start-Sleep 5
					Stop-Computer
					Start-Sleep 60 # Sleep for 1 minute after executing "Stop-Computer" because if the script exits before "Stop-Computer" shut's down, the computer will be rebooted instead.

					exit 11
				}
			}

			if ($lastTaskSucceeded) {
				Clear-Host
				Write-Output "`n  Formatting $installDriveName for Windows in $biosOrUEFI Mode...`n`n`n`n`n`n`n`n`n" # Add empty lines for PowerShell progress UI
				
				try {
					# Disk formatting commands based on:
					# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-deployment-sample-scripts-sxs#-createpartitions-uefitxt
					# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-deployment-sample-scripts-sxs#-createpartitions-biostxt
					# As well as observations from using the Windows 10 21H1 (and previous versions) ISO installer via USB.
					
					# Reference for replacing DiskPart commands with PowerShell:
					# Initialize-DiskPartition function in https://www.powershellgallery.com/packages/WindowsImageTools/1.9.19.0/Content/WindowsImageTools.psm1
					
					if ((Get-Disk $installDriveID -ErrorAction Stop).PartitionStyle -ne 'RAW') { # Clear-Disk will fail if drive is not initialized, so only clear if needed.
						Write-Host '    Erasing Drive...' -NoNewline
						
						try {
							Clear-Disk $installDriveID -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
							
							Write-Host ' ERASED' -ForegroundColor Green
						} catch {
							Write-Host ' FAILED' -ForegroundColor Red
							throw $_
						}
					}

					try {
						Write-Host '    Initializing Drive...' -NoNewline
						
						$partitionStyle = 'MBR'
						
						if ($biosOrUEFI -eq 'UEFI') {
							$partitionStyle = 'GPT'
						}

						Initialize-Disk $installDriveID -PartitionStyle $partitionStyle -ErrorAction Stop
						
						Write-Host ' INITIALIZED' -ForegroundColor Green
					} catch {
						Write-Host ' FAILED' -ForegroundColor Red
						throw $_
					}

					try {
						$systemPartition = $null

						$systemPartitionFilesystem = 'NTFS'
						
						if ($biosOrUEFI -eq 'UEFI') {
							Write-Host '    Creating EFI System Partition...' -NoNewline

							$systemPartitionFilesystem = 'FAT32'

							# Windows 10 21H1 (and previous versions) ISO Installer made EFI System Partition 100 MB
							$systemPartition = New-Partition $installDriveID -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -Size 100MB -DriveLetter 'S' -ErrorAction Stop
						} else {
							Write-Host '    Creating BIOS System Partition...' -NoNewline
							
							# Only set System partition as Active in BIOS mode.
							# Windows 10 21H1 (and previous versions) ISO Installer made BIOS System Partion 50 MB
							$systemPartition = New-Partition $installDriveID -MbrType 'IFS' -IsActive -Size 50MB -DriveLetter 'S' -ErrorAction Stop
						}

						Format-Volume -Partition $systemPartition -FileSystem $systemPartitionFilesystem -NewFileSystemLabel 'System' -ErrorAction Stop | Out-Null
						
						Write-Host ' CREATED' -ForegroundColor Green
					} catch {
						Write-Host ' FAILED' -ForegroundColor Red
						throw $_
					}
					
					if ($biosOrUEFI -eq 'UEFI') { # Only create MSR partition in UEFI mode.
						Write-Host '    Creating Microsoft Reserved Partition...' -NoNewline

						try {
							New-Partition $installDriveID -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -Size 16MB -ErrorAction Stop | Out-Null

							Write-Host ' CREATED' -ForegroundColor Green
						} catch {
							Write-Host ' FAILED' -ForegroundColor Red
							throw $_
						}
					}
					
					try {
						Write-Host '    Creating Windows Partition...' -NoNewline
						
						$windowsPartition = $null

						$windowsPartitionSize = (Get-Disk $installDriveID -ErrorAction Stop).LargestFreeExtent
						
						if ($biosOrUEFI -eq 'UEFI') {
							$windowsPartition = New-Partition $installDriveID -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -Size $windowsPartitionSize -DriveLetter 'W' -ErrorAction Stop
						} else {
							$windowsPartition = New-Partition $installDriveID -MbrType 'IFS' -Size $windowsPartitionSize -DriveLetter 'W' -ErrorAction Stop
						}

						Format-Volume -Partition $windowsPartition -FileSystem 'NTFS' -NewFileSystemLabel 'Windows' -ErrorAction Stop | Out-Null
						
						Write-Host ' CREATED' -ForegroundColor Green
					} catch {
						Write-Host ' FAILED' -ForegroundColor Red
						throw $_
					}

					# Recovery partition is created after Windows installation so that we can check the WinRE size and dynamically resize the Windows partition and create a properly sized Recovery partition.
				} catch {
					Write-Host "`n  ERROR FORMATTING DRIVE: $_" -ForegroundColor Red
					
					$lastTaskSucceeded = $false
				}

				if ($testMode -or (-not $lastTaskSucceeded)) {
					Write-Host "`n  DRIVE DETAILS:" -ForegroundColor Yellow

					try {
						# Output all partition details from DiskPart (since it shows all GPT Attributes, MBR Types, etc) to be able to examine failures in detail (and successes when in test mode).

						$diskpartGetPartitionDetailsCommands = @("select disk $installDriveID", 'list partition')

						$numberOfPartitions = 2

						if ($biosOrUEFI -eq 'UEFI') {
							$numberOfPartitions = 3
						}

						for ($thisPartitionNumber = 1; $thisPartitionNumber -le $numberOfPartitions; $thisPartitionNumber ++) {
							$diskpartGetPartitionDetailsCommands += "select partition $thisPartitionNumber"
							$diskpartGetPartitionDetailsCommands += 'detail partition'
						}

						$diskpartGetPartitionDetailsCommands += 'exit'
						
						Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

						Set-Content -Path "$Env:TEMP\fgInstall-diskpart-GetPartitionDetails-Commands.txt" -Value $diskpartGetPartitionDetailsCommands -Force -ErrorAction Stop
						
						$diskpartGetPartitionDetailsExitCode = (Start-Process 'diskpart.exe' -NoNewWindow -Wait -PassThru -ArgumentList '/s', "$Env:TEMP\fgInstall-diskpart-GetPartitionDetails-Commands.txt" -ErrorAction Stop).ExitCode # Do NOT RedirectStandardOutput OR RedirectStandardError because we want everything outputted in window.

						if ($diskpartGetPartitionDetailsExitCode -ne 0) {
							throw "DiskPart Exit Code = $diskpartGetPartitionDetailsExitCode"
						}
					} catch {
						try {
							Get-Partition $installDriveID -ErrorAction Stop # Output info from Get-Partition if DiskPart details failed.
						} catch {
							Get-Disk $installDriveID # If Get-Partition and DiskPart failed, output info from Get-Disk instead.
						}
					}
				}

				if ($lastTaskSucceeded) {
					Write-Host "`n  Successfully Formatted $installDriveName`n  for Windows in $biosOrUEFI Mode" -ForegroundColor Green

					if ($testMode) {
						Write-Host "`n`n  PAUSED TO EXAMINE DRIVE DETAILS IN TEST MODE`n" -ForegroundColor Yellow
						FocusScriptWindow
						$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
						Read-Host '  Press ENTER to Install Windows' | Out-Null
					}
				} else {
					Write-Host "`n  ERROR: Failed to format $installDriveName." -ForegroundColor Red
				}
			}
			
			if ($lastTaskSucceeded) {
				Start-Sleep 3 # Sleep for a few seconds to be able to see last results before clearing screen.
				Clear-Host
				Write-Output "`n  Installing Windows Onto $installDriveName...`n`n`n`n`n`n  Windows Version: $latestWimDisplayName" # Add empty lines for PowerShell progress UI
				
				try {
					# Would like to use Expand-WindowsImage's "-CheckIntegrity" parameter, but it generally takes too long.

					if ($latestWimPath.EndsWith('.swm')) {
						Expand-WindowsImage -ImagePath $latestWimPath -SplitImageFilePattern $latestWimPath.Replace('+1.swm', '+*.swm') -Index 1 -ApplyPath 'W:\' -Verify -ErrorAction Stop
					} else {
						Expand-WindowsImage -ImagePath $latestWimPath -Index 1 -ApplyPath 'W:\' -Verify -ErrorAction Stop
					}

					Clear-Host
					Write-Host "`n  Successfully Installed Windows Onto $installDriveName" -ForegroundColor Green
					Add-Content '\Install\Windows Install Log.txt' "Installed Windows ($latestWimDisplayName) Onto $installDriveName (Drive ID $installDriveID) in $biosOrUEFI Mode - $(Get-Date)" -ErrorAction SilentlyContinue

					$didInstallWindowsImage = $true
				} catch {
					# If Expand-WindowsImage fails, the progress bar doesn't complete itself and the incomplete progress will still show above the next progress bar during the next re-attempt.
					# I tried calling "Write-Progress -Activity 'Operation' -Status 'Running' -Completed" manually to clear it, but that doesn't work. Not sure what to do about that issue.
					
					$dismLogContents = Get-Content -Raw "$Env:WINDIR\Logs\DISM\dism.log" -ErrorAction SilentlyContinue
					if (($null -eq $dismLogContents) -or ($dismLogContents -eq '')) {
						$dismLogContents = ' N/A'
					} else {
						$dismLogContents = "`n$dismLogContents"
					}

					Write-Host "`n  DISM LOG:$dismLogContents" -ForegroundColor Red
					Write-Host "`n  ERROR INSTALLING WIM: $_" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to install Windows onto $installDriveName." -ForegroundColor Red
					
					$lastTaskSucceeded = $false
				}
			}
		}

		if ($lastTaskSucceeded -and (-not $didInstallDrivers)) {
			if ($isUSBinstall) {
				Write-Host "`n`n  Driver Installation Not Available During USB Install - WINDOWS UPDATE WILL INSTALL DRIVERS IN OS" -ForegroundColor Yellow
				Add-Content '\Install\Windows Install Log.txt' "Driver Installation Not Available During USB Install - $(Get-Date)" -ErrorAction SilentlyContinue
			} else {
				Write-Output "`n`n  Locating Drivers for This Computer Model..."
				
				$driversModelPath = $null
				$isInstallingDriverPack = $false

				$driversCacheModelNameFilePath = '\Install\Drivers Cache Model Name.txt' # This file is created by QA Helper using its detailed model info.
				if (-not (Test-Path $driversCacheModelNameFilePath)) {
					$driversCacheModelNameFilePath = '\Install\Drivers Cache Model Path.txt' # This is the old filename from when paths were specified instead of a filename.
				}

				if (Test-Path $driversCacheModelNameFilePath) {
					$driversCacheModelNameFileContents = Get-Content $driversCacheModelNameFilePath -First 1

					if ($null -ne $driversCacheModelNameFileContents) {
						if ($driversCacheModelNameFileContents.Contains('\')) {
							# Drivers Cache used to store drivers for each model in their own folder with the path specified by "Drivers Cache Model Path.txt".
							# Now, all drivers are stored in a "Unique Drivers" folder and each specific model is just a text file whose contents are a list of the drivers that were cached for that model.
							# Therefore, if an old "Drivers Cache Model Path.txt" from an old "QA Helper" was read, we must replace backslashes with spaces to be used as a filename instead of a folder path.
							$driversCacheModelNameFileContents = $driversCacheModelNameFileContents.Replace('\', ' ')
						}

						if ($driversCacheModelNameFileContents.Contains(' ')) {
							$driversCacheModelPathUniqueDriversPointerFilePath = "$driversCacheBasePath\$driversCacheModelNameFileContents.txt"

							if (Test-Path $driversCacheModelPathUniqueDriversPointerFilePath) {
								$driversCacheModelPathUniqueDriversPointerFileContents = Get-Content -Raw $driversCacheModelPathUniqueDriversPointerFilePath -ErrorAction SilentlyContinue
								
								if (($null -ne $driversCacheModelPathUniqueDriversPointerFileContents) -and ($driversCacheModelPathUniqueDriversPointerFileContents -ne '')) {
									$driversModelPath = $driversCacheModelPathUniqueDriversPointerFilePath
								}
							}
						}
					}
				}
				
				$driversSource = 'Cached'

				if ($null -eq $driversModelPath) {
					# If no Cached Drivers exists, check for Driver Pack in $driverPacksBasePath
					
					$manufacturerForDriverPacks = $null
					$possibleModelsForDriverPacks = @()
					
					try {
						$computerSystemProductVendorVersionName = (Get-CimInstance 'Win32_ComputerSystemProduct' -Property 'Vendor', 'Version', 'Name')
						$manufacturerForDriverPacks = $computerSystemProductVendorVersionName.Vendor.ToLower()

						# Dell Driver Packs (http://downloads.dell.com/catalog/DriverPackCatalog.cab) are available on the server (as of January 2021).
						# HP Driver Packs (http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab) are available on the server (as of January 2021).
						# Lenovo Driver Packs (https://download.lenovo.com/cdrt/td/catalogv2.xml & https://download.lenovo.com/cdrt/td/catalog.xml) are available on the server (as of January 2021).
						
						if ($manufacturerForDriverPacks.Contains('dell')) {
							$manufacturerForDriverPacks = 'Dell'
						} elseif ($manufacturerForDriverPacks.Contains('hp') -or $manufacturerForDriverPacks.Contains('hewlett-packard')) {
							$manufacturerForDriverPacks = 'HP'
						} elseif ($manufacturerForDriverPacks.Contains('lenovo')) {
							$manufacturerForDriverPacks = 'Lenovo'
						} else {
							throw 'UNSUPPORTED MANUFACTURER FOR DRIVER PACKS'
						}

						# The actual computer model can be stored in a variety of places, so check them all and use the first match.
						# The Classes and Properties being used for manufacturer and model names are from the thoroughly tested code in QA Helper,
						# except for some specifics for Dell and HP, which came from: https://github.com/MSEndpointMgr/ModernDriverManagement/blob/4c71b08c890f96f953849b6845e04ed2808c67f7/Invoke-CMApplyDriverPackage.ps1#L1109
						
						$possibleModelsForDriverPacks += $computerSystemProductVendorVersionName.Version
						$possibleModelsForDriverPacks += $computerSystemProductVendorVersionName.Name
						
						$computerSystemSystemSKUNumberAndOEMStringArray = (Get-CimInstance 'Win32_ComputerSystem' -Property 'SystemSKUNumber', 'OEMStringArray')
						$possibleModelsForDriverPacks += $computerSystemSystemSKUNumberAndOEMStringArray.SystemSKUNumber

						if ($manufacturerForDriverPacks -eq 'Dell') {
							# "OEMStringArray" is only used as a fallback on Dell when "SystemSKUNumber" is same as "Name" from "Win32_ComputerSystemProduct" instead of actual Type/System ID.
							$possibleModelsForDriverPacks += $computerSystemSystemSKUNumberAndOEMStringArray.OEMStringArray
						} elseif ($manufacturerForDriverPacks -eq 'HP') {
							# Only include the "Product" from "Win32_BaseBoard" for HPs since that is where the Type/System ID will be.
							# Don't want to include it for other manufacturers to avoid false positive matches on 4 character strings that are not actually the correct Type/System ID.
							$possibleModelsForDriverPacks += (Get-CimInstance 'Win32_BaseBoard' -Property 'Product').Product
						}
					} catch {
						# Proceed with whatever info was retrieved before erroring (an error could only happen if a Class does not exist, which should never happen).
					}

					if (($null -ne $manufacturerForDriverPacks) -and ($possibleModelsForDriverPacks.Count -gt 0)) {
						if ($testMode) {
							Write-Host "`n    POSSIBLE MODELS FOR $($manufacturerForDriverPacks.ToUpper()) DRIVERS:" -ForegroundColor Yellow
							$possibleModelsForDriverPacks | ForEach-Object {
								if (($null -ne $_) -and ($_.Trim() -ne '')) {
									Write-Host "      $_" -ForegroundColor Yellow
								}
							}
						}

						$fallbackDriversModelPath = $null

						foreach ($thisPossibleModelForDriverPacks in $possibleModelsForDriverPacks) {
							if (($null -ne $thisPossibleModelForDriverPacks) -and ($thisPossibleModelForDriverPacks.length -ge 4)) {
								# Driver Packs can be used for multiple Model Names or Types/System IDs...
								# Since multiple Model Names or Types/System IDs will refer back to a single unique Driver Pack, I created a very simple filesystem-based "database" to point to the correct unique Driver Pack for each Model Name or Type/System ID.
								# Within the Driver Packs folders there are text files for each Model Name or Type/System ID, and the contents of these text files refer to the relative unique Driver Pack folder.
								# So, the code below will check for this text file, and then read the contents, and then use the relative path specified for the unique Driver Pack folder and that path will be confirmed and assigned to $driversModelPath.

								$thisPossibleModelForDriverPacks = $thisPossibleModelForDriverPacks.Trim().ToLower()

								# Dell Types/Systems IDs are POSSIBLY matched with the "SystemSKUNumber" from "Win32_ComputerSystem". But some Dell's do not include it there, in that case it will HOPEFULLY get caught within the square brackets of one the fields of the "OEMStringArray" from "Win32_ComputerSystem".
								# HP Types/System IDs will be matched with "Product" from "Win32_BaseBoard" without any modification needed.
								# Lenovo Types/System IDs can be matched after a little modification of a couple possible fields, as seen below.

								if ($manufacturerForDriverPacks -eq 'Dell') {
									if ($thisPossibleModelForDriverPacks.Contains('[') -and $thisPossibleModelForDriverPacks.EndsWith(']') -and ($thisPossibleModelForDriverPacks.length -eq ($thisPossibleModelForDriverPacks.IndexOf('[') + 6))) {
										# If contains 4 characters between square brackets, they should be the Type/System ID from one of the OEMStringArray fields.
										$thisPossibleModelForDriverPacks = $thisPossibleModelForDriverPacks.Substring(($thisPossibleModelForDriverPacks.IndexOf('[') + 1), 4)
									} elseif ($thisPossibleModelForDriverPacks.StartsWith('dell system ')) {
										# Some Dell Model Names start with "Dell System" but no Dell Driver Packs do.
										$thisPossibleModelForDriverPacks = $thisPossibleModelForDriverPacks.Replace('dell system ', '')
									}
								} elseif ($manufacturerForDriverPacks -eq 'Lenovo') {
									if ($thisPossibleModelForDriverPacks.Contains('_mt_') -and ($thisPossibleModelForDriverPacks.length -ge ($thisPossibleModelForDriverPacks.IndexOf('_mt_') + 8))) {
										# If contains "_mt_", the 4 characters after "_mt_" are the Type/System ID which we want to use.
										$thisPossibleModelForDriverPacks = $thisPossibleModelForDriverPacks.Substring(($thisPossibleModelForDriverPacks.IndexOf('_mt_') + 4), 4)
									} elseif (($thisPossibleModelForDriverPacks.length -ge 4) -and ($thisPossibleModelForDriverPacks -match '^[a-z0-9]+$')) {
										# If only contains letters and numbers, the first 4 characters could be a Type/System ID.
										$thisPossibleModelForDriverPacks = $thisPossibleModelForDriverPacks.Substring(0, 4)
									}
								}

								if ((($thisPossibleModelForDriverPacks.length -eq 4) -and ($thisPossibleModelForDriverPacks -match '^[a-z0-9]+$')) -or ($null -eq $fallbackDriversModelPath)) {
									$driverPackPointerFilePath = "$driverPacksBasePath\$manufacturerForDriverPacks\$($thisPossibleModelForDriverPacks).txt"
									
									if (Test-Path $driverPackPointerFilePath) {
										$driverPackPointerFileContents = Get-Content $driverPackPointerFilePath -First 1
										
										if (($null -ne $driverPackPointerFileContents) -and $driverPackPointerFileContents.Contains('\')) {
											$possibleDriversModelPath = "$driverPacksBasePath\$manufacturerForDriverPacks\$driverPackPointerFileContents"

											if (Test-Path $possibleDriversModelPath) {
												if (($thisPossibleModelForDriverPacks.length -eq 4) -and ($thisPossibleModelForDriverPacks -match '^[a-z0-9]+$')) {
													# If the match is 4 characters and only numbers and letters, then this is a Type/System ID match and is the most precise.

													if ($testMode) {
														Write-Host "`n    LOCATED DRIVER PACK:`n      $manufacturerForDriverPacks\$thisPossibleModelForDriverPacks`n      $driverPackPointerFileContents" -ForegroundColor Yellow
													}

													$driversModelPath = $possibleDriversModelPath
													$isInstallingDriverPack = $true
													$driversSource = $manufacturerForDriverPacks
													
													break
												} elseif ($null -eq $fallbackDriversModelPath) {
													# If matched a Model Name instead of the Type/System ID, keep checking for a Type/System ID and only use the Model Name as a fallback.
													
													if ($testMode) {
														Write-Host "`n    LOCATED FALLBACK DRIVER PACK:`n      $manufacturerForDriverPacks\$thisPossibleModelForDriverPacks`n      $driverPackPointerFileContents" -ForegroundColor Yellow
													}

													$fallbackDriversModelPath = $possibleDriversModelPath
												}
											}
										}
									}
								}
							}
						}

						if (($null -eq $driversModelPath) -and ($null -ne $fallbackDriversModelPath) -and (Test-Path $fallbackDriversModelPath)) {
							if ($testMode) {
								Write-Host "`n    USING FALLBACK DRIVER PACK" -ForegroundColor Yellow
							}

							$driversModelPath = $fallbackDriversModelPath
							$isInstallingDriverPack = $true
							$driversSource = $manufacturerForDriverPacks
						}
					}
				} elseif ($testMode) {
					Write-Host "`n    LOCATED CACHED DRIVERS:`n      $driversCacheModelNameFileContents" -ForegroundColor Yellow
				}

				if (($null -ne $driversModelPath) -and (Test-Path $driversModelPath)) {
					$allAvailableDriverInfPathsForModel = @()
					
					if ($isInstallingDriverPack) {
						# Retrieve all .inf files recursively instead of using "Add-WindowsDriver -Recurse" to be able to show installation progess.
						# Also, Driver Packs can contain TONS of drivers which may not actually be necessary for the specified model, so confirm compatibility for each driver and only install compatible drivers.

						# It appears that Drivers and Driver Packs generally list their supported Windows version based on what Windows version was current at the time the drivers were released rather than what version of Windows they could actually support (essentially any Windows 7 or newer driver *should* work).
						# Therefore, my Driver Pack download code will download be the most currently released driver pack for the latest version of Windows (7 or newer), sometimes this is a Windows 7, 8, or 8.1 Driver Pack.
						
						$allAvailableDriverInfPathsForModel = (Get-ChildItem $driversModelPath -Recurse -File -Include '*.inf').FullName
					} elseif ($driversModelPath.EndsWith('.txt')) {
						# Initially chose to not install all drivers in $driversModelPath recursively (using "Add-WindowsDriver -Recurse") because of the possible multiple .inf issue mentioned here:
						# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#add-drivers-to-your-windows-image
						# But later added detailed installation progess which couldn't be done when using "Add-WindowsDriver -Recurse".
						# Also, previously did exclusions here like we do when caching but that is no longer necessary since anything not compatible will be excluded anyways.

						# Previously cached all drivers for a specific model in a folder just for that model which lead to tons of duplicate drivers being cached.
						# Have since re-structured Drivers Cache to store all drivers in a single "Unique Drivers" folder with no driver duplication between models.
						# Now, each specific model is just a text file whose contents are a list of the drivers that were cached for that model.
						# This kind of thing could also not be done when using "Add-WindowsDriver -Recurse".

						# Folders in "$driversCacheBasePath\Unique Drivers" should be named like "heci.inf_amd64_f8de8314845ca592" (as the are when copied from "C:\Windows\System32\DriverStore\FileRepository\").
						
						$driversCacheModelPathUniqueDriversPointerFileLines = Get-Content $driversModelPath -ErrorAction SilentlyContinue
						
						foreach ($thisCachedUniqueDriverName in $driversCacheModelPathUniqueDriversPointerFileLines) {
							if ($thisCachedUniqueDriverName.Contains('.inf_amd64_')) {
								$thisCachedUniqueDriverInfPath = "$driversCacheBasePath\Unique Drivers\$thisCachedUniqueDriverName\$($thisCachedUniqueDriverName.Substring(0, $thisCachedUniqueDriverName.IndexOf('.'))).inf"
							
								if (Test-Path $thisCachedUniqueDriverInfPath) {
									$allAvailableDriverInfPathsForModel += $thisCachedUniqueDriverInfPath 
								}
							}
						}
					}

					# Parse each .inf to confirm compatibility with current hardware and only install compatible drivers.
					# Tried using "Get-WindowsDriver -Path 'W:\' -Driver $thisDriverInfPath" to get compatibility details and driver name instead parsing the .inf myself, but it was TOO SLOW (2-3 seconds per driver VS 0.01-0.6 seconds per driver when parsing manually).
					# ALSO, I would still had to parse some of the .inf manually anyway to get the Compatible Software ID matching that is done below since that is not included in the output of "Get-WindowsDriver -Path 'W:\' -Driver $thisDriverInfPath".
					
					if ($testMode) {
						Write-Host "`n    CHECKING $($allAvailableDriverInfPathsForModel.Count) $($driversSource.ToUpper()) DRIVERS FOR COMPATIBILITY..." -ForegroundColor Yellow
					}
					
					Add-Content '\Install\Windows Install Log.txt' "Located $($allAvailableDriverInfPathsForModel.Count) $driversSource Drivers in `"$($driversModelPath.Replace("$driversCacheBasePath\", '').Replace('.txt', '').Replace("$driverPacksBasePath\", ''))`" - $(Get-Date)" -ErrorAction SilentlyContinue

					$driverDetailsForCompatibleInfs = @{}

					if ($allAvailableDriverInfPathsForModel.Count -gt 0) {
						$pnpEntityCompatibleAndHardwareIDs = (Get-CimInstance Win32_PnPEntity -Property 'HardwareID', 'CompatibleID')
						$compatibleDeviceIDsForDrivers = (($pnpEntityCompatibleAndHardwareIDs.HardwareID + $pnpEntityCompatibleAndHardwareIDs.CompatibleID) | Where-Object { ($null -ne $_) } | Sort-Object -Unique).ToUpper()
						
						# Some drivers only list Software Compatible IDs "SWC\..." as compatible Device IDs. I believe these drivers will only list "SWC\..." Device IDs in their models sections,
						# but I set this code up to continue checking for any compatible Device IDs and only collect the "SWC\..." IDs to be matched with another compatible driver if no other compatibility was detected.
						# These "software" drivers are associated with other "hardware" drivers and can be matched and installed along with their "hardware" driver counterparts
						# by collecting "ComponentIDs" from compatible "hardware" drivers and matching those to the Software Compatible IDs of unmatched "software" drivers.

						# Also, the following compatibility checks will allow *cached* drivers listing "Monitor\..." IDs to be installed without actually confirming compatibility.
						# This is because "Monitor\..." Hardware/Compatible IDs are not properly available from Win32_PnPEntity in WinPE (all other WMI classes related to monitor info are also unavailable in WinPE).
						# But since we are dealing with cached drivers, I think it's safe to assume the driver is actually compatible and go ahead and install it to save Windows Update from having to install it in OS.

						$softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers = @{}
						$softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers = @()

						foreach ($thisDriverInfPath in $allAvailableDriverInfPathsForModel) {
							$isInfVersionSection = $false
							$thisDriverClass = 'UNKNOWN Class'
							$thisDriverVersion = 'UNKNOWN Version'

							$isInfManufacturerSection = $false
							$compatibleModelSectionIDs = @()

							$isInfModelsSection = $false
							$softwareComponentIDsFromModelsSectionsOfThisDriver = @{}
							$softwareComponentIDsFromComponentsSectionsOfThisDriver = @()
							
							$isInfStringsSection = $false
							$stringVariablesForDriver = @{}

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
										$isInfVersionSection = ($thisDriverInfLineUPPER -eq '[VERSION]')

										# https://docs.microsoft.com/en-us/windows-hardware/drivers/install/inf-manufacturer-section
										$wasInfManufacturerSection = $isInfManufacturerSection
										$isInfManufacturerSection = ($thisDriverInfLineUPPER -eq '[MANUFACTURER]')
										
										if ($wasInfManufacturerSection -and (-not $isInfManufacturerSection) -and ($compatibleModelSectionIDs.Count -eq 0)) {
											# If passed Manufacturer sections and didn't get any compatible Model Section IDs, this is not a 64-bit driver and we can stop reading lines.
											if ($testMode) {
												Write-Host "`n      NOT 64-BIT DRIVER:`n        $($thisDriverInfPath.Replace("$driversModelPath\", ''))" -ForegroundColor Yellow
											}

											break
										}

										# https://docs.microsoft.com/en-us/windows-hardware/drivers/install/inf-models-section
										$isInfModelsSection = $compatibleModelSectionIDs.Contains($thisDriverInfLineUPPER)

										# https://docs.microsoft.com/en-us/windows-hardware/drivers/install/inf-strings-section
										$isInfStringsSection = ($thisDriverInfLineUPPER -eq '[STRINGS]') # Match exactly to only use Engligh Strings sections.
									} elseif (($lineEqualsIndex = $thisDriverInfLine.IndexOf('=')) -gt -1) {
										if ($isInfVersionSection) {
											if (($thisDriverClass -eq 'UNKNOWN Class') -and $thisDriverInfLineUPPER.Contains('CLASS') -and (-not $thisDriverInfLineUPPER.Contains('CLASSGUID'))) {
												$thisDriverClass = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Trim() # It appears that the Class Names will never be in quotes or be variables that need to be translated.

												if ($thisDriverClass -eq '') {
													$thisDriverClass = 'UNKNOWN Class'
												} elseif ($thisDriverClass -ceq $thisDriverClass.ToLower()) {
													$thisDriverClass = "$($thisDriverClass.Substring(0, 1).ToUpper())$($thisDriverClass.Substring(1))" # If Class is all lowercase, capitalized the first letter.
												}
											} elseif (($thisDriverVersion -eq 'UNKNOWN Version') -and $thisDriverInfLineUPPER.Contains('DRIVERVER')) {
												$thisDriverVersion = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Split(',').Trim() | Where-Object { ($null -ne $_) -and ($_ -ne '') } | Select-Object -Last 1
												
												if ($thisDriverVersion -eq '') {
													$thisDriverVersion = 'UNKNOWN Version'
												}
											}
										} elseif ($isInfManufacturerSection -and $thisDriverInfLine.Contains(',') -and $thisDriverInfLineUPPER.Contains('NTAMD64')) {
											$thisManufacturerLineValues = $thisDriverInfLineUPPER.Substring($lineEqualsIndex + 1).Split(',').Trim()

											$thisDriverModelsSectionName = $thisManufacturerLineValues[0]
											$theseDriverModelsSectionsTargetOSes = $thisManufacturerLineValues[1..($thisManufacturerLineValues.length - 1)]

											foreach ($thisDriverModelsSectionsTargetOS in $theseDriverModelsSectionsTargetOSes) {
												if ($thisDriverModelsSectionsTargetOS.Contains('NTAMD64')) {
													$compatibleModelSectionIDs += "[$thisDriverModelsSectionName.$thisDriverModelsSectionsTargetOS]"
												}
											}
										} elseif ($isInfModelsSection -and $thisDriverInfLine.Contains(',')) {
											# A Hardware ID and mutliple Compatible IDs could exist on a single line seperated by commas, so check them all.
											$theseDriverCompatibleDeviceID = $thisDriverInfLineUPPER.Substring($lineEqualsIndex + 1).Replace('"', '').Split(',') # Seen situations where some .inf Device IDs were quoted so remove all quotes and also seen "Vid_" and "Pid_" instead of "VID_" and "PID_" so always compare UPPER Device IDs.
											$theseDriverCompatibleDeviceID = $theseDriverCompatibleDeviceID[1..($theseDriverCompatibleDeviceID.length - 1)].Trim() # BUT, the first element will be the "install-section-name" and not a Device ID, so get rid of that one.
											
											foreach ($thisDriverCompatibleDeviceID in $theseDriverCompatibleDeviceID) {
												if ($thisDriverCompatibleDeviceID.StartsWith('SWC\') -or ((-not $driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()]) -and ($compatibleDeviceIDsForDrivers.Contains($thisDriverCompatibleDeviceID) -or ((-not $isInstallingDriverPack) -and $thisDriverCompatibleDeviceID.StartsWith('MONITOR\'))))) {
													$thisDriverName = $thisDriverInfLine.Substring(0, $lineEqualsIndex).Replace('"', '').Trim() # This value will be translated using the strings variables.
													if ($thisDriverName.StartsWith('%') -and $thisDriverName.EndsWith('%')) {
														$thisDriverName = $thisDriverName.Substring(1, ($thisDriverName.length - 2)).Trim()
													}

													if ($thisDriverName -eq '') {
														$thisDriverName = 'UNKNOWN Name'
													}
													
													if ($thisDriverCompatibleDeviceID.StartsWith('SWC\')) {
														if ($testMode) {
															Write-Host "`n      ADDING DRIVER SOFTWARE COMPONENT ID TO CHECK AGAINST COMPATIBLE DRIVERS '$thisDriverCompatibleDeviceID':`n        $($thisDriverInfPath.Replace("$driversModelPath\", ''))" -ForegroundColor Yellow
														}
														
														$softwareComponentIDsFromModelsSectionsOfThisDriver[$thisDriverCompatibleDeviceID] = @{
															InfPath = $thisDriverInfPath
															DriverName = $thisDriverName
														}
													} else {
														$driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()] = @{
															InfPath = $thisDriverInfPath
															DriverName = $thisDriverName
														}

														if ($testMode) {
															if ((-not $isInstallingDriverPack) -and $thisDriverCompatibleDeviceID.StartsWith('MONITOR\')) {
																Write-Host "`n      ADDED *CACHED* MONITOR DRIVER REGARDLESS OF COMPATIBILITY BECAUSE MONITOR IDs N/A IN WINPE:`n        FILE: $($thisDriverInfPath.Replace("$driversModelPath\", ''))`n        LINE: $thisDriverInfLine" -ForegroundColor Yellow
															} else {
																$deviceIDtype = 'HARDWARE'

																if (($pnpEntityCompatibleAndHardwareIDs.CompatibleID | Where-Object { ($null -ne $_) }).ToUpper().Contains($thisDriverCompatibleDeviceID)) {
																	$deviceIDtype = 'COMPATIBLE'
																	$compatibleIDmatchCount ++
																} else {
																	$hardwareIDmatchCount ++
																}

																Write-Host "`n      DRIVER IS COMPATIBLE WITH $deviceIDtype ID '$thisDriverCompatibleDeviceID':`n        FILE: $($thisDriverInfPath.Replace("$driversModelPath\", ''))`n        LINE: $thisDriverInfLine" -ForegroundColor Yellow
															}
														}
													}
												}
											}
										} elseif ((-not $isInfVersionSection) -and (-not $isInfManufacturerSection) -and (-not $isInfModelsSection) -and (-not $isInfStringsSection) -and $thisDriverInfLineUPPER.Contains('COMPONENTIDS')) {
											# Could parse .infs more to only get confirmed compatible Component IDs from the correct sections, but since these will only match against 64-bit Drivers listing these Component IDs in their Models sections, I think we don't need to worry about that.

											$theseSoftwareComponentIDs = $thisDriverInfLineUPPER.Substring($lineEqualsIndex + 1).Split(',').Trim() # Can contain multiple IDs on one line.

											foreach ($thisSoftwareComponentID in $theseSoftwareComponentIDs) {
												if ($thisSoftwareComponentID -ne '') {
													if (-not $thisSoftwareComponentID.StartsWith('SWC\')) {
														$thisSoftwareComponentID = "SWC\$thisSoftwareComponentID"
													}

													if ($testMode) {
														Write-Host "        DRIVER CONTAINS SOFTWARE COMPONENT ID: $thisSoftwareComponentID" -ForegroundColor Yellow
													}

													$softwareComponentIDsFromComponentsSectionsOfThisDriver += $thisSoftwareComponentID # Any string variables within an ID need be translated before being adding to $compatibleSoftwareComponentIDs
												}
											}
										} elseif ($isInfStringsSection) {
											$stringVariablesForDriver[$thisDriverInfLineUPPER.Substring(0, $lineEqualsIndex).Trim()] = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Replace('"', '').Trim()
										}
									}
								}
							}
							
							if ($driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()]) {
								$driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()].DriverClass = $thisDriverClass
								$driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()].DriverVersion = $thisDriverVersion

								$untranslatedDriverName = $driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()].DriverName
								if (($null -ne $untranslatedDriverName) -and ($null -ne $stringVariablesForDriver[$untranslatedDriverName.ToUpper()])) {
									$driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()].DriverName = $stringVariablesForDriver[$untranslatedDriverName.ToUpper()]
								}

								# If driver was compatible, translate all string variables within $softwareComponentIDsFromComponentsSectionsOfThisDriver and then add the translated IDs to $softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers
								foreach ($thisSoftwareComponentID in $softwareComponentIDsFromComponentsSectionsOfThisDriver) {
									if ($thisSoftwareComponentID.Contains('%')) {
										foreach ($thisStringVariableForDriver in $stringVariablesForDriver.GetEnumerator()) {
											$thisSoftwareComponentID = $thisSoftwareComponentID.Replace("%$($thisStringVariableForDriver.Key)%", $thisStringVariableForDriver.Value)
										}

										if ($testMode) {
											Write-Host "        TRANSLATED SOFTWARE COMPONENT ID: $thisSoftwareComponentID" -ForegroundColor Yellow
										}
									}
									
									$softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers += $thisSoftwareComponentID
								}
							} else {
								# If driver was not compatible, add $softwareComponentIDsFromModelsSectionsOfThisDriver to $softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers to be matched against $softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers.
								# Also translate Device IDs and Driver Names.

								foreach ($thisSoftwareComponentIDdetails in $softwareComponentIDsFromModelsSectionsOfThisDriver.GetEnumerator()) {
									$thisSoftwareComponentID = $thisSoftwareComponentIDdetails.Key
									if ($thisSoftwareComponentID.Contains('%')) {
										foreach ($thisStringVariableForDriver in $stringVariablesForDriver.GetEnumerator()) {
											$thisSoftwareComponentID = $thisSoftwareComponentID.Replace("%$($thisStringVariableForDriver.Key)%", $thisStringVariableForDriver.Value)
										}
									}

									$translatedDriverName = $thisSoftwareComponentIDdetails.Value.DriverName
									if (($null -ne $translatedDriverName) -and ($null -ne $stringVariablesForDriver[$translatedDriverName.ToUpper()])) {
										$translatedDriverName = $stringVariablesForDriver[$translatedDriverName.ToUpper()]
									}
									
									if ($thisDriverClass.ToUpper() -ne 'SOFTWARECOMPONENT') {
										$thisDriverClass += ' SWC' # Some Software Component drivers do not have the class of "SoftwareComponent", so add " SWC" to any that don't to identify them.
									}
									
									if (-not $softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers[$thisSoftwareComponentID]) {
										$softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers[$thisSoftwareComponentID] = @()
									}

									$softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers[$thisSoftwareComponentID] += @{
										InfPath = $thisSoftwareComponentIDdetails.Value.InfPath
										DriverName = $translatedDriverName
										DriverClass = $thisDriverClass
										DriverVersion = $thisDriverVersion
									}

									if ($testMode) {
										Write-Host "`n      TRANSLATED DRIVER SOFTWARE COMPONENT ID TO CHECK AGAINST COMPATIBLE DRIVERS '$thisSoftwareComponentID':`n        $($thisSoftwareComponentIDdetails.Value.InfPath.Replace("$driversModelPath\", ''))" -ForegroundColor Yellow
									}
								}
							}

							if ($testMode -and (-not $isInstallingDriverPack) -and (-not $driverDetailsForCompatibleInfs[$thisDriverInfPath.ToLower()])) { # Only want to log un-matched .infs for investigation when checking cached drivers, which are all supposed to match.
								Write-Host "`n      DRIVER *IS NOT* COMPATIBLE WITH ANY DEVICE ID:`n        $($thisDriverInfPath.Replace("$driversModelPath\", ''))" -ForegroundColor Yellow
							}
						}

						if ($softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers.Count -gt 0) {
							# Match $softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers with $softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers and include them to be installed.
							$softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers = $softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers | Sort-Object -Unique
							foreach ($thisCompatibleSoftwareComponentID in $softwareComponentIDsFromComponentsSectionsOfCompatibleDrivers) {
								$theseDriverDetailsForSoftwareComponentID = $softwareComponentIDsFromModelsSectionsOfUnmatchedDrivers[$thisCompatibleSoftwareComponentID]

								if ($null -ne $theseDriverDetailsForSoftwareComponentID) {
									foreach ($thisDriverDetailsForSoftwareComponentID in $theseDriverDetailsForSoftwareComponentID) {
										if (-not $driverDetailsForCompatibleInfs[$thisDriverDetailsForSoftwareComponentID.InfPath.ToLower()]) {
											if ($testMode) {
												Write-Host "`n      ADDED DRIVER FOR COMPATIBLE SOFTWARE COMPONENT ID '$thisCompatibleSoftwareComponentID':`n        $($thisDriverDetailsForSoftwareComponentID.InfPath.Replace("$driversModelPath\", ''))" -ForegroundColor Yellow
											}

											$driverDetailsForCompatibleInfs[$thisDriverDetailsForSoftwareComponentID.InfPath.ToLower()] = $thisDriverDetailsForSoftwareComponentID
										}
									}
								} elseif ($testMode) {
									Write-Host "`n      NO COMPATIBLE DRIVER FOUND FOR SOFTWARE COMPONENT ID '$thisCompatibleSoftwareComponentID'" -ForegroundColor Yellow
								}
							}
						}
						
						if ($testMode) {
							#$driverDetailsForCompatibleInfs.Values | Format-Table -AutoSize -HideTableHeaders
							Write-Host "`n    $($driverDetailsForCompatibleInfs.Count) COMPATIBLE $($driversSource.ToUpper()) DRIVERS (OF $($allAvailableDriverInfPathsForModel.Count) AVAILABLE DRIVERS)" -ForegroundColor Yellow
						}
					}

					if ($driverDetailsForCompatibleInfs.Count -gt 0) {
						Write-Host "`n  Successfully Located $($driverDetailsForCompatibleInfs.Count) $driversSource Drivers for This Computer Model" -ForegroundColor Green
						Add-Content '\Install\Windows Install Log.txt' "Confirmed Compatibility for $($driverDetailsForCompatibleInfs.Count) $driversSource Drivers - $(Get-Date)" -ErrorAction SilentlyContinue
						
						Write-Output "`n`n  Installing $($driverDetailsForCompatibleInfs.Count) $driversSource Drivers for This Computer Model`n  Onto $installDriveName`n  PLEASE WAIT, THIS MAY TAKE A FEW MINUTES..."
						
						$skipInstallDrivers = $false

						if ($testMode) {
							Write-Host "`n  Choose Whether or Not to Install $driversSource Drivers in Test Mode" -ForegroundColor Cyan
							FocusScriptWindow
							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							$confirmInstallDrivers = Read-Host "  Type `"Y`" and Press ENTER to Install $driversSource Drivers or Type ANYTHING ELSE to Skip"

							if ($confirmInstallDrivers.ToUpper() -ne 'Y') {
								$skipInstallDrivers = $true
							}
						}

						if ($testMode -and $skipInstallDrivers) {
							Write-Host "`n  Chose to Skip Installing $driversSource Drivers in Test Mode" -ForegroundColor Yellow
							Add-Content '\Install\Windows Install Log.txt' "Chose to Skip Installing $driversSource Drivers in Test Mode - $(Get-Date)" -ErrorAction SilentlyContinue
						} else {
							$thisDriverIndex = 0
							$installedDriversCount = 0

							foreach ($thisDriverDetails in ($driverDetailsForCompatibleInfs.Values | Sort-Object -Property { $_.DriverClass }, { $_.DriverName }, { $_.DriverVersion }, { $_.InfPath })) { # I'm not sure why, but this array is not getting sorted properly when just listing fields as strings, but does sort properly when I put each field in a script block.
								$thisDriverIndex ++

								$thisDriverInfPath = $thisDriverDetails.InfPath
								
								if (($null -ne $thisDriverInfPath) -and (Test-Path $thisDriverInfPath)) {
									$thisDriverInfBaseName = (Split-Path $thisDriverInfPath -Leaf).Split('.')[0]
									
									Write-Host "`n    Installing $driversSource Driver $thisDriverIndex of $($driverDetailsForCompatibleInfs.Count): `"$thisDriverInfBaseName`" Version $($thisDriverDetails.DriverVersion)`n      $($thisDriverDetails.DriverClass) - $($thisDriverDetails.DriverName)"
									
									try {
										Add-WindowsDriver -Path 'W:\' -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null

										Write-Host '      INSTALLED' -ForegroundColor Green

										$installedDriversCount ++
									} catch {
										Write-Host "      FAILED: $_" -ForegroundColor Red
									}
								} else {
									Write-Host "`n    INF NOT FOUND for $driversSource Driver $thisDriverIndex of $($driverDetailsForCompatibleInfs.Count):`n      $($thisDriverInfPath.Replace("$driversCacheBasePath\", '').Replace('.txt', '').Replace("$driverPacksBasePath\", ''))`n      CONTINUING ANYWAY..." -ForegroundColor Yellow
								}
							}
							
							if ($installedDriversCount -eq 0) {
								$dismLogContents = Get-Content -Raw "$Env:WINDIR\Logs\DISM\dism.log" -ErrorAction SilentlyContinue
								if (($null -eq $dismLogContents) -or ($dismLogContents -eq '')) {
									$dismLogContents = ' N/A'
								} else {
									$dismLogContents = "`n$dismLogContents"
								}
								
								Write-Host "`n  DISM LOG:$dismLogContents" -ForegroundColor Red
								Write-Host "`n  ERROR: Failed to install $driversSource Drivers from `"$($driversModelPath.Replace("$driversCacheBasePath\", '').Replace('.txt', '').Replace("$driverPacksBasePath\", ''))`"." -ForegroundColor Red
								Add-Content '\Install\Windows Install Log.txt' "Failed to Install $driversSource Drivers - $(Get-Date)" -ErrorAction SilentlyContinue
								
								$lastTaskSucceeded = $false
							} else {
								Write-Host "`n  Successfully Installed $installedDriversCount $driversSource Drivers Onto $installDriveName" -ForegroundColor Green
								Add-Content '\Install\Windows Install Log.txt' "Installed $installedDriversCount $driversSource Drivers - $(Get-Date)" -ErrorAction SilentlyContinue

								$didInstallDrivers = $true
							}
						}
					} else {
						Write-Host "`n  No Compatible $driversSource Drivers to Install - WINDOWS UPDATE WILL INSTALL DRIVERS IN OS" -ForegroundColor Yellow
						Add-Content '\Install\Windows Install Log.txt' "No Compatible $driversSource Drivers to Install - $(Get-Date)" -ErrorAction SilentlyContinue
					}
				} else {
					Write-Host "`n  No $driversSource Drivers to Install - WINDOWS UPDATE WILL INSTALL DRIVERS IN OS" -ForegroundColor Yellow
					Add-Content '\Install\Windows Install Log.txt' "No $driversSource Drivers to Install - $(Get-Date)" -ErrorAction SilentlyContinue
				}
			}
		}
		
		if ($lastTaskSucceeded -and (-not $isBaseInstall) -and (-not $didCreateRecoveryPartition)) {
			Write-Output "`n`n  Copying Setup Resources Onto $installDriveName..."
			
			try {
				# Copy UnattendAudit.xml to Installed OS to enter Audit mode and run "Setup Windows.ps1" (references are within XML file).
				# Install "Unattend.xml" into "W:\Windows\System32\Sysprep" instead of "W:\Windows\Panther" so that it's processed after every reboot until it's deleted manually.
				# If it's only installed into "W:\Windows\Panther" then the XML will be modified to mark the "auditUser" pass settings with "wasPassProcessed=true" which would make the "Setup Windows.ps1" only run once on the first boot, which we don't want.
				if ($testMode -and (-not $isUSBinstall) -and (Test-Path "$setupResourcesSMBtestingPath\UnattendAudit.xml")) {
					Copy-Item "$setupResourcesSMBtestingPath\UnattendAudit.xml" 'W:\Windows\System32\Sysprep\Unattend.xml' -Force -ErrorAction Stop

					Write-Host '    COPIED UNATTEND FROM TESTING RESOURCES' -ForegroundColor Yellow
				} else {
					Copy-Item "$setupResourcesPath\UnattendAudit.xml" 'W:\Windows\System32\Sysprep\Unattend.xml' -Force -ErrorAction Stop

					if ($testMode -and (-not $isUSBinstall)) {
						Write-Host '    NO UNATTEND IN TESTING RESOURCES - COPIED UNATTEND FROM PRODUCTION RESOURCES' -ForegroundColor Yellow
					}
				}

				# Copy entire \Install folder to Installed OS for QA Helper, etc.
				Copy-Item 'X:\Install' 'W:\' -Recurse -Force -ErrorAction Stop
				
				# Copy all files and folders within "setup-resources" of SMB share into "\Install" except for "UnattendAudit.xml".
				Get-ChildItem $setupResourcesPath -Exclude 'UnattendAudit.xml' -ErrorAction Stop | ForEach-Object {
					Copy-Item $_ 'W:\Install' -Recurse -Force -ErrorAction Stop

					if ($testMode -and (-not $isUSBinstall)) {
						Write-Host "    COPIED PRODUCTION RESOURCE: $($_.Name)" -ForegroundColor Yellow
					}
				}
				
				if ($testMode -and (-not $isUSBinstall)) {
					# When in test mode (and is not USB install), copy production resources first and then add or overwrite with testing resources.
					Get-ChildItem $setupResourcesSMBtestingPath -Exclude 'UnattendAudit.xml' -ErrorAction Stop | ForEach-Object {
						Copy-Item $_ 'W:\Install' -Recurse -Force -ErrorAction Stop

						Write-Host "    COPIED TESTING RESOURCE: $($_.Name)" -ForegroundColor Yellow
					}
				}

				if ($testMode -and (-not (Test-Path 'W:\Install\TESTING'))) {
					# Make sure test mode is set in OS if it's set during installation.
					New-Item -ItemType 'File' -Path 'W:\Install\TESTING' | Out-Null
					
					Write-Host '    SET TEST MODE FOR INSTALLED OS SINCE INSTALLATION WAS IN TEST MODE' -ForegroundColor Yellow
				}
				
				Write-Host "`n  Successfully Copied Setup Resources Onto $installDriveName" -ForegroundColor Green
			} catch {
				Write-Host "`n  ERROR COPYING SETUP RESOURCES: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to copy `"UnattendAudit.xml`" or `"\Install`" folder or other setup resources." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if (-not $isUSBinstall) {
			Remove-SmbMapping -RemotePath $smbShare -Force -UpdateProfile -ErrorAction SilentlyContinue # Done with SMB Share now, so remove it.
			Remove-SmbMapping -RemotePath $smbWdsShare -Force -UpdateProfile -ErrorAction SilentlyContinue # Done with SMB Share now, so remove it.
		}

		if ($lastTaskSucceeded) {
			if (Test-Path 'W:\Windows\System32\Recovery\Winre.wim') {
				if (-not $didCreateRecoveryPartition) {
					Start-Sleep 3 # Sleep for a few seconds to be able to see last results before clearing screen.
					Clear-Host
					Write-Output "`n  Creating Recovery Partition...`n`n`n`n`n`n`n`n`n" # Add empty lines for PowerShell progress UI

					try {
						# Recovery Parition Sizing Research and Notes:
						
						# Windows 10 1903 (v1) ISO Installer made Recovery partition 529 MB for 365 MB WinRE, which is 164 MB over WinRE size.
						# Windows 10 1903 (v2) ISO Installer made Recovery partition 529 MB for 409 MB WinRE, which is 120 MB over WinRE size.
						# Windows 10 1909 ISO Installer made Recovery partition 529 MB for 418 MB WinRE, which is 111 MB over WinRE size.

						# On Win 10 1909 and older, the Recovery partition was at the FRONT of the drive, contrary to documentation.
						# On Win 10 2004 and newer, the Recovery partition is at the END of the drive, as documentation specifies it should be:
						# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/hard-drives-and-partitions#recovery-partitions
						# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions#partition-layout

						# There also seems to be a change in the drive paritioning code at this point since the Recovery partition was always 529 MB in Win 10 1909 and older, regardless of WinRE size.
						# Then, in Win 10 2004 and newer, the Recovery partition size seems to get set dynamically to be 102 MB larger than actual WinRE size.

						# Windows 10 2004 ISO Installer made Recovery partition 505 MB for 403 MB WinRE, which is 102 MB over WinRE size.
						# Windows 10 20H2 (v1) ISO Installer made Recovery partition 498 MB for 396 MB WinRE, which is 102 MB over WinRE size.
						# Windows 10 20H2 (v2) ISO Installer made Recovery partition 499 MB for 397 MB WinRE, which is 102 MB over WinRE size.
						# Windows 10 21H1 ISO Installer made Recovery partition 508 MB for 406 MB WinRE, which is 102 MB over WinRE size.

						# Windows 11 Beta 22000.100 ISO Installer made Recovery partition 495 MB for 392 MB WinRE, which is 103 MB over WinRE size. (Could actually still be about 102 MB but shown as 103 MB because of MB rounding.)

						# I've seen that if there is too little free space on the Recovery partition, then Windows will move WinRE out of the Recovery partition and into Recovery folder at the root of the main Windows partition.
						# This documentations states 52 MB minimum of free space: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions#recovery-tools-partition
						# But through testing on 21H1, I found that 66 MB of free space is needed in this script for Windows to not move WinRE to the root of the main Windows partition (it will get moved with only 65 MB free, but not with 66 MB free).
						# Although, as the documentation also states, "The file system itself can take up additional space. For example, NTFS may reserve 5-15MB or more on a 750MB partition."
						# I have confirmed that the NTFS takes up these 14 MBs (by observing the used space in an "empty" NTFS partition) and that 52 MB appears to be the actual free space.
						# This script just needed to create 66 MB of free space to account for those 14 MBs that NTFS will take up for an end result of 52 MBs of free space (as the documentation states).

						# Based on the recommendation in this same documentation (https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions#recovery-tools-partition),
						# we will create a Recovery partition that is least 250 MB larger than the WinRE size (and rounded up to the nearest 50 MB for clean and round Recovery partition sizes).
						# This will result in a larger Recovery partition than the Windows ISO Installer creates, but still a drop in the bucket (less than 1 GB) for hard drive capacities and better to have extra space for safety.
						
						# The Recovery partition size is being calculated dynamically like this since Cumulative updates are pre-installed into WinRE which will make it larger than the WinRE sizes shown above from the original ISOs.
						# And, since the WinRE size will be slightly different after each time Cumulative updates are pre-installed, I don't want to have to check and change a hardcoded Recovery partition size if it becomes too small.

						$recoveryPartitionSizeFreeSpaceBytes = 250MB
						$recoveryPartitionSizeRoundUpToNearestBytes = 50MB

						$winreSizeBytes = (Get-Item 'W:\Windows\System32\Recovery\Winre.wim').Length
						$recoveryPartitionSizeBytes = ([math]::Ceiling(($winreSizeBytes + $recoveryPartitionSizeFreeSpaceBytes) / $recoveryPartitionSizeRoundUpToNearestBytes) * $recoveryPartitionSizeRoundUpToNearestBytes)

						try {
							Write-Host "    Resizing Windows Partition for $($recoveryPartitionSizeBytes / 1MB) MB Recovery Partition..." -NoNewline

							# Do not use "Get-PartitionSupportedSize -DriveLetter 'W' -ErrorAction Stop).SizeMax" here since that seems to actually include some unusable space and will result in the Recovery partition being smaller than intended.
							Resize-Partition -DriveLetter 'W' -Size ((Get-Partition -DriveLetter 'W' -ErrorAction Stop).Size - $recoveryPartitionSizeBytes) -ErrorAction Stop

							Write-Host ' RESIZED' -ForegroundColor Green
						} catch {
							Write-Host ' FAILED' -ForegroundColor Red
							throw $_
						}

						try {
							Write-Host "    Creating $($recoveryPartitionSizeBytes / 1MB) MB Recovery Partition for $([math]::Round($winreSizeBytes / 1MB)) MB WinRE..." -NoNewline
							
							# Recovery partition is created as last partition using leftover space unused by previous partitions.
							# $windowsPartitionSize was resized by subtracting $recoveryPartitionSizeBytes for this reason.

							$recoveryPartition = $null
							
							if ($biosOrUEFI -eq 'UEFI') {
								$recoveryPartition = New-Partition $installDriveID -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -UseMaximumSize -DriveLetter 'R' -ErrorAction Stop

								# The Recovery partition in UEFI mode must have GPT Attributes of 0x8000000000000001.
								# There seems to be no way to set GPT Attributes in PowerShell (specifically GPT_ATTRIBUTE_PLATFORM_REQUIRED), so DiskPart must be used for this to properly set up the Recovery partition in UEFI mode.
								# For more info: https://social.technet.microsoft.com/Forums/en-US/4f04df47-8bd6-4fff-bd79-8d3b45c23f8a/last-pieces-of-the-puzzle-converting-diskpart-script-to-powershell-storage-cmdlets
								
								$diskpartSetGptAttributesCommands = @(
									"select disk $installDriveID",
									"select partition $($recoveryPartition.PartitionNumber)",
									'gpt attributes=0x8000000000000001',
									'exit'
								)
								
								Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

								Set-Content -Path "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Commands.txt" -Value $diskpartSetGptAttributesCommands -Force -ErrorAction Stop
								
								$diskpartSetGptAttributesExitCode = (Start-Process 'diskpart.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Error.txt" -ArgumentList '/s', "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Commands.txt" -ErrorAction Stop).ExitCode
								$diskpartSetGptAttributesOutput = Get-Content -Raw "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Output.txt"
								$diskpartSetGptAttributesError = Get-Content -Raw "$Env:TEMP\fgInstall-diskpart-SetGptAttributes-Error.txt"
								
								if (($diskpartSetGptAttributesExitCode -ne 0) -or ($null -ne $diskpartSetGptAttributesError) -or ($null -eq $diskpartSetGptAttributesOutput) -or (-not $diskpartSetGptAttributesOutput.Contains('DiskPart successfully assigned the attributes to the selected GPT partition.'))) {
									if ($null -eq $diskpartSetGptAttributesOutput) {
										$diskpartSetGptAttributesOutput = 'N/A'
									}

									if ($null -eq $diskpartSetGptAttributesError) {
										$diskpartSetGptAttributesError = 'N/A (Check DISKPART OUTPUT)' # DiskPart seems to include runtime errors in the regular output.
									}

									throw "DiskPart Exit Code = $diskpartSetGptAttributesExitCode`n`n  DISKPART OUTPUT: $diskpartSetGptAttributesOutput`n`n  DISKPART ERROR: $diskpartSetGptAttributesError"
								}
							} else {
								$recoveryPartition = New-Partition $installDriveID -MbrType 'IFS' -UseMaximumSize -DriveLetter 'R' -ErrorAction Stop
							}
							
							Format-Volume -Partition $recoveryPartition -FileSystem 'NTFS' -NewFileSystemLabel 'Recovery' -ErrorAction Stop | Out-Null

							if ($biosOrUEFI -eq 'Legacy BIOS') {
								# The Recovery partition for BIOS must have a type of 0x27 (in hex, or 39 in decimal). This can be done in DiskPart with the command "set id=27"
								# But, I found it can also be done in PowerShell by setting the equivalent MbrType decimal value.
								# For some reason New-Partition only accepts specific MbrType values, so the correct value can't be set when creating the partition.
								# Luckily, Set-Partition accepts MbrType values of any UInt16 and setting MbrType 39 correctly shows as "Type: 27" when confirmed with DiskPart.

								# Also, this MUST be done AFTER the partition has been formatted or it won't take effect. Maybe because formatting overwrites it?

								$recoveryPartition | Set-Partition -MbrType 39 -ErrorAction Stop
							}
							
							Write-Host ' CREATED' -ForegroundColor Green
						} catch {
							Write-Host ' FAILED' -ForegroundColor Red
							throw $_
						}
					} catch {
						Write-Host "`n  ERROR CREATING RECOVERY PARTITION: $_" -ForegroundColor Red
						
						$lastTaskSucceeded = $false
					}

					if ($testMode -or (-not $lastTaskSucceeded)) {
						Write-Host "`n  DRIVE DETAILS:" -ForegroundColor Yellow

						try {
							# Output all partition details from DiskPart (since it shows all GPT Attributes, MBR Types, etc) to be able to examine failures in detail (and successes when in test mode).

							$diskpartGetPartitionDetailsCommands = @("select disk $installDriveID", 'list partition')

							$numberOfPartitions = 3

							if ($biosOrUEFI -eq 'UEFI') {
								$numberOfPartitions = 4
							}

							for ($thisPartitionNumber = 1; $thisPartitionNumber -le $numberOfPartitions; $thisPartitionNumber ++) {
								$diskpartGetPartitionDetailsCommands += "select partition $thisPartitionNumber"
								$diskpartGetPartitionDetailsCommands += 'detail partition'
							}

							$diskpartGetPartitionDetailsCommands += 'exit'
							
							Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

							Set-Content -Path "$Env:TEMP\fgInstall-diskpart-GetPartitionDetails-Commands.txt" -Value $diskpartGetPartitionDetailsCommands -Force -ErrorAction Stop
							
							$diskpartGetPartitionDetailsExitCode = (Start-Process 'diskpart.exe' -NoNewWindow -Wait -PassThru -ArgumentList '/s', "$Env:TEMP\fgInstall-diskpart-GetPartitionDetails-Commands.txt" -ErrorAction Stop).ExitCode # Do NOT RedirectStandardOutput OR RedirectStandardError because we want everything outputted in window.

							if ($diskpartGetPartitionDetailsExitCode -ne 0) {
								throw "DiskPart Exit Code = $diskpartGetPartitionDetailsExitCode"
							}
						} catch {
							try {
								Get-Partition $installDriveID -ErrorAction Stop # Output info from Get-Partition if DiskPart details failed.
							} catch {
								Get-Disk $installDriveID # If Get-Partition and DiskPart failed, output info from Get-Disk instead.
							}
						}
					}

					if ($lastTaskSucceeded) {
						Write-Host "`n  Successfully Created Recovery Partition" -ForegroundColor Green

						$didCreateRecoveryPartition = $true

						if ($testMode) {
							Write-Host "`n`n  PAUSED TO EXAMINE DRIVE DETAILS IN TEST MODE`n" -ForegroundColor Yellow
							FocusScriptWindow
							$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
							Read-Host '  Press ENTER to Set Up Recovery Environment' | Out-Null
						}
					} else {
						Write-Host "`n  ERROR: Failed to create Recovery partition." -ForegroundColor Red
					}
				}

				if ($lastTaskSucceeded -and (-not $didSetUpRecovery)) {
					Write-Output "`n`n  Setting Up Recovery Environment for $installDriveName..."
					
					# Setup Recovery Environment Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-deployment-sample-scripts-sxs#applyrecoverybat
					
					try {
						New-Item -ItemType 'Directory' -Force -Path 'R:\Recovery\WindowsRE' -ErrorAction Stop | Out-Null
						
						try {
							Copy-Item 'W:\Windows\System32\Recovery\Winre.wim' 'R:\Recovery\WindowsRE' -Force -ErrorAction Stop
							
							Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue
							
							# REAgentC.exe must be run from the installed OS because the executable doesn't exist in WinPE.
							# Although, running REAgentC actually seems unnecessary, running "REAgentC /info" in the installed OS shows that the Recovery Environment is properly enabled even without running "REAgentC /setreimage" here first.
							# But, do it anyway because sample code does it and it doesn't hurt anything.
							$reAgentcSetreimageExitCode = (Start-Process 'W:\Windows\System32\REAgentC.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-REAgentC-setreimage-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-REAgentC-setreimage-Error.txt" -ArgumentList '/setreimage', '/path', 'R:\Recovery\WindowsRE', '/target', 'W:\Windows' -ErrorAction Stop).ExitCode # RedirectStandardOutput just so it doesn't show in window.
							$reAgentcSetreimageError = Get-Content -Raw "$Env:TEMP\fgInstall-REAgentC-setreimage-Error.txt"
							
							if (($reAgentcSetreimageExitCode -eq 0) -and ($null -eq $reAgentcSetreimageError)) {
								Write-Host "`n  Successfully Set Up Recovery Environment for $installDriveName" -ForegroundColor Green

								$didSetUpRecovery = $true
							} else {
								if ($null -eq $reAgentcSetreimageError) {
									$reAgentcSetreimageError = Get-Content -Raw "$Env:TEMP\fgInstall-REAgentC-setreimage-Output.txt"
								}
								
								Write-Host "`n  ERROR SETTING RECOVERY IMAGE: $reAgentcSetreimageError" -ForegroundColor Red
								
								# Output Recovery Environment Configuration if REAgentC failed, sample code states that "Windows RE status may appear as Disabled, this is OK."
								Start-Process 'W:\Windows\System32\REAgentC.exe' -NoNewWindow -Wait -RedirectStandardOutput "$Env:TEMP\fgInstall-REAgentC-info-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-REAgentC-info-Error.txt" -ArgumentList '/info', '/target', 'W:\Windows' -ErrorAction Stop
								$reAgentcInfoError = Get-Content -Raw "$Env:TEMP\fgInstall-REAgentC-info-Error.txt"
								if ($null -eq $reAgentcInfoError) {
									Write-Host "`n  RECOVERY INFO:`n$(Get-Content -Raw "$Env:TEMP\fgInstall-REAgentC-info-Output.txt")" -ForegroundColor Red
								} else {
									if ($null -eq $reAgentcInfoError) {
										$reAgentcInfoError = Get-Content -Raw "$Env:TEMP\fgInstall-REAgentC-info-Output.txt"
									}

									Write-Host "`n  ERROR GETTING RECOVERY INFO: $reAgentcInfoError" -ForegroundColor Red
								}
								
								Write-Host "`n  ERROR: Failed to register `"R:\Recovery\WindowsRE`" as Recovery location (REAgentC Exit Code = $reAgentcSetreimageExitCode)." -ForegroundColor Red

								$lastTaskSucceeded = $false
							}
						} catch {
							Write-Host "`n  ERROR COPYING FILE OR STARTING REAGENTC: $_" -ForegroundColor Red
							Write-Host "`n  ERROR: Failed to copy `"W:\Windows\System32\Recovery\Winre.wim`" into `"R:\Recovery\WindowsRE\`"." -ForegroundColor Red

							$lastTaskSucceeded = $false
						}
					} catch {
						Write-Host "`n  ERROR CREATING RECOVERY DIRECTORY: $_" -ForegroundColor Red
						Write-Host "`n  ERROR: Failed to create Recovery directory at `"R:\Recovery\WindowsRE`"." -ForegroundColor Red

						$lastTaskSucceeded = $false
					}
				}
			} else {
				Write-Host "`n  ERROR: WinRE was NOT found at `"W:\Windows\System32\Recovery\Winre.wim`" within installed OS.`n`n  !!! THIS SHOULD NOT HAVE HAPPENED !!!" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}
		
		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Setting $installDriveName as Bootable..."
			
			try {
				# IMPORTANT: Set drive as bootable LAST (unlike the sample code) so that user can't boot into an incomplete installation (ie. no recovery) if anything went wrong.
				
				Remove-Item "$Env:TEMP\fgInstall-*.txt" -Force -ErrorAction SilentlyContinue

				# bcdboot.exe exists in WinPE but sample code shows running it from the installed OS.
				$bcdBootExitCode = (Start-Process 'W:\Windows\System32\bcdboot.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgInstall-bcdboot-s-Output.txt" -RedirectStandardError "$Env:TEMP\fgInstall-bcdboot-s-Error.txt" -ArgumentList 'W:\Windows', '/s', 'S:' -ErrorAction Stop).ExitCode
				$bcdBootOutput = Get-Content -Raw "$Env:TEMP\fgInstall-bcdboot-s-Output.txt"
				$bcdBootError = Get-Content -Raw "$Env:TEMP\fgInstall-bcdboot-s-Error.txt"

				if (($bcdBootExitCode -eq 0) -and ($null -eq $bcdBootError) -and ($null -ne $bcdBootOutput) -and ($bcdBootOutput -eq "Boot files successfully created.`r`n")) {
					Write-Host "`n  Successfully Set $installDriveName as Bootable" -ForegroundColor Green
				} else {
					if ($null -eq $bcdBootError) {
						$bcdBootError = $bcdBootOutput
					}
					
					Write-Host "`n  ERROR SETTING $installDriveName AS BOOTABLE: $bcdBootError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to set $installDriveName as bootable (bcdboot Exit Code = $bcdBootExitCode)." -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			} catch {
				Write-Host "`n  ERROR STARTING BCDBOOT: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to set $installDriveName as bootable." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			if ($testMode) {
				Write-Host "`n`n  LOADED MODULES (SHOULD BE $requiredModulesToPreImport):`n    $($(Get-Module).Name -Join "`n    ")" -ForegroundColor Yellow
				
				Write-Host "`n`n  AUTOMATIC REBOOT DISABLED IN TEST MODE`n" -ForegroundColor Yellow
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				Read-Host '  Press ENTER to Reboot to Finish the Windows Setup Process' | Out-Null
			} else {
				$rebootTimeout = 30
				
				Write-Output "`n`n  This Computer Will Reboot in $rebootTimeout Seconds to Finish the Windows Setup Process..."
				Write-Host "`n  Or Press Any Key to Reboot Now" -ForegroundColor Cyan
				
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				for ($secondsWaited = 0; $secondsWaited -lt $rebootTimeout; $secondsWaited ++) {
					if ($Host.UI.RawUI.KeyAvailable) {
						break
					}
					
					Start-Sleep 1
				}
			}
			
			break
		}

		Write-Host "`n`n  If this issue continues, please inform Free Geek I.T." -ForegroundColor Red
		Write-Host "`n`n  Press Any Key to Try Again or Press `"Control + C`" (or Close This Window) to Cancel and Reboot" -ForegroundColor Cyan
		
		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		for ( ; ; ) {
			if ($Host.UI.RawUI.KeyAvailable) {
				break
			}
			
			Start-Sleep 1
		}
	}
}
