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

:: TODO: Rewrite this in PowerShell to automate the entire process like the equivalent Linux script.

:: To use this script, you must download the latest JDK version and extract the folder on the Desktop.

:: Set the version of the JDK (in the folder name "jdk-#") below:
SET JDK_VERSION=21.0.8+9

ECHO.
ECHO   Creating JLink JRE %JDK_VERSION:_=+%...
ECHO.

SET DESKTOP_PATH=%USERPROFILE%\Desktop
IF NOT EXIST %DESKTOP_PATH% SET DESKTOP_PATH=%USERPROFILE%\OneDrive\Desktop

SET JDK_PATH=%DESKTOP_PATH%\jdk-%JDK_VERSION:_=+%
IF NOT EXIST "%JDK_PATH%" ECHO   ERROR: %JDK_PATH% DOES NOT EXIST!

IF EXIST "%DESKTOP_PATH%\java-jre" RMDIR /S /Q "%DESKTOP_PATH%\java-jre"
IF EXIST "%JDK_PATH%" %JDK_PATH%\bin\jlink.exe --add-modules "java.base,java.desktop,java.logging" --strip-debug --no-man-pages --no-header-files --compress "zip-9" --output "%DESKTOP_PATH%\java-jre"
:: java.datatransfer, java.prefs, and java.xml are included automatically with java.desktop

IF EXIST "%DESKTOP_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip" DEL /F "%DESKTOP_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip"
IF EXIST "%JDK_PATH%" "\Program Files\7-Zip\7z.exe" a "%DESKTOP_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip" "%DESKTOP_PATH%\java-jre"

ECHO.
ECHO   DONE!
ECHO.
ECHO   Press Any Key to Close This Window

PAUSE >NUL
