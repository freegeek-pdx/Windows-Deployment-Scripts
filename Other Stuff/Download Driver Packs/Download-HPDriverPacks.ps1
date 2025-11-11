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

# Inspired by Driver Automation Tool (https://msendpointmgr.com/driver-automation-tool/) but DOES NOT use same folder structure as Driver Automation Tool
# Created a simplified script instead of using Driver Automation Tool directly to be able to download the latest Driver Pack for each model regardless of OS version and without having to choose the specific OS version
# as well as being able to more efficiently only download unique Driver Packs and then reference the correct unique Driver Pack for each model (since multiple models use the same Driver Pack).

# https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html
# OLD PAGE (no longer updated): https://ftp.hp.com/pub/caps-softpaq/cmit/HP_Driverpack_Matrix_x64.html

$ProgressPreference = 'SilentlyContinue' # Not showing progress makes "Invoke-WebRequest" downloads MUCH faster: https://stackoverflow.com/a/43477248

if (Test-Path "$PSScriptRoot\DriverPackCatalog-HP.cab") {
	Remove-Item "$PSScriptRoot\DriverPackCatalog-HP.cab" -Force
}

if ($IsWindows -or ($null -eq $IsWindows)) {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
}

Invoke-WebRequest -Uri 'https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab' -OutFile "$PSScriptRoot\DriverPackCatalog-HP.cab"
# OLD CAB (no longer updated): http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab

