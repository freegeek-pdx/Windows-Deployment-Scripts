###########################################################################
##                                                                       ##
##   TO RUN THIS SCRIPT, LAUNCH "Run Create Windows Install Image.cmd"   ##
##                                                                       ##
###########################################################################

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

# Requires Latest Windows ISO: https://www.microsoft.com/en-us/software-download/windows10
# When the Windows 10 download page is viewed on Mac or Linux, you have the option to download the ISO directly, but when viewed on Windows you can only download the Media Creation Tool (instead of direct ISO download) which can then be used to export an ISO.
# Instead of using the Media Creation Tool on Windows, a workaround to be able to download the ISO directly on Windows is to use the Developer Tools options in Chrome or Firefox to change the User Agent or use Responsive Design Mode and then reload the page.
# Or, use the Fido script (https://github.com/pbatard/Fido) built into Rufus: https://rufus.ie/en/

# Reference (Modify a WIM): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/mount-and-modify-a-windows-image-using-dism
# Reference (Reduce Size of WIM): https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/reduce-the-size-of-the-component-store-in-an-offline-windows-image

$windowsMajorVersion = '10'
$windowsFeatureVersion = '21H2'
$sourceISOname = "Win$($windowsMajorVersion)_$($windowsFeatureVersion)_English_x64.iso" # This is the default ISO name when downloaded directly, but when the using with the Media Creation Tool (instead of direct ISO download) the default name is "Windows.iso" when exporting an ISO.

if ($false) { # Change to "$true" for Windows 11
    $windowsMajorVersion = '11'
    $windowsFeatureVersion = '21H2'
    $sourceISOname = "Win$($windowsMajorVersion)_English_x64v1.iso" # This is the default ISO name when downloaded directly.
}

$sourceISOpath = "$HOME\Documents\Free Geek\$sourceISOname"

$wimName = "Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion-Updated-$(Get-Date -UFormat '%Y%m%d')"
$winREwimName = "WinRE-$windowsMajorVersion-$windowsFeatureVersion-Updated-$(Get-Date -UFormat '%Y%m%d')"
$wimOutputPath = "$HOME\Documents\Free Geek\Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion"


Write-Output "`n  Creating Windows Install Image...`n`n`n`n" # Add empty lines for PowerShell progress UI

if (Test-Path $sourceISOpath) {
    while ($previousMountedDiskImage = Get-DiskImage $sourceISOpath | Get-Volume) {
        Write-Output "`n  Unmounting Previously Mounted $sourceISOname at $($previousMountedDiskImage.DriveLetter):\..."
        Dismount-DiskImage $sourceISOpath -ErrorAction Stop | Out-Null
    }
}


if ((Test-Path "$wimOutputPath\mount") -and ((Get-ChildItem "$wimOutputPath\mount").Count -gt 0)) {
    Write-Output "`n  Unmounting Previously Mounted OLD Windows Install Image..."
    Dismount-WindowsImage -Path "$wimOutputPath\mount" -Discard -ErrorAction Stop | Out-Null
    Remove-Item "$wimOutputPath\mount" -Recurse -Force -ErrorAction Stop
}

if ((Test-Path "$wimOutputPath\mountOS") -and ((Get-ChildItem "$wimOutputPath\mountOS").Count -gt 0)) {
    Write-Output "`n  Unmounting Previously Mounted Windows Install Image..."
    Dismount-WindowsImage -Path "$wimOutputPath\mountOS" -Discard -ErrorAction Stop | Out-Null
    Remove-Item "$wimOutputPath\mountOS" -Recurse -Force -ErrorAction Stop
}

if ((Test-Path "$wimOutputPath\mountRE") -and ((Get-ChildItem "$wimOutputPath\mountRE").Count -gt 0)) {
    Write-Output "`n  Unmounting Previously Mounted WinRE Image..."
    Dismount-WindowsImage -Path "$wimOutputPath\mountRE" -Discard -ErrorAction Stop | Out-Null
    Remove-Item "$wimOutputPath\mountRE" -Recurse -Force -ErrorAction Stop
}


if (Test-Path "$Env:WINDIR\Logs\Dism\dism.log") {
    # Delete past DISM log to make it easier to find errors in the log for this run if something goes wrong.
    Remove-Item "$Env:WINDIR\Logs\Dism\dism.log" -Force -ErrorAction Stop
}


