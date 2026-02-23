title INTUNE USB DEPLOYMENT

:: --- CONFIGURATION SECTION ---
:: Build script toggles this
SET WiFiEnabled=FALSE

:: -------------------------------------------------
:: Wi-Fi Support
:: -------------------------------------------------

echo [INFO] Starting Wireless Services
REM net start wlansvc >nul 2>&1

:: Adding the profile relative to this script's location 
echo [INFO] Adding Wi-Fi Profile: %~dp0wificonf.xml 
REM netsh wlan add profile filename="%~dp0wificonf.xml"

echo [INFO] Connecting to Wi-Fi SSID: @WIFISSID 
REM netsh wlan connect name=@WIFISSID ssid=@WIFISSID

:: -------------------------------------------------
:: Connectivity Loop (Wait for Heartbeat)
:: -------------------------------------------------
set retryCount=0

:CheckNet
set /a retryCount+=1

:: If WiFi is NOT enabled, jump to Ethernet/Global Check
if /I NOT "%WiFiEnabled%"=="TRUE" goto :GlobalCheck

:: --- Wi-Fi Specific Logic ---
:: Check if the WiFi interface is connected specifically
netsh wlan show interfaces | find /i "connected" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Wi-Fi Connected.
    goto :RUN_PROVISIONING
)

if %retryCount% GEQ 20 (
    echo [WARNING] Wi-Fi failed to connect after 80 seconds.
    goto :RUN_PROVISIONING
)

echo [WAIT] Waiting for Wi-Fi... (%retryCount%/20)
ping localhost -n 5 >nul 2>&1
goto :CheckNet

:: --- Ethernet / Global Logic ---
:GlobalCheck
ping -n 1 8.8.8.8 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Network heartbeat detected.
    goto :RUN_PROVISIONING
)

if %retryCount% GEQ 12 (
    echo [WARNING] No network connection detected.
    goto :RUN_PROVISIONING
)

echo [WAIT] Waiting for Network... (%retryCount%/12)
ping localhost -n 5 >nul 2>&1
goto :CheckNet

:: -------------------------------------------------
:: Launch Intune USB Provisioning
:: -------------------------------------------------

:RUN_PROVISIONING
echo [INFO] Proceeding to Provisioning...
call "%~dp0pwsh\pwsh.exe" -ExecutionPolicy Bypass -File "%~dp0invoke-provision.ps1"