if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path "$PSScriptRoot\DriverPackCatalog-HP.cab")) {
	$expandExitCode = (Start-Process 'expand' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList "`"$PSScriptRoot\DriverPackCatalog-HP.cab`"", "`"$PSScriptRoot\DriverPackCatalog-HP-NEW.xml`"").ExitCode

	if ($expandExitCode -ne 0) {
		Write-Output ">>> EXPANSION FAILED (EXIT CODE $expandExitCode) <<<"
	}

	if ((Test-Path "$PSScriptRoot\DriverPackCatalog-HP-NEW.xml") -and (Test-Path "$PSScriptRoot\DriverPackCatalog-HP.xml")) {
		Remove-Item "$PSScriptRoot\DriverPackCatalog-HP.xml" -Force
	}

	Move-Item "$PSScriptRoot\DriverPackCatalog-HP-NEW.xml" "$PSScriptRoot\DriverPackCatalog-HP.xml" -Force
}

Get-Date

[xml]$hpDriverPackCatalogXML = Get-Content "$PSScriptRoot\DriverPackCatalog-HP.xml"

$hpSoftPaqURLsByIDs = @{}
$allSoftPaqsSize = 0

# Compiling all SoftPaqs as a Dictionary with IDs as Keys is MUCH faster than using "$hpDriverPackCatalogXML.NewDataSet.HPClientDriverPackCatalog.SoftPaqList.SoftPaq | Where-Object Id -eq $thisDriverPack.SoftPaqId" below.
foreach ($thisSoftPaq in $hpDriverPackCatalogXML.NewDataSet.HPClientDriverPackCatalog.SoftPaqList.SoftPaq) {
	$hpSoftPaqURLsByIDs[$thisSoftPaq.Id] = [ordered]@{
		DownloadURL = $thisSoftPaq.Url
		HashSHA256 = $thisSoftPaq.SHA256 # A few SoftPaqs don't have SHA256
		HashMD5 = $thisSoftPaq.MD5 # So get MD5 as a backup
		Size = $thisSoftPaq.Size
	}

	$allSoftPaqsSize += $thisSoftPaq.Size
}

# We won't need to download all of these, but here are the stats:
# $hpSoftPaqURLsByIDs.Count # 655 as of 01/13/21
# $allSoftPaqsSize # 469220989418 bytes = 469 GB as of 01/13/21

# Create Dictionary with $thisSystemID as key to overwrite old keys with new ones to only download the latest Driver reference.
$driverPacksForSystemIDs = @{}

# Collect all System IDs for Model Names to verify that there are no situations where the wrong Driver Pack could be set for a Model Name
$systemIDsForModelNames = @{}

foreach ($thisDriverPack in $hpDriverPackCatalogXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack) {
	if (($thisDriverPack.Architecture -eq '64-bit') -and (-not $thisDriverPack.OSName.Contains(' IoT '))) {
		$osVersionNumber = 0

		if (($thisDriverPack.OSName.StartsWith('Windows 10') -or $thisDriverPack.OSName.StartsWith('Windows 11')) -and $thisDriverPack.OSName.Contains(',')) {
			$osVersionNumber = $thisDriverPack.OSName -Replace 'Windows 10 64-bit, ', '10'
			$osVersionNumber = $osVersionNumber -Replace 'Windows 11 64-bit, ', '11'
			$osVersionNumber = $osVersionNumber -Replace 'H1', '03'
			$osVersionNumber = $osVersionNumber -Replace 'H2', '09'
			$osVersionNumber = [decimal]($osVersionNumber -Replace '[^0-9]').Trim()
		} else {
			$osVersionNumber = $thisDriverPack.OSName -Replace '64-bit'
			$osVersionNumber = [decimal]($osVersionNumber -Replace '[^0-9.]').Trim()
			$osVersionNumber *= 10000
		}

		$systemIDs = $thisDriverPack.SystemId.Split(',').Trim().ToLower()

		if ($systemIDs -is [string]) {
			$systemIDs = @($systemIDs)
		}

		$modelName = $thisDriverPack.SystemName.Trim().ToLower()

		<#
		CONVERSIONS FOR MODEL NAMES IN DRIVER PACK TO MODEL NAMES FROM WINDOWS WMI:

		Convertible Minitower = CMT
		Microtower = MT
		Desktop Mini = DM
		Small Form Factor = SFF
		All-in-One = AiO (or Aio)
		Ultra-slim = USDT
		Tower = TWR
		Base Model = {REMOVED}
		(ENERGY STAR) = {REMOVED}
		(with PCI slot) = {REMOVED}
		35W = {MOVED TO END}
		65W = {MOVED TO END}
		MAY OR MAY NOT INCLUDE "PC" AT THE END - SO MAKE VARIANTS WITH AND WITHOUT " PC" AT THE END
		#>

		$modelNameConvertedForWMI = $modelName.Replace('convertible minitower', 'cmt').Replace('microtower', 'mt').Replace('desktop mini', 'dm').Replace('small form factor', 'sff').Replace('all-in-one', 'aio').Replace('ultra-slim', 'usdt').Replace('tower', 'twr').Replace(' base model', '').Replace(' (energy star)', '').Replace(' (with pci slot)', '')

		if ($modelNameConvertedForWMI.EndsWith(' pc')) {
			$modelNameConvertedForWMI = $modelNameConvertedForWMI.Substring(0, ($modelNameConvertedForWMI.length - 3))
		}

		if ($modelNameConvertedForWMI.Contains(' 35w')) {
			$modelNameConvertedForWMI = "$($modelNameConvertedForWMI.Replace(' 35w', '')) 35w"
		}

		if ($modelNameConvertedForWMI.Contains(' 65w')) {
			$modelNameConvertedForWMI = "$($modelNameConvertedForWMI.Replace(' 65w', '')) 65w"
		}

		if ($null -eq $systemIDsForModelNames[$modelName]) {
			$systemIDsForModelNames[$modelName] = @()
		}
		$systemIDsForModelNames[$modelName] += $systemIDs

		if ($null -eq $systemIDsForModelNames[$modelNameConvertedForWMI]) {
			$systemIDsForModelNames[$modelNameConvertedForWMI] = @()
		}
		$systemIDsForModelNames[$modelNameConvertedForWMI] += $systemIDs

		if ($null -eq $systemIDsForModelNames["$modelNameConvertedForWMI pc"]) {
			$systemIDsForModelNames["$modelNameConvertedForWMI pc"] = @()
		}
		$systemIDsForModelNames["$modelNameConvertedForWMI pc"] += $systemIDs

		$systemIDs += $modelName
		$systemIDs += $modelNameConvertedForWMI
		$systemIDs += "$modelNameConvertedForWMI pc"

		$systemIDs = ($systemIDs | Sort-Object -Unique)

		$thisSoftPaq = $hpSoftPaqURLsByIDs[$thisDriverPack.SoftPaqId]

		if ($null -ne $thisSoftPaq) {
			$exeDownloadURL = $thisSoftPaq.DownloadURL
			$exeFileName = Split-Path $exeDownloadURL -Leaf

			foreach ($thisSystemID in $systemIDs) {
				$addDriver = $true

				if (($null -ne $driverPacksForSystemIDs[$thisSystemID]) -and ($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber -gt $osVersionNumber)) {
					# Write-Output "Skipping OLDER DRIVERS - $thisSystemID - $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber) > $osVersionNumber"
					$addDriver = $false
				}

				if ($addDriver) {
					$driverPacksForSystemIDs[$thisSystemID] = [ordered]@{
						SystemID = $thisSystemID
						DownloadURL = $exeDownloadURL
						HashSHA256 = $thisSoftPaq.HashSHA256
						HashMD5 = $thisSoftPaq.HashMD5
						OSVersionNumber = $osVersionNumber
						Size = $thisSoftPaq.Size
						FileName = $exeFileName
						DriverPackID = $thisDriverPack.SoftPaqId
					}
				}
			}
		}
	}
}

# Make sure a Model Name only ever uses the OLDEST Driver Pack of its associated System IDs.
foreach ($theseSystemIDsForModelNames in ($systemIDsForModelNames.GetEnumerator() | Sort-Object -Property Key)) {
	$theseSystemIDs = ($theseSystemIDsForModelNames.Value | Sort-Object -Unique)

	foreach ($thisSystemID in $theseSystemIDs) {
		if (($driverPacksForSystemIDs[$thisSystemID].DriverPackID -ne $driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].DriverPackID) -and ($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber -lt $driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].OSVersionNumber)) {
			# Write-Output "CONFLICT - SETTING MODEL NAME TO USE OLDEST DRIVER PACK OF ASSOCIATED SYSTEM IDs - $thisSystemID ($($driverPacksForSystemIDs[$thisSystemID].DriverPackID)) != $($theseSystemIDsForModelNames.Key) ($($driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].DriverPackID)) && $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber) < $($driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key].OSVersionNumber)"

			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['DownloadURL'] = $driverPacksForSystemIDs[$thisSystemID].DownloadURL
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['HashSHA256'] = $driverPacksForSystemIDs[$thisSystemID].HashSHA256
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['HashMD5'] = $driverPacksForSystemIDs[$thisSystemID].HashMD5
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['OSVersionNumber'] = $driverPacksForSystemIDs[$thisSystemID].OSVersionNumber
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['Size'] = $driverPacksForSystemIDs[$thisSystemID].Size
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['FileName'] = $driverPacksForSystemIDs[$thisSystemID].FileName
			$driverPacksForSystemIDs[$theseSystemIDsForModelNames.Key]['DriverPackID'] = $driverPacksForSystemIDs[$thisSystemID].DriverPackID
		}
	}
}

