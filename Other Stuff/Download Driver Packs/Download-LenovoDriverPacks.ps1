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

# https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index

# IMPORTANT: Some Lenovo Driver Packs create very long paths and need LongPathsEnabled on Windows to be able to successfully move the extracted Driver Packs to the desired locations.
# https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation#enable-long-paths-in-windows-10-version-1607-and-later

if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV1-NEW.xml") {
    Remove-Item "$PSScriptRoot\DriverPackCatalog-LenovoV1-NEW.xml" -Force
}

if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV2-NEW.xml") {
    Remove-Item "$PSScriptRoot\DriverPackCatalog-LenovoV2-NEW.xml" -Force
}

if ($IsWindows -or ($null -eq $IsWindows)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
}

Invoke-WebRequest -Uri 'https://download.lenovo.com/cdrt/td/catalog.xml' -OutFile "$PSScriptRoot\DriverPackCatalog-LenovoV1-NEW.xml"

if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV1-NEW.xml") {
    if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml") {
        Remove-Item "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml" -Force
    }

    Move-Item "$PSScriptRoot\DriverPackCatalog-LenovoV1-NEW.xml" "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml" -Force
}

Invoke-WebRequest -Uri 'https://download.lenovo.com/cdrt/td/catalogv2.xml' -OutFile "$PSScriptRoot\DriverPackCatalog-LenovoV2-NEW.xml"

if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV2-NEW.xml") {
    if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV2.xml") {
        Remove-Item "$PSScriptRoot\DriverPackCatalog-LenovoV2.xml" -Force
    }

    Move-Item "$PSScriptRoot\DriverPackCatalog-LenovoV2-NEW.xml" "$PSScriptRoot\DriverPackCatalog-LenovoV2.xml" -Force
}

Get-Date

[xml]$lenovoDriverPackCatalogXMLv1 = Get-Content "$PSScriptRoot/DriverPackCatalog-LenovoV1.xml"
[xml]$lenovoDriverPackCatalogXMLv2 = Get-Content "$PSScriptRoot/DriverPackCatalog-LenovoV2.xml"

$driverPacksForSystemIDs = @{}

