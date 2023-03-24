#!/bin/bash
# shellcheck enable=add-default-case,avoid-nullary-conditions,check-unassigned-uppercase,deprecate-which,quote-safe-variables,require-double-brackets

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

# NOTE: This is a BASH script instead of a POWERSHELL script because a slight variation of it runs daily on a Linux server to keep the app installers up-to-date to download from an SMB share.
# Instead of needing to create another POWERSHELL version that could be run on Windows, I just run this BASH version from macOS and the app installers sync over OneDrive to access from Windows.
# In the future it may be possible to install POWERSHELL on the Linux server so this could be re-written to only have a single POWERSHELL version, but that hasn't been investigated yet.


cd "${BASH_SOURCE[0]%/*}" || exit 1

if [[ ! -d 'All' ]]; then
	mkdir 'All'
fi

cd 'All' || exit

echo -e '\n\nDownloading Installers for All Systems...'

echo '----------'

# NOTE: In Windows 10 20H2, using the Firefox and VLC MSI installers were both causing a "default browser reset" notification, so I switched to the EXE installers for those apps which did not cause that notification.
# I re-tested the Firefox and VLC MSI installers in Windows 10 22H2 and Windows 11 22H2 and did not see the "default browser reset" notification anymore, so I've switched back to the MSI installers.
# But, this is something to keep an eye on into the future in case these MSIs need to be switched back to their EXE alternatives.

latest_firefox_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US' | awk -F '/' '{ print $7; exit }')"
downloaded_firefox_version='N/A'
if [[ -f 'Firefox_Installer-Version.txt' ]]; then
	downloaded_firefox_version="$(< 'Firefox_Installer-Version.txt')"
fi

echo "Latest Firefox Version: ${latest_firefox_version}"
echo "Downloaded Firefox Installer: ${downloaded_firefox_version}"

