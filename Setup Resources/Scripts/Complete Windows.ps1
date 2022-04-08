############################################################################################
##                                                                                        ##
##         YOU WILL BE PROMPTED TO RUN THIS SCRIPT AFTER QA COMPLETE BY QA HELPER         ##
##   OR CHOOSE "Run Complete Windows Script & Shut Down" FROM SCRIPTS MENU IN QA HELPER   ##
##                                                                                        ##
############################################################################################

#
# By Pico Mitchell for Free Geek
# Originally written and tested in September 2020 for Windows 10, version 2004
# Tested in December 2021 for Windows 10, version 21H2
# AND Tested in December 2021 for Windows 11, version 21H2
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

# Version: 2022.3.29-1

param(
	[Parameter(Position = 0)]
	[String]$OverrideMode
)

$onlyCacheDriversMode = ($OverrideMode -eq 'OnlyCacheDrivers') # IMPORTANT: QA Helper checks for a line that STARTS WITH "$onlyCacheDriversMode =" to enable the "Manually Cache Drivers" menu item.

$windowTitle = 'Complete Windows'

if ($onlyCacheDriversMode) {
	$windowTitle = 'Cache Drivers'
}

$Host.UI.RawUI.WindowTitle = $windowTitle # IMPORTANT: QA Helper stops reading each Complete Windows script line to check capabilities when it gets to a line that STARTS WITH "$Host.UI.RawUI.WindowTitle =".

if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State') -or (-not (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State').ImageState.Contains('RESEAL_TO_AUDIT'))) {
	Write-Host "`n  ERROR: `"Complete Windows`" Can Only Run In Windows Audit Mode`n`n  EXITING IN 5 SECONDS..." -ForegroundColor Red
	Start-Sleep 5
	exit 1
}

if (-not (Test-Path '\Windows\System32\Sysprep\Unattend.xml')) {
	Write-Host "`n  ERROR: `"Unattend.xml`" DOES NOT EXISTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n`n  EXITING IN 5 SECONDS..." -ForegroundColor Red
	Start-Sleep 5
	exit 2
}

$isWindows11 = (Get-CimInstance Win32_OperatingSystem -Property Caption).Caption.Contains('Windows 11')

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


if ($onlyCacheDriversMode) {
	Write-Output "`n  Preparing to Cache Drivers..."
} elseif ($isWindows11) {
	Write-Output "`n  Verifying That This Computer Supports Windows 11 & Is Ready to Be Completed..."
} else {
	Write-Output "`n  Verifying That This Computer Is Ready to Be Completed..."
}

# Wait until logged in in case this script is being launched by "\Windows\System32\Sysprep\Unattend.xml" after a failure.
for ( ; ; ) {
	try {
		Get-Process 'LogonUI' -ErrorAction Stop | Out-Null
		Start-Sleep 1
	} catch {
		break
	}
}

FocusScriptWindow

try {
	Stop-Process -Name 'sysprep' -ErrorAction Stop
} catch {
	# Only try once to quit Sysprep in case it's running, but don't show any error if it's wasn't.
}

$testMode = ((Test-Path '\Install\TESTING') -or ($OverrideMode -eq 'TESTING'))