foreach ($thisDriverPack in $lenovoDriverPackCatalogXMLv2.ModelList.Model) {
    $systemIDs = $thisDriverPack.Types.Type
    
    if ($null -ne $systemIDs) {
        $systemIDs = $systemIDs.Trim().ToLower()
    } else {
        $systemIDs = @()
    }

    if ($systemIDs -is [string]) {
        $systemIDs = @($systemIDs)
    }

    $thisModelVersion = ($thisDriverPack.name.ToLower() -Split (' type '))[0]

    foreach ($thisSystemID in $systemIDs) {
        $thisModelVersion = $thisModelVersion.Replace(" $thisSystemID", '')
    }

    $modelName = $thisModelVersion.Trim()
    $systemIDs += $modelName
    
    $systemIDs = ($systemIDs | Sort-Object -Unique)
    
    $sccmVersions = $thisDriverPack.SCCM
    $exeDownloadURL = $null
    $osVersionForExe = 0

    foreach ($thisSccmVersion in $sccmVersions) {
        $osVersionNumber = 0

        if ($thisSccmVersion.version -eq '*') {
            $osVersionNumber = 10
        } else {
            $osVersionNumber = $thisSccmVersion.version
            $osVersionNumber = $osVersionNumber -Replace 'H1', '03'
            $osVersionNumber = $osVersionNumber -Replace 'H2', '09'
            $osVersionNumber = [decimal]($osVersionNumber -Replace '[a-zA-Z]').Trim()
        }

        if ($osVersionNumber -gt $osVersionForExe) {
            $osVersionForExe = $osVersionNumber
            $exeDownloadURL = $thisSccmVersion.InnerText
        }
    }

    $exeFileName = Split-Path $exeDownloadURL -Leaf
    
    foreach ($thisSystemID in $systemIDs) {
        $addDriver = $true

        if ($thisSystemID.Contains(' ')) {
            # Do NOT allow driver packs to be used for any Model names if the driver pack contains "_mt" in the filename
            # which means it is only intended for specific types and therefore we will only match it to that specific type.

            if ($exeFileName.ToLower().Contains('_mt')) {
                # Write-Output "NOT ALLOWING TYPE SPECIFIC '$exeFileName' FOR '$thisSystemID'"
                $addDriver = $false
            } else {
                # Write-Output "ALLOWING '$exeFileName' FOR ALL '$thisSystemID' TYPES"
            }
        } elseif ($exeFileName.ToLower().Contains('_mt')) {
            if ($exeFileName.ToLower().Contains("_mt$thisSystemID") -or $exeFileName.ToLower().Contains("-mt$thisSystemID") -or $exeFileName.ToLower().Contains("-$thisSystemID")) {
                # Write-Output "TYPE SPECIFIC '$exeFileName' IS CORRECT FOR '$thisSystemID'"
            } else {
                # Write-Output "INCORRECT TYPE '$thisSystemID' FOR TYPE SPECIFIC '$exeFileName'"
                $addDriver = $false
            }
        } else {
            # Write-Output "ALLOWING GENERIC EXE '$exeFileName' FOR '$thisSystemID' TYPE"
        }

        if ($addDriver) {
            if ($driverPacksForSystemIDs[$thisSystemID]) {
                if ($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber -gt $osVersionForExe) {
                    Write-Output "Skipping OLDER DRIVERS - $thisSystemID - $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumber) > $osVersionForExe"
                    $addDriver = $false
                }
            }

            if ($addDriver) {
                $driverPacksForSystemIDs[$thisSystemID] = [ordered]@{
                    SystemID = $thisSystemID
                    ModelName = $modelName
                    DownloadURL = $exeDownloadURL
                    OSVersionNumber = $osVersionForExe
                    FileName = $exeFileName
                    DriverPackID = $exeFileName.Replace('.exe', '')
                }
            }
        }
    }
}

