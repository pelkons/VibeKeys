@echo off
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:exe /codepage:65001 /out:LevelTest.exe /r:System.Windows.Forms.dll LevelTest.cs ..\SilenceWatcher.cs || exit /b 1
.\LevelTest.exe %*