$uniqueDriverPacks = @{}
$allUnqiueDriverPacksSize = 0
$redundantDriverPacksSize = 0

foreach ($thisDriverPack in ($driverPacksForSystemIDs.GetEnumerator() | Sort-Object -Property Key)) {
	$redundantDriverPacksSize += $thisDriverPack.Value.Size

	if (-not $uniqueDriverPacks[$thisDriverPack.Value.DriverPackID]) {
		$allUnqiueDriverPacksSize += $thisDriverPack.Value.Size
		$uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] = @($thisDriverPack.Value)
	} else {
		$uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] += $thisDriverPack.Value
	}
}

# We won't need to download all of these, but here are the stats:
# $driverPacksForSystemIDs.Count # 464 as of 01/13/21
# $redundantDriverPacksSize # 390130586241 = 390 GB as of 01/13/21

# THIS IS ALL WE ACTUALL NEED TO DOWNLOAD, SO THAT'S WHAT WE'LL DO:
# $uniqueDriverPacks.Count # 164 as of 01/13/21
# $allUnqiueDriverPacksSize # 131203610901 = 131 GB as of 01/13/21

$exeCount = 0
$downloadedCount = 0
$validatedExeCount = 0
$expandedCount = 0
$notEnoughSpaceCount = 0

$hpDriverPacksPath = 'F:\SMB\Drivers\Packs\HP'