if (-not $onlyCacheDriversMode) { # Only do this verification and setup if not only caching drivers.
	$auditUnattendContents = Get-Content -Raw '\Windows\System32\Sysprep\Unattend.xml'

	if (-not $auditUnattendContents.Contains('\Complete Windows.ps1')) { # Only actually verify and confirm if this script HAS NOT run before.
		if ($isWindows11) {
			# Do not show separate title (or success message) for the following Windows 11 compatibility checks as they falls under the "Verifying That This Computer Is Ready to Be Completed" phase.
			# https://www.microsoft.com/en-us/windows/windows-11-specifications

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
				Start-Process '\Install\Diagnostic Tools\WhyNotWin11.exe' -NoNewWindow -Wait -ArgumentList '/export', 'CSV', '"C:\Install\WhyNotWin11 Log.csv"', '/silent', '/force' -ErrorAction SilentlyContinue
			}

			$win11compatibleArchitecture = $false
			$win11compatibleBootMethod = $false
			$win11compatibleCPUmodel = $false
			$win11compatibleCPUcores = $false
			$win11compatibleCPUspeed = $false
			$win11compatibleGPU = $false
			$win11compatiblePartitionType = $false
			$win11compatibleRAM = $false
			$win11compatibleSecureBoot = $false
			$win11compatibleStorage = $false
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
						$win11compatibleGPU = ($whyNotWin11LogValues[6] -eq 'True')
						$win11compatiblePartitionType = ($whyNotWin11LogValues[7] -eq 'True')
						$win11compatibleRAM = ($whyNotWin11LogValues[8] -eq 'True')
						$win11compatibleSecureBoot = ($whyNotWin11LogValues[9] -eq 'True')
						$win11compatibleStorage = ($whyNotWin11LogValues[10] -eq 'True')
						$win11compatibleTPMfromWhyNotWin11 = ($whyNotWin11LogValues[11] -eq 'True') # We already manually checked TPM version, but doesn't hurt to confirm that WinNotWin11 agrees.

						$checkedWithWhyNotWin11 = $true
					}
				}
			}

			Write-Host "`n    CPU Compatible: " -NoNewline
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
			} elseif ((-not $win11compatibleTPM) -or (-not $win11compatibleArchitecture) -or (-not $win11compatibleBootMethod) -or (-not $win11compatibleCPUmodel) -or (-not $win11compatibleCPUcores) -or (-not $win11compatibleCPUspeed) -or (-not $win11compatiblePartitionType) -or (-not $win11compatibleRAM) -or (-not $win11compatibleSecureBoot) -or (-not $win11compatibleStorage) -or (-not $win11compatibleTPMfromWhyNotWin11)) {
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
		}

		$hasRefurbProductKey = $false
		$dpkID = $null
		$didUploadCBRifDPK = $true
		$isQAcompleted = $false

		try {
			Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue

			$slmgrDlvExitCode = (Start-Process 'cscript' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-slmgr-dlv-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-slmgr-dlv-Error.txt" -ArgumentList '/nologo', '\Windows\System32\slmgr.vbs', '/dlv' -ErrorAction Stop).ExitCode
			$slmgrDlvError = Get-Content -Raw "$Env:TEMP\fgComplete-slmgr-dlv-Error.txt"
			$slmgrDlvOutput = Get-Content -Raw "$Env:TEMP\fgComplete-slmgr-dlv-Output.txt"

			if (($slmgrDlvExitCode -eq 0) -and ($null -eq $slmgrDlvError)) {
				if ($slmgrDlvOutput.Contains('Product Key Channel: OEM:NONSLP')) {
					$hasRefurbProductKey = $true
				} elseif ($slmgrDlvOutput.Contains('Product Key Channel: OEM:DM') -and (Test-Path '\Install\DPK\Logs\oa3tool-assemble.xml')) {
					# "OEM:DM" could mean that the computer has an Embedded Digital Product Key OR that we have issued it Refurbished Digital Product Key using oa3tool.
					# Therefore, only allow "OEM:DM" Product Keys if the "oa3tool-assemble.xml" file exists (which contains the Refurb DPK applied by us) AND the "Partial Product Key" matches the end of that DPK.
					
					$slmgrDlvPartialProductKeyLine = (Select-String -Path "$Env:TEMP\fgComplete-slmgr-dlv-Output.txt" -Pattern 'Partial Product Key: ').Line

					if (($null -ne $slmgrDlvPartialProductKeyLine) -and ($slmgrDlvPartialProductKeyLine.length -eq 26)) {
						[xml]$oa3toolAssembleXML = Get-Content '\Install\DPK\Logs\oa3tool-assemble.xml'

						if (($null -ne $oa3toolAssembleXML.Key.ProductKey) -and ($null -ne $oa3toolAssembleXML.Key.ProductKeyID)) {
							if ($oa3toolAssembleXML.Key.ProductKey.EndsWith("-$($slmgrDlvPartialProductKeyLine.Substring(21))")) {
								$hasRefurbProductKey = $true
								$dpkID = $oa3toolAssembleXML.Key.ProductKeyID
								$didUploadCBRifDPK = $false
							}
						} else {
							Write-Host "`n  ERROR: Failed to get contents of the `"oa3tool-assemble.xml`" file." -ForegroundColor Red
						}
					} else {
						Write-Host "`n  ERROR: Failed to get Partial Product Key from slmgr." -ForegroundColor Red
					}
				}

				if (-not $hasRefurbProductKey) {
					Write-Host "`n  ERROR: Windows IS NOT activated with a Refurbished PC Product Key." -ForegroundColor Red
				}
			} else {
				if ($null -eq $slmgrDlvError) {
					$slmgrDlvError = $slmgrDlvOutput
				}
				
				Write-Host "`n  ERROR CHECKING PRODUCT KEY: $slmgrDlvError" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to check Product Key (slmgr Exit Code = $slmgrDlvExitCode)." -ForegroundColor Red
			}

			Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
		} catch {
			Write-Host "`n  ERROR STARTING CSCRIPT FOR SLMGR: $_" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to check Product Key." -ForegroundColor Red
		}

		if (Test-Path '\Install\QA Helper Log.txt') {
			$qaHelperLogLastStatusLine = 'Status: UNKNOWN'

			foreach ($thisQAhelperLogLine in (Get-Content '\Install\QA Helper Log.txt')) {
				if ($thisQAhelperLogLine.StartsWith('Status: ')) {
					$qaHelperLogLastStatusLine = $thisQAhelperLogLine
					# Continue check entire QA Helper Log for last status since all past statuses are saved.
				} elseif (($null -ne $dpkID) -and (-not $didUploadCBRifDPK) -and $thisQAhelperLogLine.StartsWith("Uploaded CBR for DPK: CBR+$dpkID+")) {
					$didUploadCBRifDPK = $true
				}
			}

			if (-not $didUploadCBRifDPK) {
				Write-Host "`n  ERROR: The CBR for the Digital Product Key HAS NOT been uploaded." -ForegroundColor Red
			}

			if ($qaHelperLogLastStatusLine.StartsWith('Status: QA Complete')) {
				$isQAcompleted = $true
			} else {
				Write-Host "`n  ERROR: This computer IS NOT marked as QA Complete." -ForegroundColor Red
			}
		} else {
			Write-Host "`n  ERROR: QA Helper Log file DOES NOT exist." -ForegroundColor Red
		}

		if ((-not $hasRefurbProductKey) -or (-not $didUploadCBRifDPK) -or (-not $isQAcompleted)) {
			Write-Host "`n`n  This Computer IS NOT Ready to Be Completed - SEE PREVIOUS ERRORS FOR DETAILS" -ForegroundColor Yellow
			
			Write-Host "`n`n  !!! THIS COMPUTER CANNOT BE SOLD UNTIL WINDOWS IS COMPLETED SUCCESSFULLY !!!" -ForegroundColor Red
			
			if ((Test-Path '\Install\QA Helper\java-jre\bin\javaw.exe') -and (Test-Path '\Install\QA Helper\QA_Helper.jar')) {
				Write-Host "`n`n  If this computer is actually ready to be completed, please inform Free Geek I.T.`n" -ForegroundColor Red
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				$notReadyResponse = Read-Host '  Press ENTER to Launch QA Helper to Correct the Specified Errors'

				if ((-not $testMode) -or ($notReadyResponse -ne 'TESTING')) { # Can bypass in test mode even if the computer isn't ready to be completed for testing purposes.
					Write-Output "`n`n  Launching QA Helper..."
					Start-Process '\Install\QA Helper\java-jre\bin\javaw.exe' -NoNewWindow -ArgumentList '-jar', '"\Install\QA Helper\QA_Helper.jar"' -ErrorAction SilentlyContinue
					
					Start-Sleep 3
					
					exit 3
				}
			} else {
				Write-Host "`n`n  ERROR: `"QA Helper`" DOES NOT EXISTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				Read-Host '  Press ENTER to Exit' | Out-Null

				exit 4
			}
		}

		for ( ; ; ) {
			Write-Host "`n  This Computer Is Ready to Be Completed" -ForegroundColor Green

			Write-Host "`n`n  Are you sure you want to run `"Complete Windows`" on this computer?" -ForegroundColor Cyan
			Write-Host "`n  This Computer Will Shut Down After `"Complete Windows`" Is Finished and Enter Out-of-Box Experience (OOBE) on Next Boot`n" -ForegroundColor Yellow
			
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$confirmComplete = Read-Host '  Type "Y" and Press ENTER to Confirm Running "Complete Windows" or Type ANYTHING ELSE to Cancel and Launch QA Helper'

			if ($confirmComplete -ne '') {
				if ($confirmComplete.ToUpper() -eq 'Y') {
					break
				} elseif ((Test-Path '\Install\QA Helper\java-jre\bin\javaw.exe') -and (Test-Path '\Install\QA Helper\QA_Helper.jar')) {
					Write-Output "`n`n  Launching QA Helper..."
					Start-Process '\Install\QA Helper\java-jre\bin\javaw.exe' -NoNewWindow -ArgumentList '-jar', '"\Install\QA Helper\QA_Helper.jar"' -ErrorAction SilentlyContinue
					
					Start-Sleep 3

					exit 5
				} else {
					Write-Host "`n`n  ERROR: `"QA Helper`" DOES NOT EXISTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
					FocusScriptWindow
					$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
					Read-Host '  Press ENTER to Exit' | Out-Null
		
					exit 6
				}
			}

			Clear-Host
		}
		
		# Update Unattend.xml to make "Complete Windows.ps1" run on boot instead of "Setup Windows.ps1" (in case the computer is rebooted or shut down prematurely).
		try {
			Set-Content -Path '\Windows\System32\Sysprep\Unattend.xml' -Value $auditUnattendContents.Replace('Setup Windows', 'Complete Windows') -Force -ErrorAction Stop
		} catch {
			Write-Host "`n  ERROR UPDATING AUDIT UNATTEND CONTENTS: $_" -ForegroundColor Red
		}
	} else {
		Write-Host "`n  The Completion Process Has Already Been Started on This Computer" -ForegroundColor Green
	}


	$didSyncSystemTime = $false

	try {
		Write-Output "`n`n  Syncing System Time..."

		Start-Service 'W32Time' -ErrorAction Stop

		Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue

		$w32tmResyncExitCode = (Start-Process 'W32tm' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-W32tm-resync-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-W32tm-resync-Error.txt" -ArgumentList '/resync', '/force' -ErrorAction Stop).ExitCode
		$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgComplete-W32tm-resync-Error.txt"
		
		if (($w32tmResyncExitCode -eq 0) -and ($null -eq $w32tmResyncError)) {
			Write-Host "`n  Successfully Synced System Time" -ForegroundColor Green

			$didSyncSystemTime = $true
		} else {
			if ($null -eq $w32tmResyncError) {
				$w32tmResyncError = Get-Content -Raw "$Env:TEMP\fgComplete-W32tm-resync-Output.txt"
			}

			Write-Host "`n  ERROR SYNCING SYSTEM TIME: $w32tmResyncError" -ForegroundColor Red
			Write-Host "`n  ERROR: Failed to sync system time (W32tm Exit Code = $w32tmResyncExitCode)." -ForegroundColor Red
		}
	} catch {
		Write-Host "`n  ERROR STARTING TIME SERVICE OR W32TM: $_" -ForegroundColor Red
		Write-Host "`n  ERROR: Failed to start system time service." -ForegroundColor Red
	}

	Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue

	if (-not $didSyncSystemTime) {
		Write-Host "`n  System Time May Be Incorrect - CONTINUING ANYWAY" -ForegroundColor Yellow
	}
}


[xml]$smbCredentialsXML = $null

try {
	[xml]$smbCredentialsXML = Get-Content '\Install\Scripts\smb-credentials.xml' -ErrorAction Stop

	if ($null -eq $smbCredentialsXML.smbCredentials.driversReadWriteShare.ip) {
		throw 'NO DRIVERS SHARE IP'
	} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadWriteShare.shareName) {
		throw 'NO DRIVERS SHARE NAME'
	} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadWriteShare.username) {
		throw 'NO DRIVERS SHARE USERNAME'
	} elseif ($null -eq $smbCredentialsXML.smbCredentials.driversReadWriteShare.password) {
		throw 'NO DRIVERS SHARE PASSWORD'
	}
} catch {
	Write-Host "`n`n  ERROR RETRIEVING SMB CREDENTIALS: $_" -ForegroundColor Red
	Write-Host "`n  ERROR: REQUIRED `"smb-credentials.xml`" DOES NOT EXISTS OR HAS INVALID CONTENTS - THIS SHOULD NOT HAVE HAPPENED - Please inform Free Geek I.T.`n" -ForegroundColor Red
	FocusScriptWindow
	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
	Read-Host '  Press ENTER to Exit' | Out-Null

	exit 7
}

$smbServerIP = $smbCredentialsXML.smbCredentials.driversReadWriteShare.ip
$smbShare = "\\$smbServerIP\$($smbCredentialsXML.smbCredentials.driversReadWriteShare.shareName)"
$smbUsername = $smbCredentialsXML.smbCredentials.driversReadWriteShare.username # (This is the user that can WRITE) domain MUST NOT be prefixed in username.
$smbPassword = $smbCredentialsXML.smbCredentials.driversReadWriteShare.password

$driversCacheBasePath = "$smbShare\Drivers\Cache"

$didCacheDrivers = $false # Keep track of if drivers were successfully checked/cached in a previous loop to not unnecessarily re-check them.
$skipCacheDrivers = $false # Can skip caching drivers after USB install

for ( ; ; ) {
	Clear-Host
	FocusScriptWindow

	if ($onlyCacheDriversMode) {
		Write-Output "`n  Preparing to Cache Drivers..."
	} else {
		if ($didCacheDrivers) {
			Write-Output "`n  Preparing to Finish Completing Windows..."
		} else {
			Write-Output "`n  Preparing to Complete Windows..."
		}
		
		try {
			Get-CimInstance Win32_Process -Filter 'Name LIKE "java%.exe" AND CommandLine LIKE "%QA_Helper.jar%"' -ErrorAction Stop | Invoke-CimMethod -Name Terminate -ErrorAction Stop | Out-Null
		} catch {
			Write-Host "    ERROR QUITTING QA HELPER: $_" -ForegroundColor Red
		}
	}
	
	$lastTaskSucceeded = $true
	
	$didConnectToServer = $false
	
	if ($didCacheDrivers) {
		Write-Host "`n  Already Cached Drivers for This Computer Model" -ForegroundColor Green
	} elseif ($skipCacheDrivers) {
		Write-Host "`n  Skipping Caching Drivers After USB Install" -ForegroundColor Yellow
	} else {
		try {
			$didConnectToServer = (Test-Connection $smbServerIP -Count 1 -Quiet -ErrorAction Stop)
		} catch {
			Write-Host "`n  ERROR CONNECTING TO LOCAL FREE GEEK SERVER: $_" -ForegroundColor Red
		}

		if ($didConnectToServer) {
			Write-Host "`n  Successfully Connected to Local Free Geek Server" -ForegroundColor Green
		} else {
			Write-Host "`n  ERROR: Failed to connect to local Free Geek server `"$smbServerIP`"." -ForegroundColor Red
			
			$lastTaskSucceeded = $false
		}

		if ($lastTaskSucceeded) {
			Write-Host "`n`n  Mounting SMB Share for Drivers Cache - PLEASE WAIT, THIS MAY TAKE A MOMENT..." -NoNewline
			
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
						
						$lastTaskSucceeded = $false
					}
				}
			}
		}
		
		if (-not $lastTaskSucceeded) {
			Write-Host "`n`n  IMPORTANT: Make sure Ethernet cable is plugged securely and try again." -ForegroundColor Red
		}

		$cachedDriversDidChange = $true
		
		if ($lastTaskSucceeded) {
			$driversCacheModelNameFilePath = '\Install\Drivers Cache Model Name.txt' # This file is created by QA Helper in WinPE using its detailed model info.
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
						Write-Output "`n`n  Detecting Installed Drivers to Cache for This Computer Model - PLEASE WAIT, THIS MAY TAKE A MOMENT..."

						$installedCompatibleDrivers = @()
						$installedCompatibleDriverFolderNames = @()
						
						try {
							$pnpEntityCompatibleAndHardwareIDs = (Get-CimInstance Win32_PnPEntity -Property 'HardwareID', 'CompatibleID' -ErrorAction Stop)
							$compatibleDeviceIDsForDrivers = (($pnpEntityCompatibleAndHardwareIDs.HardwareID + $pnpEntityCompatibleAndHardwareIDs.CompatibleID) | Where-Object { ($null -ne $_) } | Sort-Object -Unique).ToUpper()
							
							$excludedInfNames = @(
								'unifhid', # EXCLUDING "unifhid.inf" because it's just the Logitech USB Adapter Driver (and previously thought it may have been related to hanging on "Preparing Windows" screen in installed OS when installed in WinPE in Win 10 20H2 but it turns out it wasn't related. Still don't want it included in the Drivers Cache).
								'tbwkern' # EXCLUDING "tbwkern.inf" because it's just the Kensington MouseWorks Driver
							)

							Get-WindowsDriver -Online -ErrorAction Stop | ForEach-Object {
								# I have to call "Get-WindowsDriver -Online -Driver $_.Driver" for each driver instead of just using the output from "Get-WindowsDriver -Online" because that returns BasicDriverObjects while I want AdvancedDriverObjects to confirm compatiblity and get driver names (which aren't available from the BasicDriverObjects).
								# Also, must filter objects returned from "Get-WindowsDriver -Online -Driver $_.Driver" against $compatibleDeviceIDsForDrivers to get the correct HardwareDescription when a driver is compatible with a range of models (such as Intel graphics drivers).
								# Using "Get-WindowsDriver" in this way to get individual driver details was TOO SLOW in WinPE when getting details for uninstalled drivers from an SMB location, but getting details for
								# installed drivers from the online system seems to be fast enough at under 1 second per driver so sticking with this technique here since it's much simpler and much less code.
								# Also, unlike in WinPE, no special considerations need to be made for Software Component Drivers (with "SWC\..." Device IDs) since they are installed and their IDs will be included in $compatibleDeviceIDsForDrivers.

								# Historical Notes: Previously was also filtering installed drivers against *active* drivers using (-not $activeThirdPartyDriverInfNames.Contains($_.Driver)) with:
								# $activeThirdPartyDriverInfNames = (Get-CimInstance Win32_PnPSignedDriver -Property 'InfName' -ErrorAction Stop).InfName | Where-Object { ($null -ne $_) -and $_.StartsWith('oem') } | Sort-Object -Unique
								# ...but then I found that there are some Software Component Drivers (SWC) drivers whose parent drivers become inactive once the SWC is installed.
								# This resulted in only the SWC getting cached and not it's parent. Even if the SWC was re-installed on it's own (which was also problematic because compatibility couldn't be confirmed with the parent), Windows Update would still install the parent driver.
								# So, removed the filtering for active drivers and continued with checking for compatiblity to simply exclude and incompatible drivers that may have gotten installed by a technician or however else.

								if ($_.OriginalFileName.Contains('.inf_amd64_')) { # This should not be necessary, but make sure we only deal with 64-bit drivers within folder names like we expect.
									$driverIsExcluded = $false

									foreach ($thisExcludedInfName in $excludedInfNames) {
										$thisExcludedInfName = $thisExcludedInfName.ToLower()
										if (-not $thisExcludedInfName.EndsWith('.inf')) {
											$thisExcludedInfName = "$thisExcludedInfName.inf"
										}
										
										if ($_.OriginalFileName.Contains("\$($thisExcludedInfName)_")) {
											if ($testMode) {
												Write-Host "    DEBUG - EXCLUDING DRIVER FROM CACHE: $thisExcludedInfName" -ForegroundColor Yellow
											}
											
											$driverIsExcluded = $true
											break
										}
									}

									if (-not $driverIsExcluded) {
										$theseInstalledAdvancedDriverObjects = Get-WindowsDriver -Online -Driver $_.Driver -ErrorAction Stop # When testing, it appeared to faster (0.2 vs 0.5 secs) to retrieve each driver using the "oem#.inf" name in ".Driver" as opposed to using the ".OriginalFileName".
										
										foreach ($thisInstalledAdvancedDriverObject in $theseInstalledAdvancedDriverObjects) {
											if ($thisInstalledAdvancedDriverObject.Architecture -eq 9) { # Filters only "x64" compatible drivers.
												$thisInstalledAdvancedDirectoryName = Split-Path (Split-Path $thisInstalledAdvancedDriverObject.OriginalFileName -Parent) -Leaf

												if ($null -ne $thisInstalledAdvancedDriverObject.HardwareId) {
													if ($compatibleDeviceIDsForDrivers.Contains($thisInstalledAdvancedDriverObject.HardwareId.ToUpper())) {
														$installedCompatibleDrivers += $thisInstalledAdvancedDriverObject
														$installedCompatibleDriverFolderNames += $thisInstalledAdvancedDirectoryName
														break
													}
												} elseif ($null -ne $thisInstalledAdvancedDriverObject.CompatibleIds) {
													$didAddCompatibleDriver = $false

													foreach ($thisInstalledDriverCompatibleID in $thisInstalledAdvancedDriverObject.CompatibleIds) {
														if ($null -ne $thisInstalledDriverCompatibleID) {
															if ($compatibleDeviceIDsForDrivers.Contains($thisInstalledDriverCompatibleID.ToUpper())) {
																$installedCompatibleDrivers += $thisInstalledAdvancedDriverObject
																$installedCompatibleDriverFolderNames += $thisInstalledAdvancedDirectoryName
																$didAddCompatibleDriver = $true
																break
															}
														}
													}

													if ($didAddCompatibleDriver) {
														break
													}
												}
											}
										}
									}
								}
							}

							$installedCompatibleDrivers = $installedCompatibleDrivers | Sort-Object -Property 'ClassName', 'HardwareDescription', 'Version', 'OriginalFileName'
							$installedCompatibleDriverFolderNames = $installedCompatibleDriverFolderNames | Sort-Object
						} catch {
							$dismLogContents = Get-Content -Raw "$Env:WINDIR\Logs\Dism\dism.log" -ErrorAction SilentlyContinue
							if (($null -eq $dismLogContents) -or ($dismLogContents -eq '')) {
								$dismLogContents = ' N/A'
							} else {
								$dismLogContents = "`n$dismLogContents"
							}

							Write-Host "`n  DISM LOG:$dismLogContents" -ForegroundColor Red
							Write-Host "`n  ERROR DETECTING INSTALLED DRIVERS: $_" -ForegroundColor Red
							Write-Host "`n  ERROR: Failed to detect installed drivers so cannot cache them." -ForegroundColor Red

							$lastTaskSucceeded = $false
						}

						$driversCacheModelPathUniqueDriversPointerFilePath = "$driversCacheBasePath\$driversCacheModelNameFileContents.txt"

						if ($lastTaskSucceeded) {
							try {
								if (Test-Path $driversCacheModelPathUniqueDriversPointerFilePath) {
									$cachedDriversDidChange = (-not ((Compare-Object $installedCompatibleDriverFolderNames (Get-Content $driversCacheModelPathUniqueDriversPointerFilePath -ErrorAction Stop)).Length -eq 0))
								}

								Set-Content $driversCacheModelPathUniqueDriversPointerFilePath $installedCompatibleDriverFolderNames -ErrorAction Stop
							} catch {
								Write-Host "`n  ERROR: Cannot cache drivers since failed to create `"$($driversCacheModelPathUniqueDriversPointerFilePath.Replace("$driversCacheBasePath\", ''))`": $_" -ForegroundColor Red
								
								$lastTaskSucceeded = $false
							}
						}

						if ($lastTaskSucceeded) {
							if ($installedCompatibleDrivers.Count -gt 0) {
								Write-Host "`n  Successfully Detected $($installedCompatibleDrivers.Count) Installed Drivers to Cache for This Computer Model" -ForegroundColor Green

								Write-Output "`n`n  Caching $($installedCompatibleDrivers.Count) Drivers for This Computer Model - PLEASE WAIT, THIS MAY TAKE A FEW MINUTES..."
								
								$thisInstalledCompatibleDriverIndex = 0
								$cachedDriversSuccessCount = 0
								$cachedDriversFailedCount = 0

								foreach ($thisInstalledCompatibleDriver in $installedCompatibleDrivers) {
									$thisInstalledCompatibleDriverIndex ++

									$thisInstalledDriverNeedsToBeCached = $true
									
									$thisInstalledCompatibleDriverInfPath = $thisInstalledCompatibleDriver.OriginalFileName
									$thisInstalledDriverDirectoryPath = Split-Path $thisInstalledCompatibleDriverInfPath -Parent
									$thisInstalledDriverDirectoryName = Split-Path $thisInstalledDriverDirectoryPath -Leaf
									
									if (Test-Path $thisInstalledCompatibleDriverInfPath) {
										$thisInstalledCompatibleDriverInfBaseName = (Split-Path $thisInstalledCompatibleDriverInfPath -Leaf).Split('.')[0]

										$thisInstalledCompatibleDriverVersion = $thisInstalledCompatibleDriver.Version
										if (($null -eq $thisInstalledCompatibleDriverVersion) -or ($thisInstalledCompatibleDriverVersion -eq '')) {
											$thisInstalledCompatibleDriverVersion = 'UNKNOWN Version'
										}
										
										$thisInstalledCompatibleDriverClassName = $thisInstalledCompatibleDriver.ClassName
										if (($null -eq $thisInstalledCompatibleDriverClassName) -or ($thisInstalledCompatibleDriverClassName -eq '')) {
											$thisInstalledCompatibleDriverClassName = 'UNKNOWN Class'
										} elseif ($thisInstalledCompatibleDriverClassName -ceq $thisInstalledCompatibleDriverClassName.ToLower()) {
											$thisInstalledCompatibleDriverClassName = "$($thisInstalledCompatibleDriverClassName.Substring(0, 1).ToUpper())$($thisInstalledCompatibleDriverClassName.Substring(1))" # If Class is all lowercase, capitalized the first letter.
										}
										
										if (($null -ne $thisInstalledAdvancedDriverObject.HardwareId) -and $thisInstalledAdvancedDriverObject.HardwareId.ToUpper().StartsWith('SWC\')) {
											# I believe the "SWC\..." IDs will always be listed in the HardwareId and not the CompatibleIds array.
											if ($thisInstalledCompatibleDriverClassName.ToUpper() -ne 'SOFTWARECOMPONENT') {
												$thisInstalledCompatibleDriverClassName += ' SWC' # Some Software Component drivers do not have the class of "SoftwareComponent", so add " SWC" to any that don't to identify them.
											}
										}

										$thisInstalledCompatibleDriverHardwareDescription = $thisInstalledCompatibleDriver.HardwareDescription
										if (($null -eq $thisInstalledCompatibleDriverHardwareDescription) -or ($thisInstalledCompatibleDriverHardwareDescription -eq '')) {
											$thisInstalledCompatibleDriverHardwareDescription = 'UNKNOWN Name'
										}

										Write-Host "`n    Caching Driver $thisInstalledCompatibleDriverIndex of $($installedCompatibleDrivers.Count): `"$thisInstalledCompatibleDriverInfBaseName`" Version $thisInstalledCompatibleDriverVersion`n      $thisInstalledCompatibleDriverClassName - $thisInstalledCompatibleDriverHardwareDescription"
										
										$thisCachedDriverDirectoryPath = "$driversCacheBasePath\Unique Drivers\$thisInstalledDriverDirectoryName"

										if (Test-Path $thisCachedDriverDirectoryPath) {
											$thisCachedDriverInfPath = "$thisCachedDriverDirectoryPath\$(Split-Path $thisInstalledCompatibleDriverInfPath -Leaf)"

											if (Test-Path $thisCachedDriverInfPath) {
												if ((Get-FileHash $thisInstalledCompatibleDriverInfPath).Hash -eq (Get-FileHash $thisCachedDriverInfPath).Hash) {
													$theseInstalledDriverDirectoryFilePaths = (Get-ChildItem $thisInstalledDriverDirectoryPath -Recurse -File -Exclude '*.PNF').FullName
													$theseCachedDriverDirectoryFilePaths = (Get-ChildItem $thisCachedDriverDirectoryPath -Recurse -File -Exclude '*.PNF').FullName
													
													# Exclude ".PNF" when comparing driver contents since they are temporary compiled versions of ".inf" files that may or may not exist in $thisInstalledDriverDirectoryPath
													# and are always excluded from the Drivers Cache, this difference could cause unnecessary updates to the cache: https://file.org/extension/pnf
													
													$cachedDriverContentsMatchInstalledDriver = $true

													if ($theseInstalledDriverDirectoryFilePaths.Count -eq $theseCachedDriverDirectoryFilePaths.Count) {
														# Confirm that all contents within installed driver folders exist in the cache folder for the model.
														
														foreach ($thisInstalledDriverDirectoryFilePath in $theseInstalledDriverDirectoryFilePaths) {
															$thisInstalledDriverDirectoryFilePathInCache = $thisInstalledDriverDirectoryFilePath.Replace($thisInstalledDriverDirectoryPath, $thisCachedDriverDirectoryPath)
															
															if (-not (Test-Path $thisInstalledDriverDirectoryFilePathInCache)) {
																$cachedDriverContentsMatchInstalledDriver = $false
																if ($testMode) {
																	Write-Host "      DEBUG - Installed Driver File NOT in Cache: $($thisInstalledDriverDirectoryFilePathInCache.Replace("$driversCacheBasePath\", ''))" -ForegroundColor Yellow
																}
																break
															}

															# Historical Note: Would previously compare hashes of ".cat" and ".sys" files.
															# BUT, not doing that anymore since it would result in basically identical drivers from different models overwriting each other when getting cached.
															# From what I could tell comparing the binary contents, it was generally because of minor differences in the headers and footers and seemed to be because of code signing differences.
															# From testing, these differences do not make them incompatible between different models (since the ".inf" files are identical and both copies of the ".cat" and ".sys" files are valid).
														}
													} else {
														$cachedDriverContentsMatchInstalledDriver = $false
														if ($testMode) {
															Write-Host "      DEBUG - Installed Driver Contents Count ($($theseInstalledDriverDirectoryFilePaths.Count)) != Cached Driver Contents Count ($($theseCachedDriverDirectoryFilePaths.Count))" -ForegroundColor Yellow
														}
													}

													if ($cachedDriverContentsMatchInstalledDriver) {
														$thisInstalledDriverNeedsToBeCached = $false
													}
												} elseif ($testMode) {
													Write-Host "      DEBUG - inf Hash NE: $($thisCachedDriverInfPath.Replace("$driversCacheBasePath\", ''))" -ForegroundColor Yellow
												}
											} elseif ($testMode) {
												Write-Host "      DEBUG - inf DNE: $($thisCachedDriverInfPath.Replace("$driversCacheBasePath\", ''))" -ForegroundColor Yellow
											}
										} elseif ($testMode) {
											Write-Host "      DEBUG - folder DNE: $($thisCachedDriverDirectoryPath.Replace("$driversCacheBasePath\", ''))" -ForegroundColor Yellow
										}

										if ($thisInstalledDriverNeedsToBeCached) {
											try {
												$cacheDriverSuccess = 'CACHED'

												if (Test-Path $thisCachedDriverDirectoryPath) {
													Remove-Item $thisCachedDriverDirectoryPath -Recurse -Force -ErrorAction Stop
													$cacheDriverSuccess = 'UPDATED CACHE'
												}
												
												# Copy each individual driver from Get-WindowsDriver output instead of using "Export-WindowsDriver -Online -Destination "$driversCacheBasePath\Unique Drivers" -ErrorAction Stop | Out-Null"
												# so that I can show detailed progress, skip already cached drivers, only include compatible drivers, manually exclude drivers, etc.
												# Confirmed that manually copied contents are identical to Export-WindowsDriver contents.
												
												Copy-Item -Path $thisInstalledDriverDirectoryPath -Destination $thisCachedDriverDirectoryPath -Recurse -Exclude '*.PNF' -ErrorAction Stop | Out-Null
												
												# Exclude ".PNF" files from Drivers Cache since they are temporary compiled versions of ".inf" files that will be re-created when needed: https://file.org/extension/pnf
												# I confirmed through testing that drivers install successfully without the ".PNF" files and that they are re-created by Windows during driver setup.

												Write-Host "      $cacheDriverSuccess" -ForegroundColor Green

												$cachedDriversSuccessCount ++
											} catch {
												Write-Host "      FAILED: $_" -ForegroundColor Red
												$cachedDriversFailedCount ++
											}
										} else {
											Write-Host "      ALREADY CACHED" -ForegroundColor Yellow
										}
									} else {
										Write-Host "`n    INF NOT FOUND for Driver $thisInstalledCompatibleDriverIndex of $($installedCompatibleDrivers.Count): $thisInstalledDriverDirectoryName`n      CONTINUING ANYWAY..." -ForegroundColor Yellow
									}
								}

								if (($cachedDriversSuccessCount -eq 0) -and ($cachedDriversFailedCount -eq 0)) {
									Write-Host "`n  Drivers Cache Is Up-to-Date for This Computer Model" -ForegroundColor Green
									
									$didCacheDrivers = $true
								} elseif ($cachedDriversSuccessCount -gt 0) {
									Write-Host "`n  Successfully Cached $cachedDriversSuccessCount Drivers for This Computer Model" -ForegroundColor Green
									
									$didCacheDrivers = $true
								}

								if ($cachedDriversFailedCount -gt 0) {
									# If there was any success, show that first but then still fail with error if any failed.

									Write-Host "`n  ERROR: Failed to cache $cachedDriversFailedCount drivers for `"$driversCacheModelNameFileContents`"." -ForegroundColor Red
									
									$didCacheDrivers = $false
									$lastTaskSucceeded = $false
								}
							} else {
								Write-Host "`n  No Installed Drivers Detected to Cache for This Computer Model" -ForegroundColor Green

								$didCacheDrivers = $true
							}
						}
					} else {
						Write-Host "`n`n  Drivers Cache Model Name File Is Invalid - CANNOT CACHE DRIVERS - CONTINUING ANYWAY" -ForegroundColor Yellow
					}
				} else {
					Write-Host "`n`n  Drivers Cache Model Name File Is Empty - CANNOT CACHE DRIVERS - CONTINUING ANYWAY" -ForegroundColor Yellow
				}
			} else {
				Write-Host "`n`n  Drivers Cache Model Name File Does Not Exist - CANNOT CACHE DRIVERS - CONTINUING ANYWAY" -ForegroundColor Yellow
			}
		}

		if ($lastTaskSucceeded -and $didCacheDrivers -and $cachedDriversDidChange) {
			Write-Output "`n`n  Checking Drivers Cache for Stray (No Longer Referenced) Drivers to Delete..."

			try {
				$allReferencedCachedDrivers = @()

				Get-ChildItem "$driversCacheBasePath\*" -File -Include '*.txt' -ErrorAction Stop | ForEach-Object {
					$allReferencedCachedDrivers += Get-Content $_.FullName -ErrorAction Stop
				}

				$allReferencedCachedDrivers = $allReferencedCachedDrivers | Sort-Object -Unique

				$deletedStrayCachedDriversCount = 0

				Get-ChildItem "$driversCacheBasePath\Unique Drivers" -ErrorAction Stop | ForEach-Object {
					if (-not $allReferencedCachedDrivers.Contains($_.Name)) {
						$deletedStrayCachedDriversCount ++
						Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
					}
				}

				if ($deletedStrayCachedDriversCount -eq 0) {
					Write-Host "`n  Successfully Checked Drivers Cache and Found No Strays to Delete" -ForegroundColor Green
				} else {
					Write-Host "`n  Successfully Deleted $deletedStrayCachedDriversCount Strays From Drivers Cache" -ForegroundColor Green
				}
			} catch {
				Write-Host "`n  ERROR DELETED STRAY CACHED DRIVERS: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to check for or delete stray cached drivers." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		Remove-SmbMapping -RemotePath $smbShare -Force -UpdateProfile -ErrorAction SilentlyContinue # Done with SMB Share now, so remove it.
	}

	if (-not $onlyCacheDriversMode) {
		if ($lastTaskSucceeded) {
			$unigineProgramFolders = @('\Program Files (x86)\Unigine', '\Program Files\Unigine')

			foreach ($thisUnigineProgramFolder in $unigineProgramFolders) {
				if (Test-Path $thisUnigineProgramFolder) {
					$theseUniginePrograms = Get-ChildItem $thisUnigineProgramFolder

					foreach ($thisUnigineProgram in $theseUniginePrograms) {
						if (Test-Path "$($thisUnigineProgram.FullName)\unins000.exe") {
							Write-Output "`n`n  Uninstalling Unigine $($thisUnigineProgram.Name)..."
							
							try {
								Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
								
								$thisUnigineUninstallSilentExitCode = (Start-Process "$($thisUnigineProgram.FullName)\unins000.exe" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-unigineUninstall-silent-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-unigineUninstall-silent-Error.txt" -ArgumentList '/silent' -ErrorAction Stop).ExitCode
								$thisUnigineUninstallSilentError = Get-Content -Raw "$Env:TEMP\fgComplete-unigineUninstall-silent-Error.txt"
								
								if (($thisUnigineUninstallSilentExitCode -eq 0) -and ($null -eq $thisUnigineUninstallSilentError)) {
									Write-Host "`n  Successfully Uninstalled Unigine $($thisUnigineProgram.Name)" -ForegroundColor Green
								} else {
									if ($null -eq $thisUnigineUninstallSilentError) {
										$thisUnigineUninstallSilentError = Get-Content -Raw "$Env:TEMP\fgComplete-unigineUninstall-silent-Output.txt"
									}

									Write-Host "`n  ERROR UNINSTALLING UNIGINE: $thisUnigineUninstallSilentError" -ForegroundColor Red
									Write-Host "`n  ERROR: Failed to uninstall Unigine $($thisUnigineProgram.Name) (Uninstaller Exit Code = $thisUnigineUninstallSilentExitCode)." -ForegroundColor Red
									
									$lastTaskSucceeded = $false
									
									break
								}
								
								Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
							} catch {
								Write-Host "`n  ERROR STARTING UNIGINE UNINSTALLER: $_" -ForegroundColor Red
							}
						}
					}
				}

				if (-not $lastTaskSucceeded) {
					break
				}
			}
		}

		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Deleting Known Wi-Fi Networks..."
			# Known Wi-Fi networks will not be reset by Sysprep, so delete them so they will not auto-connect or show up in Known Networks list.
			
			try {
				Start-Service 'wlansvc' -ErrorAction Stop # Make sure Wireless AutoConfig Service (wlansvc) is running before trying to delete profiles since they will fail if it's not started yet.
			} catch {
				Write-Host "`n    Error Starting Wireless AutoConfig Service (wlansvc): $_" -ForegroundColor Yellow
			}

			try {
				Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
				
				$netshWlanDeleteProfilesExitCode = (Start-Process 'netsh.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-netsh-wlan-delete-profiles-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-netsh-wlan-delete-profiles-Error.txt" -ArgumentList 'wlan', 'delete', 'profile', 'name=*' -ErrorAction Stop).ExitCode
				$netshWlanDeleteProfilesError = Get-Content -Raw "$Env:TEMP\fgComplete-netsh-wlan-delete-profiles-Error.txt"
				
				if (($netshWlanDeleteProfilesExitCode -eq 0) -and ($null -eq $netshWlanDeleteProfilesError)) {
					Write-Host "`n  Successfully Deleted Known Wi-Fi Networks" -ForegroundColor Green
				} else {
					if ($null -eq $netshWlanDeleteProfilesError) {
						$netshWlanDeleteProfilesError = Get-Content -Raw "$Env:TEMP\fgComplete-netsh-wlan-delete-profiles-Output.txt"
					}

					Write-Host "`n  ERROR RUNNING NETSH TO DELETE KNOWN WI-FI NETWORKS: $netshWlanDeleteProfilesError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to run `"netsh wlan delete profile name=*`" (netsh Exit Code = $netshWlanDeleteProfilesExitCode)." -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
				
				Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR STARTING NETSH: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to delete known Wi-Fi networks." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			# Even though disabling the Network Location Wizard during testing is in HKCU and will not affect the account the customer will create, clean up after ourselves anyway.
			# https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/gg252535(v=ws.10)#to-turn-off-the-network-location-wizard-for-the-current-user
			
			$networkLocationWizardRegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Network\NwCategoryWizard'

			if (Test-Path $networkLocationWizardRegistryPath) {
				Write-Output "`n`n  Enabling Network Location Wizard..."
				
				try {
					Remove-Item $networkLocationWizardRegistryPath -Force -ErrorAction Stop
					
					Write-Host "`n  Successfully Enabled Network Location Wizard" -ForegroundColor Green
				} catch {
					Write-Host "`n  ERROR ENABLING NETWORK LOCATION WIZARD: $_" -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			}
		}
		
		if ($lastTaskSucceeded) {
			try {
				if (Get-NetConnectionProfile -ErrorAction Stop | Where-Object NetworkCategory -ne 'Public') {
					Write-Output "`n`n  Setting Network Profiles..."

					try {
						# Even though we've stopped Windows from prompting to set Network Profiles during testing (by disabling Network Location Wizard),
						# make sure they're all set to the more secure "Public" profile anyway since the settings are are not reset by Sysprep.

						Get-NetAdapter -Physical | Set-NetConnectionProfile -NetworkCategory 'Public'
						
						Write-Host "`n  Successfully Set Network Profiles" -ForegroundColor Green
					} catch {
						Write-Host "`n  ERROR SETTING NETWORK PROFILES: $_" -ForegroundColor Red

						$lastTaskSucceeded = $false
					}
				}
			} catch {
				Write-Host "`n  ERROR CHECKING NETWORK PROFILES: $_" -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Restoring Default Power Plan..."
			
			try {
				# The High Performance Power Plan set by Setup Windows script will not be reset by Sysprep and would be active in the customers account after OOBE, so set it back to Balanced.
				# "powercfg /restoredefaultschemes" will reset the default settings for the High Performance Power Plan (since we set the screen to never sleep) AS WELL AS set the active plan back to the Balanced Power Plan.
				
				Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
				
				$powercfgRestoredefaultschemesExitCode = (Start-Process 'powercfg.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-powercfg-restoredefaultschemes-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-powercfg-restoredefaultschemes-Error.txt" -ArgumentList '/restoredefaultschemes' -ErrorAction Stop).ExitCode
				$powercfgRestoredefaultschemesError = Get-Content -Raw "$Env:TEMP\fgComplete-powercfg-restoredefaultschemes-Error.txt"
			
				if (($powercfgRestoredefaultschemesExitCode -eq 0) -and ($null -eq $powercfgRestoredefaultschemesError)) {
					Write-Host "`n  Successfully Restored Default Power Plan" -ForegroundColor Green
				} else {
					if ($null -eq $powercfgRestoredefaultschemesError) {
						$powercfgRestoredefaultschemesError = Get-Content -Raw "$Env:TEMP\fgComplete-powercfg-restoredefaultschemes-Output.txt"
					}

					Write-Host "`n  ERROR RESTORING POWERCFG: $powercfgRestoredefaultschemesError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to restore default power plan (powercfg Exit Code = $powercfgRestoredefaultschemesExitCode)." -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			
				Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
			} catch {
				Write-Host "`n  ERROR STARTING POWERCFG: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to restore default power plan." -ForegroundColor Red

				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			# Even though the custom scaling set during testing is in HKCU and will not affect the account the customer will create (except for the UI glitch mentioned in the next comment), clean up after ourselves anyway.
			
			$customScreenScalingRegistryPath = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'

			if (Test-Path $customScreenScalingRegistryPath) {
				Write-Output "`n`n  Disabling Custom Screen Scaling..."

				try {
					Remove-Item $customScreenScalingRegistryPath -Recurse -Force -ErrorAction Stop
					
					# IMPORTANT NOTE: If we do not restart the graphics driver with the following code after resetting the default DPI settings (by deleting PerMonitorSettings),
					# then the "Just a moment..." screen that the customer will see on the next boot will start at the OLD DPI (our custom scaling) and then switch to the DEFAULT DPI
					# and get fuzzy and positioned incorrectly which does not give a good impression on first boot. But, we can avoid that glitch by restarting the graphics driver here.
					# To be clear, this is just a momentary cosmetic issue because when Windows shows the region chooser screen, everything is crisp and correct at the default DPI.
					# My suspicion is that this is because of Windows remembering the last DPI/resolution used during shut down to use on next boot (until it loads enough to know the DPI/resolution is should be using), but I'm not certain.
					
					# Restart the Graphics Driver after deleting PerMonitorSettings. The following code simulates the keyboard shortcut "Windows + Control + Shift + B" (https://support.microsoft.com/en-us/help/4496075/windows-10-troubleshooting-black-or-blank-screens)
					# Based On: https://stackoverflow.com/questions/57570136/how-to-restart-graphics-drivers-with-powershell-or-c-sharp-without-admin-privile (https://github.com/stefanstranger/PowerShell/blob/master/WinKeys.ps1)

					# NOTE: While we could use the Disable/Enable-PnpDevice method which requires admin privileges since we're in Audit mode,
					# this shortcut is actually quicker and looks cleaner to the user and doesn't make any sounds happen like the Disable/Enable-PnpDevice method does.
					# Also, SendKeys cannot be used for this shortcut since SendKeys can't send the Windows key.

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
					
					Write-Host "`n  Successfully Disabled Custom Screen Scaling" -ForegroundColor Green
				} catch {
					Write-Host "`n  ERROR DISABLING CUSTOM SCREEN SCALING: $_" -ForegroundColor Red

					$lastTaskSucceeded = $false
				}
			}
		}

		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Cleaning Up Leftover Files and Folders from Installation and Setup Process..."
			
			try {
				if (Test-Path "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\QA Helper.lnk") {
					Remove-Item "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\QA Helper.lnk" -Force -ErrorAction Stop
				}
				
				$desktopPath = [Environment]::GetFolderPath('Desktop')
				if (Test-Path "$desktopPath\QA Helper.lnk") {
					Remove-Item "$desktopPath\QA Helper.lnk" -Force -ErrorAction Stop
				}

				if (Test-Path '\Install\') {
					# Do not delete self yet in case something fails and we need to restart and run this script again.
					Remove-Item '\Install\*' -Exclude '*Log.txt', 'smb-credentials.xml', "$(Split-Path $PSCommandPath -Leaf)" -Recurse -Force -ErrorAction Stop
					
					Write-Host "`n  Successfully Cleaned Up Leftover Files and Folders from Installation and Setup Process" -ForegroundColor Green
				}
			} catch {
				Write-Host "`n  ERROR CLEANING UP LEFTOVERS: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to delete QA Helper shortcuts or contents of the `"\Install`" folder." -ForegroundColor Red
				
				$lastTaskSucceeded = $false
			}
		}

		if ($lastTaskSucceeded) {
			try {
				Write-Output "`n`n  Emptying Recycle Bin..."
				
				Clear-RecycleBin -Force -ErrorAction Stop

				Write-Host "`n  Successfully Emptied Recycle Bin" -ForegroundColor Green
			} catch {
				Write-Host "`n  ERROR EMPTYING REYCYLE BIN: $_`n" -ForegroundColor Red
				Write-Host "`n  Failed to empty Recycle Bin - CONTINUING ANYWAY" -ForegroundColor Yellow
			}
		}

		if ($lastTaskSucceeded) {
			Write-Output "`n`n  Running System Preparation Tool (Sysprep) to Enter Out-of-Box Experience (OOBE) on Next Boot..."
			
			try {
				# IMPORTANT INFO: The following to two blocks to use/install SetupComplete.cmd AND UnattendOOBE.xml were used while testing different cleanup options.
				# I was only playing with using them to run commands to cleanup the /Install folder so that nothing would be left behind for the customer (except for "QA Helper Log.txt").
				# In the end, I decided it was cleaner and simpler to do that cleanup here in this script by having Sysprep NOT shut down the computer and delete stuff after Sysprep is done and then shut down manually.
				# ALSO, running SetupComplete.cmd OR commands in UnattendOOBE.xml is a risk in case anything goes wrong and throws errors or messes up the setup process for the customer.
				# FURTHERMORE, the old PCs for People process would run "sysprep /oobe /generalize" with a fairly complex Unattend.xml.
				# We found that pretty commonly something would go wrong processing this Unattend.xml during Windows Setup resulting in an error which would not let Windows Setup continue and require a re-install.
				# It seems better and safer to avoid using an Unattend.xml file at all with Sysprep, unless it's absolutely necessary. And for our process, it's just not necessary. 
				# BUT, I'm leaving these two block in place for testing or use in the future if deemed necessary.

				# Install SetupComplete.cmd (if it exists as WindowsSetupComplete.txt). It's originally stored as a ".txt" file so it cannot be run by accident before installation.
				# Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup
				if ($testMode -and (Test-Path '\Install\Scripts\Resources\WindowsSetupComplete.txt')) {
					if (-not (Test-Path '\Windows\Setup\Scripts')) {
						New-Item -ItemType 'Directory' -Path '\Windows\Setup\Scripts' -ErrorAction Stop | Out-Null
					}

					Move-Item '\Install\Scripts\Resources\WindowsSetupComplete.txt' '\Windows\Setup\Scripts\SetupComplete.cmd'
				}

				$sysprepOobeArgs = @('/oobe', '/quit') # Quit after Sysprep instead of letting it shut the computer down so we can confirm success, cleanup leftovers, and then shut down ourselves.
				
				# Use UnattendOOBE.xml during Sysprep (if it exists) and determine required Sysprep command-line options from its contents.
				# Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options
				if ($testMode -and (Test-Path '\Install\Scripts\Resources\UnattendOOBE.xml')) {
					$oobeUnattendContents = Get-Content -Raw '\Install\Scripts\Resources\UnattendOOBE.xml'
					
					if ($oobeUnattendContents.Contains('<unattend xmlns="urn:schemas-microsoft-com:unattend">')) {
						if ($oobeUnattendContents.Contains('<settings pass="specialize">') -or $oobeUnattendContents.Contains('<settings pass="generalize">')) {
							# /generalize is not necessary if there is no specialize or generalize passes in the unattend file.
							# Even if there is only a specialize pass, it will only be run if we /generalize during sysprep.

							# Reference (See Note in Step 2, Item 5 about running Sysprep with vs without /generalize):
							# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/boot-windows-to-audit-mode-or-oobe#deployment-examples

							$sysprepOobeArgs += '/generalize'
						}

						$sysprepOobeArgs += '/unattend:"\Install\Scripts\Resources\UnattendOOBE.xml"'
					}
				}

				if ($testMode) {
					FocusScriptWindow
					$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
					Read-Host "    DEBUG - Press ENTER To Run Sysprep $sysprepOobeArgs" | Out-Null
				}
				
				Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue

				# Remove Previous Unattend Files
				if (Test-Path '\Windows\Panther\Unattend.xml') {
					Remove-Item '\Windows\Panther\Unattend.xml' -Force -ErrorAction Stop
				}
				
				if (Test-Path '\Windows\System32\Sysprep\Panther') {
					Remove-Item '\Windows\System32\Sysprep\Panther' -Recurse -Force -ErrorAction Stop
				}

				if (Test-Path '\Windows\System32\Sysprep\Sysprep_succeeded.tag') {
					Remove-Item '\Windows\System32\Sysprep\Sysprep_succeeded.tag' -Force -ErrorAction Stop # This tag should not exist, and Sysprep would delete it when it launches anyway.
				}

				# Sysprep Reference: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options
				$sysprepOobeExitCode = (Start-Process '\Windows\System32\Sysprep\sysprep.exe' -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Env:TEMP\fgComplete-Sysprep-oobe-Output.txt" -RedirectStandardError "$Env:TEMP\fgComplete-Sysprep-oobe-Error.txt" -ArgumentList $sysprepOobeArgs -ErrorAction Stop).ExitCode
				$sysprepOobeError = Get-Content -Raw "$Env:TEMP\fgComplete-Sysprep-oobe-Error.txt"
				$sysprepErrorLog = Get-Content -Raw '\Windows\System32\Sysprep\Panther\setuperr.log'
				
				if (($sysprepOobeExitCode -eq 0) -and ($null -eq $sysprepOobeError) -and ($null -eq $sysprepErrorLog) -and (Test-Path '\Windows\System32\Sysprep\Sysprep_succeeded.tag')) {
					# Sysprep can FAIL with and exit code of 0 and no StandardError, so we must also check for any error in "setuperr.log" and check for the "Sysprep_succeeded.tag" file.
					
					if ((Get-LocalUser 'Administrator' -ErrorAction SilentlyContinue).Enabled) {
						# Instead of disabling Administrator ourselves, use this as another indicator that Sysprep was successful and show an error if not.
						# https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/enable-and-disable-the-built-in-administrator-account#disabling-the-built-in-administrator-account
		
						Write-Host "`n  ERROR: Sysprep failed to disable Administrator account." -ForegroundColor Red
		
						$lastTaskSucceeded = $false
					} elseif (Test-Path '\Windows\System32\Sysprep\Unattend.xml') {
						try {
							# Removing THIS Unattend.xml should be done AFTER Sysprep has SUCCEEDED so that this script can re-run on reboot if any errors happen.
							Remove-Item '\Windows\System32\Sysprep\Unattend.xml' -Force -ErrorAction Stop

							Write-Host "`n  Successfully Ran System Preparation Tool (Sysprep) to Enter Out-of-Box Experience (OOBE) on Next Boot" -ForegroundColor Green
						} catch {
							Write-Host "`n  ERROR DELETING UNATTEND FILE AFTER SYSPREP: $_" -ForegroundColor Red
							Write-Host "`n  ERROR: Failed to delete `"Unattend.xml`" file after Sysprep." -ForegroundColor Red
							
							$lastTaskSucceeded = $false
						}
					}
				} else {
					if ($null -eq $sysprepOobeError) {
						$sysprepOobeError = Get-Content -Raw "$Env:TEMP\fgComplete-Sysprep-oobe-Output.txt"
					}

					if ($null -eq $sysprepOobeError) {
						$sysprepOobeError = 'N/A (Check SYSPREP LOG)'
					}

					if ($null -eq $sysprepErrorLog) {
						$sysprepErrorLog = Get-Content -Raw '\Windows\System32\Sysprep\Panther\setupact.log'
					}

					if (($null -eq $sysprepErrorLog) -or ($sysprepErrorLog -eq '')) {
						$sysprepErrorLog = ' N/A'
					} else {
						$sysprepErrorLog = "`n$sysprepErrorLog"
					}

					$sysprepSucceededTagNote = 'Succeeded Tag DNE'
					if (Test-Path '\Windows\System32\Sysprep\Sysprep_succeeded.tag') {
						$sysprepSucceededTagNote = 'Succeeded Tag Exists'
					}

					Write-Host "`n  SYSPREP LOG:$sysprepErrorLog" -ForegroundColor Red
					Write-Host "`n  SYSPREP ERROR: $sysprepOobeError" -ForegroundColor Red
					Write-Host "`n  ERROR: Failed to run `"sysprep /oobe`" ($sysprepSucceededTagNote + Sysprep Exit Code = $sysprepOobeExitCode)." -ForegroundColor Red
				
					$lastTaskSucceeded = $false
				}
			} catch {
				Write-Host "`n  ERROR DELETING PREVIOUS UNATTEND FILES OR STARTING SYSPREP: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to delete previous `"Unattend.xml`" files within `"\Windows\System32\Sysprep\`" or `"\Windows\Panther\`" or failed to start Sysprep." -ForegroundColor Red
				
				$lastTaskSucceeded = $false
			}

			Remove-Item "$Env:TEMP\fgComplete-*.txt" -Force -ErrorAction SilentlyContinue
		}

		if ($lastTaskSucceeded -and (Test-Path '\Install\')) {
			Write-Output "`n`n  Deleting `"Complete Windows`" Script..."
			
			try {
				Remove-Item '\Install\*' -Exclude 'QA Helper Log.txt' -Recurse -Force -ErrorAction Stop
				
				Write-Host "`n  Successfully Deleted `"Complete Windows`" Script" -ForegroundColor Green
			} catch {
				Write-Host "`n  ERROR DELETING SELF: $_" -ForegroundColor Red
				Write-Host "`n  ERROR: Failed to delete the `"Complete Windows`" script." -ForegroundColor Red
				
				$lastTaskSucceeded = $false
			}
		}
		
		if ($lastTaskSucceeded) {
			if ($testMode) {
				Write-Host "`n`n  AUTOMATIC SHUT DOWN DISABLED IN TEST MODE`n" -ForegroundColor Yellow
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				Read-Host '  Press ENTER to Shut Down' | Out-Null
			} else {
				$rebootTimeout = 15
				
				Write-Output "`n`n  This Computer Will Shut Down in $rebootTimeout Seconds..."
				Write-Host "`n  Or Press Any Key to Shut Down Now" -ForegroundColor Cyan
				
				FocusScriptWindow
				$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
				for ($secondsWaited = 0; $secondsWaited -lt $rebootTimeout; $secondsWaited ++) {
					if ($Host.UI.RawUI.KeyAvailable) {
						break
					}
					
					Start-Sleep 1
				}
			}
			
			Stop-Computer

			break # Not sure if Break is necessary after Stop-Computer but doesn't hurt.
		}

		Write-Host "`n`n  !!! THIS COMPUTER CANNOT BE SOLD UNTIL WINDOWS IS COMPLETED SUCCESSFULLY !!!" -ForegroundColor Red
		Write-Host "`n`n  If this issue continues, please inform Free Geek I.T.`n" -ForegroundColor Red

		if ((-not $didConnectToServer) -and (-not $didCacheDrivers) -and (-not $skipCacheDrivers)) {
			Write-Host "`n  Connecting to Local Free Geek Server Is Only Required to Cache Drivers to Expedite Future Installations" -ForegroundColor Yellow
			Write-Host "`n  IF YOU ARE COMPLETING A USB INSTALL, you can choose to continue without caching drivers...`n" -ForegroundColor Yellow
			
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			$continueWithoutDriverCacheChoice = Read-Host '  Type "Y" and Press ENTER to Continue WITHOUT Caching Drivers, or Just Press ENTER to Try Again'

			if ($continueWithoutDriverCacheChoice.ToUpper() -eq 'Y') {
				$skipCacheDrivers = $true
			}
		} else {
			FocusScriptWindow
			$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
			Read-Host '  Manually Reboot This Computer or Press ENTER to Try Again' | Out-Null
		}
	} else { # IS $onlyCacheDriversMode
		if ($didCacheDrivers) {
			Write-Host "`n`n  Press Any Key to Close This Window" -ForegroundColor Cyan
		} else {
			Write-Host "`n`n  If this issue continues, please inform Free Geek I.T." -ForegroundColor Red
			Write-Host "`n`n  Press Any Key to Try Again or Press `"Control + C`" (or Close This Window) to Cancel Caching Drivers" -ForegroundColor Cyan
		}
		
		FocusScriptWindow
		$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
		for ( ; ; ) {
			if ($Host.UI.RawUI.KeyAvailable) {
				break
			}
			
			Start-Sleep 1
		}

		if ($didCacheDrivers) {
			break
		}
	}
}