if ((Test-Path $sourceISOpath) -and (-not (Test-Path "$wimOutputPath\Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion-ISO-Source.wim"))) {
    Write-Output "`n  Mounting $sourceISOname..."

    $mountedDiskImageDriveLetter = (Mount-DiskImage $sourceISOpath -ErrorAction Stop | Get-Volume -ErrorAction Stop).DriveLetter

    Write-Output "    Mounted to $($mountedDiskImageDriveLetter):\"

    if (-not (Test-Path $wimOutputPath)) {
        New-Item -ItemType 'Directory' -Path $wimOutputPath -ErrorAction Stop | Out-Null
    }

    Write-Output "`n  Exporting Windows $windowsMajorVersion Pro Install Image from $sourceISOname..."
    $isoInstallWimName = "$($mountedDiskImageDriveLetter):\sources\install.esd" # If the ISO is exported by the Media Creation Tool, the install file will be called "install.esd"
    if (-not (Test-Path $isoInstallWimName)) {
        $isoInstallWimName = "$($mountedDiskImageDriveLetter):\sources\install.wim" # If the ISO is downloaded directly, the install file will be called "install.wim" 
    }
    Export-WindowsImage -SourceImagePath $isoInstallWimName -SourceName "Windows $windowsMajorVersion Pro" -DestinationImagePath "$wimOutputPath\Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion-ISO-Source.wim" -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
    Get-WindowsImage -ImagePath "$wimOutputPath\Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion-ISO-Source.wim" -Index 1 -ErrorAction Stop

    while ($previousMountedDiskImage = Get-DiskImage $sourceISOpath | Get-Volume) {
        Write-Output "`n  Unmounting $sourceISOname at $($previousMountedDiskImage.DriveLetter):\..."
        Dismount-DiskImage $sourceISOpath -ErrorAction Stop | Out-Null
    }
}

if (Test-Path "$wimOutputPath\$wimName-TEMP.wim") {
    Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop
}

if (Test-Path "$wimOutputPath\$winREwimName-TEMP.wim") {
    Remove-Item "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop
}


$updatesToInstallIntoWIM = @()
if (Test-Path "$wimOutputPath\OS Updates to Install") {
    $updatesToInstallIntoWIM = Get-ChildItem "$wimOutputPath\OS Updates to Install\*" -Include '*.msu', '*.cab'
}

$updatesToInstallIntoWinRE = @()
if (Test-Path "$wimOutputPath\WinRE Updates to Install") {
    $updatesToInstallIntoWinRE = Get-ChildItem "$wimOutputPath\WinRE Updates to Install\*" -Include '*.msu', '*.cab'
} else {
    $updatesToInstallIntoWinRE = $updatesToInstallIntoWIM
}


if (($updatesToInstallIntoWinRE.Count -gt 0) -or (-not (Test-Path "$wimOutputPath\$winREwimName.wim"))<# -or (-not (Test-Path "$wimOutputPath\Wi-Fi Drivers"))#>) {
    Write-Output "`n  Mounting Windows Install Image..."

    Copy-Item "$wimOutputPath\Windows-$windowsMajorVersion-Pro-$windowsFeatureVersion-ISO-Source.wim" "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop

    if (-not (Test-Path "$wimOutputPath\mountOS")) {
        New-Item -ItemType 'Directory' -Path "$wimOutputPath\mountOS" -ErrorAction Stop | Out-Null
    }

    Mount-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -Path "$wimOutputPath\mountOS" -CheckIntegrity -ErrorAction Stop | Out-Null
}


if (Test-Path "$wimOutputPath\mountOS\Windows\System32\Recovery\Winre.wim") {
    Write-Output "`n  Extracting WinRE from Windows Install Image..."
    
    Copy-Item "$wimOutputPath\mountOS\Windows\System32\Recovery\Winre.wim" "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop
} else {
    Write-Host "`n  WINRE NOT FOUND" -ForegroundColor Red
}


