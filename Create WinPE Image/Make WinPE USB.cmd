::
:: MIT License
::
:: Copyright (c) 2021 Free Geek
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
:: to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
:: and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
:: FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
:: WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
::

@ECHO OFF

:: Make sure this script is running as Administrator (and relaunch as Administrator if not) so that MakeWinPEMedia command can run.
:: Check "NET SESSION" error level since it will error if not running as Administrator.
NET SESSION 1>NUL 2>NUL
IF %ERRORLEVEL% NEQ 0 powershell.exe -NoLogo -NoProfile -Command "Start-Process '%0' -Verb RunAs" & EXIT /B 1

SET WIN_PE_NAME=WinPE 11 22H2

ECHO.
ECHO   Make %WIN_PE_NAME% USB...
ECHO.

SET WIN_PE_OUTPUT_PATH=%USERPROFILE%\Documents\Free Geek\%WIN_PE_NAME%

SET /P USB_DRIVE_LETTER="> Enter USB Drive Letter for %WIN_PE_NAME%: "

ECHO.
ECHO   STARTING ON %DATE% AT %TIME%...
ECHO.

:: https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-usb-bootable-drive#create-a-bootable-winpe-usb-drive
CALL "\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\MakeWinPEMedia.cmd" /UFD "%WIN_PE_OUTPUT_PATH%" %USB_DRIVE_LETTER%:

ECHO.
ECHO   DONE ON %DATE% AT %TIME%
ECHO.
ECHO   Press Any Key to Close This Window

PAUSE >NUL