foreach ($theseRedundantDriverPacks in ($uniqueDriverPacks.GetEnumerator() | Sort-Object -Property Key)) {
	$thisUniqueDriverPack = $theseRedundantDriverPacks.Value | Select-Object -First 1

	$exeCount ++
	Write-Output '----------'
	Write-Output "UNIQUE DRIVER PACK EXE $exeCount (USED BY $($theseRedundantDriverPacks.Value.Count) SYSTEM IDs):"

	if ($IsWindows -or ($null -eq $IsWindows)) {
		$theseRedundantDriverPacks.Value.SystemID -Join ', '
	} else {
		foreach ($thisRedundantDriverPack in $theseRedundantDriverPacks.Value) {
			Write-Output '-----'
			$thisRedundantDriverPack | Format-Table -AutoSize -HideTableHeaders
		}
	}

	if ($IsWindows -or ($null -eq $IsWindows)) {
		$thisUniqueDriverPack.DownloadURL
	}

	if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $hpDriverPacksPath)) {
		$exeDownloadPath = "$hpDriverPacksPath\Unique Driver Pack EXEs"
		$exeExpansionPath = "$hpDriverPacksPath\Unique Driver Packs"

		if (-not (Test-Path $exeDownloadPath)) {
			New-Item -ItemType 'Directory' -Force -Path $exeDownloadPath | Out-Null
		}

		if (-not (Test-Path $exeExpansionPath)) {
			New-Item -ItemType 'Directory' -Force -Path $exeExpansionPath | Out-Null
		}

		if (-not (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)")) {
			if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
				Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
			}

			if ((Get-Volume (Get-Item $hpDriverPacksPath).PSDrive.Name).SizeRemaining -ge 10GB) {
				Write-Output 'DOWNLOADING...'
				Invoke-WebRequest -Uri $thisUniqueDriverPack.DownloadURL -OutFile "$exeDownloadPath\$($thisUniqueDriverPack.FileName)"

				if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
					$downloadedCount ++

					Write-Output 'VALIDATING EXE...'
					if (($null -ne $thisUniqueDriverPack.HashSHA256) -and ($thisUniqueDriverPack.HashSHA256 -ne '')) {
						if ((Get-FileHash "$exeDownloadPath\$($thisUniqueDriverPack.FileName)").Hash -eq $thisUniqueDriverPack.HashSHA256) {
							$validatedExeCount ++
						} else {
							Write-Output '>>> INVALID - DELETING EXE <<<'
							Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
						}
					} elseif (($null -ne $thisUniqueDriverPack.HashMD5) -and ($thisUniqueDriverPack.HashMD5 -ne '')) {
						Write-Output '!!! VALIDATING WITH MD5 FALLBACK !!!'
						if ((Get-FileHash "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Algorithm 'MD5').Hash -eq $thisUniqueDriverPack.HashMD5) {
							$validatedExeCount ++
						} else {
							Write-Output '>>> INVALID EXE - DELETING EXE <<<'
							Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
						}
					} else {
						Write-Output '!!! NO HASH TO VALIDATE !!!'
					}

					if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
						Write-Output 'EXPANDING...'

						# The EXE expansion will make all necessary directories.
						$expandExitCode = (Start-Process "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -NoNewWindow -Wait -PassThru -ArgumentList '/s', '/e', "/f `"$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)`"").ExitCode

						Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force

						if (($expandExitCode -eq 0) -or ($expandExitCode -eq 1168)) {
							# It appears that 1168 is the success exit code for newer driver packs, but older ones return 0 as success
							$expandedCount ++
						} else {
							Write-Output ">>> EXPANSION FAILED (EXIT CODE $expandExitCode) - DELETING FOLDER <<<"

							if (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
								Remove-Item "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Recurse -Force
							}
						}
					}
				}
			} else {
				Write-Output 'NOT ENOUGH FREE SPACE TO DOWNLOAD'
				$notEnoughSpaceCount ++
			}
		} else {
			# TODO: Check for basic expected structure to validate expansion.
			Write-Output 'ALREADY DOWNLOADED AND EXPANDED'
		}

		if (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
			foreach ($thisRedundantDriverPack in $theseRedundantDriverPacks.Value) {
				if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $hpDriverPacksPath)) {
					Set-Content "$hpDriverPacksPath\$($thisRedundantDriverPack.SystemID).txt" "Unique Driver Packs\$($thisRedundantDriverPack.DriverPackID)"
				}
			}

			Get-ChildItem "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)\*" -File -Include '*.cva' | ForEach-Object {
				$systemIDsFromDriverPack = ($_ | Get-Content | Select-String 'SysID')
				if ($systemIDsFromDriverPack.Count -gt 0) {
					Write-Output 'SYSTEM IDs FROM DRIVER PACK:'
					((($systemIDsFromDriverPack -Split ('=')) | Sort-Object) -Join ', ').ToLower().Replace('0x', '')
				}
			}
		}
	}
}