<# THESE DRIVERS WERE NOT ENOUGH TO GET WI-FI WORKING ON MY TEST COMPUTERS, SO DON'T BOTHER EXTRACTING THEM - KEEPING CODE IN CASE I WANT TO EXTRACT OTHER DRIVERS IN THE FUTURE
if (-not (Test-Path "$wimOutputPath\Wi-Fi Drivers")) {
    Write-Output "`n  Extracting Wi-Fi Drivers from Windows Install Image..."
    
    New-Item -ItemType 'Directory' -Path "$wimOutputPath\Wi-Fi Drivers" -ErrorAction Stop | Out-Null

    $allPreInstalledDriverInfPaths = (Get-ChildItem "$wimOutputPath\mountOS\Windows\System32\DriverStore\FileRepository" -Recurse -File -Include '*.inf').FullName

    # This Driver .inf parsing code is based on code written for "Install Windows.ps1"
    foreach ($thisDriverInfPath in $allPreInstalledDriverInfPaths) {
        $thisDriverFolderPath = (Split-Path $thisDriverInfPath -Parent)
        $thisDriverFolderName = (Split-Path $thisDriverFolderPath -Leaf)

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
                    $wasInfVersionSection = $isInfVersionSection
                    $isInfVersionSection = ($thisDriverInfLineUPPER -eq '[VERSION]')

                    if ($wasInfVersionSection -and (-not $isInfVersionSection)) {
                        # If passed Version section and didn't already break from getting a NET class, then we can stop reading lines because we don't want this driver.
                        break
                    }
                } elseif ($isInfVersionSection -and (($lineEqualsIndex = $thisDriverInfLine.IndexOf('=')) -gt -1) -and $thisDriverInfLineUPPER.Contains('CLASS') -and (-not $thisDriverInfLineUPPER.Contains('CLASSGUID'))) {
                    $thisDriverClass = $thisDriverInfLine.Substring($lineEqualsIndex + 1).Trim().ToUpper() # It appears that the Class Names will never be in quotes or be variables that need to be translated.

                    if ($thisDriverClass -eq 'NET') {
                        try {
                            Write-Output "    Extracting Wi-Fi Driver: $thisDriverFolderName..."
                            Copy-Item $thisDriverFolderPath "$wimOutputPath\Wi-Fi Drivers" -Recurse -Force -ErrorAction Stop
                        } catch {
                            Write-Host "      ERROR EXTRACTING WI-FI DRIVER `"$thisDriverFolderName`": $_" -ForegroundColor Red
                        }
                    }

                    break
                }
            }
        }
    }
} else {
    Write-Host "`n  WI-FI DRIVERS ALREADY EXTRACTED" -ForegroundColor Yellow
}
#>


# To find the latest updates to be pre-installed, I just run a Windows installation and take note of any KB#'s that get installed by Windows Update during setup process and pre-install them into an updated WIM using this script instead of leaving Windows Update to do them (to save install/setup time).
# There is at least one monthly Cumulative update that will be time consuming during the setup process, so that should be pre-installed monthly or so into an updated WIM created by this script for the installation process to use instead of needing to rely on Windows Update during setup.

# Search the Microsoft Update Catalog (https://www.catalog.update.microsoft.com/Home.aspx) for the update files like this: "KB5007253 10 21H2 x64" - Explanation: KB5007253 (the specific ID of the update you want) + 10 (for Windows 10, to ignore Server updates) + 21H2 (for our version, to ignore older versions) + x64 (for our architecture, to ignore x86 and ARM64)
# Link to the previous example search: https://www.catalog.update.microsoft.com/Search.aspx?q=KB5007253%2010%2021H2%20x64

# ALSO, if you don't know the KB IDs, you can at least find the latest Cumulative Updates (for Windows and .NET) by searching: "2021-11 Cumulative 10 21H2 x64" - Explanation: Same as above except filtering for only "Cumulative" Updates for the specified month and year "2021-11" (obviously, set the month and year to the current or last month for the latest updates).
# Link to the previous example search: https://www.catalog.update.microsoft.com/Search.aspx?q=2021-11%20Cumulative%2010%2021H2%20x64

# IMPORTANT NOTE: Only ".msu" and ".cab" files can be pre-installed into the WIM. Any ".exe" updates (such as anti-virus updates) will have to be done by Windows Update after installation, which is fine because they are usually very small and quick and also get updated frequently.

# After downloading desired update files, put them into the "$wimOutputPath\OS Updates to Install" folder to be installed by this script.
# Also, (usually) only the latest updates need to be installed. For example, a previous Cumulative update file should be remove after a new Cumulative update is added so that both are not unnecessarily installed.

# Sometimes trying to install only the latest Cumulative Update will result in error 0x800f0823 (CBS_E_NEW_SERVICING_STACK_REQUIRED).
# The solution for this error is to include a past Servicing Stack Update which will be installed before the latest and resolve this incompatibility.
# Updates are installed in order by filename, which always includes the KB# making older updates install before newer ones and Servicing Stack Updates start with "ssu" which makes them correctly install before other updates which start with "windows".

# To find the required Servicing Stack Update for a specific Cumulative Update, check the Prerequisite section of the Support pages for the specific Cumulative Update, such as:
# https://support.microsoft.com/en-us/topic/september-14-2021-kb5005565-os-builds-19041-1237-19042-1237-and-19043-1237-292cf8ed-f97b-4cd8-9883-32b71e3e6b44
# (Use the Table of Contents navigation on the left of that page to navigate to the correct KB# for the Cumulative Update you are installing.)
# When an error occurs, the DISM log will be opened in Notepad and there can also be useful information about what requirement is missing if you scroll to where the error occurred.

# For WinRE, some Cumulative Updates will fail with error 0x8007007e (ERROR_MOD_NOT_FOUND) even when the proper Servicing Stack Update is included, and I'm not certain why.
# When this happens, the solution is to find the newest *previous* Cumulative Update or Cumulative Update Preview that works.
# For example, CU KB5005565 (2021-09) + SSU KB5005260 (19041.1161) errors for WinRE, but using the previous CU KB5005101 (2021-08 Preview) + SSU KB5005260 (19041.1161) works fine.
# So, in these cases, seperate older working updates for WinRE can be supplied in a "$wimOutputPath\WinRE Updates to Install" folder.

# Please note, this script will always install updates on top of the original source image directly from the ISO.
# Updates ARE NOT added on top of to the last updated WIM because it is not necessary and may just unnecessarily bloat the WIM (but DISM's /Cleanup-Image /StartComponentCleanup /ResetBase and then exporting a new compressed image should take care of any bloat anyway).
# Previous WIMs (with the updated date in the filename) will be left in the $wimOutputPath folder when newly updated WIMs are created to be deleted at your discretion. I generally keep one previous WIM for quick rollback if necessary and manually delete anything older than that.

if ($updatesToInstallIntoWinRE.Count -gt 0) {
    Write-Output "`n  Mounting WinRE for Updates..."
    
    if (-not (Test-Path "$wimOutputPath\mountRE")) {
        New-Item -ItemType 'Directory' -Path "$wimOutputPath\mountRE" -ErrorAction Stop | Out-Null
    }

    Mount-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -Path "$wimOutputPath\mountRE" -CheckIntegrity -ErrorAction Stop | Out-Null

    
    Write-Output "`n  Increasing WinRE Scratch Space..."
    # Increase WinRE Scratch Space: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-winre-part-1
    # If too manu GUI apps get launched during testing it appears the limited default of 32 MB of scratch space can get used up and then other stuff can fail to load such as required DISM PowerShell modules.
    
    Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$wimOutputPath\mountRE`"", '/Get-ScratchSpace'

    # PowerShell equivalent of DISM's "/Set-ScratchSpace" does not seem to exist.
    $dismSetScratchSpaceExitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$wimOutputPath\mountRE`"", '/Set-ScratchSpace:512').ExitCode

    if ($dismSetScratchSpaceExitCode -ne 0) {
        Write-Host "`n  ERROR: FAILED TO INCREASE WINRE SCRATCH SPACE - EXIT CODE: $dismSetScratchSpaceExitCode" -ForegroundColor Red
    }

    Write-Output "`n  WinRE Image Info Before Updates:"
    Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -ErrorAction Stop

    Write-Output "`n  Installing Updates into WinRE Image..."
    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#add-update-packages-to-winre

    foreach ($thisUpdateToInstallIntoWinRE in $updatesToInstallIntoWinRE) {
        Write-Output "    Installing into WinRE Image: $($thisUpdateToInstallIntoWinRE.Name)..."
        try {
            Add-WindowsPackage -Path "$wimOutputPath\mountRE" -PackagePath $thisUpdateToInstallIntoWinRE.FullName -WarningAction Stop -ErrorAction Stop | Out-Null
        } catch {
            notepad.exe "$Env:WINDIR\Logs\Dism\dism.log"
            throw $_
        }
    }

    Write-Output '    Superseded Packages in WinRE Image After Updates:'
    Get-WindowsPackage -Path "$wimOutputPath\mountRE" | Where-Object -Property PackageState -Eq -Value Superseded
    

    # NOTHING EXCEPT UPDATES SHOULD BE PRE-INSTALLED OR ADDED INTO THE WINRE WIM!

    
    Write-Output "`n  Cleaning Up WinRE Image After Updates..."
    # PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
    $dismCleanupREexitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$wimOutputPath\mountRE`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

    if ($dismCleanupREexitCode -eq 0) {
        Write-Output '    Superseded Packages for WinRE Image After Cleanup (Nothing Should Be Listed This Time):'
        Get-WindowsPackage -Path "$wimOutputPath\mountRE" | Where-Object -Property PackageState -Eq -Value Superseded

        
        Write-Output "`n  Unmounting and Saving Updated WinRE Image..."
        # Dism /Unmount-Image /MountDir:C:\test\offline /Commit
        Dismount-WindowsImage -Path "$wimOutputPath\mountRE" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
        Remove-Item "$wimOutputPath\mountRE" -Recurse -Force -ErrorAction Stop
        Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -Index 1 -ErrorAction Stop

        if (Test-Path "$wimOutputPath\$winREwimName.wim") {
            Write-Output "`n  Deleting Previous WinRE Image With The Same Name ($winREwimName.wim)..."
            Remove-Item "$wimOutputPath\$winREwimName.wim" -Force -ErrorAction Stop
        }


        Write-Output "`n  Exporting Compressed WinRE Image as `"$winREwimName.wim`"..."
        # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-final-image
        Export-WindowsImage -SourceImagePath "$wimOutputPath\$winREwimName-TEMP.wim" -SourceIndex 1 -DestinationImagePath "$wimOutputPath\$winREwimName.wim" -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
        Get-WindowsImage -ImagePath "$wimOutputPath\$winREwimName.wim" -Index 1 -ErrorAction Stop
        
        # Delete the TEMP WIM which can be considerably larger than the exported compressed WIM.
        # This is because the TEMP WIM will have a "[DELETED]" folder within it with all the old junk from the update process. This "[DELETED]" folder is not included when exporting a WIM.
        Remove-Item "$wimOutputPath\$winREwimName-TEMP.wim" -Force -ErrorAction Stop

        Write-Output "`n  Replacing Original WinRE with Updated WinRE in Windows Install Image..."
        Remove-Item "$wimOutputPath\mountOS\Windows\System32\Recovery\Winre.wim" -Force -ErrorAction Stop
        Copy-Item "$wimOutputPath\$winREwimName.wim" "$wimOutputPath\mountOS\Windows\System32\Recovery\Winre.wim" -Force -ErrorAction Stop
    } else {
        Write-Host "`n  ERROR: FAILED TO DISM CLEANUP FOR WINRE - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
    }
} else {
    Write-Host "`n  NO UPDATE FILES (IN `"WinRE Updates to Install`" FOLDER) TO INSTALL" -ForegroundColor Yellow

    if (Test-Path "$wimOutputPath\mountRE") {
        Write-Output "`n  Unmounting and Discarding Un-Updated WinRE Image..."
        Dismount-WindowsImage -Path "$wimOutputPath\mountRE" -Discard -ErrorAction Stop | Out-Null
        Remove-Item "$wimOutputPath\mountRE" -Recurse -Force -ErrorAction Stop
    }

    Move-Item "$wimOutputPath\$winREwimName-TEMP.wim" "$wimOutputPath\WinRE-$windowsMajorVersion-$windowsFeatureVersion-ISO-Source.wim" -Force -ErrorAction Stop
}


