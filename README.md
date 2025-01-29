## Summary
This is an update of Powers-hells module https://github.com/tabs-not-spaces/Intune.USB.Creator

Read more about it here
https://powers-hell.com/2020/05/04/create-a-bootable-windows-10-autopilot-device-with-powershell/

Works for Windows 11 and added function to register hardware hash in winpe via microsof graph api.

It consists of three scripts to prepare a bootable usb stick which can be used to image a computer with Windows.

## Pre-Reqs

- [PowerShell 7](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7)
- A copy of Windows 10/11 iso
- [Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)

## How to use

**New-WinPEMedia.ps1** (Need to be run as administrator)
Creates the WinPEMedia that will be written to the USB-stick

To create WinPE media you will need Windows ADK.

Download adkwinpesetup.exe from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
this will give you these paths

"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\Media"

"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us"

"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"

The directory "pe-files" contains three files

**PCPKsp.dll** - needed to be able to extract hash from the machine in WinPE

**startnet.cmd** - command file that starts Intune USB Creator

**winpe.jpg** - the background image for WinPE

If you need WinPE drivers for certain machines you need to download a cab from the manfacturer.

**Dell:** https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs

**Lenovo:** https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index

**HP:** https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html

Extract the cab of the driver

run the New-WinPEMedia script for example:
``` PowerShell
New-WinPEMedia.ps1 -wimpath "C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim" ´
-packagepath "C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs" ´
-winpemedia "C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\Media" ´
-driverspath "C:\Temp\winpedrivers"
```
This will create a new boot.wim and necessary files in the folder WinPE-Media

**New-IUC-Data-Folder.ps1**

Creates the IUC data folder that is needed for the bootable USB stick

Will download powershell

extract Wim file from the Windows iso.

``` PowerShell
New-IUC-Data-Folder.ps1 -windowsIsoPath .\iso\win.iso
-winPEMediaPath .\WinPE-Media
-winPEwim .\WinPE-Media\sources\boot.wim ´
```
In the folder IUC data folder there will be folders

Drivers = Computer model drivers

Images = Windows image

Packages = Windows packages, like language packs

WinPE = WinPE data from WinPE-data folder

**Publish-ImageToUSB.ps1**

``` PowerShell
Publish-ImageToUSB.ps1 -IUCdataPath .\IUC-data
```