foreach ($thisDriverPack in $lenovoDriverPackCatalogXMLv1.Products.Product) {
    if ($thisDriverPack.os -ne 'win732') { # win732, win764, win81, win10
        $systemIDs = $thisDriverPack.Queries.Types.Type

        if ($null -ne $systemIDs) {
            $systemIDs = $systemIDs.Trim().ToLower()
        } else {
            $systemIDs = @()
        }

        if ($systemIDs -is [string]) {
            $systemIDs = @($systemIDs)
        }

        $modelName = $thisDriverPack.Queries.Version.Trim().ToLower()
        $systemIDs += $modelName

        $systemIDs = ($systemIDs | Sort-Object -Unique)

        $lenovoSupportPage = ((((($thisDriverPack.DriverPack | Where-Object { ($_.id -eq 'sccm') -and $_.InnerText.Contains('/ds') }).InnerText -Replace 'http:', 'https:') -Replace '/us/', '/') -Replace '/old', '/') -Replace 'com/downloads', 'com/us/en/downloads')
        
        if (($null -ne $lenovoSupportPage) -and ($lenovoSupportPage -ne '')) {
            $osVersionNumber = 0

            if ($thisDriverPack.build -eq '*') {
                if ($thisDriverPack.os -eq 'win764') {
                    $osVersionNumber = 7
                } elseif ($thisDriverPack.os -eq 'win81') {
                    $osVersionNumber = 8.1
                } elseif ($thisDriverPack.os -eq 'win10') {
                    $osVersionNumber = 10
                }
            } elseif ($thisDriverPack.os -eq 'win10') {
                $osVersionNumber = $thisDriverPack.build
                $osVersionNumber = $osVersionNumber -Replace 'H1', '03'
                $osVersionNumber = $osVersionNumber -Replace 'H2', '09'
                $osVersionNumber = [decimal]($osVersionNumber -Replace '[a-zA-Z]').Trim()
            }
            
            foreach ($thisSystemID in $systemIDs) {
                if ($driverPacksForSystemIDs[$thisSystemID]) {
                    if ($driverPacksForSystemIDs[$thisSystemID].OSVersionNumberForSupportPage) {
                        if ($osVersionNumber -gt $driverPacksForSystemIDs[$thisSystemID].OSVersionNumberForSupportPage) {
                            if ($driverPacksForSystemIDs[$thisSystemID]['LenovoSupportPage']) {
                                # Write-Output "($osVersionNumber > $($driverPacksForSystemIDs[$thisSystemID].OSVersionNumberForSupportPage)) UPDATING SUPPORT PAGE FOR '$thisSystemID' TO '$lenovoSupportPage'"
                                $driverPacksForSystemIDs[$thisSystemID]['LenovoSupportPage'] = $lenovoSupportPage
                                $driverPacksForSystemIDs[$thisSystemID]['OSVersionNumberForSupportPage'] = $osVersionNumber
                            }
                        }
                    } else {
                        # Write-Output "ADDING SUPPORT PAGE TO EXISTING ID '$thisSystemID'"
                        $driverPacksForSystemIDs[$thisSystemID]['LenovoSupportPage'] = $lenovoSupportPage
                        $driverPacksForSystemIDs[$thisSystemID]['OSVersionNumberForSupportPage'] = $osVersionNumber
                    }
                } else {
                    # Write-Output "ADDING '$thisSystemID' WITH SUPPORT PAGE '$lenovoSupportPage'"

                    $driverPacksForSystemIDs[$thisSystemID] = [ordered]@{
                        SystemID = $thisSystemID
                        ModelName = $modelName
                        LenovoSupportPage = $lenovoSupportPage
                        OSVersionNumberForSupportPage = $osVersionNumber
                    }
                }
            }
        }
    }
}

$supportPageDetailsForEXEs = @{}

