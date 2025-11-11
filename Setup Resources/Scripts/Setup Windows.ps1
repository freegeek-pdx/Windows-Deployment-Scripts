#################################################################################
##                                                                             ##
##   THIS SCRIPT WILL BE RUN AUTOMATICALLY ON FIRST BOOT AFTER INSTALLATION    ##
##   TO RUN THIS SCRIPT MANUALLY, LAUNCH "\Install\Re-Run Setup Windows.cmd"   ##
##   OR CHOOSE "Re-Run Setup Windows Script" FROM SCRIPTS MENU IN QA HELPER    ##
##                                                                             ##
#################################################################################

#
# By Pico Mitchell for Free Geek
# Originally written and tested in September 2020 for Windows 10, version 2004
# Tested in November 2022 for Windows 10, version 22H2
# AND Tested in November 2023 for Windows 11, version 23H2
# AND Tested in October 2024 for Windows 11, version 24H2
# AND Tested in October 2025 for Windows 11, version 25H2
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

# Version: 2025.11.10-1

#Requires -RunAsAdministrator

param(
	[Parameter(Position = 0)]
	[String]$LastWindowsUpdatesCount # Use a String since passing a bool via "powershell.exe -File" seems impossible. And don't use int because it defaults to 0 when omitted.
)

$Host.UI.RawUI.WindowTitle = 'Setup Windows'

