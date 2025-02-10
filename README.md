## Summary
This is an update of Powers-hells module https://github.com/tabs-not-spaces/Intune.USB.Creator

Read more about it here
https://powers-hell.com/2020/05/04/create-a-bootable-windows-10-autopilot-device-with-powershell/

Works for Windows 11 and added function to register hardware hash in winpe via microsof graph api.

Logic for extraction of autopilot hash: [https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/](https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/)

This script prepares a bootable usb stick which can be used to image a computer with Windows.

## Pre-Reqs

- [PowerShell 7](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7)
- A copy of Windows 10/11 iso
- [Windows WinPE add-on for the Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- A copy of PCPKsp.dll (found on C:\Windows\System32 on a Windows 10/11 machine)
- A copy of oa3tool.exe in _DOWNLOAD\SCRIPT (found in [Windows ADK Deployment Tools](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), run ".\adksetup.exe /installpath C:\temp\adk /features OptionId.DeploymentTools /quiet" and copy C:\Temp\adk\Assessment and Deployment Kit\Deployment Tools\amd64\Licensing\OA30\oa3tool.exe)
- Register an Enterprise app in Entra under App registration with permission DeviceManagementServiceConfig.ReadWrite.All and admin consent, create a client secret for uploading of hashes to intune
![image](https://github.com/user-attachments/assets/1b8c2dce-06ee-4dad-801f-c625c2f7c2e2)

## Optional

Computer model drivers 

**Dell:** [https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)

**HP:** [https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html](https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html)

**Lenovo:** [https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index](https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index)

WinPE drivers

**Dell:** https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs

**Lenovo:** https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index

**HP:** https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html

If you want to use you own welcome banner you can use [https://www.asciiart.eu/text-to-ascii-art](https://www.asciiart.eu/text-to-ascii-art) and then encode it to base64

## Prepare Config
The directory "_DOWNLOAD\WINPEFILES" contains files that will be added to the WinPE Boot image

**PCPKsp.dll** - needed to be able to extract hash from the machine in WinPE, need to get your own copy from a C:\Windows\System32 on a Windows 10/11 machine

**startnet.cmd** - command file that starts Intune USB Deployment

**winpe.jpg** - the background image for WinPE

**_GLOBAL_PARAM\GLOBAL_PARAM.JSON**

graphsecret = clientsecret from the enterprise app

graphclientid = application client id from the enterprise app

tenantid = Your Microsoft 365 Tenant ID

iudwelcomebanner = Banner in Base64

grouptag = GroupTag that will be used when register devices in Intune

windowsIsoPath = Path to Windows 10/11 iso

imageIndex = windows wim image index

## How to use
``` PowerShell
Publish-ImageToUSB.ps1 -createDataFolder
```
(Needs to be run as administrator)

This creates the WinPE boot image and extract Wim file from the Windows iso before creating the USB stick.
After the creation of the DataFolder the _DATA folder will contain:

**Drivers** = Computer model drivers, extract driver cab manually from the manufacturer and name the folder as the model name i.e. Latitude 5350

**Images** = Windows Wim image

**Packages** = Windows packages, i.e. language packs, dotnet 3.5, need to be copied manual

**WinPE** = WinPE data from WinPE-data folder

**WinPE\Script** = The main script and needed files is stored here (i.e. pwsh 7 and oa3tool.exe to extract autopilot hash)
