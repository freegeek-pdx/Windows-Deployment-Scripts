#################################################################
##                                                             ##
##   TO RUN THIS SCRIPT, LAUNCH "Run Create WinPE Image.cmd"   ##
##                                                             ##
#################################################################

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

# Requires ADK with WinPE Add-On: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install

# Reference (Adding PowerShell to WinPE): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe
# Reference (Optimize and Shrink WinPE): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-optimize

# IMPORTANT: "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat" must be run from within the CMD launcher file first for copype to work.

$windows10featureVersion = '21H2'
$windows11featureVersion = $windows10featureVersion

$winPEmajorVersion = '11' # It is fine to use WinPE/WinRE from Windows 11 even when Windows 10 will be installed.
$winPEfeatureVersion = $windows11featureVersion
$winREfeatureVersion = $winPEfeatureVersion

$winPEname = "WinPE-$winPEmajorVersion-$winPEfeatureVersion"

$basePath = "$HOME\Documents\Free Geek"
if (Test-Path "$HOME\Documents\Free Geek.lnk") {
    $basePath = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Documents\Free Geek.lnk").TargetPath
}

$winPEoutputPath = "$basePath\$winPEname"

$winPEdriversPath = "$basePath\WinPE Drivers to Install"
$winREnetDriversPath = "$basePath\WinRE Net Drivers to Install"

$winREimagesSourcePath = "$basePath\Windows-$winPEmajorVersion-Pro-$winREfeatureVersion"
$winREname = "WinRE-$winPEmajorVersion-$winREfeatureVersion"

# Used to include latest installation WIM in "os-images" folder in WinPE USB
$win10imagesSourcePath = "$basePath\Windows-10-Pro-$windows10featureVersion"
$win11imagesSourcePath = "$basePath\Windows-11-Pro-$windows11featureVersion"

$setupResourcesSourcePath = "$(Split-Path -Parent $PSScriptRoot)\Setup Resources" # Used to include "setup-resources" folder in WinPE USB
$appInstallersSourcePath = "$PSScriptRoot\App Installers" # Used to include "app-installers" folder in WinPE USB


Write-Output "`n  Creating WinPE Image...`n`n`n`n" # Add empty lines for PowerShell progress UI

$systemTempDir = [System.Environment]::GetEnvironmentVariable('TEMP', 'Machine') # Get SYSTEM (not user) temporary directory, which should be "\Windows\Temp".
if (-not (Test-Path $systemTempDir)) {
    $systemTempDir = '\Windows\Temp'
}

if ((Test-Path "$systemTempDir\mountPE") -and ((Get-ChildItem "$systemTempDir\mountPE").Count -gt 0)) {
    Write-Output "`n  Unmounting Previously Mounted WinPE Image..."
    Dismount-WindowsImage -Path "$systemTempDir\mountPE" -Discard -ErrorAction Stop | Out-Null
    Remove-Item "$systemTempDir\mountPE" -Recurse -Force -ErrorAction Stop
}


# TODO: Eventually, re-work this script to not need to re-create the entire WinPE everytime and be able to easily maintain the 2 versions with and without Wi-Fi (net) drivers (for iPXE vs USB).
if (Test-Path "$winPEoutputPath\media\sources\boot.wim") {
    $promptCaption = "  `"$winPEname`" Has Already Been Created - Do You Want to Delete & Re-Create WinPE?"
    $promptChoices = '&No, Exit', '&Yes'

    $promptResponse = $Host.UI.PromptForChoice($promptCaption, "`n", $promptChoices, 1)

    if ($promptResponse -eq 0) {
        exit 0
    } elseif (Test-Path $winPEoutputPath) {
        Remove-Item $winPEoutputPath -Recurse -Force -ErrorAction Stop
    }
}


$didJustRunCopyPE = $false