if ((-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State')) -or (-not (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState.Contains('RESEAL_TO_AUDIT'))) {
	Write-Host "`n  ERROR: `"Setup Windows`" Can Only Run In Windows Audit Mode`n`n  EXITING IN 5 SECONDS..." -ForegroundColor Red
	Start-Sleep 5
	exit 1
}


$testMode = ((Test-Path "$Env:SystemDrive\Install\fgFLAG-TEST") -or (Test-Path "$Env:SystemDrive\Install\TESTING")) # Still check for old flag names (which are easier to create manually).
$extraAppsMode = ((Test-Path "$Env:SystemDrive\Install\fgFLAG-EXTRAAPPS") -or (Test-Path "$Env:SystemDrive\Install\EXTRAAPPS")) # If EXTRAAPPS flag file/folder exists, auto-install extra apps.
$noAppsMode = ((Test-Path "$Env:SystemDrive\Install\fgFLAG-NOAPPS") -or (Test-Path "$Env:SystemDrive\Install\NOAPPS")) # If NOAPPS flag file/folder exists, do not install any apps.
$ipdtMode = ((Test-Path "$Env:SystemDrive\Install\fgFLAG-IPDT") -or (Test-Path "$Env:SystemDrive\Install\IPDT")) # If IPDT flag file/folder exists, auto-launch "Intel Processor Diagnostic Tool" instead of auto-lauching "QA Helper" (which will still be installed). This is a special mode for Hardware Testing.

$desktopPath = [Environment]::GetFolderPath('Desktop')

$windowsVersionName = (Get-CimInstance 'Win32_OperatingSystem' -Property 'Caption' -ErrorAction SilentlyContinue).Caption
$isWindows11 = ($windowsVersionName -and $windowsVersionName.ToUpper().Contains('WINDOWS 11'))
$cpuInfo = (Get-CimInstance 'Win32_Processor' -Property 'Manufacturer', 'Name' -ErrorAction SilentlyContinue)

if ($isWindows11) {
	# When on Windows 11, use C# code to detect if the Start Menu is open on first boot. See "CloseStartMenuOnFirstBootOfWindows11" function below for more information.
	# From: https://social.technet.microsoft.com/Forums/lync/en-US/c0652d6e-a4fd-4547-942a-7d28ca58b440/call-cocreateinstance-with-clsid#answers & https://stackoverflow.com/a/12010841

	Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Reflection;
using System.Runtime.InteropServices;

namespace AppVisible
{
	[ComImport, Guid("2246EA2D-CAEA-4444-A3C4-6DE827E44313"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	public interface IAppVisibility {
		HRESULT GetAppVisibilityOnMonitor([In] IntPtr hMonitor, [Out] out MONITOR_APP_VISIBILITY pMode);
		HRESULT IsLauncherVisible([Out] out bool pfVisible);
		HRESULT Advise([In] IAppVisibilityEvents pCallback, [Out] out int pdwCookie);
		HRESULT Unadvise([In] int dwCookie);
	}

	public enum HRESULT : long {
		S_FALSE = 0x0001,
		S_OK = 0x0000,
		E_INVALIDARG = 0x80070057,
		E_OUTOFMEMORY = 0x8007000E
	}
	public enum MONITOR_APP_VISIBILITY {
		MAV_UNKNOWN = 0, // The mode for the monitor is unknown
		MAV_NO_APP_VISIBLE = 1,
		MAV_APP_VISIBLE = 2
	}

	[ComImport, Guid("6584CE6B-7D82-49C2-89C9-C6BC02BA8C38"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	public interface IAppVisibilityEvents {
		HRESULT AppVisibilityOnMonitorChanged(
			[In] IntPtr hMonitor,
			[In] MONITOR_APP_VISIBILITY previousMode,
			[In] MONITOR_APP_VISIBILITY currentMode);

		HRESULT LauncherVisibilityChange([In] bool currentVisibleState);
	}

	public class App
	{
		public static bool IsLauncherVisible()
		{
			Type tIAppVisibility = Type.GetTypeFromCLSID(new Guid("7E5FE3D9-985F-4908-91F9-EE19F9FD1514"));
			IAppVisibility appVisibility = (IAppVisibility)Activator.CreateInstance(tIAppVisibility);
			bool launcherVisible;
			if (HRESULT.S_OK == appVisibility.IsLauncherVisible(out launcherVisible)) {
				return launcherVisible;
			}
			return false;
		}
	}
}
'@
}

function CloseStartMenuOnFirstBootOfWindows11 {
	if ($isWindows11 -and (-not (Test-Path "$desktopPath\QA Helper.lnk")) -and [AppVisible.App]::IsLauncherVisible()) { # Checking that QA Helper shortcut is not on the Desktop indicates first boot.
		# In Windows 11 (as of 21H2), the Start Menu opens automatically on first boot, so detect if it's open and then send Control+Escape key to toggle it closed.
		# This is called the "quiet period" where no other apps are supposed to launch and the Start menu is opened to encourage users to check it out: https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11#reaching-the-desktop-and-the-quiet-period
		# But, this is just an inconvenience when booting into Audit mode for testing, I hope to some day find a way to disable this "quite period", probably via some Registry changes or something.
		# This function will be called periodically throughout the script (mostly in each FocusScriptWindow call) since we can't know exactly when the Desktop will be loaded since the script runs before login.

		(New-Object -ComObject Wscript.Shell).SendKeys('^{ESC}') # Simulate Control+Escape to TOGGLE the Start Menu (https://superuser.com/a/1072520), which will CLOSE it in this case since we've confirmed it's open with the "IsLauncherVisible" function.
	}
}

$windowFunctionTypes = Add-Type -PassThru -Name WindowFunctions -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
'@ # Based On: https://stackoverflow.com/a/58548853 & https://stackoverflow.com/a/58542670

function FocusScriptWindow {
	try {
		Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
		# Don't bother trying to focus window if not logged in yet.
	} catch {
		CloseStartMenuOnFirstBootOfWindows11

		$scriptWindowHandle = (Get-Process -Id $PID).MainWindowHandle

		if ($scriptWindowHandle) {
			$windowFunctionTypes::SetForegroundWindow($scriptWindowHandle) | Out-Null
			if ($windowFunctionTypes::IsIconic($scriptWindowHandle)) {
				$windowFunctionTypes::ShowWindow($scriptWindowHandle, 9) | Out-Null
			}
		}

		(New-Object -ComObject Wscript.Shell).AppActivate($Host.UI.RawUI.WindowTitle) | Out-Null # Also try "AppActivate" since "SetForegroundWindow" seems to maybe not work as well on Windows 11.
	}
}


FocusScriptWindow

if ($LastWindowsUpdatesCount -eq '') {
	# Only run the following tasks if no LastWindowsUpdatesCount arg (don't bother re-running these if we're just relaunching this script).


	if (-not $isWindows11) { # In Windows 11 (as of 21H2), this appears to no longer be necessary.
		# Disable Network Location Wizard FIRST because some fast computers can get to the Desktop very quickly after this script is launched during the Preparing Windows phase.
		try {
			# Setting "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Network\NwCategoryWizard\Show" to "0" will turn off the Network Location Wizard
			# which stops Windows from prompting to set Network Profiles so we can avoid a big blue prompt on the right side of the screen on first boot.
			# https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/gg252535(v=ws.10)#to-turn-off-the-network-location-wizard-for-the-current-user

			# This is effective at stopping the Network Profiles prompt on first boot because this script is launched by "\Windows\System32\Sysprep\Unattend.xml"
			# which means this code runs while LogonUI is still showing the "Preparing Windows" screen and the desktop has not been shown yet to display the prompt.

			$networkLocationWizardRegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Network\NwCategoryWizard'

			if (-not (Test-Path $networkLocationWizardRegistryPath)) {
				New-Item $networkLocationWizardRegistryPath -Force -ErrorAction Stop | Out-Null
			}

			if ((Get-ItemProperty $networkLocationWizardRegistryPath).Show -ne 0) {
				Write-Output "`n  Disabling Network Location Wizard..."

				Set-ItemProperty $networkLocationWizardRegistryPath -Name 'Show' -Value 0 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

				Write-Host "`n  Successfully Disabled Network Location Wizard`n" -ForegroundColor Green

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Disabled Network Location Wizard - $(Get-Date)" -ErrorAction SilentlyContinue
			}
		} catch {
			Write-Host "`n  ERROR DISABLING NETWORK LOCATION WIZARD: $_`n" -ForegroundColor Red
		}
	} else {
		try {
			# On Windows 11 24H2, launching "powershell.exe" will now launch the newer Terminal app instead of the old PowerShell GUI app.
			# Setting "HKCU:\Console\%%Startup\DelegationConsole" and "HKCU:\Console\%%Startup\DelegationTerminal" to "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}" will force "powershell.exe" to still launch the PowerShell GUI app for consistency.
			# https://support.microsoft.com/en-us/windows/command-prompt-and-windows-powershell-for-windows-11-6453ce98-da91-476f-8651-5c14d5777c20
	
			$consoleStartupRegistryPath = 'HKCU:\Console\%%Startup'

			if (-not (Test-Path $consoleStartupRegistryPath)) {
				New-Item $consoleStartupRegistryPath -Force -ErrorAction Stop | Out-Null
			}

			$windowsConsoleHostGUID = '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
			if (((Get-ItemProperty $consoleStartupRegistryPath).DelegationConsole -ne $windowsConsoleHostGUID) -or ((Get-ItemProperty $consoleStartupRegistryPath).DelegationTerminal -ne $windowsConsoleHostGUID)) {
				Write-Output "`n  Setting Host Console to Not Always Launch Terminal..."

				if ((Get-ItemProperty $consoleStartupRegistryPath).DelegationConsole -ne $windowsConsoleHostGUID) {
					Set-ItemProperty $consoleStartupRegistryPath -Name 'DelegationConsole' -Value $windowsConsoleHostGUID -Type 'String' -Force -ErrorAction Stop | Out-Null
				}

				if ((Get-ItemProperty $consoleStartupRegistryPath).DelegationTerminal -ne $windowsConsoleHostGUID) {
					Set-ItemProperty $consoleStartupRegistryPath -Name 'DelegationTerminal' -Value $windowsConsoleHostGUID -Type 'String' -Force -ErrorAction Stop | Out-Null
				}

				Write-Host "`n  Successfully Set Host Console to Not Always Launch Terminal`n" -ForegroundColor Green

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set Host Console to Not Always Launch Terminal - $(Get-Date)" -ErrorAction SilentlyContinue
			}
		} catch {
			Write-Host "`n  ERROR SETTING HOST CONSOLE TO NOT ALWAYS LAUNCH TERMINAL: $_`n" -ForegroundColor Red
		}
	}

	try {
		# Setting "HKCU:\SOFTWARE\Policies\Microsoft\Edge\HideFirstRunExperience" to "1" will bypass the fullscreen first run screens for Edge.
		# https://admx.help/?Category=EdgeChromium&Policy=Microsoft.Policies.Edge::HideFirstRunExperience

		$edgePoliciesRegistryPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'

		if (-not (Test-Path $edgePoliciesRegistryPath)) {
			New-Item $edgePoliciesRegistryPath -Force -ErrorAction Stop | Out-Null
		}

		if ((Get-ItemProperty $edgePoliciesRegistryPath).HideFirstRunExperience -ne 1) {
			Write-Output "`n  Disabling Edge First Run Screen..."

			Set-ItemProperty $edgePoliciesRegistryPath -Name 'HideFirstRunExperience' -Value 1 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

			Write-Host "`n  Successfully Disabled Edge First Run Screen`n" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Disabled Edge First Run Screen - $(Get-Date)" -ErrorAction SilentlyContinue
		}
	} catch {
		Write-Host "`n  ERROR DISABLING EDGE FIRST RUN SCREEN: $_`n" -ForegroundColor Red
	}

	try {
		# Setting "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop\Enabled" to "0" will turn off all
		# OneDrive notifications which stops Windows from prompting to "Turn On Windows Backup" to OneDrive with a notification/prompt in the bottom right,
		# which was enabled with the September 2023 Cumulative Updates for both Windows 10 and 11 (the notification seems to appear a few days after install, so wouldn't normally be seen by technicians anyways).
		# https://learn.microsoft.com/en-us/answers/questions/1376997/turn-off-onedrive-backup-notification-via-gpo-or-s#answer-1326409

		$oneDriveNotificationsRegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop'

		if (-not (Test-Path $oneDriveNotificationsRegistryPath)) {
			New-Item $oneDriveNotificationsRegistryPath -Force -ErrorAction Stop | Out-Null
		}

		if ((Get-ItemProperty $oneDriveNotificationsRegistryPath).Enabled -ne 0) {
			Write-Output "`n  Disabling OneDrive Notifications..."

			Set-ItemProperty $oneDriveNotificationsRegistryPath -Name 'Enabled' -Value 0 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

			Write-Host "`n  Successfully Disabled OneDrive Notifications`n" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Disabled OneDrive Notifications - $(Get-Date)" -ErrorAction SilentlyContinue
		}
	} catch {
		Write-Host "`n  ERROR DISABLING ONEDRIVE NOTIFICATIONS: $_`n" -ForegroundColor Red
	}

	try {
		# Setting "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy\LetAppsAccessCamera" (and "LetAppsAccessMicrophone") to "1" will bypass
		# Camera and Microphone permission prompts when launching the "Camera" app to perform the Camera test from QA Helper.
		# https://admx.help/?Category=Windows_10_2016&Policy=Microsoft.Policies.AppPrivacy::LetAppsAccessCamera
		# https://admx.help/?Category=Windows_10_2016&Policy=Microsoft.Policies.AppPrivacy::LetAppsAccessMicrophone

		$appPrivacyRegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'

		if (-not (Test-Path $appPrivacyRegistryPath)) {
			New-Item $appPrivacyRegistryPath -Force -ErrorAction Stop | Out-Null
		}

		if ((Get-ItemProperty $appPrivacyRegistryPath).LetAppsAccessCamera -ne 1) {
			Write-Output "`n  Allowing Camera Access for All Apps..."

			Set-ItemProperty $appPrivacyRegistryPath -Name 'LetAppsAccessCamera' -Value 1 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

			Write-Host "`n  Successfully Allowed Camera Access for All Apps`n" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Allowed Camera Access for All Apps - $(Get-Date)" -ErrorAction SilentlyContinue
		}

		if ((Get-ItemProperty $appPrivacyRegistryPath).LetAppsAccessMicrophone -ne 1) {
			Write-Output "`n  Allowing Microphone Access for All Apps..."

			Set-ItemProperty $appPrivacyRegistryPath -Name 'LetAppsAccessMicrophone' -Value 1 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

			Write-Host "`n  Successfully Allowed Microphone Access for All Apps`n" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Allowed Microphone Access for All Apps - $(Get-Date)" -ErrorAction SilentlyContinue
		}
	} catch {
		Write-Host "`n  ERROR ALLOWING CAMERA OR MICROPHONE ACCESS FOR ALL APPS: $_`n" -ForegroundColor Red
	}


	Write-Output "`n  Quitting System Preparation Tool..."

	for ($stopSysprepAttempt = 0; $stopSysprepAttempt -lt 5; $stopSysprepAttempt ++) {
		try {
			Stop-Process -Name 'sysprep' -ErrorAction Stop

			Write-Host "`n  Successfully Quit System Preparation Tool" -ForegroundColor Green

			break
		} catch {
			if ($stopSysprepAttempt -lt 4) {
				Start-Sleep 1
			} else {
				Write-Host "`n  System Preparation Tool Was Not Running" -ForegroundColor Yellow
			}
		}
	}


	$didSetPowerPlan = $false

	try {
		if ((-not (Get-CimInstance 'Win32_PowerPlan' -Namespace 'ROOT\CIMV2\power' -Filter 'IsActive = True' -ErrorAction Stop).InstanceID.Contains('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')) -or (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power')) -or ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled -ne 0)) {
			Write-Output "`n`n  Setting High Performance Power Plan and Disabling Screen Sleep and Hibernation..."

			Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue

			$powercfgSetactiveExitCode = (Start-Process 'powercfg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-powercfg-setactive-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-powercfg-setactive-Error.txt" -ArgumentList '/setactive', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -ErrorAction Stop).ExitCode
			$powercfgSetactiveError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-setactive-Error.txt"

			if (($powercfgSetactiveExitCode -eq 0) -and ($null -eq $powercfgSetactiveError)) {
				$powercfgChangeAcExitCode = (Start-Process 'powercfg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-powercfg-change-ac-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-powercfg-change-ac-Error.txt" -ArgumentList '/change', 'monitor-timeout-ac', '0' -ErrorAction Stop).ExitCode
				$powercfgChangeAcError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-change-ac-Error.txt"

				if (($powercfgChangeAcExitCode -eq 0) -and ($null -eq $powercfgChangeAcError)) {
					$powercfgChangeDcExitCode = (Start-Process 'powercfg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-powercfg-change-dc-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-powercfg-change-dc-Error.txt" -ArgumentList '/change', 'monitor-timeout-dc', '0' -ErrorAction Stop).ExitCode
					$powercfgChangeDcError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-change-dc-Error.txt"

					if (($powercfgChangeDcExitCode -eq 0) -and ($null -eq $powercfgChangeDcError)) {
						# Disable hibernation during testing so that pressing the power button fully shuts the computer down instead of doing hibernation for "fast startup" which would make the boot script not run on the next "boot".
						$powercfgHibernateOffExitCode = (Start-Process 'powercfg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-powercfg-hibernate-off-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-powercfg-hibernate-off-Error.txt" -ArgumentList '/hibernate', 'off' -ErrorAction Stop).ExitCode
						$powercfgHibernateOffError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-hibernate-off-Error.txt"

						if (($powercfgHibernateOffExitCode -eq 0) -and ($null -eq $powercfgHibernateOffError)) {
							Write-Host "`n  Successfully Set High Performance Power Plan and Disabled Screen Sleep and Hibernation" -ForegroundColor Green

							Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set High Performance Power Plan and Disabled Screen Sleep and Hibernation - $(Get-Date)" -ErrorAction SilentlyContinue

							$didSetPowerPlan = $true
						} else {
							if ($null -eq $powercfgHibernateOffError) {
								$powercfgHibernateOffError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-hibernate-off-Output.txt"
							}

							Write-Host "`n  ERROR DISABLING HIBERNATION: $powercfgHibernateOffError" -ForegroundColor Red
							Write-Host "`n  ERROR: Failed to disable hibernation (powercfg Exit Code = $powercfgHibernateOffExitCode)." -ForegroundColor Red
						}
					} else {
						if ($null -eq $powercfgChangeDcError) {
							$powercfgChangeDcError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-change-dc-Output.txt"
						}

						Write-Host "`n  ERROR CHANGING DC POWERCFG: $powercfgChangeDcError" -ForegroundColor Red
						Write-Host "`n  ERROR: Failed to disable screen sleep on DC power (powercfg Exit Code = $powercfgChangeDcExitCode)." -ForegroundColor Red
					}
				} else {
					if ($null -eq $powercfgChangeAcError) {
						$powercfgChangeAcError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-change-ac-Output.txt"
					}

					Write-Host "`n  ERROR CHANGING AC POWERCFG: $powercfgChangeAcError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to disable screen sleep on AC power (powercfg Exit Code = $powercfgChangeAcExitCode)." -ForegroundColor Red
				}
			} else {
				if ($null -eq $powercfgSetactiveError) {
					$powercfgSetactiveError = Get-Content -Raw "$Env:TEMP\fgSetup-powercfg-setactive-Output.txt"
				}

				Write-Host "`n  ERROR SETTING POWERCFG: $powercfgSetactiveError" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to set High Performance power plan (powercfg Exit Code = $powercfgSetactiveExitCode)." -ForegroundColor Red
			}

			Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue
		} else {
			$didSetPowerPlan = $true
		}
	} catch {
		Write-Host "`n  ERROR CHECKING POWER PLAN OR STARTING POWERCFG: $_" -ForegroundColor Red
	}

	if (-not $didSetPowerPlan) {
		Write-Host "`n  Computer or Screen May Sleep During Testing - CONTINUING ANYWAY - WILL TRY AGAIN ON NEXT REBOOT" -ForegroundColor Yellow
		Start-Sleep 3
	}


	if (Test-Path "$Env:SystemDrive\Install\Scripts\Wi-Fi Profiles\") {
		# Wi-Fi Profiles must be exported with: netsh wlan export profile name="Name" key=clear folder="C:\Path\"
		# The "key=clear" argument is very important because it seems that while the profile with an encrypted password (key) can be successfully imported on another computer,
		# the encrypted password will not actually work and the computer will not connect to the Wi-Fi network.
		# Since Wi-Fi Profiles only need to be added once, and we don't want to leave plain text passwords around,
		# the "Wi-Fi Profiles" directory will be deleted after any profile has successfully been added or Windows Update has run at least once (so Wi-Fi drivers has a chance to get installed).

		$wiFiProfileFiles = Get-ChildItem "$Env:SystemDrive\Install\Scripts\Wi-Fi Profiles\*" -Include '*.xml' -ErrorAction SilentlyContinue

		$didAddAnyProfile = $false

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

				Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue

				try {
					$netshWlanAddProfileExitCode = (Start-Process 'netsh' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-netsh-wlan-add-profile-$thisWiFiProfileName-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-netsh-wlan-add-profile-$thisWiFiProfileName-Error.txt" -ArgumentList 'wlan', 'add', 'profile', "filename=`"$($thisWiFiProfileFile.FullName)`"" -ErrorAction Stop).ExitCode
					$netshWlanAddProfileError = Get-Content -Raw "$Env:TEMP\fgSetup-netsh-wlan-add-profile-$thisWiFiProfileName-Error.txt"

					if (($netshWlanAddProfileExitCode -eq 0) -and ($null -eq $netshWlanAddProfileError)) {
						Write-Host ' ADDED' -ForegroundColor Green

						$didAddAnyProfile = $true

						Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Added Wi-Fi Network Profile: $thisWiFiProfileName - $(Get-Date)" -ErrorAction SilentlyContinue
					} else {
						Write-Host ' FAILED' -NoNewline -ForegroundColor Red
						Write-Host ' (CONTINUING ANYWAY)' -ForegroundColor Yellow

						if ($null -eq $netshWlanAddProfileError) {
							$netshWlanAddProfileError = Get-Content -Raw "$Env:TEMP\fgSetup-netsh-wlan-add-profile-$thisWiFiProfileName-Output.txt"
						}

						if ($null -ne $netshWlanAddProfileError) {
							$netshWlanAddProfileError = $netshWlanAddProfileError.Trim()
						}

						Write-Host "      ERROR ADDING PROFILE (Code $netshWlanAddProfileExitCode): $netshWlanAddProfileError" -ForegroundColor Red

						Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Error Code $netshWlanAddProfileExitCode Adding Wi-Fi Network Profile: $thisWiFiProfileName - $(Get-Date)" -ErrorAction SilentlyContinue
					}
				} catch {
					Write-Host ' FAILED' -NoNewline -ForegroundColor Red
					Write-Host ' (CONTINUING ANYWAY)' -ForegroundColor Yellow
					Write-Host "      ERROR STARTING NETSH: $_" -ForegroundColor Red

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "netsh Error for Wi-Fi Network Profile: $thisWiFiProfileName - $(Get-Date)" -ErrorAction SilentlyContinue
				}
			}

			Write-Host "`n  Finished Adding Wi-Fi Network Profiles" -ForegroundColor Green

			Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue
		}

		if ($didAddAnyProfile -or (Test-Path "$Env:SystemDrive\Install\Windows Update Log.txt")) {
			Remove-Item "$Env:SystemDrive\Install\Scripts\Wi-Fi Profiles" -Recurse -Force -ErrorAction SilentlyContinue
		}
	}


	$didSyncSystemTime = $false

	try {
		Write-Output "`n`n  Syncing System Time..."

		Start-Service 'W32Time' -ErrorAction Stop

		Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue

		$w32tmResyncExitCode = (Start-Process 'W32tm' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-W32tm-resync-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-W32tm-resync-Error.txt" -ArgumentList '/resync', '/force' -ErrorAction Stop).ExitCode
		$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgSetup-W32tm-resync-Error.txt"

		if (($w32tmResyncExitCode -eq 0) -and ($null -eq $w32tmResyncError)) {
			Write-Host "`n  Successfully Synced System Time" -ForegroundColor Green

			$didSyncSystemTime = $true
		} else {
			if ($null -eq $w32tmResyncError) {
				$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgSetup-W32tm-resync-Output.txt"
			}

			Write-Host "`n  ERROR SYNCING SYSTEM TIME: $w32tmResyncError" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to sync system time (W32tm Exit Code = $w32tmResyncExitCode)." -ForegroundColor Red
		}
	} catch {
		Write-Host "`n  ERROR STARTING TIME SERVICE OR W32TM: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: Failed to start system time service." -ForegroundColor Red
	}

	Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue

	if (-not $didSyncSystemTime) {
		Write-Host "`n  System Time May Be Incorrect - CONTINUING ANYWAY - WILL TRY AGAIN ON NEXT REBOOT" -ForegroundColor Yellow
	}


	try {
		if (Get-NetConnectionProfile -ErrorAction Stop | Where-Object NetworkCategory -ne 'Public') {
			Write-Output "`n`n  Setting Network Profiles..."

			try {
				# Even though we've stopped Windows from prompting to set Network Profiles during testing (by disabling Network Location Wizard),
				# make sure they're all set to the more secure "Public" profile anyway since the settings are not reset by Sysprep.

				Get-NetAdapter -Physical | Set-NetConnectionProfile -NetworkCategory 'Public'

				Write-Host "`n  Successfully Set Network Profiles" -ForegroundColor Green

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set Network Profiles - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR SETTING NETWORK PROFILES: $_" -ForegroundColor Red
			}
		}
	} catch {
		Write-Host "`n  ERROR CHECKING NETWORK PROFILES: $_" -ForegroundColor Red
	}


	try {
		Write-Output "`n`n  Emptying Recycle Bin..."

		Clear-RecycleBin -Force -ErrorAction Stop

		Write-Host "`n  Successfully Emptied Recycle Bin" -ForegroundColor Green
	} catch {
		Write-Host "`n  ERROR EMPTYING REYCYLE BIN: $_`n" -ForegroundColor Red
		Write-Host "`n  Failed to empty Recycle Bin - CONTINUING ANYWAY" -ForegroundColor Yellow
	}
} else {
	Write-Output "`n  Preparing to Finish Setting Up Windows..."

	try {
		Stop-Process -Name 'sysprep' -ErrorAction Stop
	} catch {
		# Only try once to quit Sysprep in case it's running, but don't show any error if it's wasn't.
	}

	if (-not $isWindows11) {
		try {
			# PC Health Check app will be installed and automatically opened if/when KB5005463 is installed on Windows 10 (https://support.microsoft.com/en-us/topic/kb5005463-pc-health-check-application-e33cf4e2-49e2-4727-b913-f3c5b1ee0e56),
			# but we don't want that opened so close it since it doesn't matter for our Windows 10 installations (but Windows will generally be rebooted after Windows Updates are installed instead of getting to this code and PC Health Check WILL NOT be automatically re-opened on upon reboot).
			Stop-Process -Name 'PCHealthCheck' -ErrorAction Stop
		} catch {
			# Only try once to quit PCHealthCheck in case it's running, but don't show any error if it's wasn't.
		}
	}

	if ($LastWindowsUpdatesCount -eq '0') {
		Write-Host "`n  No Windows Updates Available - Windows Is Up-to-Date" -ForegroundColor Green
	} elseif ($LastWindowsUpdatesCount -eq 'MaxUpdateCycles') {
		Write-Host "`n  Maximum Windows Update Cycles Run - Windows May Not Be Up-to-Date - CONTINUING ANYWAY" -ForegroundColor Yellow
		Start-Sleep 3 # Sleep for a few seconds to be able to see the issue
	} else {
		Write-Host "`n  Installed $LastWindowsUpdatesCount Windows Updates During Last Update Cycle" -ForegroundColor Green
	}
}


if (-not (Get-LocalUser 'Administrator' -ErrorAction SilentlyContinue).Enabled) {
	Write-Output '' # Line break so we get 2 line breaks for the first attempt but only one after clearing host for any re-attempts after failure.

	for ( ; ; ) {
		# The Administrator account should only be disabled on first boot (booting into Audit enables it to log in and then disables it again right after login):
		# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/audit-mode-overview

		Write-Output "`n  Enabling Administrator Account..."

		try {
			# If Administrator is not enabled/active then you won't be able to log back in if the screen gets locked (but you could reboot to get logged back in).
			Enable-LocalUser 'Administrator' -ErrorAction Stop

			Write-Host "`n  Successfully Enabled Administrator Account" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Enabled Administrator Account - $(Get-Date)" -ErrorAction SilentlyContinue
		} catch {
			Write-Host "`n  ERROR ENABLING ADMINISTRATOR ACCOUNT: $_" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to enable Administrator account." -ForegroundColor Red
		}

		if (-not (Get-LocalUser 'Administrator' -ErrorAction SilentlyContinue).Enabled) {
			Write-Host "`n`n  >>> THE ADMINISTATOR ACCOUNT MUST BE ENABLED TO CONTINUE SETTING UP THIS COMPUTER <<<" -ForegroundColor Yellow
			Write-Host "`n  !!! THIS COMPUTER CANNOT BE SOLD UNTIL SETUP IS COMPLETED SUCCESSFULLY !!!" -ForegroundColor Red
			Write-Host "`n`n  If this issue continues, please inform Free Geek I.T.`n" -ForegroundColor Red

			# Wait until logged in so we can actually focus the script window.
			for ( ; ; ) {
				try {
					Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
					Start-Sleep 1
				} catch {
					break
				}
			}

			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			Read-Host '  Manually Reboot This Computer or Press ENTER to Try Again' | Out-Null
			Clear-Host
		} else {
			break
		}
	}
}


function Install-QAHelper {
	Write-Output '' # Line break so we get 2 line breaks for the first attempt but only one after clearing host for any re-attempts after failure.

	for ( ; ; ) {
		Write-Output "`n  Preparing to Install QA Helper..."

		$qaHelperInstallMode = 'update' # Use update mode to make sure the Shortcuts are recreated since the drive letter will be wrong from being installed in WinPE.

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

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Loaded QA Helper Installer - $(Get-Date)" -ErrorAction SilentlyContinue

					break
				} else {
					throw 'Invalid Installer Script Contents'
				}
			} catch {
				Write-Host "`n  ERROR LOADING QA HELPER INSTALLER: $_" -ForegroundColor Red
				Write-Host '  IMPORTANT: Internet Is Required During Installation Process' -ForegroundColor Red

				if ($downloadAttempt -lt 4) {
					Write-Host "  Load Installer Attempt $($downloadAttempt + 1) of 5 - TRYING AGAIN..." -ForegroundColor Yellow
					Start-Sleep ($downloadAttempt + 1) # Sleep a little longer after each attempt.
				} else {
					Write-Host '  Failed to Load QA Helper Installer After 5 Attempts' -ForegroundColor Yellow
				}
			}
		}

		if ((-not (Test-Path "$Env:SystemDrive\Install\QA Helper\java-jre\bin\javaw.exe")) -or (-not (Test-Path "$Env:SystemDrive\Install\QA Helper\QA_Helper.jar")) -or (-not (Test-Path "$desktopPath\QA Helper.lnk"))) {
			Write-Host "`n`n  >>> QA HELPER MUST BE INSTALLED TO CONTINUE SETTING UP THIS COMPUTER <<<" -ForegroundColor Yellow
			Write-Host "`n  !!! THIS COMPUTER CANNOT BE SOLD UNTIL SETUP IS COMPLETED SUCCESSFULLY !!!" -ForegroundColor Red
			Write-Host "`n`n  If this issue continues, please inform Free Geek I.T.`n" -ForegroundColor Red

			# Wait until logged in so we can actually focus the script window.
			for ( ; ; ) {
				try {
					Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
					Start-Sleep 1
				} catch {
					break
				}
			}

			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			Read-Host '  Manually Reboot This Computer or Press ENTER to Try Again' | Out-Null
			Clear-Host
		} else {
			break
		}
	}
}


