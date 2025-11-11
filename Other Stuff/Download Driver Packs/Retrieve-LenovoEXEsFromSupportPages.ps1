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

$ProgressPreference = 'SilentlyContinue' # Not showing progress makes "Invoke-WebRequest" downloads MUCH faster: https://stackoverflow.com/a/43477248

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
				} elseif ($thisDriverPack.os -eq 'win11') {
					$osVersionNumber = 11
				}
			} elseif (($thisDriverPack.os -eq 'win10') -or ($thisDriverPack.os -eq 'win11')) {
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

Write-Output "`n`nLoading Selenium WebDriver..."

Import-Module "$PSScriptRoot\Selenium" -Force -ErrorAction Stop # This is a manual download/extraction of https://www.powershellgallery.com/packages/Selenium/3.0.1 (".nupkg" is actuall just a ".zip")

$webDriver = New-Object OpenQA.Selenium.Firefox.FirefoxDriver # The Selenium module loaded above has "geckodriver.exe" included in it, but Firefox app must be installed on the system.

Write-Output "`n"

$webDriver.Navigate().GoToURL('https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index')

$linksFromDriverPacksWebsite = @()

foreach ($thisTableCell in $webDriver.FindElementsByXPath('//h3[text()="Driver Packs"]/following-sibling::table//td[last()]')) {
	$thisTableCellText = $thisTableCell.GetAttribute('innerText')

	while ($thisTableCellText -eq '-') {
		$thisTableCell = $thisTableCell.FindElementByXPath('.//preceding-sibling::td[1]')
		$thisTableCellText = $thisTableCell.GetAttribute('innerText')
	}

	$theseLinks = $null
	if ($thisTableCellText.Contains('-bit')) {
		$theseLinks = $thisTableCell.FindElementsByTagName('a')
	}

	if ($null -ne $theseLinks) {
		foreach ($thisLink in $theseLinks) {
			$thisLinkHref = $thisLink.GetAttribute('href').ToLower()

			if ($thisLinkHref.Contains('/ds')) {
				$linksFromDriverPacksWebsite += $thisLinkHref.Replace('http:', 'https:').Replace('/pcsupport.', '/support.').Replace('com/downloads', 'com/us/en/downloads').Replace('https://downloads/', 'https://support.lenovo.com/us/en/downloads/')
			}
		}
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

	$didSkipDrivers = $false

	$webDriver.Navigate().GoToURL($thisLenovoURL)

	$pageTitle = $webDriver.FindElementsByTagName('h1').GetAttribute('innerText')

	Write-Output "PAGE TITLE: '$pageTitle'"

	$allDriversForURLs[$thisLenovoURL] = @()

	foreach ($thisPageLink in $webDriver.FindElementsByXPath('//div/div/div/div/a')) {
		$thisPageLinkHref = $thisPageLink.GetAttribute('href')
		if (($null -ne $thisPageLinkHref) -and $thisPageLinkHref.ToLower().EndsWith('.exe')) {
			Write-Output '-----'

			$osVersion = $thisPageLink.FindElementByXPath('./../../../div[4]').GetAttribute('innerText')

			if ($null -eq $osVersion) {
				$osVersion = 'N/A'
			} else {
				$osVersion = $osVersion.Split([Environment]::NewLine)[0].Trim().ToLower()
			}

			if (($osVersion -eq '') -or ($osVersion -eq 'N/A')) { # https://support.lenovo.com/us/en/downloads/ds039169
				if ($thisPageLinkHref.Contains('_win7_32bit')) {
					$osVersion = 'windows 7 (32-bit)'
				} elseif ($thisPageLinkHref.Contains('_win7_64bit')) {
					$osVersion = 'windows 7 (64-bit)'
				} elseif ($thisPageLinkHref.Contains('_win8_64bit')) {
					$osVersion = 'windows 8 (64-bit)'
				}
			}

			if ((-not $osVersion.StartsWith('windows 7')) -and (-not $osVersion.StartsWith('windows 8')) -and (-not $osVersion.StartsWith('windows 8.1')) -and (-not $osVersion.StartsWith('windows 10')) -and (-not $osVersion.StartsWith('windows 11'))) {
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

			$packageTitle = $thisPageLink.FindElementByXPath('./../../../div[1]').GetAttribute('innerText')

			if ($null -eq $packageTitle) {
				$packageTitle = 'N/A'
			} else {
				$packageTitle = $packageTitle.Split([Environment]::NewLine)[0].Trim()
			}

			if ($osVersion.StartsWith('windows 10') -or $osVersion.StartsWith('windows 11')) {
				$possibleFeatureVersion = $packageTitle.ToLower()
				if ($possibleFeatureVersion.Contains('version ')) {
					$possibleFeatureVersion = ($possibleFeatureVersion -Split ('version ')) | Select-Object -Last 1 # Must use -Split and parens around arg to split on string instead of char.
					if ($possibleFeatureVersion.Contains(',') -or $possibleFeatureVersion.Contains('/')) {
						$possibleFeatureVersionSplitString = ','
						if ($possibleFeatureVersion.Contains('/')) {
							$possibleFeatureVersionSplitString = '/'
						}

						$possibleFeatureVersion = $possibleFeatureVersion.Split($possibleFeatureVersionSplitString) | Select-Object -Last 1
					}

					$possibleFeatureVersion = ($possibleFeatureVersion -Replace '[^0-9h]').ToUpper()
					if ($possibleFeatureVersion.length -eq 4) {
						$osVersion = $osVersion -Replace 'windows 10', "Windows 10 (Version $possibleFeatureVersion)"
						$osVersion = $osVersion -Replace 'windows 11', "Windows 11 (Version $possibleFeatureVersion)"
					} else {
						Write-Output "WARNING: INVALID FEATURE VERSION IN `"$possibleFeatureVersion`""
					}
				} else {
					Write-Output "WARNING: NO FEATURE VERSION IN `"$possibleFeatureVersion`""
				}
			}

			$osVersion = $osVersion -Replace 'windows ', 'Windows '

			$thisDriverPack = [ordered]@{
				PageTitle = $pageTitle
				DownloadURL = $thisPageLinkHref
				PackageTitle = $packageTitle
				ReleaseDate = $thisPageLink.FindElementByXPath('./../../../div[5]').GetAttribute('innerText')
				Version = $thisPageLink.FindElementByXPath('./../../../div[3]').GetAttribute('innerText')
				OS = $osVersion
				HashType = $thisPageLink.FindElementByXPath('./../../../../following-sibling::div[@class="table-children-description"]//span[@class="checksum-code-name"]').GetAttribute('innerText')
				Hash = $thisPageLink.FindElementByXPath('./../../../../following-sibling::div[@class="table-children-description"]//span[@class="checksum-code-text"]').GetAttribute('innerText')
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

Write-Output "`n"

Get-Date

Write-Output "`n`nClosing Selenium WebDriver..."
$webDriver.Close()
$webDriver.Quit()
Write-Output "`n"

if ($IsWindows -or ($null -eq $IsWindows)) {
	$Host.UI.RawUI.FlushInputBuffer() # So that key presses before this point are ignored.
}

Read-Host 'DONE - PRESS ENTER TO EXIT' | Out-Null
