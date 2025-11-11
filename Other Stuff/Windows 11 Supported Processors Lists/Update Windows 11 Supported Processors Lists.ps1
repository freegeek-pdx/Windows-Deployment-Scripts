#
# MIT License
#
# Copyright (c) 2025 Free Geek
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

$processorBrands = @('Intel', 'AMD', 'Qualcomm')
$windowsVersions = @('11')

$subtractYears = 0
do {
	$featureVersion = "$((Get-Date).AddYears($subtractYears).ToString('yy'))H2"
	$windowsVersions += "11 $featureVersion"
	$subtractYears --
}
until ($featureVersion -eq '22H2')

$dateString = $(Get-Date -Format 'yyyy.M.d')

$outputFolderPath = "$PSScriptRoot\Windows 11 Supported Processors Lists $dateString"
if (-not (Test-Path $outputFolderPath)) {
	New-Item -ItemType 'Directory' -Path $outputFolderPath -ErrorAction Stop | Out-Null
}

$processorSeriesURLCache = @{}

foreach ($thisProcessorBrand in $processorBrands) {
	$allSupportedProcessorNames = @()

	foreach ($thisWindowsVersion in $windowsVersions) {
		$thisSupportedProcessorsURL = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-$($thisWindowsVersion.ToLower().Replace(' ', '-'))-supported-$($thisProcessorBrand.ToLower())-processors"

		Write-Output "`n$thisProcessorBrand $thisWindowsVersion`n$thisSupportedProcessorsURL"

		$tableContents = ''
		try {
			$tableContents = [System.IO.StreamReader]::new((Invoke-WebRequest -TimeoutSec 5 -Uri $thisSupportedProcessorsURL -ErrorAction Stop).RawContentStream).ReadToEnd()
			# Parse the "RawContentStream" instead of "Content" so that multi-byte characters (® and ™) don't get mangled: https://www.reddit.com/r/PowerShell/comments/17h8koy/comment/k6otsr1
		} catch {
			Write-Host "SUPPORTED PROCESSOR LIST HTTP ERROR: $($_.Exception.Response.StatusCode)"
		}

		$tableTagIndex = $tableContents.indexOf('<table>') # Extract only the table to avoid HTML parsing issues with Select-Xml
		if ($tableTagIndex -gt -1) {
			$tableContents = $tableContents.Substring($tableTagIndex, ($tableContents.indexOf('</table>') + 8 - $tableTagIndex)).Replace('&nbsp;', ' ')

			$thisSupportedProcessorNames = @()
			$possiblyUnmatchedProcessorWhichAreSupported = @{}

			Select-Xml -Content $tableContents -XPath '//tr' -ErrorAction Stop | Select-Object -Skip 1 | ForEach-Object {
				$tdNodes = $_.Node.ChildNodes
				if ($tdNodes.Count -ge 3) {
					if (($tdNodes.Count -lt 4) -or ($tdNodes[3].InnerText -ne 'IoT Enterprise Only')) {
						# Processor names are modified to match format of the following WhyNotWin11 files (which match the brand strings of the processors):
						# https://github.com/rcmaehl/WhyNotWin11/blob/main/includes/SupportedProcessorsIntel.txt
						# https://github.com/rcmaehl/WhyNotWin11/blob/main/includes/SupportedProcessorsAMD.txt
						# https://github.com/rcmaehl/WhyNotWin11/blob/main/includes/SupportedProcessorsQualcomm.txt

						$registeredSymbolReplacement = '(R)'
						$trademarkSymbolReplacement = '(TM)'
						if ($thisProcessorBrand -eq 'AMD') {
							$registeredSymbolReplacement = ''
							$trademarkSymbolReplacement = ''
						}

						if (($thisProcessorBrand -eq 'Intel') -and ($tdNodes[2].ChildNodes[0].Name -eq 'a')) {
							$thisProcessorSeriesDescription = $tdNodes[2].InnerText.Trim() -Replace '\s+', ' '
							$thisProcessorSeriesURL = $tdNodes[2].ChildNodes[0].href

							Write-Output "  $thisProcessorSeriesDescription - $thisProcessorSeriesURL"
							if ($processorSeriesURLCache.ContainsKey("$thisProcessorSeriesDescription - $thisProcessorSeriesURL")) {
								Write-Output "    USING CACHE FROM PREVIOUS LIST RATHER THAN LOADING AGAIN"
								$thisSupportedProcessorNames += $processorSeriesURLCache["$thisProcessorSeriesDescription - $thisProcessorSeriesURL"]
							} else {
								$thisProcessorSeriesSubsetMatchString = ''
								if ($thisProcessorSeriesDescription.ToLower().EndsWith(' series')) {
									$thisProcessorSeriesDescriptionParts = $thisProcessorSeriesDescription.Split(' ')
									$thisProcessorSeriesSubsetMatchString = $thisProcessorSeriesDescriptionParts[$thisProcessorSeriesDescriptionParts.Count - 2].Replace('0', '\d')
									if ($thisProcessorSeriesSubsetMatchString.StartsWith('W-')) {
										# NOTE: Some of the newer Xeon "W-####" series that are intended to be matched are actually named like "w3-####" or "w5-####" etc.
										$thisProcessorSeriesSubsetMatchString = $thisProcessorSeriesSubsetMatchString.Replace('W-', '[Ww]\d?-')
									}

									Write-Output "  MATCHING SUBSET $thisProcessorSeriesDescription = $thisProcessorSeriesSubsetMatchString"
								}

								$processorSeriesURLCache["$thisProcessorSeriesDescription - $thisProcessorSeriesURL"] = @()

								try {
									$thisProcessorSeriesTableContents = [System.IO.StreamReader]::new((Invoke-WebRequest -UserAgent 'curl' -TimeoutSec 5 -Uri $thisProcessorSeriesURL -ErrorAction Stop).RawContentStream).ReadToEnd()
									# NOTE: If the default PowerShell user agent string is used, the request is "Forbidden", but with the "curl" user agent string the page loads properly.
								} catch {
									Write-Host "PROCESSOR SERIES HTTP ERROR: $($_.Exception.Response.StatusCode)"
								}

								$thisProcessorSeriesTableTagIndex = $thisProcessorSeriesTableContents.indexOf('<table') # Extract only the table to avoid HTML parsing issues with Select-Xml
								if ($thisProcessorSeriesTableTagIndex -gt -1) {
									$thisProcessorSeriesTableContents = $thisProcessorSeriesTableContents.Substring($thisProcessorSeriesTableTagIndex, ($thisProcessorSeriesTableContents.indexOf('</table>') + 8 - $thisProcessorSeriesTableTagIndex)).Replace('&nbsp;', ' ')
									$thisProcessorSeriesTableContents = $thisProcessorSeriesTableContents.Replace('<label ', '<!-- ').Replace('</label>', '-->').Replace('<br>', '<br/>') # If the <label> tags aren't commented out, the unlosed <input> tag within them will cause "Select-Xml"to throw an error (same with unclosed "<br>" tags).

									Select-Xml -Content $thisProcessorSeriesTableContents -XPath '//tr' -ErrorAction Stop | Select-Object -Skip 1 | ForEach-Object {
										$thisProcessorSeriesTdNodes = $_.Node.ChildNodes

										if ($thisProcessorSeriesTdNodes.Count -ge 6) {
											$isActuallySupported = $true
											$processorModel = $thisProcessorSeriesTdNodes[0].InnerText.Replace("$([char]0x00AE)", $registeredSymbolReplacement).Replace("$([char]0x2122)", $trademarkSymbolReplacement)
											$releaseYearAndQuarter = $thisProcessorSeriesTdNodes[1].InnerText.Trim()
											$releaseYear = 0
											if ($releaseYearAndQuarter.StartsWith('Q') -and $releaseYearAndQuarter.Contains("'")) {
												$releaseYear = [int]$releaseYearAndQuarter.Split("'")[1]
											}

											if ($thisProcessorBrand -eq 'Intel') {
												$processorModel = $processorModel.Replace('Intel(R) ', '').Replace('Intel ', '').Replace(' X-series', '').Replace(' Extreme Edition', '').Replace('+8','-8').Trim() -Replace '\s+', ' '

												$processorModel = $processorModel  -Replace ' with Radeon.* Graphics', ''

												$processorModel = $processorModel  -Replace ' \(.* Memory', ''
												# This removes the following suffix info (and the "+" is replaced with "-" above)
												# Core(TM) i5+8400  (9M Cache, up to 4.00 GHz) includes Intel(R) Optane(TM) Memory
												# Core(TM) i5+8500  (9M Cache, up to 4.10 GHz) includes Intel(R) Optane(TM) Memory
												# Core(TM) i7+8700  (12M Cache, up to 4.60 GHz) includes Intel(R) Optane(TM) Memory

												if ($processorModel.Contains("Core(TM) i")) {
													$processorModel = $processorModel -Replace ' processor ', '-' # For "Core(TM) i5 processor 14500" (BUT NOT "Core(TM) 3 processor 100U" which should just have a SPACE and not a DASH and will be replaced properly below).
												}
												$processorModel = $processorModel -Replace ' [Pp]rocessor', ''
											}

											if ($thisProcessorSeriesSubsetMatchString -ne '') {
												# Some links are for series that include older CPUs that are not actually supported (such as https://www.intel.com/content/www/us/en/ark/products/series/123588/intel-core-x-series-processors.html)
												# and the text of the link indicates some supported subset (such as "Intel Core 9000X Series")
												# so match the extracted series match string (such as "9??X").

												if ($processorModel -match ".*[ -]$thisProcessorSeriesSubsetMatchString.*") {
													Write-Host "    MATCHED CPU FROM ${releaseYearAndQuarter}: $processorModel == $thisProcessorSeriesSubsetMatchString"
												} else {
													$isActuallySupported = $false
													Write-Host "    SKIPPING UNMATCHED CPU FROM ${releaseYearAndQuarter}: $processorModel != $thisProcessorSeriesSubsetMatchString"

													if (($processorModel.StartsWith("Atom(R) ") -and ($releaseYear -ge 21)) -or
														($processorModel.StartsWith("Celeron(R) ") -and ($releaseYear -ge 21)) -or
														($processorModel.StartsWith("Pentium(R) Gold ") -and ($releaseYear -ge 20)) -or
														($processorModel.StartsWith("Pentium(R) Silver ") -and ($releaseYear -ge 17)) -or
														($processorModel.StartsWith("Xeon(R) W-") -and ($releaseYear -ge 19))) {
														# Some CPUs in these lists are NOT included in any of the specified series, but they are quite new.
														# Through comparison with previous lists, I found that the models which are left out but match the
														# conditions above WERE included in previous supported CPU lists from Microsoft and SHOULD be included.

														if (-not $possiblyUnmatchedProcessorWhichAreSupported.ContainsKey($releaseYearAndQuarter)) {
															$possiblyUnmatchedProcessorWhichAreSupported[$releaseYearAndQuarter] = @()
														}

														$possiblyUnmatchedProcessorWhichAreSupported[$releaseYearAndQuarter] += $processorModel

														# Below, the "possiblyUnmatchedProcessorWhichAreSupported" will be iterated and checked to be sure they
														# were not actually included in another series than the one currently being checked
														# and only actually unmatched models will be added.
													}
												}
											}

											if ($isActuallySupported) {
												$processorModel = $processorModel.Trim() -Replace '\s+', ' '
												$processorSeriesURLCache["$thisProcessorSeriesDescription - $thisProcessorSeriesURL"] += $processorModel
											}
										} else {
											Write-Output "DEBUG: $($thisProcessorSeriesTdNodes.Count)"
										}
									}
								}

								if (($thisProcessorSeriesSubsetMatchString -ne '') -and ($processorSeriesURLCache["$thisProcessorSeriesDescription - $thisProcessorSeriesURL"].Count -eq 0)) {
									Write-Host "  !!! WARNING - DID NOT MATCH ANY CPUs !!!"
								} else {
									$thisSupportedProcessorNames += $processorSeriesURLCache["$thisProcessorSeriesDescription - $thisProcessorSeriesURL"]
								}
							}
						} else {
							$processorFamily = $tdNodes[1].InnerText.Replace("$([char]0x00AE)", $registeredSymbolReplacement).Replace("$([char]0x2122)", $trademarkSymbolReplacement).Replace("$([char]0x200B)", '').Trim() -Replace '\s+', ' '
							$processorModel = ($tdNodes[2].InnerText.Replace("$([char]0x00AE)", $registeredSymbolReplacement).Replace("$([char]0x2122)", $trademarkSymbolReplacement).Replace("$([char]0x200B)", '') -Replace '\[\d+\]', '').Trim() -Replace '\s+', ' '
							# On https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-24h2-supported-amd-processors some model names such as "4345P" has a zero-width space (ZWSP) character (0x200B) after them that needs to be removed.

							if ($thisProcessorBrand -eq 'Intel') {
								$processorModel = $processorModel -Replace ' [Pp]rocessor ', '-'
							} elseif ($thisProcessorBrand -eq 'AMD') {
								$processorModel = $processorModel.Replace(' (OEM Only)', '').Replace(' Microsoft Surface Edition', '').Replace(' Processor', '') -Replace ' with Radeon .* Graphics', ''

								if ($processorModel.EndsWith('Series')) {
									# IMPORTANT: Not sure how to handle the "Series" listings without links (and some with Exceptions) on https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-25h2-supported-amd-processors
									# So, just omit them for now since the strings wouldn't match and CPU strings anyways.

									$processorModel = ''
								}
							} elseif ($thisProcessorBrand -eq 'Qualcomm') {
								$processorModel = $processorModel.Replace('Snapdragon', 'Snapdragon (TM)')

								# The series pages on https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-25h2-supported-qualcomm-processors
								# are all loaded with JavaScript, so can't scrape them like Intel pages.
								# But, I believe all the supported brand strings should match the following formats.
								# For example, see "Other Names" on https://www.cpubenchmark.net/cpu.php?cpu=Qualcomm+Snapdragon+X+Elite+-+X1E-78-100&id=6095
								if ($processorModel.StartsWith('X1')) {
									$processorModel = $processorModel.Replace('-', '')

									if ($processorModel -eq 'X1E') {
										$processorModel = 'Snapdragon(R) X Elite'
									} elseif ($processorModel.StartsWith('X1E')) {
										$processorModel = "Snapdragon(R) X Elite - $processorModel"
									} elseif ($processorModel -eq 'X1P') {
										$processorModel = 'Snapdragon(R) X Plus'
									} elseif ($processorModel.StartsWith('X1P')) {
										$processorModel = "Snapdragon(R) X Plus - $processorModel"
									} elseif ($processorModel -eq 'X1') {
										$processorModel = 'Snapdragon(R) X'
									} else {
										$processorModel = "Snapdragon(R) X - $processorModel"
									}
								}
							}

							if ($processorModel -ne '') {
								if (($processorFamily -ne '') -and ($processorFamily -ne $thisProcessorBrand) -and ($thisProcessorBrand -ne 'Qualcomm')) {
									$thisSupportedProcessorNames += "$processorFamily $processorModel"
								} else {
									$thisSupportedProcessorNames += $processorModel
								}
							}
						}
					}
				}
			}

			foreach ($releaseYearAndQuarter in $possiblyUnmatchedProcessorWhichAreSupported.Keys) {
				foreach ($thisPossiblyUnmatchedProcessorWhichIsSupported in $possiblyUnmatchedProcessorWhichAreSupported[$releaseYearAndQuarter]) {
					if (-not $thisSupportedProcessorNames.Contains($thisPossiblyUnmatchedProcessorWhichIsSupported)) {
						Write-Host "  ADDING UNMATCHED SUPPORTED CPU FROM ${releaseYearAndQuarter}: $thisPossiblyUnmatchedProcessorWhichIsSupported"
						$thisSupportedProcessorNames += $thisPossiblyUnmatchedProcessorWhichIsSupported
					}
				}
			}

			$thisSupportedProcessorNames = $thisSupportedProcessorNames | Sort-Object -Unique
			$allSupportedProcessorNames += $thisSupportedProcessorNames

			$thisSupportedProcessorNames = ,$dateString + $thisSupportedProcessorNames + 'EOF'
			$thisSupportedProcessorNames | Set-Content "$outputFolderPath\SupportedProcessors$thisProcessorBrand $thisWindowsVersion.txt"
		} else {
			Write-Output "FAILED TO DETECT SUPPORTED PROCESSORS TABLE FOR $thisProcessorBrand - $thisWindowsVersion"
		}
	}

	$allSupportedProcessorNames = $allSupportedProcessorNames | Sort-Object -Unique
	$allSupportedProcessorNames = ,$dateString + $allSupportedProcessorNames + 'EOF'
	$allSupportedProcessorNames | Set-Content "$outputFolderPath\SupportedProcessors$thisProcessorBrand.txt"
}