if (-not (Test-Path "$winPEoutputPath\media\sources\boot.wim")) {
    if (Test-Path $winPEoutputPath) {
        Remove-Item $winPEoutputPath -Recurse -Force -ErrorAction Stop
    }

    Write-Output "`n  Copying New WinPE Image from ADK..."
    $copypeExitCode = (Start-Process 'copype' -NoNewWindow -Wait -PassThru -ArgumentList 'amd64', "`"$winPEoutputPath`"").ExitCode

    if ($copypeExitCode -ne 0) {
        Write-Host "`n  ERROR: FAILED TO RUN COPYPE - EXIT CODE: $copypeExitCode" -ForegroundColor Red
        exit $copypeExitCode
    }

    # Delete the "mount" folder created by ADK since we won't use it.
    Remove-Item "$winPEoutputPath\mount" -Recurse -Force -ErrorAction Stop

    if ((Test-Path "$winPEoutputPath\media\sources\boot.wim") -and ($latestWinRE = Get-ChildItem $winREimagesSourcePath -Filter "$winREname-*.wim" | Sort-Object -Property LastWriteTime | Select-Object -Last 1)) {
        $latestWinREpath = $latestWinRE.FullName
        $latestWinREfilename = $latestWinRE.BaseName

        $promptCaption = "  Would You Like to REPLACE WinPE from the ADK with WinRE ($latestWinREfilename) from Windows $winPEmajorVersion ($winREfeatureVersion)?"
        $promptMessage = "`n  WinRE can support Wi-Fi (with the correct drivers) and Audio and also has the `"BCD`" and `"boot.sdi`" files built-in`n  for iPXE/wimboot to extract and load automatically without having to include and specify them seperately.`n`n"
        $promptChoices = '&Yes', '&No'

        # Info about replacing WinPE with WinRE: https://msendpointmgr.com/2018/03/06/build-a-winpe-with-wireless-support/

        $promptResponse = $Host.UI.PromptForChoice($promptCaption, $promptMessage, $promptChoices, 0)

        if ($promptResponse -eq 0) {
            Remove-Item "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
            Copy-Item $latestWinREpath "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
        }
    } else {
        Write-Host "    NO WINRE IMAGE FILE FOUND" -ForegroundColor Yellow
    }

    $didJustRunCopyPE = $true
}

$startDate = Get-Date
Write-Output "`n  Starting at $startDate..."

$wimDetails = Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop
$wimDetails # Print wimDetails

$wimImageBaseName = 'WinPE'
if ($wimDetails.ImageName -like '*Recovery Environment*') {
    $wimImageBaseName = 'WinRE'
    $winPEname = "$wimImageBaseName-$winPEmajorVersion-$winREfeatureVersion"
}


Write-Output "`n  Mounting $wimImageBaseName Image..."

if (-not (Test-Path "$systemTempDir\mountPE")) {
    New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE" -ErrorAction Stop | Out-Null
}

# Dism /Mount-Image /ImageFile:"C:\WinPE_amd64_PS\media\sources\boot.wim" /Index:1 /MountDir:"C:\WinPE_amd64_PS\mount"
Mount-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -Path "$systemTempDir\mountPE" -CheckIntegrity -ErrorAction Stop | Out-Null


Write-Output "`n  Increasing WinPE Scratch Space..."
# Increase WinPE Scratch Space: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-mount-and-customize#add-temporary-storage-scratch-space
# If too manu GUI apps get launched during testing it appears the limited default of 32 MB of scratch space can get used up and then other stuff can fail to load such as required DISM PowerShell modules.

Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Get-ScratchSpace'

# PowerShell equivalent of DISM's "/Set-ScratchSpace" does not seem to exist.
$dismSetScratchSpaceExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Set-ScratchSpace:512').ExitCode

if ($dismSetScratchSpaceExitCode -ne 0) {
    Write-Host "`n  ERROR: FAILED TO INCREASE WINPE SCRATCH SPACE - EXIT CODE: $dismSetScratchSpaceExitCode" -ForegroundColor Red
}


$winPEoptionalFeatures = (Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Enabled).FeatureName | Sort-Object -Unique
# Pre-Installed WinPE Features: *NONE*
# Pre-Installed WinRE Features: Microsoft-Windows-WinPE-ATBroker-Package, Microsoft-Windows-WinPE-AudioCore-Package, Microsoft-Windows-WinPE-AudioDrivers-Package, Microsoft-Windows-WinPE-Narrator-Package, Microsoft-Windows-WinPE-Speech-TTS-Package, Microsoft-Windows-WinPE-SRH-Package, WinPE-EnhancedStorage, WinPE-FMAPI-Package, WinPE-HTA, WinPE-Rejuv, WinPE-Scripting, WinPE-SecureStartup, WinPE-SRT, WinPE-StorageWMI, WinPE-TPM, WinPE-WDS-Tools, WinPE-WiFi, WinPE-WMI

if ($didJustRunCopyPE) {
    Write-Output "`n  Installed Features BEFORE PowerShell: $($winPEoptionalFeatures -Join ', ')"

    Write-Output "`n  Installing PowerShell Into $wimImageBaseName Image..."
    $winPEpackagesToInstall = @('WMI', 'NetFX', 'Scripting', 'PowerShell', 'StorageWMI', 'DismCmdlets')
    foreach ($thisWinPEpackageToInstall in $winPEpackagesToInstall) {
        if ($winPEoptionalFeatures -notcontains "WinPE-$thisWinPEpackageToInstall") { # Some of these will already be installed if we are starting with a WinRE image...
            $packageStartDate = Get-Date
            Write-Output "    Installing $thisWinPEpackageToInstall Package Into $wimImageBaseName Image at $($updateStartDate)..."
            # Dism /Add-Package /Image:"C:\WinPE_amd64_PS\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-PACKAGENAME.cab"
            Add-WindowsPackage -Path "$systemTempDir\mountPE" -PackagePath "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-$thisWinPEpackageToInstall.cab" -WarningAction Stop -ErrorAction Stop | Out-Null
            # Dism /Add-Package /Image:"C:\WinPE_amd64_PS\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-PACKAGENAME_en-us.cab"
            Add-WindowsPackage -Path "$systemTempDir\mountPE" -PackagePath "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-$($thisWinPEpackageToInstall)_en-us.cab" -WarningAction Stop -ErrorAction Stop | Out-Null
            $packageEndDate = Get-Date
            Write-Output "      Finished Installing at $($packageEndDate) ($([math]::Round(($packageEndDate - $packageStartDate).TotalMinutes, 2)) Minutes)"
        } else {
            Write-Output "    $thisWinPEpackageToInstall Package ALREADY INSTALLED"
        }
    }

    $winPEoptionalFeatures = (Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Enabled).FeatureName | Sort-Object -Unique
    Write-Output "`n  Installed Features AFTER PowerShell: $($winPEoptionalFeatures -Join ', ')"
    
    Write-Output "`n  Disabled Features: $((Get-WindowsOptionalFeature -Path "$systemTempDir\mountPE" | Where-Object State -eq Disabled | Sort-Object -Unique).FeatureName -Join ', ')"
    
    if (Test-Path $winPEdriversPath) {
        $winPEdriverInfPaths = (Get-ChildItem $winPEdriversPath -Recurse -File -Include '*.inf').FullName

        if ($winPEdriverInfPaths.Count -gt 0) {
            Write-Output "`n  Installing $($winPEdriverInfPaths.Count) Drivers Into $wimImageBaseName Image..."

            $thisDriverIndex = 0
            foreach ($thisDriverInfPath in $winPEdriverInfPaths) {
                $thisDriverIndex ++
                $thisDriverFolderName = (Split-Path (Split-Path $thisDriverInfPath -Parent) -Leaf)
                
                try {
                    Write-Output "    Installing Driver $thisDriverIndex of $($winPEdriverInfPaths.Count): $thisDriverFolderName..."
                    Add-WindowsDriver -Path "$systemTempDir\mountPE" -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null
                } catch {
                    Write-Host "      ERROR INSTALLING DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
                }
            }
        }
    }
} else {
    Write-Host "`n  Chose Not to Fully Re-Create Existing $wimImageBaseName - UPDATING RESOURCES ONLY" -ForegroundColor Yellow
}


Write-Output "`n  Setting LongPathsEnabled in $wimImageBaseName Registry..."

# IMPORTANT: Some Lenovo Driver Packs create very long paths and LongPathsEnabled needs to be set in WinPE to be able to successfully read the files at long paths within these Driver Packs.
# https://docs.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=powershell#enable-long-paths-in-windows-10-version-1607-and-later
# To edit registry of offline wim: https://www.tenforums.com/tutorials/95002-dism-edit-registry-offline-image.html

$regLoadExitCode = (Start-Process 'reg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList 'load', "HKLM\OFFLINE-$wimImageBaseName-SYSTEM", "`"$systemTempDir\mountPE\Windows\System32\Config\System`"").ExitCode

if ($regLoadExitCode -eq 0) {
    $winPEfileSystemRegistryPath = "HKLM:\OFFLINE-$wimImageBaseName-SYSTEM\ControlSet001\Control\FileSystem"
    
    if (Test-Path $winPEfileSystemRegistryPath) {
        if ((Get-ItemProperty $winPEfileSystemRegistryPath).LongPathsEnabled -ne 1) {
            New-ItemProperty $winPEfileSystemRegistryPath -Name 'LongPathsEnabled' -Value 1 -PropertyType 'DWord' -Force | Out-Null

            if ((Get-ItemProperty $winPEfileSystemRegistryPath).LongPathsEnabled -eq 1) {
                Write-Output "    Set LongPathsEnabled to 1 in $wimImageBaseName Registry"
            } else {
                Write-Output "    !!! FAILED TO SET LongPathsEnabled TO 1 IN $wimImageBaseName REGISTRY !!!"
            }
        } else {
            Write-Output "    LongPathsEnabled Already Set to 1 in $wimImageBaseName Registry"
        }
    } else {
        Write-Output "    !!! $wimImageBaseName SYSTEM REGISTRY PATH NOT FOUND !!!"
    }
} else {
    Write-Output "    !!! FAILED TO LOAD $wimImageBaseName SYSTEM REGISTRY !!!"
}

$regUnloadExitCode = (Start-Process 'reg' -NoNewWindow -Wait -PassThru -RedirectStandardOutput 'NUL' -ArgumentList 'unload', "HKLM\OFFLINE-$wimImageBaseName-SYSTEM").ExitCode

if ($regUnloadExitCode -ne 0) {
    Write-Output "    !!! FAILED TO UNLOAD $wimImageBaseName SYSTEM REGISTRY !!!"
}


if (Test-Path "$PSScriptRoot\Process Explorer Exports for Missing DLLs") {
    $processExplorerExportsToParse = Get-ChildItem "$PSScriptRoot\Process Explorer Exports for Missing DLLs\*" -Include '*.exe.txt', '*.dll.txt'

    # NOTE ABOUT DETECTING REQUIRED DLLs FOR AN APP:
    # Before exporting the list of DLLs as described below, click around in the desired app and perform all the actions that will be performed in WinPE so any extra DLLs get loaded as they may not be needed/loaded yet right when an app launches.
    
    # Process Explorer: https://docs.microsoft.com/en-us/sysinternals/downloads/process-explorer
    # In Process Explorer, first make sure "Show DLLs" is enabled and the DLLs are visible in the lower pane (otherwise the list of DLLs will not get exported in the next step).
    # Then, select desired running process (such as javaw.exe) in the list and choose "Save" to save the process info (which includes DLLs) into a text file (ending in ".exe.txt") into the "Process Explorer Exports for Missing DLLs" for parsing below.
    # IMPORTANT: Any missing DLLs detected will be copied from the running version of Windows into WinPE/WinRE, so the running version should be compatible with the feature version (ie. Win 10 21H2) as the WinPE/WinRE version.

    if ($processExplorerExportsToParse.Count -gt 0) {
        Write-Output "`n  Checking Process Explorer Exports for Missing DLLs in $wimImageBaseName Image..."
        
        $copiedDLLcount = 0

        # When re-detecting Java QA Helper DLLs on Windows 10 21H2 with Java 17.0.1 to make sure everything was up-to-date,
        # new DLLs were detected since the last time when last detected on Windows 10 2004 with Java 15.
        # But, the new set of DLLs caused Wpeinit.exe to stall and then exit with error code -2147023436.
        # So, ignore any problematic DLLs here in code so that any future DLL detections don't accidentally bring this issue back.
        # The one problematic DLL listed here was figured out through trial and error by arbitrarily ignoring sets of the new DLLs until Wpeinit.exe worked with the fewest possible DLLs ignored.
        $ignoreMissingDLLs = @('policymanager.dll')

        $processExplorerExportsToParse | ForEach-Object {
            Write-Output "    Analyzing `"$($_.Name)`" Process Explorer Export for Missing DLLs..."
            
            foreach ($thisProcessExplorerLogLine in (Get-Content $_.FullName)) {
                if ($thisProcessExplorerLogLine.Contains('\Windows\System32\') -and (-not ($thisProcessExplorerLogLine.EndsWith('.exe')))) {
                    $thisDLLPathInOS = $thisProcessExplorerLogLine -replace '^[^:\\]*:\\', '\'
                    $thisDLLPathInWinPE = $thisProcessExplorerLogLine -replace '^[^:\\]*:\\', "$systemTempDir\mountPE\"
                    
                    if (-not (Test-Path $thisDLLPathInWinPE)) {
                        if ($ignoreMissingDLLs.Contains($(Split-Path $thisDLLPathInOS -Leaf))) {
                            Write-Output "      Ignoring Missing DLL From `"$($_.BaseName)`": $thisDLLPathInOS"
                        } else {
                            Write-Output "      Copying Missing DLL From `"$($_.BaseName)`" Into $wimImageBaseName Image: $thisDLLPathInOS"
                            Copy-Item $thisDLLPathInOS $thisDLLPathInWinPE -ErrorAction Stop
                            $copiedDLLcount ++
                        }
                    }
                }
            }
        }

        Write-Output "    Copied $copiedDLLcount Missing DLLs Into $wimImageBaseName Image"
    } else {
        Write-Host "`n  NO EXPORTS IN `"Process Explorer Exports for Missing DLLs`" TO PARSE" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n  NO `"Process Explorer Exports for Missing DLLs`" FOLDER" -ForegroundColor Yellow
}


if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\W32tm.exe")) {
    Write-Output "`n  Copying `"W32tm.exe`" Into $wimImageBaseName Image..."

    # Install W32tm.exe into WinPE so we can sync time in WinPE to be sure QA Helper can be installed since if time is far off HTTPS will fail.
    Copy-Item '\Windows\System32\W32tm.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
}

if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\taskkill.exe")) {
    Write-Output "`n  Copying `"taskkill.exe`" Into $wimImageBaseName Image for QA Helper to Use..."

    # Install taskkill.exe into WinPE so we can call it from QA Helper for convenience of not having to rely on killing with PowerShell (which is slower to load).
    Copy-Item '\Windows\System32\taskkill.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
}

if ($winPEoptionalFeatures -contains 'Microsoft-Windows-WinPE-AudioDrivers-Package') {
    # WinRE supports audio, so add these files for QA Helper to be able to use.
    
    if (-not (Test-Path "$systemTempDir\mountPE\Windows\System32\SndVol.exe")) {
        Write-Output "`n  Copying `"SndVol.exe`" Into $wimImageBaseName Image for QA Helper Audio Test..."
    
        Copy-Item '\Windows\System32\SndVol.exe' "$systemTempDir\mountPE\Windows\System32" -Force -ErrorAction Stop
    }

    if (-not (Test-Path "$systemTempDir\mountPE\Windows\Media")) {
        Write-Output "`n  Copying Success and Error Sound Files Into $wimImageBaseName Image for QA Helper to Use..."

        New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE\Windows\Media" -ErrorAction Stop | Out-Null

        Copy-Item '\Windows\Media\Windows Foreground.wav' "$systemTempDir\mountPE\Windows\Media" -Force -ErrorAction Stop 
        Copy-Item '\Windows\Media\Windows Exclamation.wav' "$systemTempDir\mountPE\Windows\Media" -Force -ErrorAction Stop  
    }
}

if (Test-Path "$PSScriptRoot\System32 Folder Resources") {
    $system32FolderResourcesToCopy = Get-ChildItem "$PSScriptRoot\System32 Folder Resources"

    if ($system32FolderResourcesToCopy.Count -gt 0) {
        Write-Output "`n  Copying System32 Folder Resources Into $wimImageBaseName Image..."
        Copy-Item "$PSScriptRoot\System32 Folder Resources\*" "$systemTempDir\mountPE\Windows\System32" -Recurse -Force -ErrorAction Stop
    } else {
        Write-Host "`n  NOTHING IN `"System32 Folder Resources`" TO COPY" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n  NO `"System32 Folder Resources`" FOLDER" -ForegroundColor Yellow
}


if (Test-Path "$PSScriptRoot\Install Folder Resources") {
    $installFolderResourcesToCopy = Get-ChildItem "$PSScriptRoot\Install Folder Resources"

    if ($installFolderResourcesToCopy.Count -gt 0) {
        Write-Output "`n  Copying Install Folder Resources Into $wimImageBaseName Image..."

        if (Test-Path "$systemTempDir\mountPE\Install") {
            Remove-Item "$systemTempDir\mountPE\Install" -Recurse -Force -ErrorAction Stop
        }

        New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE\Install" -ErrorAction Stop | Out-Null

        Copy-Item "$PSScriptRoot\Install Folder Resources\*" "$systemTempDir\mountPE\Install" -Recurse -Force -ErrorAction Stop

        Write-Output "    Unarchiving Java in Install Folder in $wimImageBaseName Image..."

        if (Test-Path "$systemTempDir\mountPE\Install\QA Helper\java-jre") {
            Remove-Item "$systemTempDir\mountPE\Install\QA Helper\java-jre" -Recurse -Force -ErrorAction Stop
        }

        Expand-Archive "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip" "$systemTempDir\mountPE\Install\QA Helper\" -Force -ErrorAction Stop

        if (Test-Path "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip") {
            Remove-Item "$systemTempDir\mountPE\Install\QA Helper\jlink-jre-*_windows-x64.zip" -Force -ErrorAction Stop
        }
    } else {
        Write-Host "`n  NOTHING IN `"Install Folder Resources`" TO COPY" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n  NO `"Install Folder Resources`" FOLDER" -ForegroundColor Yellow
}


Write-Output "`n  Cleaning Up $wimImageBaseName Image..."
# PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
$dismCleanupExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

if ($dismCleanupExitCode -eq 0) {
    Write-Output "`n  Unmounting and Saving Updated $wimImageBaseName Image..."
    # Dism /Unmount-Image /MountDir:C:\WinPE_amd64_PS\mount /Commit
    Dismount-WindowsImage -Path "$systemTempDir\mountPE" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
    Remove-Item "$systemTempDir\mountPE" -Recurse -Force -ErrorAction Stop
    Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop

    Write-Output "`n  Exporting Compressed $wimImageBaseName Image as `"$winPEname.wim`"..."
    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-optimize#export-and-then-replace-the-image
    
    if (Test-Path "$winPEoutputPath\$winPEname.wim") {
        Write-Output "    Deleting Previous $wimImageBaseName Image `"$winPEname.wim`"..."
        Remove-Item "$winPEoutputPath\$winPEname.wim" -Force -ErrorAction Stop
    }
    
    # "-Setbootable" does not seem to be necessary (USBs will boot without it being set), but it doesn't seem to hurt anything so leaving it in place.
    Export-WindowsImage -SourceImagePath "$winPEoutputPath\media\sources\boot.wim" -SourceIndex 1 -DestinationImagePath "$winPEoutputPath\$winPEname.wim" -CheckIntegrity -CompressionType 'max' -Setbootable -ErrorAction Stop | Out-Null
    Get-WindowsImage -ImagePath "$winPEoutputPath\$winPEname.wim" -Index 1 -ErrorAction Stop
    

    Write-Output "`n  Overwriting Original $wimImageBaseName Image with Compressed $wimImageBaseName for USB Install..."
    # Replace boot.wim in sources folder for MakeWinPEMedia script.
    Copy-Item "$winPEoutputPath\$winPEname.wim" "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
    Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop
} else {
    Write-Host "`n  ERROR: FAILED TO DISM CLEANUP - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
}


if ($didJustRunCopyPE -and ($winPEoptionalFeatures -contains 'WinPE-WiFi') -and (Test-Path $winREnetDriversPath)) {
    $winREnetDriverInfPaths = (Get-ChildItem $winREnetDriversPath -Recurse -File -Include '*.inf').FullName

    if ($winREnetDriverInfPaths.Count -gt 0) {
        if (Test-Path "$winPEoutputPath\media\sources\boot.wim") {
            Write-Output "`n  Re-Mounting $wimImageBaseName Image for Net Drivers..."
            
            if (-not (Test-Path "$systemTempDir\mountPE")) {
                New-Item -ItemType 'Directory' -Path "$systemTempDir\mountPE" -ErrorAction Stop | Out-Null
            }
        
            Mount-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -Path "$systemTempDir\mountPE" -CheckIntegrity -ErrorAction Stop | Out-Null
        }

        $startDriversDate = Get-Date
        Write-Output "`n  Installing $($winREnetDriverInfPaths.Count) Net Drivers Into $wimImageBaseName Image at $startDriversDate..."

        $thisDriverIndex = 0
        foreach ($thisDriverInfPath in $winREnetDriverInfPaths) {
            $thisDriverIndex ++
            $thisDriverFolderName = (Split-Path (Split-Path $thisDriverInfPath -Parent) -Leaf)
            
            try {
                Write-Output "    Installing Net Driver $thisDriverIndex of $($winREnetDriverInfPaths.Count): $thisDriverFolderName..."
                Add-WindowsDriver -Path "$systemTempDir\mountPE" -Driver $thisDriverInfPath -ErrorAction Stop | Out-Null
            } catch {
                Write-Host "      ERROR INSTALLING NET DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
            }
        }

        $endDriversDate = Get-Date
        Write-Output "`n  Installing Net Driver at $endDriversDate ($([math]::Round(($endDriversDate - $startDriversDate).TotalMinutes, 2)) Minutes)..."
    }

    Write-Output "`n  Cleaning Up $wimImageBaseName Net Image..."
    # PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
    $dismCleanupExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$systemTempDir\mountPE`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

    if ($dismCleanupExitCode -eq 0) {
        Write-Output "`n  Unmounting and Saving Updated $wimImageBaseName Net Image..."
        # Dism /Unmount-Image /MountDir:C:\WinPE_amd64_PS\mount /Commit
        Dismount-WindowsImage -Path "$systemTempDir\mountPE" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
        Remove-Item "$systemTempDir\mountPE" -Recurse -Force -ErrorAction Stop
        Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop

        Write-Output "`n  Exporting Compressed $wimImageBaseName Image as `"$winPEname-NetDrivers.wim`"..."
        # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-optimize#export-and-then-replace-the-image
        
        if (Test-Path "$winPEoutputPath\$winPEname-NetDrivers.wim") {
            Write-Output "    Deleting Previous $wimImageBaseName Image `"$winPEname-NetDrivers.wim`"..."
            Remove-Item "$winPEoutputPath\$winPEname-NetDrivers.wim" -Force -ErrorAction Stop
        }
        
        # "-Setbootable" does not seem to be necessary (USBs will boot without it being set), but it doesn't seem to hurt anything so leaving it in place.
        Export-WindowsImage -SourceImagePath "$winPEoutputPath\media\sources\boot.wim" -SourceIndex 1 -DestinationImagePath "$winPEoutputPath\$winPEname-NetDrivers.wim" -CheckIntegrity -CompressionType 'max' -Setbootable -ErrorAction Stop | Out-Null
        Get-WindowsImage -ImagePath "$winPEoutputPath\$winPEname-NetDrivers.wim" -Index 1 -ErrorAction Stop
        

        Write-Output "`n  Overwriting Original $wimImageBaseName Image with Compressed $wimImageBaseName Net for USB Install..."
        # Replace boot.wim in sources folder for MakeWinPEMedia script.
        Copy-Item "$winPEoutputPath\$winPEname-NetDrivers.wim" "$winPEoutputPath\media\sources\boot.wim" -Force -ErrorAction Stop
        Get-WindowsImage -ImagePath "$winPEoutputPath\media\sources\boot.wim" -Index 1 -ErrorAction Stop
    } else {
        Write-Host "`n  ERROR: FAILED TO DISM CLEANUP - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
    }
}


if (Test-Path "$winPEoutputPath\media") {
    Write-Output "`n`n  Updating `"windows-resources`" Folder Contents for USB Install..."

    if (Test-Path "$winPEoutputPath\media\windows-resources") {
        Remove-Item "$winPEoutputPath\media\windows-resources" -Recurse -Force -ErrorAction Stop
    }

    New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources" -ErrorAction Stop | Out-Null

    $maxFat32FileSize = 4294967294

    if (Test-Path $win10imagesSourcePath) {
        if ($latestWin10wim = Get-ChildItem $win10imagesSourcePath -Filter "Windows-10-Pro-$windows10featureVersion-*.wim" | Sort-Object -Property LastWriteTime | Select-Object -Last 1) {
            $latestWin10wimPath = $latestWin10wim.FullName
            $latestWin10wimFilename = $latestWin10wim.BaseName

            Write-Output "    Copying Latest Windows 10 Install Image ($latestWin10wimFilename) Into `"windows-resources\os-images`"..."
            
            New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop | Out-Null

            $wimFileSize = $latestWin10wim.Length

            if ($wimFileSize -le $maxFat32FileSize) {
                Write-Output "      Windows 10 Install Image Is Within FAT32 Max File Size ($wimFileSize <= $maxFat32FileSize)"

                Copy-Item $latestWin10wimPath "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop
            } else {
                $splitMBs = 2500
                Write-Host "      Windows 10 Install Image Is Bigger Than FAT32 Max File Size ($wimFileSize > $maxFat32FileSize)`n      SPLITTING WINDOWS IMAGE INTO $splitMBs MB SWMs" -ForegroundColor Yellow

                Split-WindowsImage -ImagePath $latestWin10wimPath -SplitImagePath "$winPEoutputPath\media\windows-resources\os-images\$latestWin10wimFilename+.swm" -FileSize $splitMBs -CheckIntegrity -ErrorAction Stop | Out-Null

                Rename-Item "$winPEoutputPath\media\windows-resources\os-images\$latestWin10wimFilename+.swm" "$winPEoutputPath\media\windows-resources\os-images\$latestWin10wimFilename+1.swm"
            }
        } else {
            Write-Host "    NO WINDOWS 10 INSTALL IMAGE FILE FOR $wimImageBaseName USB" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    NO WINDOWS 10 INSTALL IMAGE FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
    }

    if (Test-Path $win11imagesSourcePath) {
        if ($latestWin11wim = Get-ChildItem $win11imagesSourcePath -Filter "Windows-11-Pro-$windows11featureVersion-*.wim" | Sort-Object -Property LastWriteTime | Select-Object -Last 1) {
            $latestWin11wimPath = $latestWin11wim.FullName
            $latestWin11wimFilename = $latestWin11wim.BaseName

            Write-Output "    Copying Latest Windows 11 Install Image ($latestWin11wimFilename) Into `"windows-resources\os-images`"..."
            
            if (-not (Test-Path "$winPEoutputPath\media\windows-resources\os-images")) {
                New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop | Out-Null
            }

            $wimFileSize = $latestWin11wim.Length

            if ($wimFileSize -le $maxFat32FileSize) {
                Write-Output "      Windows 11 Install Image Is Within FAT32 Max File Size ($wimFileSize <= $maxFat32FileSize)"

                Copy-Item $latestWin11wimPath "$winPEoutputPath\media\windows-resources\os-images" -ErrorAction Stop
            } else {
                $splitMBs = 2500
                Write-Host "      Windows 11 Install Image Is Bigger Than FAT32 Max File Size ($wimFileSize > $maxFat32FileSize)`n      SPLITTING WINDOWS IMAGE INTO $splitMBs MB SWMs" -ForegroundColor Yellow

                Split-WindowsImage -ImagePath $latestWin11wimPath -SplitImagePath "$winPEoutputPath\media\windows-resources\os-images\$latestWin11wimFilename+.swm" -FileSize $splitMBs -CheckIntegrity -ErrorAction Stop | Out-Null

                Rename-Item "$winPEoutputPath\media\windows-resources\os-images\$latestWin11wimFilename+.swm" "$winPEoutputPath\media\windows-resources\os-images\$latestWin11wimFilename+1.swm"
            }
        } else {
            Write-Host "    NO WINDOWS 11 INSTALL IMAGE FILE FOR $wimImageBaseName USB" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    NO WINDOWS 11 INSTALL IMAGE FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
    }

    if (Test-Path $setupResourcesSourcePath) {
        Write-Output "    Copying Setup Resources Into `"windows-resources\setup-resources`"..."
        
        Copy-Item $setupResourcesSourcePath "$winPEoutputPath\media\windows-resources\setup-resources" -Recurse -ErrorAction Stop
    } else {
        Write-Host "    NO SETUP RESOURCES FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
    }

    if (Test-Path $appInstallersSourcePath) {
        Write-Output "    Copying App Installers Into `"windows-resources\app-installers`"..."

        New-Item -ItemType 'Directory' -Path "$winPEoutputPath\media\windows-resources\app-installers" -ErrorAction Stop | Out-Null
        
        Get-ChildItem $appInstallersSourcePath -Exclude '*.sh', '*.ps1' -ErrorAction Stop | ForEach-Object {
            Copy-Item $_ "$winPEoutputPath\media\windows-resources\app-installers" -Recurse -Force -ErrorAction Stop
        }
    } else {
        Write-Host "    NO APP INSTALLERS FOLDER FOR $wimImageBaseName USB" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n`n  NO MEDIA FOLDER FOR $wimImageBaseName USB" -ForegroundColor Red
}

$endDate = Get-Date
Write-Output "`n  Finished at $endDate ($([math]::Round(($endDate - $startDate).TotalMinutes, 2)) Minutes)"
