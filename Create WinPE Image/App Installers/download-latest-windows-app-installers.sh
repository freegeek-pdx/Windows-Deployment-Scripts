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
# Instead of needing to create another POWERSHELL version that could be run on Windows, I just run this BASH version from macOS and the app installers cloud sync to access from Windows.
# In the future it may be possible to install POWERSHELL on the Linux server so this could be re-written to only have a single POWERSHELL version, but that hasn't been investigated yet.
# AS OF 10/12/23 I HAVE WRITTEN A POWERSHELL VERSION OF THIS SCRIPT WHICH IS "Download Latest Windows App Installers.ps1" IN THIS SAME FOLDER.


TMPDIR="$([[ -d "${TMPDIR}" && -w "${TMPDIR}" ]] && echo "${TMPDIR%/}" || echo '/tmp')" # Make sure "TMPDIR" is always set and that it DOES NOT have a trailing slash for consistency regardless of the current environment.

download_app_installer() {
	local app_name="$1"
	local installer_extension="$2"
	local latest_version="$3"
	local download_url="$4"

	if [[ -z "${app_name}" || -z "${installer_extension}" || -z "${latest_version}" || -z "${download_url}" ]]; then
		echo "MISSING REQUIRED ARGS FOR ${app_name:-UNKNOWN APP}"
		return 1
	fi

	echo "Latest ${app_name} Version: ${latest_version}"

	local downloaded_version='N/A'
	local possible_downloaded_version
	possible_downloaded_version="$(find . -type f -name "${app_name}_*" -print -quit | cut -d '_' -f 2)"
	if [[ "${possible_downloaded_version}" =~ ^[[:digit:]][.[:digit:]]*$ ]]; then
		downloaded_version="${possible_downloaded_version}"
	fi

	echo "Downloaded ${app_name} Installer: ${downloaded_version}"

	if [[ "${latest_version}" =~ ^[[:digit:]][.[:digit:]]*$ ]]; then
		installer_download_filename="${app_name}_${latest_version}_Installer.${installer_extension}"
		if [[ ! -f "${installer_download_filename}" ]]; then
			echo "Downloading Latest ${app_name} Installer..."

			rm -f "${TMPDIR}/${installer_download_filename}-download"

			if curl --connect-timeout 5 --progress-bar -fL "${download_url}" -o "${TMPDIR}/${installer_download_filename}-download" && rm -f "${app_name}_"* && mv -f "${TMPDIR}/${installer_download_filename}-download" "${installer_download_filename}" && [[ -f "${installer_download_filename}" ]]; then
				echo "Downloaded Latest ${app_name} Installer"
			else
				echo "ERROR $? DOWNLOADING LATEST ${app_name} INSTALLER"
			fi
		else
			echo "Latest ${app_name} Installer Already Downloaded"
		fi
	else
		echo "INVALID Latest ${app_name} Version"
	fi

	echo '----------'
}


echo -e '\n\nDownloading Standard App Installers...'

cd "${BASH_SOURCE[0]%/*}" || exit 1

if [[ ! -d 'Standard' ]]; then
	mkdir 'Standard'
fi

cd 'Standard' || exit

echo '----------'

# NOTE: In Windows 10 20H2, using the Firefox and VLC MSI installers were both causing a "default browser reset" notification, so I switched to the EXE installers for those apps which did not cause that notification.
# I re-tested the Firefox and VLC MSI installers in Windows 10 22H2 and Windows 11 22H2 and did not see the "default browser reset" notification anymore, so I've switched back to the MSI installers.
# But, this is something to keep an eye on into the future in case these MSIs need to be switched back to their EXE alternatives.

latest_firefox_download_url='https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US'
latest_firefox_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null "${latest_firefox_download_url}" | awk -F '/' '{ print $7; exit }')"
download_app_installer 'Firefox' 'msi' "${latest_firefox_version}" "${latest_firefox_download_url}"

latest_libreoffice_version="$(curl -m 5 -sfL 'https://download.documentfoundation.org/libreoffice/stable/' | awk -F '"|/' '/<td><a href="/ { latest_version = $5 } END { print latest_version }')"
latest_libreoffice_download_url="https://download.documentfoundation.org/libreoffice/stable/${latest_libreoffice_version}/win/x86_64/LibreOffice_${latest_libreoffice_version}_Win_x86-64.msi"
download_app_installer 'LibreOffice' 'msi' "${latest_libreoffice_version}" "${latest_libreoffice_download_url}"

