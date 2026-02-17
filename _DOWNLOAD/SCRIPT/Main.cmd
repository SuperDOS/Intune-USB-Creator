title INTUNE USB DEPLOYMENT

::Load WinPE Drivers
for /r "%~dp0WinPE" %%F in (*.inf) do (
    echo Loading WinPE driver: %%F
    drvload "%%F"
)

::WiFi Support using WinRE
REM net start wlansvc
REM netsh wlan add profile filename= %~dp0wificonf.xml
REM netsh wlan connect name=@WIFISSID ssid=@WIFISSID
REM ping localhost -n 30 >nul

call %~dp0pwsh\pwsh.exe %~dp0invoke-provision.ps1