if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $hpDriverPacksPath)) {
	Write-Output '----------'
	Write-Output 'CHECKING FOR STRAY DRIVER PACKS...'

	$allReferencedDriverPacks = @()

	Get-ChildItem "$hpDriverPacksPath\*" -File -Include '*.txt' | ForEach-Object {
		$thisDriverPack = ($_ | Get-Content -First 1)

		if (($null -ne $thisDriverPack) -and $thisDriverPack.Contains('\')) {
			$thisDriverPack = $thisDriverPack.Split('\')[1]

			if (-not $allReferencedDriverPacks.Contains($thisDriverPack)) {
				$allReferencedDriverPacks += $thisDriverPack
			}
		}
	}

	Get-ChildItem "$hpDriverPacksPath\Unique Driver Packs" | ForEach-Object {
		if (-not $allReferencedDriverPacks.Contains($_.Name)) {
			Write-Output "DELETING STRAY DRIVER PACK: $($_.Name)"
			Remove-Item $_.FullName -Recurse -Force
		}
	}

	if (Test-Path "$hpDriverPacksPath\Unique Driver Pack EXEs") {
		Remove-Item "$hpDriverPacksPath\Unique Driver Pack EXEs" -Recurse -Force
	}
}

Write-Output '----------'
Write-Output "FINISHED AT: $(Get-Date)"
Write-Output "DETECTED: $($uniqueDriverPacks.Count) Unique HP Driver Packs (for $($driverPacksForSystemIDs.Count) System IDs)"
Write-Output "DOWNLOADED: $downloadedCount"
Write-Output "VALIDATED EXEs: $validatedExeCount"
Write-Output "EXPANDED: $expandedCount"
Write-Output "NOT ENOUGH SPACE TO DOWNLOAD: $notEnoughSpaceCount"
Write-Output '----------'

if ($IsWindows -or ($null -eq $IsWindows)) {
	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
}

Read-Host 'DONE - PRESS ENTER TO EXIT' | Out-Null
