@echo off
setlocal enabledelayedexpansion

:: Set High Performance Power Scheme [cite: 2]
powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 
@echo Starting timer...
call |time>x:\starttime.txt

:: Initialize WinPE [cite: 4]
@echo Initializing WinPE (wpeinit)...
wpeinit

@echo.
@echo *****************************************************************
@echo  Searching for USB Partitions...
@echo *****************************************************************

set WinPESource=
set DriverSource=

:: Loop through drive letters to find our tag files
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\WINPE.tag" (
        set "WinPESource=%%D:"
        echo Found Boot Partition: !WinPESource!
    )
    if exist "%%D:\DRIVERS.tag" (
        set "DriverSource=%%D:\Drivers"
        echo Found Driver Partition: !DriverSource!
    )
)

:: Validation
if "%WinPESource%"=="" (
    echo ERROR: Could not find WINPE.tag on any drive.
    goto :ERROR
)

if "%DriverSource%"=="" (
    echo WARNING: Driver partition not found.
    echo Main.cmd may fail to load drivers.
)

@echo.
@echo *****************************************************************
@echo  Launching Main Deployment Script
@echo *****************************************************************
:: Pass the detected paths to Main.cmd 
call "%WinPESource%\Scripts\Main.cmd"

:END
@echo Deployment Phase Finished.
pause
exit

:ERROR
@echo.
@echo [!] FATAL ERROR: Deployment environment not detected.
@echo. 
pause
goto :END