# "DriverPackCatalog-LenovoV1-EXEsFromSupportPages.xml" is created by running "Retrieve-LenovoEXEsFromSupportPages.ps1" on Windows.
if (Test-Path "$PSScriptRoot/DriverPackCatalog-LenovoV1-EXEsFromSupportPages.xml") {
    $exesFromSupportPagesForLenovoDriverPackCatalogXMLv1 = Import-Clixml -Path "$PSScriptRoot/DriverPackCatalog-LenovoV1-EXEsFromSupportPages.xml"
    
    foreach ($supportPageInfo in ($exesFromSupportPagesForLenovoDriverPackCatalogXMLv1.GetEnumerator() | Sort-Object -Property Key)) {
        foreach ($thisSupportPageInfo in $supportPageInfo.Value) {
            if ($null -ne $thisSupportPageInfo.DownloadURL) {
                $driverPackID = (Split-Path $thisSupportPageInfo.DownloadURL -Leaf).ToLower().Replace('.exe', '')
                $supportPageDetailsForEXEs[$driverPackID] = $thisSupportPageInfo
            }
        }
    }

    foreach ($thisDriverPack in ($driverPacksForSystemIDs.GetEnumerator() | Sort-Object -Property Key)) {
        if ($thisDriverPack.Value.LenovoSupportPage) {
            $exeAndModelInfoFromSupportPage = $exesFromSupportPagesForLenovoDriverPackCatalogXMLv1[$thisDriverPack.Value.LenovoSupportPage]
            
            $exeDownloadURL = $null

            $osVersionForExe = 0
            $osVersionNumber = 0

            foreach ($thisExeFromSupportPage in $exeAndModelInfoFromSupportPage) {
                if ($null -ne $thisExeFromSupportPage.DownloadURL) {
                    $osVersionNumber = $thisExeFromSupportPage.OS -Replace '64-bit'

                    if ($osVersionNumber.StartsWith('Windows 10') -and $osVersionNumber.Contains(' (Version ')) {
                        $osVersionNumber = $osVersionNumber -Replace 'Windows 10 \(Version '
                        $osVersionNumber = $osVersionNumber -Replace 'H1', '03'
                        $osVersionNumber = $osVersionNumber -Replace 'H2', '09'
                        $osVersionNumber = [decimal]($osVersionNumber -Replace '[^0-9]').Trim()
                    } else {
                        $osVersionNumber = [decimal]($osVersionNumber -Replace '[^0-9.]').Trim()
                    }

                    if ($osVersionNumber -gt $osVersionForExe) {
                        # Write-Output "$($thisDriverPack.Value.LenovoSupportPage) - $osVersionNumber > $osVersionForExe = $($thisExeFromSupportPage.DownloadURL)"
                        $osVersionForExe = $osVersionNumber
                        $exeDownloadURL = $thisExeFromSupportPage.DownloadURL
                    } elseif ($osVersionNumber -eq $osVersionForExe) {
                        $modelNameID = $thisDriverPack.Value.ModelName.Split(' ')[1]

                        if ($thisExeFromSupportPage.DownloadURL.ToLower().Contains("_$($modelNameID)_")) {
                            $exeDownloadURL = $thisExeFromSupportPage.DownloadURL
                        } elseif ($exeDownloadURL.Contains("_$modelNameID_")) {
                            # Write-Output "KEEPING '$exeDownloadURL' FOR $($thisDriverPack.Value.ModelName)"
                        } else {
                            Write-Output "THIS SHOULD NOT HAPPEN - $($thisDriverPack.Value.SystemID) - $($thisDriverPack.Value.LenovoSupportPage) - $osVersionNumber == $osVersionForExe - $exeDownloadURL / $($thisExeFromSupportPage.DownloadURL)"
                        }

                        # Write-Output "$($thisDriverPack.Value.ModelName) = $exeDownloadURL"
                    }
                } else {
                    Write-Output "THIS SHOULD NOT HAPPEN (NULL DownloadURL) - $($thisDriverPack.Value.SystemID) - $($thisDriverPack.Value.LenovoSupportPage)"
                }
            }

            if ($null -ne $exeDownloadURL) {
                $addDriver = $true
                
                $exeFileName = Split-Path $exeDownloadURL -Leaf

                if ($thisDriverPack.Key.Contains(' ')) {
                    # Do NOT allow driver packs to be used for any Model names if the driver pack contains "_mt" in the filename
                    # which means it is only intended for specific types and therefore we will only match it to that specific type.
        
                    if ($exeFileName.ToLower().Contains('_mt')) {
                        # Write-Output "NOT ALLOWING TYPE SPECIFIC '$exeFileName' FOR '$($thisDriverPack.Key)'"
                        $addDriver = $false
                    } else {
                        # Write-Output "ALLOWING '$exeFileName' FOR ALL '$($thisDriverPack.Key)' TYPES"
                    }
                } elseif ($exeFileName.ToLower().Contains('_mt')) {
                    if ($exeFileName.ToLower().Contains("_mt$($thisDriverPack.Key)") -or $exeFileName.ToLower().Contains("-mt$($thisDriverPack.Key)") -or $exeFileName.ToLower().Contains("-$($thisDriverPack.Key)")) {
                        # Write-Output "TYPE SPECIFIC '$exeFileName' IS CORRECT FOR '$($thisDriverPack.Key)'"
                    } else {
                        # Write-Output "INCORRECT TYPE '$($thisDriverPack.Key)' FOR TYPE SPECIFIC '$exeFileName'"
                        $addDriver = $false
                    }
                } else {
                    # Write-Output "ALLOWING GENERIC EXE '$exeFileName' FOR '$($thisDriverPack.Key)' TYPE"
                }

                if ($addDriver) {
                    if (($null -ne $thisDriverPack.Value.DownloadURL) -and ($null -ne $thisDriverPack.Value.OSVersionNumber)) {
                        # Special conditions for when we already have a DownloadURL and only want to replace it with a possible newer one.
                        
                        if ($osVersionForExe -le $thisDriverPack.Value.OSVersionNumber) {
                            # DO NOT replace existing DownloadURL if this EXE is for an OLDER or EQUAL version.
                            $addDriver = $false
                        } elseif ($exeDownloadURL.length -eq $thisDriverPack.Value.DownloadURL.length) {
                            # Only use NEWER EXE if the URL length are equal, meaning the only change in the name would likely be the support version.
                            # Write-Output "FOUND NEWER EXE - $($thisDriverPack.Value.SystemID) - $($thisDriverPack.Value.ModelName) - $osVersionForExe > $($thisDriverPack.Value.OSVersionNumber)`n`tNEW: $exeDownloadURL`n`tOLD: $($thisDriverPack.Value.DownloadURL)"
                        } else {
                            # Don't use a NEWER EXE if the URL lengths ARE NOT equal, which could mean that there a different model listed in the file name. Only want to trust exact matches with these replacements since we already have a trusted exe.
                            # Write-Output "FOUND POSSIBLE NEWER EXE BUT URL LENGTHS ARENT EQUAL - NOT USING IT! - $($thisDriverPack.Value.SystemID) - $($thisDriverPack.Value.ModelName) - $osVersionForExe > $($thisDriverPack.Value.OSVersionNumber)`n`tNEW: $exeDownloadURL`n`tOLD: $($thisDriverPack.Value.DownloadURL)"
                            $addDriver = $false
                        }
                    }

                    if ($addDriver) {
                        $thisDriverPack.Value['DownloadURL'] = $exeDownloadURL
                        $thisDriverPack.Value['OSVersionNumber'] = $osVersionForExe
                        $thisDriverPack.Value['FileName'] = $exeFileName
                        $thisDriverPack.Value['DriverPackID'] = $exeFileName.Replace('.exe', '')
                    }
                }
            } elseif ($null -eq $thisDriverPack.Value.DownloadURL) {
                Write-Output "THIS SHOULD NOT HAPPEN $($thisDriverPack.Value.SystemID) - $($thisDriverPack.Value.ModelName) - $($thisDriverPack.Value.LenovoSupportPage)"
            }
        }
    }
} else {
    Write-Output "!!! DriverPackCatalog-LenovoV1-EXEsFromSupportPages.xml NOT FOUND !!!"
}

