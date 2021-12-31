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

if (Test-Path "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml") {
    Remove-Item "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml" -Force
}

if ($IsWindows -or ($null -eq $IsWindows)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Ssl3
}

Invoke-WebRequest -Uri 'https://download.lenovo.com/cdrt/td/catalog.xml' -OutFile "$PSScriptRoot\DriverPackCatalog-LenovoV1.xml"

[xml]$lenovoDriverPackCatalogXMLv1 = Get-Content "$PSScriptRoot/DriverPackCatalog-LenovoV1.xml"

$supportPagesForSystemIDs = @{}

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
                if ($supportPagesForSystemIDs[$thisSystemID]) {
                    if ($osVersionNumber -gt $supportPagesForSystemIDs[$thisSystemID].OSVersionNumber) {
                        # Write-Output "($osVersionNumber > $($supportPagesForSystemIDs[$thisSystemID].OSVersionNumber)) UPDATING SUPPORT PAGE FOR '$thisSystemID' TO '$lenovoSupportPage'"
                        $supportPagesForSystemIDs[$thisSystemID]['LenovoSupportPage'] = $lenovoSupportPage
                        $supportPagesForSystemIDs[$thisSystemID]['OSVersionNumber'] = $osVersionNumber
                    }
                } else {
                    # Write-Output "ADDING '$thisSystemID' WITH SUPPORT PAGE '$lenovoSupportPage'"

                    $supportPagesForSystemIDs[$thisSystemID] = [ordered]@{
                        SystemID = $thisSystemID
                        ModelName = $modelName
                        LenovoSupportPage = $lenovoSupportPage
                        OSVersionNumber = $osVersionNumber
                    }
                }
            }
        }
    }
}

$uniqueSupportPages = @()

foreach ($thisSupportPageForSystemID in ($supportPagesForSystemIDs.GetEnumerator() | Sort-Object -Property Key)) {
    $uniqueSupportPages += $thisSupportPageForSystemID.Value.LenovoSupportPage
}

$uniqueSupportPages = ($uniqueSupportPages | Sort-Object -Unique)

Write-Output "$($uniqueSupportPages.Count) LENOVO URLs DETECTED IN V1 XML"

foreach ($thisIE in (New-Object -COM 'Shell.Application').Windows() | Where-Object { $_.Name -like '*Internet Explorer*' }) {
    $thisIE.Quit()
    [Runtime.Interopservices.Marshal]::ReleaseComObject($thisIE) | Out-Null
}

[GC]::Collect()
[GC]::WaitForPendingFinalizers()

$ie = New-Object -ComObject 'InternetExplorer.Application'
$ie.Visible = $true

$ie.Navigate('https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index')

for ($pageLoadWaitSeconds = 0; $pageLoadWaitSeconds -lt 30; $pageLoadWaitSeconds ++) {
    if ((-not $ie.Busy) -and ($ie.ReadyState -eq 4)) {
        try {
            if ($ie.Document.getElementsByTagName('h1').Length -gt 0) {
                break
            }
        } catch {
            Write-Output 'WARNING: FAILED TO CONFIRM PAGE LOAD - STILL WAITING'
            # Keep waiting if element check fails
        }
    } elseif ($null -eq $ie.ReadyState) {
        Write-Output 'LOST CONNECTION TO IE'
        break
    }
    
    Start-Sleep 1
    $pageLoadWaitSeconds ++
}

if ($pageLoadWaitSeconds -ge 30) {
    Write-Output 'WARNING: PAGE LOAD TIMED OUT'
    $pageNeedsLoad = $true
}

$linksFromDriverPacksWebsite = @()

foreach ($thisLink in $ie.Document.getElementsByTagName('a')) {
    if ($thisLink.href.ToLower().Contains('/ds') -and $thisLink.parentNode.parentNode.childNodes.length -gt 9) {
        foreach ($thisChildNode in $thisLink.parentNode.parentNode.childNodes) {
            if ($thisChildNode.lastChild.tagName -eq 'A') {
                $latestLinkForRow = $thisChildNode.lastChild.href.ToLower().Replace('http:', 'https:').Replace('/pcsupport.', '/support.').Replace('com/downloads', 'com/us/en/downloads')
            }
        }
        
        $linksFromDriverPacksWebsite += $latestLinkForRow
    }
}

$linksFromDriverPacksWebsite = ($linksFromDriverPacksWebsite | Sort-Object -Unique)

Write-Output "$($linksFromDriverPacksWebsite.Count) LENOVO URLs DETECTED IN DRIVER PACKS SITE"

$uniqueSupportPages += $linksFromDriverPacksWebsite

$uniqueSupportPages = ($uniqueSupportPages | Sort-Object -Unique)

Write-Output "$($uniqueSupportPages.Count) TOTAL UNIQUE URLs FROM V1 XML AND DRIVER PACKS SITE"

Get-Date

$linkLoadCount = 1

$allDriversForURLs = @{}