latest_vlc_version="$(curl -m 5 -sfL 'https://get.videolan.org/vlc/last/win64/' | awk -F '=|-' '/\-win64\.msi"/ { print $3; exit }')"
if [[ -z "${latest_vlc_version}" ]]; then latest_vlc_version='3.0.20'; fi # MSI for VLC 3.0.21 is being skipped: https://code.videolan.org/videolan/vlc/-/issues/28677#note_461571
latest_vlc_download_url="https://get.videolan.org/vlc/${latest_vlc_version}/win64/vlc-${latest_vlc_version}-win64.msi"
download_app_installer 'VLC' 'msi' "${latest_vlc_version}" "${latest_vlc_download_url}"

latest_7zip_version="$(curl -m 5 -sfL 'https://www.7-zip.org/download.html' 2> /dev/null | awk '/<P><B>Download 7-Zip / { print $3; exit }')"
latest_7zip_download_url="https://www.7-zip.org/$(curl -m 5 -sfL 'https://www.7-zip.org/download.html' 2> /dev/null | awk -F '"' '/\-x64\.msi"/ { print $6; exit }')"
download_app_installer '7-Zip' 'msi' "${latest_7zip_version}" "${latest_7zip_download_url}"


echo -e '\n\nDownloading Extra App Installers...'

cd '../'

if [[ ! -d 'Extra' ]]; then
	mkdir 'Extra'
fi

cd 'Extra' || exit

echo '----------'

latest_chrome_version="$(curl -m 5 -sfL 'https://versionhistory.googleapis.com/v1/chrome/platforms/win64/channels/stable/versions/all/releases?filter=fraction=1' | awk -F '"' '($2 == "version") { print $4; exit }')" # https://developer.chrome.com/docs/web-platform/versionhistory/examples#release & https://developer.chrome.com/docs/web-platform/versionhistory/reference#filter & https://macadmins.slack.com/archives/C013HFTFQ13/p1701811746942389?thread_ts=1701685863.377489&cid=C013HFTFQ13
latest_chrome_download_url='https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi'
# NOTE: It's important to download the offline MSI installer since the EXE installer would require internet when run, which we don't want to require for USB installations.
download_app_installer 'Google Chrome' 'msi' "${latest_chrome_version}" "${latest_chrome_download_url}"

latest_zoom_download_url='https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'
latest_zoom_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null "${latest_zoom_download_url}" | awk -F '/' '{ print $5; exit }')"
download_app_installer 'Zoom' 'msi' "${latest_zoom_version}" "${latest_zoom_download_url}"

latest_teamviewer_version="$(curl -m 5 -sfL 'https://www.teamviewer.com/download/portal/windows/' | awk -F ': |>|<' '($1 ~ /Current version$/) { print $4; exit }')"
latest_teamviewer_download_url='https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe'
download_app_installer 'TeamViewer' 'exe' "${latest_teamviewer_version}" "${latest_teamviewer_download_url}"

latest_dropbox_download_url='https://www.dropbox.com/download?full=1&os=win'
latest_dropbox_version="$(curl -m 5 -sfw '%{redirect_url}' -o /dev/null "${latest_dropbox_download_url}" | awk -F '%20' '{ print $2; exit }')"
download_app_installer 'Dropbox' 'exe' "${latest_dropbox_version}" "${latest_dropbox_download_url}"


echo -e '\n\nDownloading Installers for Intel Systems...'

cd '../'

if [[ ! -d 'Intel' ]]; then
	mkdir 'Intel'
fi

cd 'Intel' || exit

echo '----------'

latest_ipdt_download_url="$(curl -m 5 -sfL 'https://www.intel.com/content/www/us/en/download/15951/intel-processor-diagnostic-tool.html' | awk -F '"' '/downloadmirror\.intel\.com.*IPDT_Installer_.*_64bit\.msi/ { print $(NF-1); exit }')"
latest_ipdt_version="$(echo "${latest_ipdt_download_url}" | cut -d '_' -f 3)"
download_app_installer 'Intel Processor Diagnostic Tool' 'msi' "${latest_ipdt_version}" "${latest_ipdt_download_url}"