$uniqueDriverPacks = @{}

$modelNamesWithOnlyTypeSpecificDriversCount = 0

foreach ($thisDriverPack in ($driverPacksForSystemIDs.GetEnumerator() | Sort-Object -Property Key)) {
    if ($thisDriverPack.Value.DriverPackID) { # Anything without an ID is a SystemID of a ModelName where only a SystemID-specific EXE is available.
        if (-not $uniqueDriverPacks[$thisDriverPack.Value.DriverPackID]) {
            $uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] = @($thisDriverPack.Value)
        } else {
            $uniqueDriverPacks[$thisDriverPack.Value.DriverPackID] += $thisDriverPack.Value
        }
    } else {
        $modelNamesWithOnlyTypeSpecificDriversCount ++
    }
}

# We won't need to download all of these, but here are the stats:
# $driverPacksForSystemIDs.Count # 968 as of 01/19/21

# THIS IS ALL WE ACTUALL NEED TO DOWNLOAD, SO THAT'S WHAT WE'LL DO:
# $uniqueDriverPacks.Count # 149 as of 01/19/21

$exeCount = 0
$downloadedCount = 0
$validatedExeCount = 0
$expandedCount = 0

$lenovoDriverPacksPath = 'F:\SMB\Drivers\Packs\Lenovo'