foreach ($thisLenovoURL in $uniqueSupportPages) {
    Write-Output "`n$linkLoadCount ----------"
    Write-Output "LOADING URL: $thisLenovoURL"
    $allDriversForURLs[$thisLenovoURL] = @()
    
    $pageNeedsLoad = $true
    $didSkipDrivers = $false

    for ($loadPageAttempt = 0; $loadPageAttempt -lt 10; $loadPageAttempt ++) {
        try {
            if ($pageNeedsLoad) {
                $ie.Navigate($thisLenovoURL)
            } else {
                Write-Output 'NOTE: DID NOT RELOAD PAGE'
            }
            
            for ($pageLoadWaitSeconds = 0; $pageLoadWaitSeconds -lt 30; $pageLoadWaitSeconds ++) {
                if ((-not $ie.Busy) -and ($ie.ReadyState -eq 4)) {
                    try {
                        if (($ie.Document.getElementsByTagName('h1').Length -gt 0) -or ($ie.Document.getElementsByClassName('errorpage-newcontent').Length -gt 0)) {
                            break
                        }
                    } catch {
                        Write-Output 'WARNING: FAILED TO CONFIRM PAGE LOAD - STILL WAITING'
                        # Keep waiting if element check fails
                    }
                } elseif ($null -eq $ie.ReadyState) {
                    throw 'LOST CONNECTION TO IE - NEED NEW IE OBJECT'
                }
                
                Start-Sleep 1
                $pageLoadWaitSeconds ++
            }

            if ($pageLoadWaitSeconds -ge 30) {
                Write-Output 'WARNING: PAGE LOAD TIMED OUT - TRYING AGAIN'
                $pageNeedsLoad = $true
                continue
            }
            
            if ($ie.Document.getElementsByClassName('errorpage-newcontent').Length -gt 0) {
                Write-Output "ERROR: $($ie.Document.getElementsByClassName('errorpage-newcontent')[0].firstChild.innerText)"
                break
            }

            $pageTitle = $ie.Document.getElementsByTagName('h1')[0].innerText
            
            if (($null -eq $pageTitle) -or ($pageTitle -eq '')) {
                Write-Output 'WARNING: NO PAGE TITLE DETECTED - TRYING AGAIN'
                Start-Sleep 1
                $pageNeedsLoad = ($loadPageAttempt -eq 5)
                continue
            }

            Write-Output "PAGE TITLE: '$pageTitle'"
            
            foreach ($thisHashLink in $ie.Document.getElementsByClassName('icon-checksum')) {
                $thisHashLink.click() # Must click these links to create Checksum elements.
            }
            
            $allDriversForURLs[$thisLenovoURL] = @()

            foreach ($thisPageLink in $ie.Document.getElementsByTagName('a')) {
                if (($null -ne $thisPageLink.href) -and $thisPageLink.href.ToLower().EndsWith('.exe')) {
                    Write-Output '-----'

                    $osVersion = $thisPageLink.parentNode.previousSibling.previousSibling.previousSibling.previousSibling.previousSibling.firstChild.innerText
                    
                    if ($null -eq $osVersion) {
                        $osVersion = 'N/A'
                    } else {
                        $osVersion = $osVersion.ToLower()
                    }

                    if ((-not $osVersion.StartsWith('windows 7')) -and (-not $osVersion.StartsWith('windows 8')) -and (-not $osVersion.StartsWith('windows 8.1')) -and (-not $osVersion.StartsWith('windows 10'))) {
                        Write-Output "WARNING: SKIPPING INVALID WINDOWS VERSION `"$osVersion`""
                        $didSkipDrivers = $true
                        continue
                    } elseif ($osVersion.EndsWith(' (32-bit)')) {
                        Write-Output "NOTE: SKIPPING 32-BIT DRIVERS"
                        $didSkipDrivers = $true
                        continue
                    } elseif (-not $osVersion.Contains('-bit')) {
                        Write-Output "WARNING: NO BIT SPECIFIED"
                    }

                    $packageTitle = $thisPageLink.parentNode.parentNode.firstChild.childNodes[1].innerText

                    if ($null -eq $packageTitle) {
                        $packageTitle = 'N/A'
                    } else {
                        $packageTitle = $packageTitle.Trim()
                    }

                    if ($osVersion.StartsWith('windows 10')) {
                        $possibleWinTenVersion = $packageTitle.ToLower()
                        if ($possibleWinTenVersion.Contains('version ')) {
                            $possibleWinTenVersion = ($possibleWinTenVersion -Split ('version '))[1] # Must use -Split and parens around arg to split on string instead of char.
                            if ($possibleWinTenVersion.Contains(',') -or $possibleWinTenVersion.Contains('/')) {
                                $possibleWinTenVersionSplitString = ','
                                if ($possibleWinTenVersion.Contains('/')) {
                                    $possibleWinTenVersionSplitString = '/'
                                }

                                $possibleWinTenVersion = $possibleWinTenVersion.Split($possibleWinTenVersionSplitString) | Select-Object -Last 1
                            }

                            $possibleWinTenVersion = ($possibleWinTenVersion -Replace '[^0-9h]').ToUpper()
                            if ($possibleWinTenVersion.length -eq 4) {
                                $osVersion = $osVersion -Replace 'windows 10', "Windows 10 (Version $possibleWinTenVersion)"
                            } else {
                                Write-Output "WARNING: INVALID WIN 10 VERSION IN `"$possibleWinTenVersion`""
                            }
                        } else {
                            Write-Output "WARNING: NO WIN 10 VERSION IN `"$possibleWinTenVersion`""
                        }
                    }

                    $osVersion = $osVersion -Replace 'windows ', 'Windows '

                    $thisDriverPack = [ordered]@{
                        PageTitle = $pageTitle
                        DownloadURL = $thisPageLink.href
                        PackageTitle = $packageTitle
                        ReleaseDate = $thisPageLink.parentNode.previousSibling.previousSibling.previousSibling.innerText
                        Version = $thisPageLink.parentNode.previousSibling.previousSibling.previousSibling.previousSibling.innerText
                        OS = $osVersion
                    }

                    for ($getHashAttempt = 0; $getHashAttempt -lt 10; $getHashAttempt ++) {
                        if ($thisPageLink.parentNode.parentNode.nextSibling.tagName.ToUpper() -eq 'DIV') {
                            $thisDriverPack['HashType'] = $thisPageLink.parentNode.parentNode.nextSibling.childNodes[1].firstChild.firstChild.innerText.ToUpper() -Replace '[^A-Z0-9]'
                            $thisDriverPack['Hash'] = $thisPageLink.parentNode.parentNode.nextSibling.childNodes[1].firstChild.childNodes[1].innerText
                            break
                        } else {
                            Write-Output 'WARNING: HASH NOT LOADED - TRYING AGAIN'
                            
                            foreach ($thisHashLink in $ie.Document.getElementsByClassName('icon-checksum')) {
                                $thisHashLink.click() # Must click these links to create Checksum elements.
                            }

                            Start-Sleep 1
                        }
                    }

                    if ($null -eq $thisDriverPack['Hash']) {
                        Write-Output 'ERROR: FAILED TO LOAD HASHES'
                    }

                    $allDriversForURLs[$thisLenovoURL] += $thisDriverPack

                    Write-Output "DownloadURL: '$($thisDriverPack.DownloadURL)'"
                    Write-Output "PackageTitle: '$($thisDriverPack.PackageTitle)'"
                    Write-Output "ReleaseDate: '$($thisDriverPack.ReleaseDate)'"
                    Write-Output "Version: '$($thisDriverPack.Version)'"
                    Write-Output "OS: '$($thisDriverPack.OS)'"
                    Write-Output "HashType: '$($thisDriverPack.HashType)'"
                    Write-Output "Hash: '$($thisDriverPack.Hash)'"
                }
            }
            
            if (($allDriversForURLs[$thisLenovoURL].Count -gt 0) -or $didSkipDrivers) {
                break
            } else {
                Write-Output 'WARNING: NO DRIVERS DETECTED - TRYING AGAIN'
                Start-Sleep 1
                $pageNeedsLoad = ($loadPageAttempt -eq 5)
            }
        } catch {
            Write-Output "WARNING: $_ - TRYING AGAIN"

            foreach ($thisIE in (New-Object -COM 'Shell.Application').Windows() | Where-Object { $_.Name -like '*Internet Explorer*' }) {
                $thisIE.Quit()
                [Runtime.Interopservices.Marshal]::ReleaseComObject($thisIE) | Out-Null
            }
            
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            
            Start-Sleep 1

            $ie = New-Object -ComObject 'InternetExplorer.Application'
            $ie.Visible = $true

            $pageNeedsLoad = $true
        }
    }

    if ($allDriversForURLs[$thisLenovoURL].Count -eq 0) {
        if ($didSkipDrivers) {
            Write-Output 'WARNING: NO 64-BIT DRIVERS DETECTED'
        } else {
            Write-Output 'ERROR: FAILED TO DETECT DRIVERS'
        }
    }

    $linkLoadCount ++
}

$allDriversForURLs | Export-Clixml -Path "$PSScriptRoot\DriverPackCatalog-LenovoV1-EXEsFromSupportPages.xml"

Get-Date

# https://stackoverflow.com/questions/30642883/how-to-properly-close-internet-explorer-when-launched-from-powershell#30643155

foreach ($thisIE in (New-Object -COM 'Shell.Application').Windows() | Where-Object { $_.Name -like '*Internet Explorer*' }) {
    $thisIE.Quit()
    [Runtime.Interopservices.Marshal]::ReleaseComObject($thisIE) | Out-Null
}

[GC]::Collect()
[GC]::WaitForPendingFinalizers()

if ($IsWindows -or ($null -eq $IsWindows)) {
    $Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
}

Read-Host 'DONE - PRESS ENTER TO EXIT'
