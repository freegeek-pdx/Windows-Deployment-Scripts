##################################################################################
##                                                                              ##
##   TO RUN THIS SCRIPT, LAUNCH "Run Update Windows on FG Install Drives.cmd"   ##
##                                                                              ##
##################################################################################

#
# MIT License
#
# Copyright (c) 2024 Free Geek
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

$Host.UI.RawUI.WindowTitle = 'Update Windows on FG Install Drives'

$promptCaption = "  Would you like to check for app installer updates?"
$promptChoices = '&Yes', '&No'

$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
$promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 0)

if ($promptResponse -eq 0) {
	Start-Process 'powershell' -NoNewWindow -Wait -ArgumentList '-NoLogo', '-NoProfile', '-ExecutionPolicy Unrestricted', "-File `"$PSScriptRoot\App Installers\Download Latest Windows App Installers.ps1`"" -ErrorAction Stop
}

$Host.UI.RawUI.WindowTitle = 'Update Windows on FG Install Drives'

Write-Output "`n`n  Locating FG Install Drives..."

$allDisks = Get-Disk # DO NOT USE " | Where-Object DriveType -eq 'Removable'" because NVMe M.2 enclosures mount as "Fixed" drives.

foreach ($thisDisk in $allDisks) {
	# Each drive will take up 3 drive letters by default, and if there are enough drives plugged into take up every drive letter through "Z" some partitions may not get mounted.
	# So, unmount "FG BOOT" partitions to make more drive letters available to be able to mount "FG WINDOWS" and "FG Install" partitions in the next loop if needed.
	# Unmounting all "FG BOOT" partitions is done all at once in a loop before mounting "FG WINDOWS" and "FG Install" partitions and starting the actual update on each drive
	# in another loop since the order of disks could end up where mounting is attempted before drive letters have been made available by unmounting enough "FG BOOT" partitions first.

	if ($thisDisk.IsOffline -eq $True) {
		Write-Output "`n  Setting Offline Disk to Online..."

		# Disks starting as offline was an issue when the Linux script started with cloning the Linux installation ISO (which is no longer the case)
		# and partitions across multiple drives had the same UUIDs and were considered conflicting duplicates and not mounted.
		$thisDisk | Set-Disk -IsOffline $False # Now, all disks should start as "online" but doesn't hurt to double-check.
	}

	$thisFGBootVolume = $thisDisk | Get-Partition | Get-Volume | Where-Object FileSystemLabel -eq 'FG BOOT' | Select-Object -First 1
	$thisFGBootDriveLetter = $thisFGBootVolume.DriveLetter

	if (($null -ne $thisFGBootVolume) -and ($null -ne $thisFGBootDriveLetter)) {
		Write-Output "`n  Unmounting `"FG BOOT`" Partition At `"$($thisFGBootDriveLetter):`"..."

		Remove-PartitionAccessPath -DriveLetter $thisFGBootDriveLetter -AccessPath "$($thisFGBootDriveLetter):"
	}
}

$thisDiskIndex = 1
foreach ($thisDisk in $allDisks) {
	$thisDiskVolumes = $thisDisk | Get-Partition | Get-Volume

	$thisFGInstallVolume = $thisDiskVolumes | Where-Object FileSystemLabel -eq 'FG Install' | Select-Object -First 1
	$thisFGInstallDriveLetter = $thisFGInstallVolume.DriveLetter

	if (($null -ne $thisFGInstallVolume) -and ($null -eq $thisFGInstallDriveLetter)) {
		Write-Output "`n`n  Mounting `"FG Install`" Partition..."

		$thisFGInstallVolume | Get-Partition | Add-PartitionAccessPath -AssignDriveLetter

		$thisDiskVolumes = $thisDisk | Get-Partition | Get-Volume
		$thisFGInstallVolume = $thisDiskVolumes | Where-Object FileSystemLabel -eq 'FG Install' | Select-Object -First 1
		$thisFGInstallDriveLetter = $thisFGInstallVolume.DriveLetter
	}

	$thisFGWindowsVolume = $thisDiskVolumes | Where-Object FileSystemLabel -eq 'FG WINDOWS' | Select-Object -First 1
	$thisFGWindowsDriveLetter = $thisFGWindowsVolume.DriveLetter

	if (($null -ne $thisFGWindowsVolume) -and ($null -eq $thisFGWindowsDriveLetter)) {
		Write-Output "`n`n  Mounting `"FG WINDOWS`" Partition..."

		$thisFGWindowsVolume | Get-Partition | Add-PartitionAccessPath -AssignDriveLetter

		$thisDiskVolumes = $thisDisk | Get-Partition | Get-Volume
		$thisFGWindowsVolume = $thisDiskVolumes | Where-Object FileSystemLabel -eq 'FG WINDOWS' | Select-Object -First 1
		$thisFGWindowsDriveLetter = $thisFGWindowsVolume.DriveLetter
	}

	if (($null -ne $thisFGInstallDriveLetter) -and ($null -ne $thisFGWindowsDriveLetter)) {
		$thisFGInstallDriveLetter = "$($thisFGInstallDriveLetter):"
		$thisFGWindowsDriveLetter = "$($thisFGWindowsDriveLetter):"

		Write-Output "`n`n  FG Install Drive $($thisDiskIndex): FG Install `"$thisFGInstallDriveLetter`" | FG WINDOWS `"$thisFGWindowsDriveLetter`""

		Write-Output "`n  Starting Copying Files in New Minimized Window..."

		Start-Process 'powershell' -WindowStyle Minimized -ArgumentList '-NoLogo', '-NoProfile', '-NoExit', '-WindowStyle Minimized', '-ExecutionPolicy Unrestricted', "-File `"$PSScriptRoot\Copy Windows to FG Install Drive.ps1`"", $thisFGInstallDriveLetter, $thisFGWindowsDriveLetter -ErrorAction Stop

		Start-Sleep 1 # Sleep a second before starting the next background process.

		$thisDiskIndex ++
	}
}

Write-Output ''