foreach ($theseRedundantDriverPacks in ($uniqueDriverPacks.GetEnumerator() | Sort-Object -Property Key)) {
    $thisUniqueDriverPack = $theseRedundantDriverPacks.Value | Select-Object -First 1
    
    $exeCount ++
    Write-Output '----------'
    Write-Output "UNIQUE DRIVER PACK EXE $($exeCount) (USED BY $($theseRedundantDriverPacks.Value.Count) SYSTEM IDs):"
    
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

    $hashSHA256 = $null
        
    if ($supportPageDetailsForEXEs[$thisUniqueDriverPack.DriverPackID.ToLower()] -and $supportPageDetailsForEXEs[$thisUniqueDriverPack.DriverPackID.ToLower()].HashType -eq 'SHA256') {
        $hashSHA256 = $supportPageDetailsForEXEs[$thisUniqueDriverPack.DriverPackID.ToLower()].Hash
    }

    if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $lenovoDriverPacksPath)) {
        $exeDownloadPath = "$lenovoDriverPacksPath\Unique Driver Pack EXEs"
        
        if (-not (Test-Path $exeDownloadPath)) {
            New-Item -ItemType 'Directory' -Force -Path $exeDownloadPath | Out-Null
        }

        if (-not (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)")) {
            Write-Output 'DOWNLOADING...'
            Invoke-WebRequest -Uri $thisUniqueDriverPack.DownloadURL -OutFile "$exeDownloadPath\$($thisUniqueDriverPack.FileName)"

            if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
                $downloadedCount ++
            }
        } else {
            Write-Output 'ALREADY DOWNLOADED'
        }

        if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
            Write-Output 'VALIDATING EXE...'
            if (($null -ne $hashSHA256) -and ($hashSHA256 -ne '')) {
                if ((Get-FileHash "$exeDownloadPath\$($thisUniqueDriverPack.FileName)").Hash -eq $hashSHA256) {
                    $validatedExeCount ++
                } else {
                    Write-Output '>>> INVALID - DELETING EXE <<<'
                    Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
                }
            } else {
                Write-Output '!!! NO HASH TO VALIDATE !!!'
            }
        }

        $exeExpansionPath = "$lenovoDriverPacksPath\Unique Driver Packs"
        
        if (Test-Path "$exeDownloadPath\$($thisUniqueDriverPack.FileName)") {
            if (-not (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)")) {
                Write-Output 'EXPANDING...'
                
                if (Test-Path 'C:\DRIVERS') {
                    Remove-Item 'C:\DRIVERS' -Recurse -Force
                }

                # COMMAND LINE ARGS: https://jrsoftware.org/ishelp/index.php?topic=setupcmdline
                # Extract in default location (which should be within "C:\DRIVERS") instead of intended location using "/DIR=" because some
                # driver packs prompt with a "You have changed the extraction locaion..." alert that stops the process until manually clicking OK.
                $expandExitCode = (Start-Process "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -NoNewWindow -Wait -PassThru -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES').ExitCode
                
                if ($expandExitCode -eq 0) {
                    if (Test-Path 'C:\DRIVERS') {
                        $thisExpansionFoldersToMove = Get-ChildItem 'C:\DRIVERS'
                        while ($thisExpansionFoldersToMove.Count -eq 1) {
                            $thisExpansionFoldersToMove = $thisExpansionFoldersToMove | Get-ChildItem
                        }

                        try {
                            Write-Output 'MOVING EXPANDED FOLDER...'

                            New-Item -ItemType 'Directory' -Force -Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -ErrorAction Stop | Out-Null
                            Move-Item $thisExpansionFoldersToMove.FullName "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -ErrorAction Stop

                            $expandedCount ++
                        } catch {
                            Write-Output ">>> ERROR MOVING EXPANDED FOLDER - DELETING FOLDERS ($_) <<<"
                            Remove-Item "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Recurse -Force
                        }

                        Remove-Item "C:\DRIVERS" -Recurse -Force
                    } else {
                        Write-Output '>>> EXPANSION FOLDER NOT FOUND AT "\DRIVERS" <<<'
                    }
                } else {
                    Write-Output '>>> EXPANSION FAILED - DELETING EXE AND FOLDERS <<<'
                    
                    Remove-Item "$exeDownloadPath\$($thisUniqueDriverPack.FileName)" -Force
                    Remove-Item "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Recurse -Force
                    Remove-Item "C:\DRIVERS" -Recurse -Force
                }
            } else {
                Write-Output 'ALREADY EXPANDED'

                # TODO: Check for basic expected structure to validate expansion.
            }
        } elseif (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
            # Delete expanded folder if EXE does not exist
            Write-Output '>>> NO EXE - DELETING FOLDER <<<'
            Remove-Item "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)" -Recurse -Force
        }

        if (Test-Path "$exeExpansionPath\$($thisUniqueDriverPack.DriverPackID)") {
            foreach ($thisRedundantDriverPack in $theseRedundantDriverPacks.Value) {
                if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $lenovoDriverPacksPath)) {
                    Set-Content "$lenovoDriverPacksPath\$($thisRedundantDriverPack.SystemID).txt" "Unique Driver Packs\$($thisRedundantDriverPack.DriverPackID)"
                }
            }
        }
    } elseif ($null -ne $hashSHA256) {
        Write-Output "HashSHA256: $hashSHA256"
    } else {
        Write-Output "NO HASH AVAILABLE"
    }
}

