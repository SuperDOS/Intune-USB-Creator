## Summary
This is an update of Powers-hells module https://github.com/tabs-not-spaces/Intune.USB.Creator

Read more about it here
https://powers-hell.com/2020/05/04/create-a-bootable-windows-10-autopilot-device-with-powershell/

Works for Windows 11 and added function to register hardware hash in winpe via microsof graph api.

Logic for extraction of autopilot hash: [https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/](https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/)

It consists of three scripts to prepare a bootable usb stick which can be used to image a computer with Windows.

## Pre-Reqs

- [PowerShell 7](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7)
- A copy of Windows 10/11 iso
- [Windows WinPE add-on for the Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- A copy of PCPKsp.dll (found on C:\Windows\System32 on a Windows 10/11 machine)
- A copy of oa3tool.exe (found in [Windows ADK Deployment Tools](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), run ".\adksetup.exe /installpath C:\temp\adk /features OptionId.DeploymentTools /quiet" and copy C:\Temp\adk\Assessment and Deployment Kit\Deployment Tools\amd64\Licensing\OA30\oa3tool.exe)
- Register an Enterprise app in Entra under App registration with permission DeviceManagementServiceConfig.ReadWrite.All and admin consent, create a client secret for uploading of hashes to intune
![image](https://github.com/user-attachments/assets/1b8c2dce-06ee-4dad-801f-c625c2f7c2e2)

## Optional
Computer model drivers

**Dell:** [https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)

**HP:** [https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html](https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html)

**Lenovo:** [https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index](https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index)

## How to use

**New-WinPEMedia.ps1** (Needs to be run as administrator)
Creates the WinPEMedia that will be written to the USB-stick

To create WinPE media you will need Windows WinPE add-on for Windows ADK.

Download adkwinpesetup.exe from [https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)

Run adkwinpesetup.exe /installpath c:\temp\adkoffline /quiet

this will give you these paths

"C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\Media"

"C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us"

"C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"

The directory "pe-files" contains three files

**PCPKsp.dll** - needed to be able to extract hash from the machine in WinPE, need to get your own copy from a C:\Windows\System32 on a Windows 10/11 machine

**startnet.cmd** - command file that starts Intune USB Deployment

**winpe.jpg** - the background image for WinPE

If you need WinPE drivers for certain machines you need to download a cab from the manfacturer.

**Dell:** https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs

**Lenovo:** https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index

**HP:** https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html

Extract the cab of the winpe drivers to a desired folder

run the New-WinPEMedia script for example:
``` PowerShell
New-WinPEMedia.ps1 -wimpath "C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim" ´
-packagepath "C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs" ´
-winpemedia "C:\Temp\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\Media" ´
-driverspath "C:\Temp\winpedrivers"
```
This will create a new boot.wim and necessary files in the folder WinPE-Media

**New-IUC-Data-Folder.ps1**

Creates the IUC data folder that is needed for the bootable USB stick

in the IUC-Script folder contains the main script and oa3tool.exe (add from Windows ADK) to extract autopilot hash

the script will download powershell 7

extract Wim file from the Windows iso.

``` PowerShell
New-IUC-Data-Folder.ps1 -windowsIsoPath .\iso\win.iso
-winPEMediaPath .\WinPE-Media
-winPEwim .\WinPE-Media\sources\boot.wim ´
```
In the folder IUC data folder there will be these folders

Drivers = Computer model drivers, extract driver cab from the manufacturer and name the folder as the model name i.e. Latitude 5350

Images = Windows image

Packages = Windows packages, i.e. language packs, dotnet 3.5

WinPE = WinPE data from WinPE-data folder

**Publish-ImageToUSB.ps1**

This will create the bootable usb stick and if the WinPE and IUC-data folder is prepared go ahead and run it :)

``` PowerShell
Publish-ImageToUSB.ps1 -IUCdataPath .\IUC-data
```



