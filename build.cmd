@echo off
cd /d "%~dp0"
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /codepage:65001 /out:VibeKeys.exe /win32icon:vibekeys.ico /resource:vibekeys.ico,vibekeys.ico /r:System.Windows.Forms.dll /r:System.Drawing.dll VibeKeys.cs SilenceWatcher.cs NoFocus.cs SymbolPopup.cs