if ($updatesToInstallIntoWIM.Count -gt 0) {    
    Write-Output "`n  Windows Image Info Before Updates:"
    Get-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -ErrorAction Stop

    Write-Output "`n  Installing Updates into Windows Install Image..."
    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#add-windows-updates-to-your-image
    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-desktop-editions#add-windows-updates-to-your-image

    foreach ($thisUpdateToInstallIntoWIM in $updatesToInstallIntoWIM) {
        Write-Output "    Installing into Windows Install Image: $($thisUpdateToInstallIntoWIM.Name)..."
        # Dism /Image:C:\test\offline /Add-Package /PackagePath:C:\packages\package1.cab (https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-or-remove-packages-offline-using-dism)
        try {
            Add-WindowsPackage -Path "$wimOutputPath\mountOS" -PackagePath $thisUpdateToInstallIntoWIM.FullName -WarningAction Stop -ErrorAction Stop | Out-Null
        } catch {
            notepad.exe "$Env:WINDIR\Logs\Dism\dism.log"
            throw $_
        }
    }

    Write-Output '    Superseded Packages in Windows Install Image After Updates:'
    Get-WindowsPackage -Path "$wimOutputPath\mountOS" | Where-Object -Property PackageState -Eq -Value Superseded
    

    # NOTHING EXCEPT UPDATES SHOULD BE PRE-INSTALLED OR ADDED INTO THE WINDOWS INSTALL WIM!
    # ALL NECESSARY WINDOWS INSTALL SETUP FILES ARE ADDED FROM SERVER OR USB DURING THE INSTALLATION PROCESS.


    Write-Output "`n  Cleaning Up Windows Install Image After Updates..."
    # PowerShell equivalent of DISM's "/Cleanup-Image /StartComponentCleanup /ResetBase" does not seem to exist.
    $dismCleanupOSexitCode = (Start-Process 'DISM' -NoNewWindow -Wait -PassThru -ArgumentList "/Image:`"$wimOutputPath\mountOS`"", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase').ExitCode

    if ($dismCleanupOSexitCode -eq 0) {
        Write-Output '    Superseded Packages for Windows Install Image After Cleanup (Nothing Should Be Listed This Time):'
        Get-WindowsPackage -Path "$wimOutputPath\mountOS" | Where-Object -Property PackageState -Eq -Value Superseded

        
        Write-Output "`n  Unmounting and Saving Updated Windows Install Image..."
        # Dism /Unmount-Image /MountDir:C:\test\offline /Commit
        Dismount-WindowsImage -Path "$wimOutputPath\mountOS" -CheckIntegrity -Save -ErrorAction Stop | Out-Null
        Remove-Item "$wimOutputPath\mountOS" -Recurse -Force -ErrorAction Stop
        Get-WindowsImage -ImagePath "$wimOutputPath\$wimName-TEMP.wim" -Index 1 -ErrorAction Stop

        if (Test-Path "$wimOutputPath\$wimName.wim") {
            Write-Output "`n  Deleting Previous Windows Install Image With The Same Name ($wimName.wim)..."
            Remove-Item "$wimOutputPath\$wimName.wim" -Force -ErrorAction Stop
        }


        Write-Output "`n  Exporting Compressed Windows Install Image as `"$wimName.wim`"..."
        # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-10-for-desktop-editions#optimize-final-image
        Export-WindowsImage -SourceImagePath "$wimOutputPath\$wimName-TEMP.wim" -SourceIndex 1 -DestinationImagePath "$wimOutputPath\$wimName.wim" -CheckIntegrity -CompressionType 'max' -ErrorAction Stop | Out-Null
        Get-WindowsImage -ImagePath "$wimOutputPath\$wimName.wim" -Index 1 -ErrorAction Stop
        
        # Delete the TEMP WIM which can be considerably larger than the exported compressed WIM.
        # This is because the TEMP WIM will have a "[DELETED]" folder within it with all the old junk from the update process. This "[DELETED]" folder is not included when exporting a WIM.
        Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop
    } else {
        Write-Host "`n  ERROR: FAILED TO DISM CLEANUP FOR OS - EXIT CODE: $dismCleanupExitCode" -ForegroundColor Red
    }
} else {
    Write-Host "`n  NO UPDATE FILES (IN `"OS Updates to Install`" FOLDER) TO INSTALL" -ForegroundColor Yellow

    if (Test-Path "$wimOutputPath\mountOS") {
        Write-Output "`n  Unmounting and Discarding Un-Updated Windows Install Image..."
        Dismount-WindowsImage -Path "$wimOutputPath\mountOS" -Discard -ErrorAction Stop | Out-Null
        Remove-Item "$wimOutputPath\mountOS" -Recurse -Force -ErrorAction Stop
        Remove-Item "$wimOutputPath\$wimName-TEMP.wim" -Force -ErrorAction Stop
    }
}
