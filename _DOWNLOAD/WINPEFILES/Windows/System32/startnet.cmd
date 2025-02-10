@echo off
@rem 
@rem  Capture the START time so we can evaluate total WinPE phase time.
@rem
@rem  Set the power scheme to High Performance.
@echo Set High Performance Power Scheme...
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 
@echo Starting timer...
call |time>x:\starttime.txt
@echo.
@rem  *****************************************************************
@rem  Script to deploy an image on a target device in a standard configuration
@rem  Stop in Audit mode for customization and then automatically capture.
@rem  *****************************************************************
@rem Initialize WinPE
@echo wpeinit
wpeinit
@rem Load WinPE SYSTEM hive:
Reg Load HKLM\WinPE "C:\WinPE\mount\Windows\System32\config\SYSTEM"
@rem Show hidden files:
  Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v Hidden /t REG_DWORD /d 1
  Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v ShowSuperHidden /t REG_DWORD /d 1
@rem Show file extensions:
  Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v HideFileExt /t REG_DWORD /d 0
@remUnload Hive:
  Reg Unload HKLM\WinPE
@echo.
@echo.
@echo.
@echo *****************************************************************
@rem  Get the USB Drive letter of the device we booted WinPE from
@echo *****************************************************************
@echo call wpeutil UpdateBootInfo
wpeutil UpdateBootInfo
@echo.
set WinPEREG="HKLM\System\CurrentControlSet\Control"
set WinPEKey=PEBootRamdiskSourceDrive
set WinPESource=
@echo.
@rem Get volume letter of USB Key
@echo for /f "skip=2 tokens=3" %%A in ('call Reg query %WinPEREG% /v %WinPEKEY%') do set WinPESource=%%A
for /f "skip=2 tokens=3" %%A in ('call Reg query %WinPEREG% /v %WinPEKEY%') do set WinPESource=%%A
@echo WinPESource is drive letter "%WinPESource%"
@echo.
@echo.
@echo.
if "%WinPESource%"=="" echo Drive letter NOT found.&& call :FindDrive
echo WinPESource is "%WinPESource%"
echo.
@echo *****************************************************************
@echo  Call and run main.cmd on the USB Key
@echo *****************************************************************
@echo call %WinPESource%Scripts\main.cmd
call %WinPESource%Scripts\main.cmd
@echo.
@echo.
@echo.
@echo *****************************************************************
@echo  Image deployment COMPLETE. Type EXIT from Command
@echo  Prompt to restart or turn off device.
@echo *****************************************************************
goto :END

:ERROR
@echo.
@echo An error has been detected.
@echo. 
goto :END

:FindDrive
echo.
echo Trying to find drive letter using diskpart
echo.
echo Lis Vol>x:\FindVol.txt
echo.
echo Running Diskpart to get Volume letters
echo.
diskpart /s x:\FindVol.txt>x:\VolumeList.txt
echo.
echo Parsing list to find WinPE
echo.
for /f "skip=8 tokens=3-4" %%A in (x:\VolumeList.txt) do (
echo Checking drive letter %%A has volume label of %%B
if /i "%%B"=="WINPE" set WinPESource=%%A
)
set WinPESource=%WinPESource%:\
goto :EOF

:END