# NEITHER Dell SupportAssist NOR Dell Command Update work for Driver installations in Audit Mode.

# echo -e '\n\nDownloading Installers for Dell Systems...'

# cd '../'

# if [[ ! -d 'Dell' ]]; then
# 	mkdir 'Dell'
# fi

# cd 'Dell' || exit

# echo '----------'

# # The "https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update" page lists a link to the latest app download page, but will get access denied using CURL because of User-Agent.
# # Can workaround this with "-A ''" arg (setting user agent to nothing) and can then retrieve the latest app download page with the following command:
# # curl -A '' -sfL 'https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update' 2> /dev/null | awk -F '"' '/Universal Windows Platform/ { print $2; exit }'
# # This will return something like: https://www.dell.com/support/home/drivers/DriversDetails?driverId=PF5GJ
# # But then when trying to load THAT page (with the User-Agent workaround), a Captcha page will load which I can't seem to workaround.
# # Cookies must be set by that Captcha page to load the actual DriversDetails page, so unless I can figure that out with CURL, I will need to manually update installer EXE periodically (which can luckily be downloaded without any cookies).

# latest_dellcommandupdate_version='4.0.0'
# latest_dellcommandupdate_download_url='https://dl.dell.com/FOLDER06747944M/1/Dell-Command-Update-Application_0W0YJ_WIN_4.0.0_A00.EXE'
# download_app_installer 'Dell Command Update' 'exe' "${latest_dellcommandupdate_version}" "${latest_dellcommandupdate_download_url}"


echo -e '\n\nDownloading Installers for Lenovo Systems...'

cd '../'

if [[ ! -d 'Lenovo' ]]; then
	mkdir 'Lenovo'
fi

cd 'Lenovo' || exit

echo '----------'

# Could not figure out how to get latest version dymanically from https://support.lenovo.com/downloads/DS012808 since it's all loaded with JavaScript.
# But luckily found that the download link is also listed on https://support.lenovo.com/us/en/solutions/ht037099 and was able to retrieve the latest version from there.
# At some point between August 9th, 2021 and September 2nd, 2021 https://support.lenovo.com/us/en/solutions/ht037099 has changed to be all loaded with JavaScript as well, but I was able to find the download link within the JavaScript source.
# Sometime in early 2025, this URL stopped returning anything via CURL, presumably because of intentionally blocked User-Agent strings.
# This can be worked around by setting an empty User-Agent string via "-A ''".

latest_lenovosystemupdate_version="$(curl -m 5 -A '' -sfL "https://support.lenovo.com$(curl -m 5 -A '' -sfL 'https://support.lenovo.com/us/en/solutions/ht037099' | awk -F '"' '/src="\/us\/en\/api\/v4\/contents\/cdn\// { print $4; exit }')" | awk -F 'https://download[.]lenovo[.]com/pccbbs/thinkvantage_en/system_update_|[.]exe' '{ print $2; exit }')"
latest_lenovosystemupdate_download_url="https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_${latest_lenovosystemupdate_version}.exe"
download_app_installer 'Lenovo System Update' 'exe' "${latest_lenovosystemupdate_version}" "${latest_lenovosystemupdate_download_url}"


# DO NOT INSTALL HP SUPPORT ASSISTANT UNTIL I'VE HAD AND CHANCE TO TEST

# echo -e '\n\nDownloading Installers for HP Systems...'

# cd '../'

# if [[ ! -d 'HP' ]]; then
# 	mkdir 'HP'
# fi

# cd 'HP' || exit

# echo '----------'

# # Get download URL from JavaScript file used by http://www.hp.com/go/hpsupportassistant

# latest_hpsupportassistant_version="$(curl -m 5 -sfL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '//' '/ return getProtocol()/ { print $2; exit }')"
# latest_hpsupportassistant_download_url="https://$(curl -m 5 -sfL 'https://hpsa-redirectors.hpcloud.hp.com/common/hpsaredirector.js' | awk -F '"' '/ return getProtocol()/ { print $2; exit }')"
# download_app_installer 'HP Support Assistant' 'exe' "${latest_hpsupportassistant_version}" "${latest_hpsupportassistant_download_url}"
