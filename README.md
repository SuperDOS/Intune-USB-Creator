## Summary
This script prepares a bootable usb drive which can be used to image a computer with Windows.

This is an update of Powers-hells module https://github.com/tabs-not-spaces/Intune.USB.Creator

Read more about it here
https://powers-hell.com/2020/05/04/create-a-bootable-windows-10-autopilot-device-with-powershell/

Works for Windows 11 and added function to register hardware hash in winpe via microsof graph api.

Logic for extraction of autopilot hash: [https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/](https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/)

## What does it do?
When booting up the USB Intune Deployment it will look up the USB drive and setup all the drive letters needed

It will then look for any WinPE drivers under Drivers\WinPE and load them

Then a menu will be shown what you want to do

- Install Windows
- Install Windows and Register Autopilot
- Register Autopilot

If you choose Install Windows and Register Autopilot it will extract the hardware hash with OA3.tool and typ to upload it via graph to Intune

After it has succeded it will prompt to enter a device name

If you look under Intune/Windows Enrollment/Devices it will be updated there

![image](https://github.com/user-attachments/assets/9710580e-2429-4ff4-a7f2-e49f49730f83)

It will proceed and format the computer's drive and partition it, if there's storage drivers for the detected model it will be injected to the windows recovery image.

If there's a unattented.xml and ppkg files under the scripts folder it will be copied as well

Public shortcuts will be removed

Computer specific drivers will be added to the installation

Any Packages like language packs will be added

Done!

## Pre-Reqs

- [PowerShell 7](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7)
- A copy of Windows 10/11 iso
- [Windows WinPE add-on for the Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
- A copy of PCPKsp.dll (found on C:\Windows\System32 on a Windows 10/11 machine)
- A copy of oa3tool.exe in _DOWNLOAD\SCRIPT (found in [Windows ADK Deployment Tools](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), run ".\adksetup.exe /installpath C:\temp\adk /features OptionId.DeploymentTools /quiet" and copy C:\Temp\adk\Assessment and Deployment Kit\Deployment Tools\amd64\Licensing\OA30\oa3tool.exe)
- Register an Enterprise app in Entra under App registration with permission DeviceManagementServiceConfig.ReadWrite.All and admin consent, create a client secret for uploading of hashes to intune
![image](https://github.com/user-attachments/assets/1b8c2dce-06ee-4dad-801f-c625c2f7c2e2)

## Optional

Language Packs and Optional Features


Copy the needed cabs from the Windows Language Packs and Optional Features and put them in _DATA\Packages

[https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs](https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs)

Computer model drivers 

**Dell:** [https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)

**HP:** [https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html](https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HP_Driverpack_Matrix_x64.html)

**Lenovo:** [https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index](https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index)

WinPE drivers

**Dell:** https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs

**Lenovo:** https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index

**HP:** https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html

If you want to use your own welcome banner you can use [https://www.asciiart.eu/text-to-ascii-art](https://www.asciiart.eu/text-to-ascii-art) and then encode it to base64

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

grouptag = GroupTag that will be used when register devices in Intune, great to use for dynamic groups

windowsIsoPath = Path to Windows 10/11 iso

imageIndex = windows wim image index

## How to use
``` PowerShell
Publish-ImageToUSB.ps1 -createDataFolder
```
(Needs to be run as administrator)

This creates the WinPE boot image and extract Wim file from the Windows iso before creating the USB drive.
The script will also download the latest powershell version and add the needed script files to the USB drive.
After the creation of the DataFolder the _DATA folder will contain:

**Drivers** = Computer model drivers, extract driver cab manually from the manufacturer and name the folder as the model name i.e. Latitude 5350, if you need to add a driver to WinPE after creating the drive you can add a folder here name WinPE and i will load these drivers before starting

**Images** = Windows Wim image

**Packages** = Windows packages, i.e. language packs, dotnet 3.5, need to be copied manual

**WinPE** = WinPE data from WinPE-data folder

**WinPE\Script** = The main script and needed files is stored here (i.e. pwsh 7 and oa3tool.exe to extract autopilot hash)
