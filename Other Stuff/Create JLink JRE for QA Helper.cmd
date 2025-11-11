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
SET JDK_VERSION=25.0.1+8

ECHO.
ECHO   Creating JLink JRE %JDK_VERSION:_=+%...
ECHO.

SET JDK_PARENT_PATH=%PUBLIC%\Windows Deployment\Java JRE

SET JDK_PATH=%JDK_PARENT_PATH%\jdk-%JDK_VERSION:_=+%
IF NOT EXIST "%JDK_PATH%" ECHO   ERROR: %JDK_PATH% DOES NOT EXIST!

IF EXIST "%JDK_PARENT_PATH%\java-jre" RMDIR /S /Q "%JDK_PARENT_PATH%\java-jre"
IF EXIST "%JDK_PATH%" "%JDK_PATH%\bin\jlink.exe" --add-modules "java.base,java.desktop,java.logging" --strip-debug --no-man-pages --no-header-files --compress "zip-9" --output "%JDK_PARENT_PATH%\java-jre"
:: java.datatransfer, java.prefs, and java.xml are included automatically with java.desktop

IF EXIST "%JDK_PARENT_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip" DEL /F "%JDK_PARENT_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip"
IF EXIST "%JDK_PARENT_PATH%\java-jre" "%ProgramFiles%\7-Zip\7z.exe" a "%JDK_PARENT_PATH%\jlink-jre-%JDK_VERSION:+=_%_windows-x64.zip" "%JDK_PARENT_PATH%\java-jre"

ECHO.
ECHO   DONE!
ECHO.
ECHO   Press Any Key to Close This Window

PAUSE >NUL