function AdjustScreenScaling {
	try {
		# If screen is scaled above 100% (higher than 96 DPI), silently set the screen scaling down 2 steps.
		# Only do this on first run because if the technician needs to adjust it later we don't want to keep changing it back.

		# IMPORTANT NOTES: This must be run after fully logged in because the shortcut simulation to restart the graphics driver doesn't work when on LogonUI.
		# ALSO, this must be run after drivers are installed because the screen ID within PerMonitorSettings is different with and without the drivers installed.

		# Based On: https://www.sysopnotes.com/archives/set-dpi-scale-from-powershell/ (https://github.com/cattanach-mfld/SysOpNotes/blob/master/Modules/ChangeDPI.psm1)

		# Previously checked screen resolution and screen size to determine if scaling should be changed like the original code does, but decided to always scale down 2 steps
		# no matter the resolution or screen size after seeing Windows set scaling to 125% on 1024x768 resolution (but also, that only on a desktop and before the driver was installed).
		# Also, checking screen size does not detect external screens for desktops.
		# If I decide to bring back resolution and screen size checking, here is the code:
		#	$currentHorizontalResolution = (Get-CimInstance 'Win32_VideoController' -Property 'CurrentHorizontalResolution' -ErrorAction Stop).CurrentHorizontalResolution
		#	$monitorBasicDisplayParameters = (Get-CimInstance 'WmiMonitorBasicDisplayParams' -Namespace 'ROOT\WMI' -Property 'MaxHorizontalImageSize', 'MaxVerticalImageSize' -ErrorAction Stop)
		#	$screenSize = [System.Math]::Round(([System.Math]::Sqrt([System.Math]::Pow($monitorBasicDisplayParameters.MaxHorizontalImageSize, 2) + [System.Math]::Pow($monitorBasicDisplayParameters.MaxVerticalImageSize, 2)) / 2.54), 2)

		$appliedDPI = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction Stop).AppliedDPI

		if ($appliedDPI -gt 96) {
			Write-Host "`n`n  Adjusting Screen Scaling..." # NOTE: Can't use Write-Output in function with return value.

			$customScreenScalingRegistryPath = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'

			if (-not (Test-Path $customScreenScalingRegistryPath)) {
				New-Item $customScreenScalingRegistryPath -Force -ErrorAction Stop | Out-Null
			}

			if (-not (Get-ChildItem $customScreenScalingRegistryPath -ErrorAction Stop)) {
				(Get-ChildItem 'HKLM:\System\CurrentControlSet\Control\GraphicsDrivers\Configuration\' -ErrorAction Stop).PSChildName | ForEach-Object {
					New-Item "$customScreenScalingRegistryPath\$_" -Force -ErrorAction Stop | Out-Null
				}
			}

			# Set DpiValue: 4294967294 (0xfffffffe) refers to -2 and 4294967295 (0xffffffff) refers to -1.  These numbers are needed because you can't set a negative number in the Registry, so -1 is max value and so on.
			# -1 and -2 refer to the steps down (25% per step) from the "Recommended" DPI value set by Windows and this can change from screen to screen.
			# If the recommended DPI is 150%, then setting the value to 4294967294 will turn it down 2 steps to 100%.

			# We will always just turn it down 2 steps, if the recommended DPI is 200% this will set it to 150% which is probably good since the screen is probably very high resolution in that case.
			# Also worth noting that turning it down too many steps is not an issue, Windows will just use 100% if it's set too low.
			# If we wanted to always guarantee 100% scaling, we could just go down a large number steps or we could do the math to figure out how many steps down from $appliedDPI are needed.

			(Get-ChildItem $customScreenScalingRegistryPath).PSPath | ForEach-Object {
				Set-ItemProperty $_ -Name 'DpiValue' -Value 4294967294 -Type 'DWord' -Force -ErrorAction Stop | Out-Null
			}

			# INFO ABOUT REBOOTING AFTER SETTING SCREEN SCALING: While the following code is a quick way to make the new screen scaling take effect (and is the same thing that is done when setting screen scaling from Settings app),
			# it is not perfect and there is still weirdness from changing the screen scaling. For example, shortcut badges on desktop icons will not be the right size and also text in QA Helper will not be the right size.
			# And while explorer.exe could be restarted to fix the shorcut badge sizing, that makes the desktop icon positioning incorrect and spaced out too much. In regards to QA Helper, it seem that some of this may just be
			# Java's fault for being bad at honoring the new screen scaling on the fly, but it's also clear with the other examples mentioned that the new screen scaling does not fully take effect in Windows until signing out and back in, or rebooting.
			# We could force a sign out, but then the technician would need to interact to sign back in and QA Helper would not open automatically. So, the simplest option for the best experience is to always reboot after setting screen scaling.
			# And even though we will reboot after setting screen scaling, it doesn't hurt to still do the following code to restart the graphics driver for the quick and imperfect way of making the new screen scaling take effect.

			# Restart the Graphics Driver after setting DpiValue. The following code simulates the keyboard shortcut "Windows + Control + Shift + B" (https://support.microsoft.com/en-us/help/4496075/windows-10-troubleshooting-black-or-blank-screens)
			# Based On: https://stackoverflow.com/questions/57570136/how-to-restart-graphics-drivers-with-powershell-or-c-sharp-without-admin-privile (https://github.com/stefanstranger/PowerShell/blob/master/WinKeys.ps1)

			# NOTE: While we could use the Disable/Enable-PnpDevice method which requires admin privileges since we're in Audit mode,
			# this shortcut is actually quicker and looks cleaner to the user and doesn't make any sounds happen like the Disable/Enable-PnpDevice method does.
			# Also, SendKeys cannot be used for this shortcut since SendKeys can't send the Windows key.

			# Even though we should always be logged in by this point, wait until logged in just in case so the shortcut simulation will work (since is doesn't work when on LogonUI).
			for ( ; ; ) {
				try {
					Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
					Start-Sleep 1
				} catch {
					break
				}
			}

			$keyboardEventFunctionType = Add-Type -PassThru -Name KeybdEvent -MemberDefinition @'
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
'@
			# Key Codes: https://docs.microsoft.com/en-us/dotnet/api/system.windows.forms.keys?view=netcore-3.1
			# 91 = LWin
			# 162 = LControlKey
			# 160 = LShiftKey
			# 66 = B

			$shortcutKeys = 91, 162, 160, 66

			# Shortcut Keys Down
			foreach ($thisShortcutKey in $shortcutKeys) {
				$keyboardEventFunctionType::keybd_event($thisShortcutKey, 0, 1, 0)
			}

			# Shortcut Keys Up
			foreach ($thisShortcutKey in $shortcutKeys) {
				$keyboardEventFunctionType::keybd_event($thisShortcutKey, 0, (1 -bOr 2), 0)
			}

			Write-Host "`n  Successfully Adjusted Screen Scaling" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Adjusted Screen Scaling - $(Get-Date)" -ErrorAction SilentlyContinue

			return $true
		}
	} catch {
		Write-Host "`n  ERROR ADJUSTING SCREEN SCALING: $_" -ForegroundColor Red
	}

	return $false
}


