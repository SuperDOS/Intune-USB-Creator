title INTUNE USB DEPLOYMENT

::Load WinPE Drivers
echo Loading WinPE drivers using DISM...
dism /online /add-driver /driver:"%WinPESource%Drivers\WinPE" /recurse

::WiFi Support using WinRE
REM net start wlansvc
REM netsh wlan add profile filename= %~dp0wificonf.xml
REM netsh wlan connect name=@WIFISSID ssid=@WIFISSID
REM ping localhost -n 30 >nul

call %~dp0pwsh\pwsh.exe %~dp0invoke-provision.ps1
