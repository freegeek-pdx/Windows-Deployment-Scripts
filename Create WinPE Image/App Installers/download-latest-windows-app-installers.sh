#!/bin/bash

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

cd "$(dirname -- "${BASH_SOURCE[0]}")" || exit

if [[ ! -d 'All' ]]; then
	mkdir 'All'
fi

cd 'All' || exit

echo '----------'

latest_firefox_version="$(curl -si 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US' | awk -F '/' '($1 == "Location: https:") { print $7; exit }')"
downloaded_firefox_version="$(cat 'Firefox_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
echo "Latest Firefox Version: ${latest_firefox_version}"
echo "Downloaded Firefox Installer: ${downloaded_firefox_version}"

if [[ "${latest_firefox_version}" == *"."* && -n "$(echo "${latest_firefox_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'Firefox_Installer.exe' || "${latest_firefox_version}" != "${downloaded_firefox_version}" ]]; then
		echo 'Downloading Latest Firefox Installer...'
		rm -f 'Firefox_Installer_LATEST.exe'
		
		if curl -#L 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US' -o 'Firefox_Installer_LATEST.exe' && [[ -f 'Firefox_Installer_LATEST.exe' ]]; then
			rm -f 'Firefox_Installer.msi' # Used to download the MSI, so get rid of it.
			rm -f 'Firefox_Installer.exe'
			mv -f 'Firefox_Installer_LATEST.exe' 'Firefox_Installer.exe'
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

latest_libreoffice_version="$(curl -sL 'https://download.documentfoundation.org/libreoffice/stable/' | awk -F '"|/' '/<td><a href="/ { latest_version = $5 } END { print latest_version }')"
downloaded_libreoffice_version="$(cat 'LibreOffice_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
echo "Latest LibreOffice Version: ${latest_libreoffice_version}"
echo "Downloaded LibreOffice Installer: ${downloaded_libreoffice_version}"

if [[ "${latest_libreoffice_version}" == *"."* && -n "$(echo "${latest_libreoffice_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'LibreOffice_Installer.msi' || "${latest_libreoffice_version}" != "${downloaded_libreoffice_version}" ]]; then
		echo 'Downloading Latest LibreOffice Installer...'
		rm -f 'LibreOffice_Installer_LATEST.msi'
		
		if curl -#L "https://download.documentfoundation.org/libreoffice/stable/${latest_libreoffice_version}/win/x86_64/LibreOffice_${latest_libreoffice_version}_Win_x64.msi" -o 'LibreOffice_Installer_LATEST.msi' && [[ -f 'LibreOffice_Installer_LATEST.msi' ]]; then
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

latest_vlc_version="$(curl -sL 'https://get.videolan.org/vlc/last/win64/' | awk -F '=|-' '/\-win64.exe"/ { print $3; exit }')"
downloaded_vlc_version="$(cat 'VLC_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
echo "Latest VLC Version: ${latest_vlc_version}"
echo "Downloaded VLC Installer: ${downloaded_vlc_version}"

if [[ "${latest_vlc_version}" == *"."* && -n "$(echo "${latest_vlc_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'VLC_Installer.exe' || "${latest_vlc_version}" != "${downloaded_vlc_version}" ]]; then
		echo 'Downloading Latest VLC Installer...'
		rm -f 'VLC_Installer_LATEST.exe'
		
		if curl -#L "https://get.videolan.org/vlc/last/win64/vlc-${latest_vlc_version}-win64.exe" -o 'VLC_Installer_LATEST.exe' && [[ -f 'VLC_Installer_LATEST.exe' ]]; then
			rm -f 'VLC_Installer.msi' # Used to download the MSI, so get rid of it.
			rm -f 'VLC_Installer.exe'
			mv -f 'VLC_Installer_LATEST.exe' 'VLC_Installer.exe'
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

latest_7zip_version="$(curl -sL 'https://www.7-zip.org/download.html' 2> /dev/null | awk '/<P><B>Download 7-Zip / { print $3; exit }')"
downloaded_7zip_version="$(cat '7-Zip_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
echo "Latest 7-Zip Version: ${latest_7zip_version}"
echo "Downloaded 7-Zip Installer: ${downloaded_7zip_version}"

if [[ "${latest_7zip_version}" == *"."* && -n "$(echo "${latest_7zip_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f '7-Zip_Installer.exe' || "${latest_7zip_version}" != "${downloaded_7zip_version}" ]]; then
		echo 'Downloading Latest 7-Zip Installer...'
		rm -f '7-Zip_Installer_LATEST.exe'
		
		if curl -#L "https://www.7-zip.org/$(curl -sL 'https://www.7-zip.org/download.html' 2> /dev/null | awk -F '"' '/\-x64.exe"/ { print $6; exit }')" -o '7-Zip_Installer_LATEST.exe' && [[ -f '7-Zip_Installer_LATEST.exe' ]]; then
			rm -f '7-Zip_Installer.msi' # Used to download the MSI, so get rid of it.
			rm -f '7-Zip_Installer.exe'
			mv -f '7-Zip_Installer_LATEST.exe' '7-Zip_Installer.exe'
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

# NEITHER Dell SupportAssist NOR Dell Command Update work for Driver installations in Audit Mode.
# cd '../'
# 
# if [[ ! -d 'Dell' ]]; then
# 	mkdir 'Dell'
# fi
# 
# cd 'Dell' || exit
# 
# # The "https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update" page lists a link to the latest app download page, but will get access denied using CURL because of User-Agent.
# # Can workaround this with "-A ''" arg (setting user agent to nothing) and can then retrieve the latest app download page with the following command:
# # curl -A '' -sL 'https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update' 2> /dev/null | awk -F '"' '/Universal Windows Platform/ { print $2; exit }'
# # This will return something like: https://www.dell.com/support/home/drivers/DriversDetails?driverId=PF5GJ
# # But then when trying to load THAT page (with the User-Agent workaround), a Captcha page will load which I can't seem to workaround.
# # Cookies must be set by that Captcha page to load the actual DriversDetails page, so unless I can figure that out with CURL, I will need to manually update installer EXE periodically (which can luckily be downloaded without any cookies).
# 
# latest_dellcommandupdate_version='4.0.0'
# downloaded_dellcommandupdate_version="$(cat 'DellCommandUpdate_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
# echo "Latest Dell Command Update Version: ${latest_dellcommandupdate_version}"
# echo "Downloaded Dell Command Update Installer: ${downloaded_dellcommandupdate_version}"
# 
# if [[ "${latest_dellcommandupdate_version}" == *"."* && -n "$(echo "${latest_dellcommandupdate_version}" | tr -cd '[:digit:]')" ]]; then
# 	if [[ ! -f 'DellCommandUpdate_Installer.exe' || "${latest_dellcommandupdate_version}" != "${downloaded_dellcommandupdate_version}" ]]; then
# 		echo 'Downloading Latest Dell Command Update Installer...'
# 		rm -f 'DellCommandUpdate_Installer_LATEST.exe'
# 		
# 		if curl -#L 'https://dl.dell.com/FOLDER06747944M/1/Dell-Command-Update-Application_0W0YJ_WIN_4.0.0_A00.EXE' -o 'DellCommandUpdate_Installer_LATEST.exe' && [[ -f 'DellCommandUpdate_Installer_LATEST.exe' ]]; then
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

# Could not figure out how to get latest version dymanically from https://support.lenovo.com/downloads/DS012808 since it's all loaded with JavaScript.
# But luckily found that the download link is also listed on https://support.lenovo.com/us/en/solutions/ht037099 and was able to retrieve the latest version from there.
# At some point between August 9th, 2021 and September 2nd, 2021 https://support.lenovo.com/us/en/solutions/ht037099 has changed to be all loaded with JavaScript as well, but I was able to find the download link within the JavaScript source.

latest_lenovosystemupdate_version="$(curl -sL "https://support.lenovo.com$(curl -sL 'https://support.lenovo.com/us/en/solutions/ht037099' | awk -F '"' '/src="\/us\/en\/api\/v4\/contents\/cdn\// { print $4; exit }')" | awk -F 'https:\/\/download.lenovo.com\/pccbbs\/thinkvantage_en\/system_update_|[.]exe' '{ print $2; exit }')"
downloaded_lenovosystemupdate_version="$(cat 'LenovoSystemUpdate_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
echo "Latest Lenovo System Update Version: ${latest_lenovosystemupdate_version}"
echo "Downloaded Lenovo System Update Installer: ${downloaded_lenovosystemupdate_version}"

if [[ "${latest_lenovosystemupdate_version}" == *"."* && -n "$(echo "${latest_lenovosystemupdate_version}" | tr -cd '[:digit:]')" ]]; then
	if [[ ! -f 'LenovoSystemUpdate_Installer.exe' || "${latest_lenovosystemupdate_version}" != "${downloaded_lenovosystemupdate_version}" ]]; then
		echo 'Downloading Latest Lenovo System Update Installer...'
		rm -f 'LenovoSystemUpdate_Installer_LATEST.exe'
		
		if curl -#L "https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_${latest_lenovosystemupdate_version}.exe" -o 'LenovoSystemUpdate_Installer_LATEST.exe' && [[ -f 'LenovoSystemUpdate_Installer_LATEST.exe' ]]; then
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
# # Get download URL from JavaScript file used by http://www.hp.com/go/hpsupportassistant
# 
# latest_hpsupportassistant_version="$(curl -sL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '//' '/ return getProtocol()/ { print $2; exit }')"
# downloaded_hpsupportassistant_version="$(cat 'HPSupportAssistant_Installer-Version.txt' 2> /dev/null || echo 'N/A')"
# echo "Latest HP Support Assistant Version: ${latest_hpsupportassistant_version}"
# echo "Downloaded HP Support Assistant Installer: ${downloaded_hpsupportassistant_version}"
# 
# if [[ "${latest_hpsupportassistant_version}" == *"."* && -n "$(echo "${latest_hpsupportassistant_version}" | tr -cd '[:digit:]')" ]]; then
# 	if [[ ! -f 'HPSupportAssistant_Installer.exe' || "${latest_hpsupportassistant_version}" != "${downloaded_hpsupportassistant_version}" ]]; then
# 		echo 'Downloading Latest HP Support Assistant Installer...'
# 		rm -f 'HPSupportAssistant_Installer_LATEST.exe'
# 		
# 		if curl -#L "https://$(curl -sL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '"' '/ return getProtocol()/ { print $2; exit }')" -o 'HPSupportAssistant_Installer_LATEST.exe' && [[ -f 'HPSupportAssistant_Installer_LATEST.exe' ]]; then
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