if (($IsWindows -or ($null -eq $IsWindows)) -and (Test-Path $lenovoDriverPacksPath)) {
    Write-Output '----------'
    Write-Output 'CHECKING FOR STRAY DRIVER EXEs AND FOLDERS...'
    
    $allReferencedDriverEXEs = @()

    Get-ChildItem "$lenovoDriverPacksPath\*" -File -Include '*.txt' | ForEach-Object {
        $thisDriverEXE = ($_ | Get-Content -First 1)

        if (($null -ne $thisDriverEXE) -and $thisDriverEXE.Contains('\')) {
            $thisDriverEXE = $thisDriverEXE.Split('\')[1]

            # TODO: Doubly confirm that NO Model paths contain references to Type-specific Driver Packs (to catch any mistakes from above).

            if (-not $allReferencedDriverEXEs.Contains($thisDriverEXE)) {
                $allReferencedDriverEXEs += $thisDriverEXE
            }
        }
    }

    Get-ChildItem "$lenovoDriverPacksPath\Unique Driver Pack EXEs" | ForEach-Object {
        if (-not $allReferencedDriverEXEs.Contains($_.BaseName)) {
            Write-Output "DELETING STRAY DRIVER EXE: $($_.Name)"
            Remove-Item $_.FullName -Force
        }
    }

    Get-ChildItem "$lenovoDriverPacksPath\Unique Driver Packs" | ForEach-Object {
        if (-not $allReferencedDriverEXEs.Contains($_.Name)) {
            Write-Output "DELETING STRAY DRIVER FOLDER: $($_.Name)"
            Remove-Item $_.FullName -Recurse -Force
        }
    }
}

Write-Output '----------'
Write-Output "FINISHED AT: $(Get-Date)"
Write-Output "DETECTED: $($uniqueDriverPacks.Count) Unique Lenovo Driver Packs (for $($driverPacksForSystemIDs.Count - $modelNamesWithOnlyTypeSpecificDriversCount) System IDs)"
Write-Output "DOWNLOADED: $downloadedCount"
Write-Output "VALIDATED EXEs: $validatedExeCount"
Write-Output "EXPANDED: $expandedCount"
Write-Output '----------'

if ($IsWindows -or ($null -eq $IsWindows)) {
    $Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
}

Read-Host 'DONE - PRESS ENTER TO EXIT'