function Install-WindowsUpdates {
	$maximumWindowsUpdateCycleCount = 5
	# Windows Update cycles are tracked (including between reboots) to be able to stop after the specified maximumWindowsUpdateCycleCount (in case some failed driver keep tring to re-install over and over, which happens sometimes).

	if ((Get-Content "$Env:SystemDrive\Install\Windows Update Log.txt" -ErrorAction SilentlyContinue | Measure-Object -Line).Lines -ge $maximumWindowsUpdateCycleCount) {
		# If maximumWindowsUpdateCycleCount has been reached, stop update cycle and uninstall PSWindowsUpdate no matter what.
		# Pass "MaxUpdateCycles" as parameter so a relevant result message can be displayed.
		Start-Process 'powershell' -WindowStyle Maximized -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle Maximized', '-ExecutionPolicy Unrestricted', "-File `"$PSCommandPath`" MaxUpdateCycles" -ErrorAction SilentlyContinue

		exit 0 # MUST exit here so this instance doesn't stay open and continue or show an incorrect error.
	} else {
		Write-Output "`n`n  Checking Windows Update for OS Updates and Drivers..."

		try {
			if (Test-Path "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate\PSWindowsUpdate.psd1") {
				Import-Module "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate" -Force -ErrorAction Stop
			}

			$rebootRequiredAfterWindowsUpdates = $false

			$windowsUpdates = $null

			$windowsUpdates = Get-WindowsUpdate -NotTitle 'Cumulative Update' -ErrorAction Stop

			if ($windowsUpdates.Count -gt 0) {
				Write-Host "`n  $($windowsUpdates.Count) Windows Updates Are Available" -ForegroundColor Green
				Start-Sleep 2

				Clear-Host
				Write-Output "`n  Installing $($windowsUpdates.Count) Windows Updates for OS Updates and Drivers...`n`n`n`n`n" # Add empty lines for PowerShell progress UI

				foreach ($thisWindowsUpdate in $windowsUpdates) {
					# PSWindowsUpdate's RebootRequired field only gets marked as true AFTER an update has been installed, so it's useless for checking if a reboot will be required in advance.
					# Instead, check for any Cumulative updates manually to determine if reboot is required. Also, type 2 is Drivers which we should always reboot for so they all get enabled after installation.
					# NOTE: Cumulative Updates are now excluded, but drivers still require a reboot.
					if ($thisWindowsUpdate.Title.Contains('Cumulative') -or ($thisWindowsUpdate.Type -eq 2)) {
						$rebootRequiredAfterWindowsUpdates = $true
						Write-Host '  This Computer Will Reboot Itself After Windows Updates Are Installed' -ForegroundColor Yellow
						break
					}
				}

				if ($testMode) {
					$windowsUpdates | Format-Table -HideTableHeaders -Wrap @{ Label = '    Update Type'; Expression = {"    $($_.KB)$($_.DriverClass)"} },Size,Title
					Write-Host "  ONLY LISTING WINDOWS UPDATES (NOT INSTALLING) IN TEST MODE`n" -ForegroundColor Yellow
				} else {
					# For whatever reason, using the "Install-WindowsUpdate" alias does not work when imported from "\Install\Scripts\PSWindowsUpdate" rather than being installed.
					Get-WindowsUpdate -NotTitle 'Cumulative Update' -Install -AcceptAll -IgnoreReboot -ErrorAction Stop | Format-Table -HideTableHeaders -Wrap @{ Label = '    Status'; Expression = {"    $($_.Result):"}},@{ Label = 'Update Type'; Expression = {"$($_.KB)$($_.DriverClass)"} },Size,Title

					Add-Content "$Env:SystemDrive\Install\Windows Update Log.txt" "$($windowsUpdates.Count) Installed - $(Get-Date)" -ErrorAction Stop # Log Windows Update finished time to track update cycles to be able to stop after maximumWindowsUpdateCycleCount.
				}

				# DO NOT run another pass of Windows Update HERE because if there was a Cumulative Update that just got installed it will show up again until it's been fully installing during a reboot (this couldn't actually happen anymore because Cumulative Updates are now being excluded to save time, but reboot anyways before running another cycle).
				# Instead, Windows Update will keep running after reboots or new script instances until there are no more updates available.

				if ((-not $rebootRequiredAfterWindowsUpdates) -and (Get-WURebootStatus -Silent)) {
					# If $rebootRequiredAfterWindowsUpdates WAS NOT determinted to be true in advance, double check from PSWindowsUpdate now that it will have the RebootRequired field correctly set to true after installing updates that require rebooting.
					$rebootRequiredAfterWindowsUpdates = $true

					Write-Host "  This Computer Will Reboot Itself Momentarily`n" -ForegroundColor Yellow
				}

				Write-Host "  Finished Installing $($windowsUpdates.Count) Windows Updates" -ForegroundColor Green # No extra line break needed at the beginning because of line breaks in PSWindowsUpdate output.

				# Set screen scaling here so that we can potentially avoid an extra reboot if we are gonna reboot anyway after updates. And if we weren't gonna reboot, now is a good time to do so.
				# Also, setting screen scaling after drivers are installed is important because the screen ID within PerMonitorSettings is different with and without the drivers installed.
				$rebootRequiredAfterAdjustingScreenScaling = AdjustScreenScaling # See comments within function for info about rebooting after setting screen scaling.

				if ($rebootRequiredAfterAdjustingScreenScaling -and (-not $rebootRequiredAfterWindowsUpdates)) {
					$rebootRequiredAfterWindowsUpdates = $true

					Write-Host "`n  This Computer Will Reboot Itself After Adjusting Screen Scaling Momentarily" -ForegroundColor Yellow
				}
			} else {
				Write-Host "`n  No Windows Updates Available - Windows Is Up-to-Date" -ForegroundColor Green

				# PSWindowsUpdate will be uninstalled after no more updates are available in a new PowerShell instance since if we try to uninstall here it will error stating it is currently in use.

				Add-Content "$Env:SystemDrive\Install\QA Helper Log.txt" "Task: Updates Verified - $(Get-Date)" -ErrorAction SilentlyContinue # Automatically mark Windows Update as Verified in QA Helper after all updates have been installed.
			}

			if ($testMode) {
				# Always stop update cycle and uninstall PSWindowsUpdate after one check in test mode since updates won't be installed.

				# Wait until logged in so we can actually focus the script window.
				for ( ; ; ) {
					try {
						Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
						Start-Sleep 1
					} catch {
						break
					}
				}

				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				Read-Host "`n`n  Press ENTER to Finish Setup Without Windows Updates" | Out-Null

				Start-Process 'powershell' -WindowStyle Maximized -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle Maximized', '-ExecutionPolicy Unrestricted', "-File `"$PSCommandPath`" 0" -ErrorAction SilentlyContinue
			} elseif ($rebootRequiredAfterWindowsUpdates) {
				# Wait until logged in so we don't ever restart before Windows is done doing its own setup during the "Preparing Windows" phase.
				for ( ; ; ) {
					try {
						Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
						Start-Sleep 1
					} catch {
						break
					}
				}

				$rebootTimeout = 15

				Write-Output "`n`n  This Computer Will Reboot After Windows Updates in $rebootTimeout Seconds..."
				Write-Host "`n  Or Press Any Key to Reboot Now" -ForegroundColor Cyan

				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				for ($secondsWaited = 0; $secondsWaited -lt $rebootTimeout; $secondsWaited ++) {
					if ($Host.UI.RawUI.KeyAvailable) {
						break
					}

					Start-Sleep 1
				}

				Restart-Computer
			} else {
				# If Reboot isn't required, just relaunch this script in a new powershell instance to be able to uninstall PSWindowsUpdate

				Start-Sleep 3 # Sleep for a few seconds to be able to see last results before this window closes.

				# Pass arg for LastWindowsUpdatesCount to determine if Windows is Up-to-Date to stop update cycle and uninstall PSWindowsUpdate.
				Start-Process 'powershell' -WindowStyle Maximized -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle Maximized', '-ExecutionPolicy Unrestricted', "-File `"$PSCommandPath`" $($windowsUpdates.Count)" -ErrorAction SilentlyContinue
			}

			exit 0 # Not sure if exit is necessary after Restart-Computer but doesn't hurt & MUST exit here if not restarting so this instance doesn't stay open and continue or show an incorrect error.
		} catch {
			Write-Host "`n  ERROR RUNNING WINDOWS UPDATE: $_" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to finish running Windows Update." -ForegroundColor Red

			Write-Host "`n`n  IMPORTANT: Make sure Ethernet cable is plugged securely or Wi-Fi is connected and try again." -ForegroundColor Red
		}
	}
}


# Only run App Installations and start Windows Update cycle if QA Helper shortcut is not on the Desktop (such as, after first boot from WinPE).