if [[ "${latest_firefox_version}" == *"."* && -n "$(echo "${latest_firefox_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'Firefox_Installer.msi' || "${latest_firefox_version}" != "${downloaded_firefox_version}" ]]; then
		echo 'Downloading Latest Firefox Installer...'
		rm -f 'Firefox_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL 'https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US' -o 'Firefox_Installer_LATEST.msi' && [[ -f 'Firefox_Installer_LATEST.msi' ]]; then
			rm -f 'Firefox_Installer.msi'
			mv -f 'Firefox_Installer_LATEST.msi' 'Firefox_Installer.msi'
			echo "${latest_firefox_version}" > 'Firefox_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LATEST FIREFOX INSTALLER"
		fi
	else
		echo 'Latest Firefox Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Firefox Version'
fi

echo '----------'

latest_libreoffice_version="$(curl -m 5 -sfL 'https://download.documentfoundation.org/libreoffice/stable/' | awk -F '"|/' '/<td><a href="/ { latest_version = $5 } END { print latest_version }')"
downloaded_libreoffice_version='N/A'
if [[ -f 'LibreOffice_Installer-Version.txt' ]]; then
	downloaded_libreoffice_version="$(< 'LibreOffice_Installer-Version.txt')"
fi

echo "Latest LibreOffice Version: ${latest_libreoffice_version}"
echo "Downloaded LibreOffice Installer: ${downloaded_libreoffice_version}"

if [[ "${latest_libreoffice_version}" == *"."* && -n "$(echo "${latest_libreoffice_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'LibreOffice_Installer.msi' || "${latest_libreoffice_version}" != "${downloaded_libreoffice_version}" ]]; then
		echo 'Downloading Latest LibreOffice Installer...'
		rm -f 'LibreOffice_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL "https://download.documentfoundation.org/libreoffice/stable/${latest_libreoffice_version}/win/x86_64/LibreOffice_${latest_libreoffice_version}_Win_x86-64.msi" -o 'LibreOffice_Installer_LATEST.msi' && [[ -f 'LibreOffice_Installer_LATEST.msi' ]]; then
			rm -f 'LibreOffice_Installer.msi'
			mv -f 'LibreOffice_Installer_LATEST.msi' 'LibreOffice_Installer.msi'
			echo "${latest_libreoffice_version}" > 'LibreOffice_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LATEST LIBREOFFICE INSTALLER"
		fi
	else
		echo 'Latest LibreOffice Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest LibreOffice Version'
fi

echo '----------'

latest_vlc_version="$(curl -m 5 -sfL 'https://get.videolan.org/vlc/last/win64/' | awk -F '=|-' '/\-win64\.msi"/ { print $3; exit }')"
downloaded_vlc_version='N/A'
if [[ -f 'VLC_Installer-Version.txt' ]]; then
	downloaded_vlc_version="$(< 'VLC_Installer-Version.txt')"
fi

echo "Latest VLC Version: ${latest_vlc_version}"
echo "Downloaded VLC Installer: ${downloaded_vlc_version}"

if [[ "${latest_vlc_version}" == *"."* && -n "$(echo "${latest_vlc_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'VLC_Installer.msi' || "${latest_vlc_version}" != "${downloaded_vlc_version}" ]]; then
		echo 'Downloading Latest VLC Installer...'
		rm -f 'VLC_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL "https://get.videolan.org/vlc/last/win64/vlc-${latest_vlc_version}-win64.msi" -o 'VLC_Installer_LATEST.msi' && [[ -f 'VLC_Installer_LATEST.msi' ]]; then
			rm -f 'VLC_Installer.msi'
			mv -f 'VLC_Installer_LATEST.msi' 'VLC_Installer.msi'
			echo "${latest_vlc_version}" > 'VLC_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING VLC INSTALLER"
		fi
	else
		echo 'Latest VLC Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest VLC Version'
fi

echo '----------'

latest_7zip_version="$(curl -m 5 -sfL 'https://www.7-zip.org/download.html' 2> /dev/null | awk '/<P><B>Download 7-Zip / { print $3; exit }')"
downloaded_7zip_version='N/A'
if [[ -f '7-Zip_Installer-Version.txt' ]]; then
	downloaded_7zip_version="$(< '7-Zip_Installer-Version.txt')"
fi

echo "Latest 7-Zip Version: ${latest_7zip_version}"
echo "Downloaded 7-Zip Installer: ${downloaded_7zip_version}"

if [[ "${latest_7zip_version}" == *"."* && -n "$(echo "${latest_7zip_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f '7-Zip_Installer.msi' || "${latest_7zip_version}" != "${downloaded_7zip_version}" ]]; then
		echo 'Downloading Latest 7-Zip Installer...'
		rm -f '7-Zip_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL "https://www.7-zip.org/$(curl -m 5 -sfL 'https://www.7-zip.org/download.html' 2> /dev/null | awk -F '"' '/\-x64\.msi"/ { print $6; exit }')" -o '7-Zip_Installer_LATEST.msi' && [[ -f '7-Zip_Installer_LATEST.msi' ]]; then
			rm -f '7-Zip_Installer.msi'
			mv -f '7-Zip_Installer_LATEST.msi' '7-Zip_Installer.msi'
			echo "${latest_7zip_version}" > '7-Zip_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING 7-ZIP INSTALLER"
		fi
	else
		echo 'Latest 7-Zip Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest 7-Zip Version'
fi

echo '----------'

cd '../'

if [[ ! -d 'SNAP' ]]; then
	mkdir 'SNAP'
fi

cd 'SNAP' || exit

echo -e '\n\nDownloading Installers for SNAP Systems...'

echo '----------'

latest_chrome_version="$(curl -m 5 -sfL 'https://omahaproxy.appspot.com/history' | awk -F ',' '($1 == "win64" && $2 == "stable") { print $3; exit }')" # https://developer.chrome.com/docs/web-platform/chrome-release-channels/#find-out-more
downloaded_chrome_version='N/A'
if [[ -f 'GoogleChrome_Installer-Version.txt' ]]; then
	downloaded_chrome_version="$(< 'GoogleChrome_Installer-Version.txt')"
fi

echo "Latest Chrome Version: ${latest_chrome_version}"
echo "Downloaded Chrome Installer: ${downloaded_chrome_version}"

if [[ "${latest_chrome_version}" == *"."* && -n "$(echo "${latest_chrome_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'GoogleChrome_Installer.msi' || "${latest_chrome_version}" != "${downloaded_chrome_version}" ]]; then
		echo 'Downloading Latest Chrome Installer...'
		rm -f 'GoogleChrome_Installer_LATEST.msi'

		# NOTE: It's important to download the offline MSI installer since the EXE installer would require internet when run, which we don't want to require for USB installations.
		if curl --connect-timeout 5 --progress-bar -fL 'https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi' -o 'GoogleChrome_Installer_LATEST.msi' && [[ -f 'GoogleChrome_Installer_LATEST.msi' ]]; then
			rm -f 'GoogleChrome_Installer.msi'
			mv -f 'GoogleChrome_Installer_LATEST.msi' 'GoogleChrome_Installer.msi'
			echo "${latest_chrome_version}" > 'GoogleChrome_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LATEST CHROME INSTALLER"
		fi
	else
		echo 'Latest Chrome Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Chrome Version'
fi

echo '----------'

latest_zoom_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64' | awk -F '/' '{ print $5; exit }')"
downloaded_zoom_version='N/A'
if [[ -f 'Zoom_Installer-Version.txt' ]]; then
	downloaded_zoom_version="$(< 'Zoom_Installer-Version.txt')"
fi

echo "Latest Zoom Version: ${latest_zoom_version}"
echo "Downloaded Zoom Installer: ${downloaded_zoom_version}"

if [[ "${latest_zoom_version}" == *"."* && -n "$(echo "${latest_zoom_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'Zoom_Installer.msi' || "${latest_zoom_version}" != "${downloaded_zoom_version}" ]]; then
		echo 'Downloading Latest Zoom Installer...'
		rm -f 'Zoom_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64' -o 'Zoom_Installer_LATEST.msi' && [[ -f 'Zoom_Installer_LATEST.msi' ]]; then
			rm -f 'Zoom_Installer.msi'
			mv -f 'Zoom_Installer_LATEST.msi' 'Zoom_Installer.msi'
			echo "${latest_zoom_version}" > 'Zoom_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LATEST ZOOM INSTALLER"
		fi
	else
		echo 'Latest Zoom Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Zoom Version'
fi

echo '----------'

latest_teamviewer_version="$(curl -m 5 -sfL 'https://www.teamviewer.com/en/download/windows/' | awk -F '>|: |<' '($3 == "Current version") { print $4; exit }')"
downloaded_teamviewer_version='N/A'
if [[ -f 'TeamViewer_Installer-Version.txt' ]]; then
	downloaded_teamviewer_version="$(< 'TeamViewer_Installer-Version.txt')"
fi

echo "Latest TeamViewer Version: ${latest_teamviewer_version}"
echo "Downloaded TeamViewer Installer: ${downloaded_teamviewer_version}"

if [[ "${latest_teamviewer_version}" == *"."* && -n "$(echo "${latest_teamviewer_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'TeamViewer_Installer.exe' || "${latest_teamviewer_version}" != "${downloaded_teamviewer_version}" ]]; then
		echo 'Downloading Latest TeamViewer Installer...'
		rm -f 'TeamViewer_Installer_LATEST.exe'

		if curl --connect-timeout 5 --progress-bar -fL 'https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe' -o 'TeamViewer_Installer_LATEST.exe' && [[ -f 'TeamViewer_Installer_LATEST.exe' ]]; then
			rm -f 'TeamViewer_Installer.exe'
			mv -f 'TeamViewer_Installer_LATEST.exe' 'TeamViewer_Installer.exe'
			echo "${latest_teamviewer_version}" > 'TeamViewer_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING TEAMVIEWER INSTALLER"
		fi
	else
		echo 'Latest TeamViewer Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest TeamViewer Version'
fi

echo '----------'

latest_dropbox_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null 'https://www.dropbox.com/download?full=1&os=win' | awk -F '%20' '{ print $2; exit }')"
downloaded_dropbox_version='N/A'
if [[ -f 'Dropbox_Installer-Version.txt' ]]; then
	downloaded_dropbox_version="$(< 'Dropbox_Installer-Version.txt')"
fi

echo "Latest Dropbox Version: ${latest_dropbox_version}"
echo "Downloaded Dropbox Installer: ${downloaded_dropbox_version}"

if [[ "${latest_dropbox_version}" == *"."* && -n "$(echo "${latest_dropbox_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'Dropbox_Installer.exe' || "${latest_dropbox_version}" != "${downloaded_dropbox_version}" ]]; then
		echo 'Downloading Latest Dropbox Installer...'
		rm -f 'Dropbox_Installer_LATEST.exe'

		if curl --connect-timeout 5 --progress-bar -fL 'https://www.dropbox.com/download?full=1&os=win' -o 'Dropbox_Installer_LATEST.exe' && [[ -f 'Dropbox_Installer_LATEST.exe' ]]; then
			rm -f 'Dropbox_Installer.exe'
			mv -f 'Dropbox_Installer_LATEST.exe' 'Dropbox_Installer.exe'
			echo "${latest_dropbox_version}" > 'Dropbox_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING DROPBOX INSTALLER"
		fi
	else
		echo 'Latest Dropbox Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Dropbox Version'
fi

echo '----------'

cd '../'

if [[ ! -d 'Intel' ]]; then
	mkdir 'Intel'
fi

cd 'Intel' || exit

echo -e '\n\nDownloading Installers for Intel Systems...'

echo '----------'

latest_ipdt_download_url="$(curl -m 5 -sfL 'https://www.intel.com/content/www/us/en/download/15951/intel-processor-diagnostic-tool.html' | awk -F '"' '/downloadmirror\.intel\.com.*IPDT_Installer_.*_64bit\.msi/ { print $(NF-1); exit }')"
latest_ipdt_version="$(echo "${latest_ipdt_download_url}" | cut -d '_' -f 3)"
downloaded_ipdt_version='N/A'
if [[ -f 'IntelProcessorDiagnosticTool_Installer-Version.txt' ]]; then
	downloaded_ipdt_version="$(< 'IntelProcessorDiagnosticTool_Installer-Version.txt')"
fi

echo "Latest Intel Processor Diagnostic Tool Version: ${latest_ipdt_version}"
echo "Downloaded Intel Processor Diagnostic Tool Installer: ${downloaded_ipdt_version}"

if [[ "${latest_ipdt_version}" == *"."* && -n "$(echo "${latest_ipdt_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'IntelProcessorDiagnosticTool_Installer.msi' || "${latest_ipdt_version}" != "${downloaded_ipdt_version}" ]]; then
		echo 'Downloading Latest Intel Processor Diagnostic Tool Installer...'
		rm -f 'IntelProcessorDiagnosticTool_Installer_LATEST.msi'

		if curl --connect-timeout 5 --progress-bar -fL "${latest_ipdt_download_url}" -o 'IntelProcessorDiagnosticTool_Installer_LATEST.msi' && [[ -f 'IntelProcessorDiagnosticTool_Installer_LATEST.msi' ]]; then
			rm -f 'IntelProcessorDiagnosticTool_Installer.msi'
			mv -f 'IntelProcessorDiagnosticTool_Installer_LATEST.msi' 'IntelProcessorDiagnosticTool_Installer.msi'
			echo "${latest_ipdt_version}" > 'IntelProcessorDiagnosticTool_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LATEST INTEL PROCESSOR DIAGNOSTIC TOOL INSTALLER"
		fi
	else
		echo 'Latest Intel Processor Diagnostic Tool Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Intel Processor Diagnostic Tool Version'
fi

echo '----------'

# NEITHER Dell SupportAssist NOR Dell Command Update work for Driver installations in Audit Mode.
# cd '../'
#
# if [[ ! -d 'Dell' ]]; then
# 	mkdir 'Dell'
# fi
#
# cd 'Dell' || exit
#
# echo -e '\n\nDownloading Installers for Dell Systems...'
#
# echo '----------'
#
# # The "https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update" page lists a link to the latest app download page, but will get access denied using CURL because of User-Agent.
# # Can workaround this with "-A ''" arg (setting user agent to nothing) and can then retrieve the latest app download page with the following command:
# # curl -A '' -sfL 'https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update' 2> /dev/null | awk -F '"' '/Universal Windows Platform/ { print $2; exit }'
# # This will return something like: https://www.dell.com/support/home/drivers/DriversDetails?driverId=PF5GJ
# # But then when trying to load THAT page (with the User-Agent workaround), a Captcha page will load which I can't seem to workaround.
# # Cookies must be set by that Captcha page to load the actual DriversDetails page, so unless I can figure that out with CURL, I will need to manually update installer EXE periodically (which can luckily be downloaded without any cookies).
#
# latest_dellcommandupdate_version='4.0.0'
# downloaded_dellcommandupdate_version='N/A'
# if [[ -f 'DellCommandUpdate_Installer-Version.txt' ]]; then
# 	downloaded_dellcommandupdate_version="$(< 'DellCommandUpdate_Installer-Version.txt')"
# fi
#
# echo "Latest Dell Command Update Version: ${latest_dellcommandupdate_version}"
# echo "Downloaded Dell Command Update Installer: ${downloaded_dellcommandupdate_version}"
#
# if [[ "${latest_dellcommandupdate_version}" == *"."* && -n "$(echo "${latest_dellcommandupdate_version}" | tr -cd '[:digit:]')" ]]; then
# 	if [[ ! -f 'DellCommandUpdate_Installer.exe' || "${latest_dellcommandupdate_version}" != "${downloaded_dellcommandupdate_version}" ]]; then
# 		echo 'Downloading Latest Dell Command Update Installer...'
# 		rm -f 'DellCommandUpdate_Installer_LATEST.exe'
#
# 		if curl --connect-timeout 5 --progress-bar -fL 'https://dl.dell.com/FOLDER06747944M/1/Dell-Command-Update-Application_0W0YJ_WIN_4.0.0_A00.EXE' -o 'DellCommandUpdate_Installer_LATEST.exe' && [[ -f 'DellCommandUpdate_Installer_LATEST.exe' ]]; then
# 			rm -f 'DellCommandUpdate_Installer.exe'
# 			mv -f 'DellCommandUpdate_Installer_LATEST.exe' 'DellCommandUpdate_Installer.exe'
# 			echo "${latest_dellcommandupdate_version}" > 'DellCommandUpdate_Installer-Version.txt'
# 		else
# 			echo "ERROR $? DOWNLOADING DELL COMMAND UPDATE INSTALLER"
# 		fi
# 	else
# 		echo 'Latest Dell Command Update Installer Already Downloaded'
# 	fi
# else
# 	echo 'INVALID Latest Dell Command Update Version'
# fi
#
# echo '----------'

cd '../'

if [[ ! -d 'Lenovo' ]]; then
	mkdir 'Lenovo'
fi

cd 'Lenovo' || exit

echo -e '\n\nDownloading Installers for Lenovo Systems...'

echo '----------'

# Could not figure out how to get latest version dymanically from https://support.lenovo.com/downloads/DS012808 since it's all loaded with JavaScript.
# But luckily found that the download link is also listed on https://support.lenovo.com/us/en/solutions/ht037099 and was able to retrieve the latest version from there.
# At some point between August 9th, 2021 and September 2nd, 2021 https://support.lenovo.com/us/en/solutions/ht037099 has changed to be all loaded with JavaScript as well, but I was able to find the download link within the JavaScript source.

latest_lenovosystemupdate_version="$(curl -m 5 -sfL "https://support.lenovo.com$(curl -m 5 -sfL 'https://support.lenovo.com/us/en/solutions/ht037099' | awk -F '"' '/src="\/us\/en\/api\/v4\/contents\/cdn\// { print $4; exit }')" | awk -F 'https://download[.]lenovo[.]com/pccbbs/thinkvantage_en/system_update_|[.]exe' '{ print $2; exit }')"
downloaded_lenovosystemupdate_version='N/A'
if [[ -f 'LenovoSystemUpdate_Installer-Version.txt' ]]; then
	downloaded_lenovosystemupdate_version="$(< 'LenovoSystemUpdate_Installer-Version.txt')"
fi

echo "Latest Lenovo System Update Version: ${latest_lenovosystemupdate_version}"
echo "Downloaded Lenovo System Update Installer: ${downloaded_lenovosystemupdate_version}"

if [[ "${latest_lenovosystemupdate_version}" == *"."* && -n "$(echo "${latest_lenovosystemupdate_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'LenovoSystemUpdate_Installer.exe' || "${latest_lenovosystemupdate_version}" != "${downloaded_lenovosystemupdate_version}" ]]; then
		echo 'Downloading Latest Lenovo System Update Installer...'
		rm -f 'LenovoSystemUpdate_Installer_LATEST.exe'

		if curl --connect-timeout 5 --progress-bar -fL "https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_${latest_lenovosystemupdate_version}.exe" -o 'LenovoSystemUpdate_Installer_LATEST.exe' && [[ -f 'LenovoSystemUpdate_Installer_LATEST.exe' ]]; then
			rm -f 'LenovoSystemUpdate_Installer.exe'
			mv -f 'LenovoSystemUpdate_Installer_LATEST.exe' 'LenovoSystemUpdate_Installer.exe'
			echo "${latest_lenovosystemupdate_version}" > 'LenovoSystemUpdate_Installer-Version.txt'
		else
			echo "ERROR $? DOWNLOADING LENOVO SYSTEM UPDATE INSTALLER"
		fi
	else
		echo 'Latest Lenovo System Update Installer Already Downloaded'
	fi
else
	echo 'INVALID Latest Lenovo System Update Version'
fi

echo '----------'

# DO NOT INSTALL HP SUPPORT ASSISTANT UNTIL I'VE HAD AND CHANCE TO TEST
# cd '../'
#
# if [[ ! -d 'HP' ]]; then
# 	mkdir 'HP'
# fi
#
# cd 'HP' || exit
#
# echo -e '\n\nDownloading Installers for HP Systems...'
#
# echo '----------'
#
# # Get download URL from JavaScript file used by http://www.hp.com/go/hpsupportassistant
#
# latest_hpsupportassistant_version="$(curl -m 5 -sfL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '//' '/ return getProtocol()/ { print $2; exit }')"
# downloaded_hpsupportassistant_version='N/A'
# if [[ -f 'HPSupportAssistant_Installer-Version.txt' ]]; then
# 	downloaded_hpsupportassistant_version="$(< 'HPSupportAssistant_Installer-Version.txt')"
# fi
#
# echo "Latest HP Support Assistant Version: ${latest_hpsupportassistant_version}"
# echo "Downloaded HP Support Assistant Installer: ${downloaded_hpsupportassistant_version}"
#
# if [[ "${latest_hpsupportassistant_version}" == *"."* && -n "$(echo "${latest_hpsupportassistant_version}" | tr -cd '[:digit:]')" ]]; then
# 	if [[ ! -f 'HPSupportAssistant_Installer.exe' || "${latest_hpsupportassistant_version}" != "${downloaded_hpsupportassistant_version}" ]]; then
# 		echo 'Downloading Latest HP Support Assistant Installer...'
# 		rm -f 'HPSupportAssistant_Installer_LATEST.exe'
#
# 		if curl --connect-timeout 5 --progress-bar -fL "https://$(curl -m 5 -sfL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '"' '/ return getProtocol()/ { print $2; exit }')" -o 'HPSupportAssistant_Installer_LATEST.exe' && [[ -f 'HPSupportAssistant_Installer_LATEST.exe' ]]; then
# 			rm -f 'HPSupportAssistant_Installer.exe'
# 			mv -f 'HPSupportAssistant_Installer_LATEST.exe' 'HPSupportAssistant_Installer.exe'
# 			echo "${latest_hpsupportassistant_version}" > 'HPSupportAssistant_Installer-Version.txt'
# 		else
# 			echo "ERROR $? DOWNLOADING HP SUPPORT ASSISTANT INSTALLER"
# 		fi
# 	else
# 		echo 'Latest HP Support Assistant Installer Already Downloaded'
# 	fi
# else
# 	echo 'INVALID Latest HP Support Assistant Version'
# fi
#
# echo '----------'