if (-not (Test-Path "$desktopPath\QA Helper.lnk")) {
	[xml]$smbCredentialsXML = $null

	try {
		[xml]$smbCredentialsXML = Get-Content "$Env:SystemDrive\Install\Scripts\smb-credentials.xml" -ErrorAction Stop

		if ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.ip) {
			throw 'NO RESOURCES SHARE IP'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.shareName) {
			throw 'NO RESOURCES SHARE NAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.username) {
			throw 'NO RESOURCES SHARE USERNAME'
		} elseif ($null -eq $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.password) {
			throw 'NO RESOURCES SHARE PASSWORD'
		}
	} catch {
		Write-Host "`n`n  ERROR RETRIEVING SMB CREDENTIALS: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: REQUIRED `"smb-credentials.xml`" DOES NOT EXISTS OR HAS INVALID CONTENTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		Read-Host '  Press ENTER to Exit' | Out-Null

		exit 2
	}

	$smbServerIP = $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.ip
	$smbShare = "\\$smbServerIP\$($smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.shareName)"
	$smbUsername = "$smbServerIP\$($smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.username)" # Domain must be prefixed in any username.
	$smbPassword = $smbCredentialsXML.smbCredentials.resourcesReadOnlyShare.password

	$didInstallApps = $false # Keep track of if apps were successfully installed in a previous loop to not unnecessarily reinstall them.

	Remove-Item "$Env:SystemDrive\Install\Windows Update Log.txt" -Force -ErrorAction SilentlyContinue # Delete Windows Update Log to start update cycle over if Setup is being manually re-run.

	for ( ; ; ) {
		if ($testMode) {
			Write-Output ''
		} else {
			Clear-Host
		}

		FocusScriptWindow

		if ($didInstallApps) {
			Write-Output "`n  Preparing to Finish Setting Up Windows..."
		} else {
			Write-Output "`n  Preparing to Setup Windows..."
		}

		$appInstallersUSBpath = $null
		# Check all drives for "windows-resources" folder (a better version of https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-identify-drive-letters)
		# Do these checks within the loop because it seems that sometimes the USB isn't mounted on boot and needs to be unplugged and replugged and the technician needs to be able to try again.
		$allVolumes = Get-Volume # DO NOT USE " | Where-Object DriveType -eq 'Removable'" because NVMe M.2 enclosures mount as "Fixed" drives.
		foreach ($thisVolume in $allVolumes) {
			$thisPossibleAppInstallersUSBpath = "$($thisVolume.DriveLetter):\windows-resources\app-installers"

			if (Test-Path $thisPossibleAppInstallersUSBpath) {
				$appInstallersUSBpath = $thisPossibleAppInstallersUSBpath

				break
			}
		}

		$lastTaskSucceeded = $true

		$appInstallersPath = "$smbShare\windows-resources\app-installers"

		$usbAppInstallersAccessible = $false

		if ($null -ne $appInstallersUSBpath) {
			Write-Host "`n  Setting Up Windows via USB" -ForegroundColor Green

			$appInstallersPath = $appInstallersUSBpath

			$usbAppInstallersAccessible = $true
		}

		$localServerResourcesAccessible = $false

		try {
			$localServerResourcesAccessible = (Test-Connection $smbServerIP -Count 1 -Quiet -ErrorAction Stop)
		} catch {
			Write-Host "`n  ERROR CONNECTING TO LOCAL FREE GEEK SERVER: $_" -ForegroundColor Red
		}

		if ($localServerResourcesAccessible) {
			Write-Host "`n  Successfully Connected to Local Free Geek Server" -ForegroundColor Green
		} elseif (-not $usbAppInstallersAccessible) {
			Write-Host "`n  ERROR: Failed to locate app installers on USB and failed connect to local Free Geek server." -ForegroundColor Red

			$lastTaskSucceeded = $false
		}

		if ($lastTaskSucceeded -and $localServerResourcesAccessible) {
			Write-Host "`n`n  Mounting SMB Share for App Installers - PLEASE WAIT, THIS MAY TAKE A MOMENT..." -NoNewline

			# Try to connect to SMB Share 5 times before stopping to show error to user because sometimes it takes a few attempts, or it sometimes just fails and takes more manual reattempts before it finally works.
			for ($smbMountAttempt = 0; $smbMountAttempt -lt 5; $smbMountAttempt ++) {
				try {
					# If we don't get the New-SmbMapping return value it seems to be asynchronous, which results in messages being show out of order result and also result in a failure not being detected.
					$smbMappingStatus = (New-SmbMapping -RemotePath $smbShare -UserName $smbUsername -Password $smbPassword -Persistent $false -ErrorAction Stop).Status

					if ($smbMappingStatus -eq 0) {
						Write-Host "`n`n  Successfully Mounted SMB Share for App Installers" -ForegroundColor Green
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

						$lastTaskSucceeded = $false
					}
				}
			}
		}

		if ($lastTaskSucceeded -and (-not $didInstallApps)) {
			if ($noAppsMode) {
				$didInstallApps = $true
			} else {
				Write-Output "`n`n  Locating App Installer Files..."

				$standardAppInstallersPath = "$appInstallersPath\Standard"
				if (-not (Test-Path $standardAppInstallersPath)) {
					$standardAppInstallersPath = $appInstallersPath
				}

				$appInstallerFiles = Get-ChildItem "$standardAppInstallersPath\*" -Include '*.msi', '*.exe' -ErrorAction SilentlyContinue | Sort-Object -Property 'Length' -Descending

				if ($extraAppsMode -and (Test-Path "$appInstallersPath\Extra")) {
					$appInstallerFiles += Get-ChildItem "$appInstallersPath\Extra\*" -Include '*.msi', '*.exe' -ErrorAction SilentlyContinue | Sort-Object -Property 'Length' -Descending
				}

				$driversCacheModelNameFilePath = "$Env:SystemDrive\Install\Drivers Cache Model Name.txt" # This file is created by QA Helper in WinPE using its detailed model info. Use it here to check manufacturers since it will always be cleaned up and consistent.
				if (-not (Test-Path $driversCacheModelNameFilePath)) {
					$driversCacheModelNameFilePath = "$Env:SystemDrive\Install\Drivers Cache Model Path.txt" # This is the old filename from when paths were specified instead of a filename.
				}

				$manufacturerName = ''
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
							$manufacturerName = $driversCacheModelNameFileContents.Split(' ')[0]
							$appInstallersPathForManufacturer = "$appInstallersPath\$manufacturerName"

							if (Test-Path $appInstallersPathForManufacturer) { # Check for and include manufacturer specific apps.
								$appInstallerFiles += Get-ChildItem "$appInstallersPathForManufacturer\*" -Include '*.msi', '*.exe' -ErrorAction SilentlyContinue | Sort-Object -Property 'Length' -Descending
							}
						}
					}
				}

				if ($cpuInfo.Manufacturer -and $cpuInfo.Manufacturer.ToUpper().Contains('INTEL') -and ($manufacturerName -ne 'Intel') -and (Test-Path "$appInstallersPath\Intel")) {
					# "Manufacturer" should be "GenuineIntel" for all Intel processors, but do a case-insenstive check anything that contains "INTEL" just to be safe.
					# Also, skip this if computer manufacturer/brand is "Intel" (such as for NUCs) since the "$appInstallersPath\Intel" folder would already have been added above.
					# FUTURE NOTE: If there is ever an issue where different apps need to be installed for Intel brand systems vs any system with an Intel CPU this could be adjusted to be an "Intel CPU" folder instead of just and "Intel" folder which could be just for Intel brand systems.

					# Always install "Intel Processor Diagnostic Tool" (IPDT) on any computers with Intel processors (which is the only app the "Intel" folder currently contains).
					# This app is *installed* instead of included in "Diagnostic Tools" because even if the custom working directory is set correctly, the main app will launch and start,
					# BUT the individual test exe's will fail with "could not load DetectUtils64.dll" which is in the working directory and it should be checking in, but seem to instead be checking for a hardcoded path within "Program Files".
					# Also, IPDT will always be *uninstalled* in "Complete Windows" script if it was installed.
					# NOTE: If in "ipdtMode", then IPDT will be launched instead of "QA Helper" when this script is finished (and on each boot).

					$appInstallerFiles += Get-ChildItem "$appInstallersPath\Intel\*" -Include '*.msi', '*.exe' -ErrorAction SilentlyContinue | Sort-Object -Property 'Length' -Descending
				}

				if (($null -ne $appInstallerFiles) -and ($appInstallerFiles.Count -gt 0)) {
					Write-Host "`n  Successfully Located $($appInstallerFiles.Count) App Installer Files" -ForegroundColor Green
				} else {
					$lastTaskSucceeded = $false
				}

				if ($lastTaskSucceeded -and ($null -ne $appInstallerFiles)) {
					foreach ($thisAppInstallerFile in $appInstallerFiles) {
						CloseStartMenuOnFirstBootOfWindows11 # Only close the Start menu (without FocusScriptWindow) before each installation (which opens automatically on first login on Windows 11) so that the installer window is visible since we don't know exactly when the Desktop will be loaded.

						try {
							$thisInstallerNameParts = $thisAppInstallerFile.BaseName.Split('_')
							$thisAppName = $thisInstallerNameParts[0]

							$thisAppVersion = ''
							if (($thisInstallerNameParts.Count -gt 1) -and ($thisInstallerNameParts[1] -Match '^\d[.\d]*$')) {
								$thisAppVersion = " $($thisInstallerNameParts[1])"
							}

							Write-Output "`n`n  Installing $thisAppName$thisAppVersion..."

							Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue

							$appInstallExitCode = 9999
							if ($thisAppInstallerFile.Extension -eq '.msi') {
								$appInstallExitCode = (Start-Process 'msiexec' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-$thisAppName-installer-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-$thisAppName-installer-Error.txt" -ArgumentList '/package', "`"$($thisAppInstallerFile.FullName)`"", '/passive' -ErrorAction Stop).ExitCode
							} elseif ($thisAppInstallerFile.Extension -eq '.exe') {
								$silentExeInstallationArgument = '/S'
								if ($thisAppName -eq 'Dropbox') { # https://help.dropbox.com/installs/enterprise-installer
									$silentExeInstallationArgument = '/NOLAUNCH'
								} elseif ($thisAppName -eq 'Lenovo System Update') {
									$silentExeInstallationArgument = '/SILENT'
								}

								$appInstallExitCode = (Start-Process $thisAppInstallerFile -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgSetup-$thisAppName-installer-Output.txt" -RedirectStandardError "$Env:TEMP\fgSetup-$thisAppName-installer-Error.txt" -ArgumentList $silentExeInstallationArgument -ErrorAction Stop).ExitCode
							}
							$appInstallError = Get-Content -Raw "$Env:TEMP\fgSetup-$thisAppName-installer-Error.txt"

							if ((($appInstallExitCode -eq 0) -or ($appInstallExitCode -eq 1603)) -and ($null -eq $appInstallError)) {
								if ($appInstallExitCode -eq 1603) { # https://learn.microsoft.com/en-us/troubleshoot/windows-server/application-management/msi-installation-error-1603
									# This "error" seems to happen when re-install an MSI *if and only if* the filename is different from the MSI that was originally installed.
									Write-Host "`n  Already Installed $thisAppName$thisAppVersion" -ForegroundColor Yellow

									Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Already Installed $thisAppName$thisAppVersion - $(Get-Date)" -ErrorAction SilentlyContinue
								} else {
									Write-Host "`n  Successfully Installed $thisAppName$thisAppVersion" -ForegroundColor Green

									Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Installed $thisAppName$thisAppVersion - $(Get-Date)" -ErrorAction SilentlyContinue
								}
							} else {
								if ($null -eq $appInstallError) {
									$appInstallError = Get-Content -Raw "$Env:TEMP\fgSetup-$thisAppName-installer-Output.txt"
								}

								Write-Host "`n  ERROR INSTALLING APP: $appInstallError" -ForegroundColor Red
								Write-Host "`n  ERROR: Failed to install $thisAppName$thisAppVersion (Installer Exit Code = $appInstallExitCode)." -ForegroundColor Red

								$lastTaskSucceeded = $false

								break
							}
						} catch {
							Write-Host "`n  ERROR STARTING APP INSTALLER: $_" -ForegroundColor Red
							Write-Host "`n  ERROR: Failed to install $($thisAppInstallerFile.BaseName)." -ForegroundColor Red

							$lastTaskSucceeded = $false

							break
						}
					}

					FocusScriptWindow # Take focus after installations are complete to make sure script window is front since the installers took focus.

					Remove-Item "$Env:TEMP\fgSetup-*.txt" -Force -ErrorAction SilentlyContinue
				} else {
					Write-Host "`n  ERROR: Failed to locate any App installation files within `"$appInstallersPath`"." -ForegroundColor Red
				}

				if ($lastTaskSucceeded) {
					$didInstallApps = $true
				}
			}
		}

		if ($localServerResourcesAccessible) {
			Remove-SmbMapping -RemotePath $smbShare -Force -UpdateProfile -ErrorAction SilentlyContinue # Done with SMB Share now, so remove it.
		}

		$waitForPreparingWindowsSeconds = 0
		$didRestartExplorer = $false

		# The following loop is to workaround an in issue in Win 10 20H2. I am not sure if it's fixed in 21H1 but I've left it in place since it won't do anything even if it's no longer necessary.
		for ( ; ; ) {
			try {
				Get-Process 'LogonUI' -ErrorAction Stop | Out-Null

				if ((-not $didRestartExplorer) -or (($waitForPreparingWindowsSeconds % 10) -eq 0)) {
					# This is here to catch an odd issue that seems to happen occasionally in Win 10 20H2 (never noticed it in Win 10 2004) where Windows stays on the "Preparing Windows" screen for an excessively long time (like for 8 MINUTES LONGER than a normal setup).
					# I noticed that whenever this happened, by the time Windows finally did get to the Desktop, the taskbar was not fully set up. When clicking the Start menu, a progress display would appear for a moment and then the taskbar would get setup.
					# After some more experimentation when this happened, I tried restarting explorer.exe instead of clicking the Start menu to see if that would properly set up the taskbar as well, and it did!
					# Then I had the thought that maybe when this long delay was happening because the "Preparing Windows" phase was simply waiting for the taskbar to get setup and only finally getting to the Desktop after giving up after some long timeout.
					# So, I experimented with restarting explorer.exe while STILL ON the "Preparing Windows" screen instead of waiting until the Desktop was loaded...
					# Wonderfully, this seemed to cause the taskbar to get setup properly while still on "Preparing Windows" screen and the Desktop was properly loaded just a FEW SECONDS after manually restarting explorer.exe here.
					# During one timed test, when NOT manually restarting explorer.exe here, Windows stayed on the "Preparing Windows" screen for another 8 MINUTES from this point before finally getting to the Desktop.
					# So, this will not only properly setup the taskbar when it fails to setup on its own during the "Preparing Windows" phase, but will also allow Windows to finish the "Preparing Windows" phase MUCH MORE QUICKLY when this issue occurs.

					# If the taskbar got setup properly on its own during the "Preparing Windows" phase, this will not get run because LogonUI will not still be running by this point.
					# Under normal circumstances when everything works properly, the "Preparing Windows" phase should finish and get to the Desktop during the app installations in this script (the previous task before this point).

					# Just ONE time, I saw that Windows stayed on the "Preparing Windows" screen for a very long time and the taskbar was not fully set up even AFTER this code ran.
					# At the time, this code was only set to run once and did not fail if explorer.exe happened to not be running yet (I assumed explorer.exe would always be running by the time this script ran).
					# Since I couldn't easily reproduce this one occurence, I solved for the possibility that explorer.exe was not running yet by not marking $didRestartExplorer as $true in that case,
					# as well as allowed this code to restart explorer.exe every 10 seconds if Windows is still on the "Preparing Windows" screen even after already restarting explorer.exe before.
					# Hopefully, whether the situation was that explorer.exe wasn't running yet, or that explorer.exe got restarted too early in the the "Preparing Windows" phase to properly setup the taskbar,
					# or that explorer.exe needed to be restarted multiple times for some other reason, these changes should solve it.

					try {
						Stop-Process -Name 'explorer' -ErrorAction Stop # This will actually restart explorer.exe rather than just stopping it.
						$didRestartExplorer = $true

						Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Restarted Explorer While Preparing Windows - $(Get-Date)" -ErrorAction SilentlyContinue
					} catch {
						# Stop-Process will error if explorer.exe is not running yet, so $didRestartExplorer will not be set as $true and we can try again.
						Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Explorer Needs Restart While Preparing Windows but Not Running Yet - $(Get-Date)" -ErrorAction SilentlyContinue
					}
				}

				Start-Sleep 1
				$waitForPreparingWindowsSeconds ++
			} catch {
				break
			}
		}

		if ($didRestartExplorer) {
			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Finished Preparing Windows After Restarting Explorer - $(Get-Date)" -ErrorAction SilentlyContinue

			FocusScriptWindow # Make sure script window is focused since we weren't logged on any of the previous focus calls, but now we are.

			Start-Sleep 2 # Sleep for a couple seconds to be able to see last results before continuing.
		}

		if (-not $lastTaskSucceeded) {
			Write-Host "`n`n  IMPORTANT: Unplug and re-plug the USB drive and try again. " -ForegroundColor Red
			Write-Host "`n  ALSO IMPORTANT: Make sure Ethernet cable is plugged securely and try again." -ForegroundColor Yellow
		}

		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Setting Up Diagnostic Tools and Shortcuts..."
			# NOTE: All of the following Shortcut creation and other Diagnostic Tool setup tasks are NOT logged to
			# the console individually since it's just lots of very quick tasks (but are each logged to the file).
			# Although, if any one of the tasks error that will be shown and setup still stop.

			try {
				if (Test-Path "$desktopPath\Diagnostic Tools") {
					Remove-Item "$desktopPath\Diagnostic Tools" -Recurse -Force -ErrorAction Stop
				}

				New-Item -ItemType 'Directory' -Path "$desktopPath\Diagnostic Tools" -ErrorAction Stop | Out-Null

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created Diagnostic Tools Folder on Desktop - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING DIAGNOSTIC TOOLS FOLDER ON DESKTOP: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:ProgramFiles\Intel Corporation\Intel Processor Diagnostic Tool 64bit\Win-IPDT64.exe")) {
			try {
				$ipdtGuiConfigPath = "$Env:ProgramFiles\Intel Corporation\Intel Processor Diagnostic Tool 64bit\ipdt_gui_config.xml"
				[xml]$ipdtGuiConfigXML = Get-Content $ipdtGuiConfigPath -ErrorAction Stop
				$ipdtGuiConfigXML.ipdt_gui.IPDTAutoUpdate = 'NO'
				$ipdtGuiConfigXML.Save($ipdtGuiConfigPath)

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set Intel Processor Diagnostic Tool to Not Check for Updates - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR SETTING INTEL PROCESSOR DIAGNOSTIC TOOL TO NOT CHECK FOR UPDATES: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}

			if ($lastTaskSucceeded -and (Test-Path "$Env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Intel Processor Diagnostic Tool 64bit.lnk")) {
				try {
					if (Test-Path "$Env:PUBLIC\Desktop\Intel Processor Diagnostic Tool 64bit.lnk") { # Remove default IPDT shortcut from Public folder Desktop since it will be copied into the Diagnostic Tools folders on the Desktop and within the Install folder.
						Remove-Item "$Env:PUBLIC\Desktop\Intel Processor Diagnostic Tool 64bit.lnk" -Force -ErrorAction Stop
					}

					if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Intel Processor Diagnostic Tool.lnk") {
						Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\Intel Processor Diagnostic Tool.lnk" -Force -ErrorAction Stop
					}

					if (Test-Path "$desktopPath\Intel Processor Diagnostic Tool.lnk") {
						Remove-Item "$desktopPath\Intel Processor Diagnostic Tool.lnk" -Force -ErrorAction Stop
					}

					Copy-Item "$Env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Intel Processor Diagnostic Tool 64bit.lnk" "$Env:SystemDrive\Install\Diagnostic Tools\Intel Processor Diagnostic Tool.lnk" -Force -ErrorAction Stop
					Copy-Item "$Env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Intel Processor Diagnostic Tool 64bit.lnk" "$desktopPath\Diagnostic Tools\Intel Processor Diagnostic Tool.lnk" -Force -ErrorAction Stop

					if ($ipdtMode) {
						# If in "ipdtMode" (which will launch IPDT instead of "QA Helper" when this script is finished, and on each boot), also copy the IPDT Shortcut onto
						# the user Desktop (and rename it to be a bit cleaner than the default shortcut that was in the Public folder Destkop) for easy re-launch if needed.
						Copy-Item "$Env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Intel Processor Diagnostic Tool 64bit.lnk" "$desktopPath\Intel Processor Diagnostic Tool.lnk" -Force -ErrorAction Stop

					}

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created Intel Processor Diagnostic Tool Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
				} catch {
					Write-Host "`n  ERROR MOVING INTEL PROCESSOR DIAGNOSTIC TOOL SHORTCUT INTO DIAGNOSTIC TOOLS FOLDER ON DESKTOP: $_" -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\GPU-Z.exe")) {
			try {
				# Set Registry key to make "GPU-Z" run in Standalone Mode without prompting for install on launch and also to not check for updates which shows a notification below the window.
				# https://www.techpowerup.com/forums/threads/how-to-gpu-z-to-run-option-to-install.191730/#post-2988383

				$gpuzRegistryPath = 'HKCU:\SOFTWARE\techPowerUp\GPU-Z'

				if (-not (Test-Path $gpuzRegistryPath)) {
					New-Item $gpuzRegistryPath -Force -ErrorAction Stop | Out-Null
				}

				if ((Get-ItemProperty $gpuzRegistryPath).Install_Dir -ne 'no') {
					Set-ItemProperty $gpuzRegistryPath -Name 'Install_Dir' -Value 'no' -Type 'String' -Force -ErrorAction Stop | Out-Null

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set GPU-Z to Standalone Mode - $(Get-Date)" -ErrorAction SilentlyContinue
				}

				if ((Get-ItemProperty $gpuzRegistryPath).CheckForUpdates -ne 0) {
					Set-ItemProperty $gpuzRegistryPath -Name 'CheckForUpdates' -Value 0 -Type 'DWord' -Force -ErrorAction Stop | Out-Null

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Set GPU-Z to Not Check for Updates - $(Get-Date)" -ErrorAction SilentlyContinue
				}
			} catch {
				Write-Host "`n  ERROR SETTING GPU-Z TO STANDALONE MODE OR TO NOT CHECK FOR UPDATES: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}

			if ($lastTaskSucceeded) {
				try {
					$gpuzShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$desktopPath\Diagnostic Tools\GPU-Z.lnk")
					$gpuzShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\GPU-Z.exe"
					$gpuzShortcut.Save()

					if (-not (Test-Path "$desktopPath\Diagnostic Tools\GPU-Z.lnk")) {
						throw "Shortcut Not Created: $desktopPath\Diagnostic Tools\GPU-Z.lnk"
					}

					if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\GPU-Z.lnk") {
						Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\GPU-Z.lnk" -Force -ErrorAction Stop
					}

					if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs") {
						Copy-Item "$desktopPath\Diagnostic Tools\GPU-Z.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\GPU-Z.lnk" -Force -ErrorAction Stop
					} else {
						throw "User Start Menu Programs Folder Does Not Exist ($Env:APPDATA\Microsoft\Windows\Start Menu\Programs)"
					}

					Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created GPU-Z Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
				} catch {
					Write-Host "`n  ERROR CREATING GPU-Z SHORTCUT: $_" -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\btVersion_x64.exe")) {
			try {
				$btVersionShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$desktopPath\Diagnostic Tools\Bluetooth Version Finder.lnk")
				$btVersionShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\btVersion_x64.exe"
				$btVersionShortcut.Save()

				if (-not (Test-Path "$desktopPath\Diagnostic Tools\Bluetooth Version Finder.lnk")) {
					throw "Shortcut Not Created: $desktopPath\Diagnostic Tools\Bluetooth Version Finder.lnk"
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Bluetooth Version Finder.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Bluetooth Version Finder.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$desktopPath\Diagnostic Tools\Bluetooth Version Finder.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Bluetooth Version Finder.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created Bluetooth Version Finder Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING BLUETOOTH VERSION FINDER SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\WhyNotWin11.exe")) {
			try {
				$whyNotWin11Shortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$desktopPath\Diagnostic Tools\WhyNotWin11.lnk")
				$whyNotWin11Shortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\WhyNotWin11.exe"
				$whyNotWin11Shortcut.Save()

				if (-not (Test-Path "$desktopPath\Diagnostic Tools\WhyNotWin11.lnk")) {
					throw "Shortcut Not Created: $desktopPath\Diagnostic Tools\WhyNotWin11.lnk"
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\WhyNotWin11.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\WhyNotWin11.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$desktopPath\Diagnostic Tools\WhyNotWin11.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\WhyNotWin11.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created WhyNotWin11 Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING WHYNOTWIN11 SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}

			if (Test-Path "$Env:SystemDrive\Install\Scripts\Windows 11 Supported Processors Lists\SupportedProcessorsIntel.txt") {
				$whyNotWin11LocalAppDataFolderPath = "$Env:LOCALAPPDATA\WhyNotWin11"
				if (Test-Path $whyNotWin11LocalAppDataFolderPath) {
					Remove-Item $whyNotWin11LocalAppDataFolderPath -Recurse -Force -ErrorAction Stop
				}

				New-Item -ItemType 'Directory' -Path $whyNotWin11LocalAppDataFolderPath -ErrorAction Stop | Out-Null

				Copy-Item "$Env:SystemDrive\Install\Scripts\Windows 11 Supported Processors Lists\SupportedProcessors*.txt" $whyNotWin11LocalAppDataFolderPath -Force -ErrorAction Stop

				New-Item -ItemType 'Directory' -Path "$whyNotWin11LocalAppDataFolderPath\Langs" -ErrorAction Stop | Out-Null # If the "Langs" folder doesn't exist, WhyNotWin11 will overwrite the supported processor lists with its older embedded lists.
				Set-Content "$whyNotWin11LocalAppDataFolderPath\Langs\version" '0' # The language version file must exist for WhyNotWin11 to copy in the language files. Setting the value to "0" so it will be a version that will always be outdated so WhyNotWin11 will update the language files.

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Updated Windows 11 Supported Processors Lists for WhyNotWin11 - $(Get-Date)" -ErrorAction SilentlyContinue
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo\DiskInfo64.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk" -Force -ErrorAction Stop
				}

				$crystalDiskInfoShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk")
				$crystalDiskInfoShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo\DiskInfo64.exe"
				$crystalDiskInfoShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo"
				$crystalDiskInfoShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\CrystalDiskInfo.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskInfo.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskInfo.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskInfo.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskInfo.lnk" "$desktopPath\Diagnostic Tools\CrystalDiskInfo.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created CrystalDiskInfo Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING CRYSTALDISKINFO SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark\DiskMark64.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk" -Force -ErrorAction Stop
				}

				$crystalDiskMarkShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk")
				$crystalDiskMarkShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark\DiskMark64.exe"
				$crystalDiskMarkShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark"
				$crystalDiskMarkShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\CrystalDiskMark.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskMark.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskMark.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\CrystalDiskMark.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\CrystalDiskMark.lnk" "$desktopPath\Diagnostic Tools\CrystalDiskMark.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created CrystalDiskMark Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING CRYSTALDISKMARK SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView\BatteryInfoView.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk" -Force -ErrorAction Stop
				}

				$batteryInfoViewkShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk")
				$batteryInfoViewkShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView\BatteryInfoView.exe"
				$batteryInfoViewkShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\BatteryInfoView.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\BatteryInfoView.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\BatteryInfoView.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\BatteryInfoView.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\BatteryInfoView.lnk" "$desktopPath\Diagnostic Tools\BatteryInfoView.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created BatteryInfoView Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING BATTERYINFOVIEW SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk" -Force -ErrorAction Stop
				}

				$openHardwareMonitorShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk")
				$openHardwareMonitorShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.exe"
				$openHardwareMonitorShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor"
				$openHardwareMonitorShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\Open Hardware Monitor.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Open Hardware Monitor.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Open Hardware Monitor.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Open Hardware Monitor.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\Open Hardware Monitor.lnk" "$desktopPath\Diagnostic Tools\Open Hardware Monitor.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created OpenHardwareMonitor Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue

				# Also set "OpenHardwareMonitor.config" to always open in top left corner with a reasonable window size and the plot in the bottom of the window if revealed and also do not minimize to tray so that the window can be re-opened if minimized when explorer isn't running.
				Set-Content "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.config" @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="mainForm.Location.X" value="0" />
    <add key="mainForm.Location.Y" value="0" />
    <add key="mainForm.Width" value="500" />
    <add key="mainForm.Height" value="800" />
    <add key="plotLocation" value="1" />
    <add key="minTrayMenuItem" value="false" />
  </appSettings>
</configuration>
'@ -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING OPENHARDWAREMONITOR SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench 6\Geekbench 6.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk" -Force -ErrorAction Stop
				}

				$geekbenchShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk")
				$geekbenchShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench 6\Geekbench 6.exe"
				$geekbenchShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench 6"
				$geekbenchShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\Geekbench.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Geekbench.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Geekbench.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Geekbench.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\Geekbench.lnk" "$desktopPath\Diagnostic Tools\Geekbench.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created Geekbench Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING GEEKBENCH SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FurMark\FurMark_GUI.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk" -Force -ErrorAction Stop
				}

				$furMarkShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk")
				$furMarkShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\FurMark\FurMark_GUI.exe"
				$furMarkShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\FurMark"
				$furMarkShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\FurMark.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FurMark.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FurMark.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FurMark.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\FurMark.lnk" "$desktopPath\Diagnostic Tools\FurMark.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created FurMark Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING FURMARK SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\PerformanceTest64.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk" -Force -ErrorAction Stop
				}

				$performanceTestShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk")
				$performanceTestShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\PerformanceTest64.exe"
				$performanceTestShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest"
				$performanceTestShortcut.WindowStyle = 3 # Maximized Windows Style
				$performanceTestShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\PerformanceTest.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\PerformanceTest.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\PerformanceTest.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\PerformanceTest.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest.lnk" "$desktopPath\Diagnostic Tools\PerformanceTest.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created PerformanceTest Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING PERFORMANCETEST SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded -and (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FanControl\FanControl.exe")) {
			try {
				if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk") {
					Remove-Item "$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk" -Force -ErrorAction Stop
				}

				$fanControlShortcut = (New-Object -ComObject Wscript.Shell).CreateShortcut("$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk")
				$fanControlShortcut.TargetPath = "$Env:SystemDrive\Install\Diagnostic Tools\FanControl\FanControl.exe"
				$fanControlShortcut.WorkingDirectory = "$Env:SystemDrive\Install\Diagnostic Tools\FanControl"
				$fanControlShortcut.Save()

				if (-not (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk")) {
					throw 'Shortcut Not Created: \Install\Diagnostic Tools\FanControl.lnk'
				}

				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FanControl.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FanControl.lnk" -Force -ErrorAction Stop
				}

				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk" "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\FanControl.lnk" -Force -ErrorAction Stop
				Copy-Item "$Env:SystemDrive\Install\Diagnostic Tools\FanControl.lnk" "$desktopPath\Diagnostic Tools\FanControl.lnk" -Force -ErrorAction Stop

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Created FanControl Shortcuts - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR CREATING FANCONTROL SHORTCUT: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			Write-Host "`n  Successfully Set Up Diagnostic Tools and Shortcuts" -ForegroundColor Green
		}

		if ($lastTaskSucceeded -and (-not (Test-Path "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate\PSWindowsUpdate.psd1")) -and (-not (Get-Module -ListAvailable -Name PSWindowsUpdate))) {
			Write-Output "`n`n  Installing Automated Windows Update Tool..."

			try {
				# Will use the local PSWindowsUpdate copy if it exists, otherwise install it from NuGet.
				$psWindowsUpdateNuPkgs = Get-ChildItem "$Env:SystemDrive\Install\Scripts" -Filter 'pswindowsupdate*.nupkg'

				if ($psWindowsUpdateNuPkgs.Count -gt 0) {
					# SilentlyContinue for any failures here because we will just install from NuGet if anything fails.

					Remove-Item "$Env:TEMP\fgSetup-*.zip" -Force -ErrorAction SilentlyContinue
					# .nupkg is just a .zip but we must rename it to be able to use Expand-Archive.
					Copy-Item ($psWindowsUpdateNuPkgs | Sort-Object -Property 'LastWriteTime' | Select-Object -Last 1).FullName "$Env:TEMP\fgSetup-PSWindowsUpdate.zip" -Force -ErrorAction SilentlyContinue

					Remove-Item "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate" -Recurse -Force -ErrorAction SilentlyContinue
					Expand-Archive "$Env:TEMP\fgSetup-PSWindowsUpdate.zip" "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate" -Force -ErrorAction SilentlyContinue
					Remove-Item "$Env:TEMP\fgSetup-*.zip" -Force -ErrorAction SilentlyContinue
				}

				if (-not (Test-Path "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate\PSWindowsUpdate.psd1")) {
					Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
					# There is no "Uninstall-PackageProvider" or other simple way to uninstall a package provider, so NuGet will be left installed.

					Install-Module -Name PSWindowsUpdate -Force -ErrorAction Stop
					# PSWindowsUpdate will be uninstalled after all available Windows Updates have been installed.
				}

				Write-Host "`n  Successfully Installed Automated Windows Update Tool" -ForegroundColor Green

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Installed Automated Windows Update Tool - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR INSTALLING PSWINDOWSUPDATE: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to install automated Windows Update tool (PSWindowsUpdate)." -ForegroundColor Red

				Write-Host "`n`n  IMPORTANT: Make sure Ethernet cable is plugged securely or Wi-Fi is connected and try again." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			Install-QAHelper

			if ((-not (Test-Path "$Env:SystemDrive\Install\QA Helper\java-jre\bin\javaw.exe")) -or (-not (Test-Path "$Env:SystemDrive\Install\QA Helper\QA_Helper.jar"))) {
				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			Install-WindowsUpdates # Will exit (and launch a new instance of this script) or reboot if successful.
		}

		# Wait until logged in so we can actually focus the script window.
		for ( ; ; ) {
			try {
				Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
				Start-Sleep 1
			} catch {
				break
			}
		}

		Write-Host "`n`n  !!! THIS COMPUTER CANNOT BE SOLD UNTIL SETUP IS COMPLETED SUCCESSFULLY !!!" -ForegroundColor Red
		Write-Host "`n`n  If this issue continues, please inform Free Geek I.T.`n" -ForegroundColor Red

		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		Read-Host '  Manually Reboot This Computer or Press ENTER to Try Again' | Out-Null
	}
} else {
	if ((Test-Path "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate\PSWindowsUpdate.psd1") -or (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
		if (($LastWindowsUpdatesCount -eq '0') -or ($LastWindowsUpdatesCount -eq 'MaxUpdateCycles')) {
			# Screen scaling may have already been set after running updates, in which case this won't do anything.
			# But if drivers were installed from cache and no updates installed, then we'll need to set screen scaling here as the last thing in the setup cycle.
			$needsRebootAfterAdjustingScreenScaling = AdjustScreenScaling # See comments within function for info about rebooting after setting screen scaling.

			Write-Output "`n`n  Uninstalling Automated Windows Update Tool (Windows Update from Settings App IS NOT Affected)..."

			try {
				# Only try to uninstall PSWindowsUpdate when this script was launched with LastWindowsUpdatesCount of 0 (or MaxUpdateCycles) so that we know updates are done
				# and that this is a new PowerShell instance which PSWindowsUpdate hasn't been run in so it won't error stating it is currently in use.

				if (Test-Path "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate\PSWindowsUpdate.psd1") {
					# Delete the local PSWindowsUpdate when we're done updating just to stop the auto updating cycle.
					Remove-Item "$Env:SystemDrive\Install\Scripts\PSWindowsUpdate" -Recurse -Force -ErrorAction Stop
				} else {
					# Delete the installed PSWindowsUpdate when we're done updating to stop the auto updating cycle AND to not leave junk on computer.
					Uninstall-Module PSWindowsUpdate -ErrorAction Stop
				}

				Write-Host "`n  Successfully Uninstalled Automated Windows Update Tool" -ForegroundColor Green

				Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Uninstalled Automated Windows Update Tool - $(Get-Date)" -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR UNINSTALLING PSWINDOWSUPDATE: $_" -ForegroundColor Red
			}

			if ($needsRebootAfterAdjustingScreenScaling) {
				# Wait until logged in so we don't ever restart before Windows is done doing its own setup during the "Preparing Windows" phase.
				for ( ; ; ) {
					try {
						Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
						Start-Sleep 1
					} catch {
						break
					}
				}

				if ($testMode) {
					FocusScriptWindow
					Write-Host "`n`n  AUTOMATIC REBOOT DISABLED IN TEST MODE`n" -ForegroundColor Yellow

					$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
					Read-Host '  Press ENTER to Reboot After Adjusting Screen Scaling' | Out-Null
				} else {
					$rebootTimeout = 15

					Write-Output "`n`n  This Computer Will Reboot After Adjusting Screen Scaling in $rebootTimeout Seconds..."
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

				Restart-Computer

				exit 0 # Not sure if exit is necessary after Restart-Computer but doesn't hurt.
			}
		} else {
			Install-WindowsUpdates # Will exit (and launch a new instance of this script) or reboot if successful.
		}
	}

	if ($isWindows11) {
		Write-Output "`n`n  Verifying That This Computer Supports Windows 11...`n" # https://www.microsoft.com/en-us/windows/windows-11-specifications

		$tpmSpecVersionString = (Get-CimInstance 'Win32_TPM' -Namespace 'ROOT\CIMV2\Security\MicrosoftTPM' -ErrorAction SilentlyContinue).SpecVersion
		$win11compatibleTPM = $false

		if ($null -ne $tpmSpecVersionString) {
			$tpmSpecVersionString = $tpmSpecVersionString.Split(',')[0] # Use the first value in the "SpecVersion" comma separated string instead of "PhysicalPresenseVersionInfo" since the latter can be inaccurate when the former is correct.
			$win11compatibleTPM = ((($tpmSpecVersionString -Replace '[^0-9.]', '') -as [double]) -ge 2.0)
		} else {
			$tpmSpecVersionString = 'UNKNOWN'
		}

		# Check for SSE4.2 support (even though it should be supported on every compatible CPU): https://www.tomshardware.com/software/windows/microsoft-updates-windows-11-24h2-requirements-cpu-must-support-sse42-or-the-os-will-not-boot
		$processorFeatureFunctionTypes = Add-Type -PassThru -Name ProcessorFeature -MemberDefinition @'
[DllImport("kernel32")]
public static extern bool IsProcessorFeaturePresent(uint ProcessorFeature);
'@ # Based On: https://superuser.com/a/1861418

		$win11compatibleSSE4dot2 = $processorFeatureFunctionTypes::IsProcessorFeaturePresent(38) # 38 = PF_SSE4_2_INSTRUCTIONS_AVAILABLE

		$win11compatibleStorage = $false
		if ((Get-Partition -DriveLetter (Get-CimInstance 'Win32_OperatingSystem' -Property 'SystemDrive' -ErrorAction SilentlyContinue).SystemDrive.Replace(':', '') -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue).Size -ge 55GB) {
			# NOT using "Storage Available" from WhyNotWin11 below because it will get the VOLUME size which could be smaller after formatting and a Recovery Volume is partitioned rather than checking the WHOLE DISK size which I believe is the actual requirement.
			# Allowing 55 GB or more since some drives marketed as 64 GB (the specified requirement) can be a few GB under (seen first hand a drive marketed as 64 GB actually be 58 GB, but give a little more leeway than that just to be sure all drives marketed as 64 GB are allowed).
			$win11compatibleStorage = $true
		}

		$eleventhToThirteenthGenIntelCPU = $false
		if ($cpuInfo.Manufacturer -and $cpuInfo.Name -and $cpuInfo.Manufacturer.ToUpper().Contains('INTEL') -and $cpuInfo.Name.ToUpper().Contains(' GEN ')) {
			# "Manufacturer" should be "GenuineIntel" for all Intel processors, but do a case-insenstive check anything that contains "INTEL" just to be safe.
			# Only 11th-13th Gen Intel CPUs contain " Gen " in their model name strings, and they will always be compatible with Windows 11.
			# This boolean will be used as a fallback to the "win11compatibleCPUmodel" check done by WhyNotWin11 below in case WhyNotWin11
			# is not updated promptly and we run into a newer CPU that is not yet in the WhyNotWin11 list of compatible CPUs.
			$eleventhToThirteenthGenIntelCPU = $true
		}

		if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\WhyNotWin11.exe") { # Use WhyNotWin11 to help detect if the exact CPU model is compatible and more: https://github.com/rcmaehl/WhyNotWin11
			Remove-Item "$Env:SystemDrive\Install\WhyNotWin11 Log.csv" -Force -ErrorAction SilentlyContinue
			Start-Process "$Env:SystemDrive\Install\Diagnostic Tools\WhyNotWin11.exe" -NoNewWindow -Wait -ArgumentList '/export', 'CSV', "`"$Env:SystemDrive\Install\WhyNotWin11 Log.csv`"", '/skip', 'CPUFreq,Storage', '/silent', '/force' -ErrorAction SilentlyContinue
		}

		$win11compatibleArchitecture = $false
		$win11compatibleBootMethod = $false
		$win11compatibleCPUmodel = $false
		$win11compatibleCPUcores = $false
		$win11compatibleGPU = $false
		$win11compatiblePartitionType = $false
		$win11compatibleRAM = $false
		$win11compatibleSecureBoot = $false
		$win11compatibleTPMfromWhyNotWin11 = $false
		$checkedWithWhyNotWin11 = $false

		if (Test-Path "$Env:SystemDrive\Install\WhyNotWin11 Log.csv") {
			$whyNotWin11LogLastLine = Get-Content "$Env:SystemDrive\Install\WhyNotWin11 Log.csv" -Last 1

			if ($null -ne $whyNotWin11LogLastLine) {
				$whyNotWin11LogValues = $whyNotWin11LogLastLine.Split(',')

				if ($whyNotWin11LogValues.Count -eq 12) {
					# Index 0 is "Hostname" which is not useful for these Windows 11 compatibility checks.
					$win11compatibleArchitecture = ($whyNotWin11LogValues[1] -eq 'True')
					$win11compatibleBootMethod = ($whyNotWin11LogValues[2] -eq 'True')
					$win11compatibleCPUmodel = ($whyNotWin11LogValues[3] -eq 'True')
					$win11compatibleCPUcores = ($whyNotWin11LogValues[4] -eq 'True')
					# Index 5 is "CPU Frequency" which we are ignoring (and also SKIPPED with arguments in the command above) because sometimes the detected speed is inaccurate and under 1 Ghz which causes this check to fail even though the CPU is in the compatible list and is actually faster.
					$win11compatibleGPU = ($whyNotWin11LogValues[6] -eq 'True')
					$win11compatiblePartitionType = ($whyNotWin11LogValues[7] -eq 'True')
					$win11compatibleRAM = ($whyNotWin11LogValues[8] -eq 'True')
					$win11compatibleSecureBoot = ($whyNotWin11LogValues[9] -eq 'True')
					# Index 10 is "Storage Available" which we are ignoring (and also SKIPPED with arguments in the command above) and checking manually above since WhyNotWin11 will get the VOLUME size which could be smaller after formatting and a Recovery Volume is partitioned rather than checking the WHOLE DISK size which I believe is the actual requirement.
					$win11compatibleTPMfromWhyNotWin11 = ($whyNotWin11LogValues[11] -eq 'True') # We already manually checked TPM version, but doesn't hurt to confirm that WinNotWin11 agrees.

					$checkedWithWhyNotWin11 = $true
				}
			}
		}

		Write-Host '    CPU Compatible: ' -NoNewline
		if (-not $win11compatibleSSE4dot2) {
			Write-Host 'NO (SSE 4.2 Support REQUIRED)' -ForegroundColor Red
		} elseif (-not $win11compatibleCPUcores) {
			Write-Host 'NO (At Least Dual-Core REQUIRED)' -ForegroundColor Red
		} elseif (-not $win11compatibleArchitecture) {
			# This incompatibility should never happen since we only refurbish 64-bit processors and only have 64-bit Windows installers.
			Write-Host 'NO (64-bit REQUIRED)' -ForegroundColor Red
		} elseif (-not $win11compatibleCPUmodel) {
			if ($eleventhToThirteenthGenIntelCPU) {
				Write-Host 'YES' -NoNewline -ForegroundColor Green
				Write-Host ' (Fallback Check Passed)' -ForegroundColor Yellow
			} else {
				Write-Host 'NO (Model NOT Supported)' -ForegroundColor Red
			}
		} else {
			Write-Host 'YES' -ForegroundColor Green
		}

		Write-Host '    RAM 4 GB or More: ' -NoNewline
		if ($win11compatibleRAM) {
			Write-Host 'YES' -ForegroundColor Green
		} else {
			Write-Host 'NO (At Least 4 GB REQUIRED)' -ForegroundColor Red
		}

		Write-Host '    Storage 64 GB or More: ' -NoNewline
		if ($win11compatibleStorage) { 
			Write-Host 'YES' -ForegroundColor Green
		} else {
			Write-Host 'NO (At Least 64 GB REQUIRED)' -ForegroundColor Red
		}

		Write-Host '    GPU Compatible: ' -NoNewline
		if ($win11compatibleGPU) {
			Write-Host 'YES' -ForegroundColor Green
		} else {
			Write-Host 'NO (DirectX 12 + WDDM 2.0 REQUIRED)' -ForegroundColor Red
		}

		Write-Host '    UEFI Enabled: ' -NoNewline
		if (-not $win11compatibleBootMethod) {
			Write-Host 'NO (Booted in Legacy BIOS Mode)' -ForegroundColor Red
		} elseif (-not $win11compatibleSecureBoot) {
			# Secure Boot DOES NOT need to be enabled, the computer just needs to be Secure Boot capable: https://support.microsoft.com/en-us/windows/windows-11-and-secure-boot-a8ff1202-c0d9-42f5-940f-843abef64fad
			# And WhyNotWin11 only verifies that the computer is Secure Boot capable, not that it is enabled: https://github.com/rcmaehl/WhyNotWin11/blob/16123e4e891e9ba90c23cffccd5876d7ab2cfef3/includes/_Checks.au3#L219 & https://github.com/rcmaehl/WhyNotWin11/blob/1a2459a8cfc754644af7e94f33762eaaca544a07/includes/WhyNotWin11_accessibility.au3#L223
			Write-Host 'NO (NOT Secure Boot Capable)' -ForegroundColor Red
		} elseif (-not $win11compatiblePartitionType) {
			Write-Host 'NO (GPT Format REQUIRED)' -ForegroundColor Red
		} else {
			Write-Host 'YES' -ForegroundColor Green
		}

		Write-Host '    TPM 2.0 Enabled: ' -NoNewline
		if ($win11compatibleTPM) {
			if ($win11compatibleTPMfromWhyNotWin11) {
				Write-Host 'YES' -ForegroundColor Green
			} else {
				Write-Host 'MAYBE' -ForegroundColor Yellow
			}
		} elseif (($tpmSpecVersionString -eq 'UNKNOWN') -or ($tpmSpecVersionString -eq 'Not Supported')) {
			Write-Host 'NO (Not Detected)' -ForegroundColor Red
		} else {
			Write-Host "NO (Version $tpmSpecVersionString)" -ForegroundColor Red
		}

		if (-not $checkedWithWhyNotWin11) {
			Write-Host "`n  ERROR: Failed to run WhyNotWin11 to verify Windows 11 support. - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$notWin11compatibleResponse = Read-Host '  Press ENTER to Shut Down This Computer'

			if ((-not $testMode) -or ($notWin11compatibleResponse -ne 'TESTING')) { # Can bypass in test mode even if the computer isn't compatible with Windows 11.
				Stop-Computer

				exit 0 # Not sure if exit is necessary after Stop-Computer but doesn't hurt.
			}
		} elseif (-not $win11compatibleGPU) {
			# The GPU could not be verified in WinPE/WinRE since GPU drivers were not available, but it's generally assumed that GPUs will be compatible if everything else was compatible.
			# So, if this check failed, we need to make sure the technician makes I.T. aware that this issue could actually happen since it was a time wasting Windows 11 installation when Windows 10 must be installed instead.

			Write-Host "`n  ERROR: GPU is NOT compatible with Windows 11. - THIS IS UNEXPECTED - Please inform Free Geek I.T.`n" -ForegroundColor Red
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$notWin11compatibleResponse = Read-Host '  Press ENTER to Shut Down This Computer'

			if ((-not $testMode) -or ($notWin11compatibleResponse -ne 'TESTING')) { # Can bypass in test mode even if the computer isn't compatible with Windows 11.
				Stop-Computer

				exit 0 # Not sure if exit is necessary after Stop-Computer but doesn't hurt.
			}
		} elseif ($win11compatibleTPM -and $win11compatibleArchitecture -and $win11compatibleBootMethod -and ($win11compatibleCPUmodel -or $eleventhToThirteenthGenIntelCPU) -and $win11compatibleCPUcores -and $win11compatibleSSE4dot2 -and $win11compatiblePartitionType -and $win11compatibleRAM -and $win11compatibleSecureBoot -and $win11compatibleStorage -and $win11compatibleTPMfromWhyNotWin11) {
			Write-Host "`n  Successfully Verified Windows 11 Support" -ForegroundColor Green

			Add-Content "$Env:SystemDrive\Install\Windows Setup Log.txt" "Verified Windows 11 Support - $(Get-Date)" -ErrorAction SilentlyContinue
		} else {
			# None of the previous elseif checks should fail (unless in Test Mode) because it was all verified in WinPE before allowing Windows 11 to be installed.
			# So, if we got here, this computer needs to be sent to Free Geek I.T. to see what went wrong.

			Write-Host "`n  ERROR: Failed to verify Windows 11 support. - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$notWin11compatibleResponse = Read-Host '  Press ENTER to Shut Down This Computer'

			if ((-not $testMode) -or ($notWin11compatibleResponse -ne 'TESTING')) { # Can bypass in test mode even if the computer isn't compatible with Windows 11.
				Stop-Computer

				exit 0 # Not sure if exit is necessary after Stop-Computer but doesn't hurt.
			}
		}
	} else {
		Write-Host "`n`n  Windows 10 CANNOT Be Licensed or Sold - ONLY Use for Testing or Firmware Updates" -ForegroundColor Yellow
	}

	if ((-not (Test-Path "$Env:SystemDrive\Install\QA Helper\java-jre\bin\javaw.exe")) -or (-not (Test-Path "$Env:SystemDrive\Install\QA Helper\QA_Helper.jar"))) {
		Install-QAHelper
	}

	if ($ipdtMode -and (Test-Path "$Env:ProgramFiles\Intel Corporation\Intel Processor Diagnostic Tool 64bit\Win-IPDT64.exe")) { # See comments in above about why IPDT is installed instead of run from "Diagnostic Tools".
		Write-Output "`n`n  Launching OpenHardwareMonitor for PerformanceTest and Intel Processor Diagnostic Tool..."

		if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.exe") {
			Start-Process "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.exe" -NoNewWindow -ErrorAction SilentlyContinue

			# Make OpenHardwareMonitor stay on top of all other windows during the next PerformanceTest phase so the CPU temp is always visible and never blocked by the CPU test window (must wait for window to open to do this, but only wait for up to 1 minute).
			for ($waitForWindowAttempt = 0; $waitForWindowAttempt -lt 60; $waitForWindowAttempt ++) {
				$openHardwareMonitorHandle = (Get-Process | Where-Object MainWindowTitle -eq 'Open Hardware Monitor').MainWindowHandle
				if ($openHardwareMonitorHandle) {
					$openHardwareMonitorHandle = $openHardwareMonitorHandle[0] # In case there are multiple OpenHardwareMonitor windows open somehow.
					$windowFunctionTypes::SetWindowPos($openHardwareMonitorHandle, -1, 0, 0, 0, 0, 0x0003) | Out-Null # -1 = HWND_TOPMOST (https://stackoverflow.com/a/58542670 & https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
					break
				} else {
					Start-Sleep 1
				}
			}

			Write-Host "`n  Successfully Launched OpenHardwareMonitor" -ForegroundColor Green
		} else {
			Write-Host "`n  OpenHardwareMonitor Not Found - CONTINUING ANYWAY" -ForegroundColor Yellow
		}

		Write-Output "`n`n  Warming Up CPU With PerformanceTest Before Launching Intel Processor Diagnostic Tool..."

		if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\PerformanceTest64.exe") {
			Set-Content "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\WarmUpCPU.ptscript" @'
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
RUN CPU_ALL
EXIT
'@ -ErrorAction SilentlyContinue

			Start-Process "$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\PerformanceTest64.exe" -WindowStyle Maximized -Wait -ArgumentList '/s' , "`"$Env:SystemDrive\Install\Diagnostic Tools\PerformanceTest\WarmUpCPU.ptscript`"" -ErrorAction SilentlyContinue

			Write-Host "`n  Successfully Warmed Up CPU With PerformanceTest" -ForegroundColor Green
		} else {
			Write-Host "`n  PerformanceTest Not Found - CONTINUING ANYWAY" -ForegroundColor Yellow
		}

		if (Test-Path "$Env:SystemDrive\Install\Diagnostic Tools\OpenHardwareMonitor\OpenHardwareMonitor.exe") {
			# After PerformanceTest phase is done it is not important to monitor CPU temps during the IPDT phase, so set the OpenHardwareMonitor window back to regular non-topmost window so that it doesn't cover the PASS/FAIL portion of the IPDT window.
			$openHardwareMonitorHandle = (Get-Process | Where-Object MainWindowTitle -eq 'Open Hardware Monitor').MainWindowHandle
			if ($openHardwareMonitorHandle) {
				$openHardwareMonitorHandle = $openHardwareMonitorHandle[0] # In case there are multiple OpenHardwareMonitor windows open somehow.
				$windowFunctionTypes::SetWindowPos($openHardwareMonitorHandle, -2, 0, 0, 0, 0, 0x0003) | Out-Null # -2 = HWND_NOTOPMOST (https://stackoverflow.com/a/58542670 & https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
			}
		}

		Write-Output "`n`n  Launching Intel Processor Diagnostic Tool..."

		Start-Process "$Env:ProgramFiles\Intel Corporation\Intel Processor Diagnostic Tool 64bit\Win-IPDT64.exe" -NoNewWindow -WorkingDirectory "$Env:ProgramFiles\Intel Corporation\Intel Processor Diagnostic Tool 64bit" -ErrorAction SilentlyContinue # NOTE: Working directory MUST be set for the exe to be able to find the included DLLs to launch properly.

		# Quit "explorer" to have a minimal interface only showing the IPDT window. (Must use "taskkill" to fully quit "explorer" since using "Stop-Process" will quit and relaunch it while "taskkill" will just quit it.)
		# NO LONGER QUIT EXPLORER BUT KEEP THIS COMMENTED OUT IN CASE FOR FUTURE USE:
		# Start-Process 'taskkill' -NoNewWindow -RedirectStandardOutput 'NUL' -ArgumentList '/f', '/im', 'explorer.exe' -ErrorAction SilentlyContinue
	} elseif ((Test-Path "$Env:SystemDrive\Install\QA Helper\java-jre\bin\javaw.exe") -and (Test-Path "$Env:SystemDrive\Install\QA Helper\QA_Helper.jar")) {
		Write-Output "`n`n  Launching QA Helper..."

		Start-Process "$Env:SystemDrive\Install\QA Helper\java-jre\bin\javaw.exe" -NoNewWindow -ArgumentList '-jar', "`"$Env:SystemDrive\Install\QA Helper\QA_Helper.jar`"" -ErrorAction SilentlyContinue
	}

	Start-Sleep 3 # Sleep for a few seconds to be able to see last results before window closes.
}
