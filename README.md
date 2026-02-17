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

If you choose Install Windows and Register Autopilot it will extract the hardware hash with OA3.tool and try to upload it via graph to Intune

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
- A copy of Windows 11 iso
- [Windows WinPE add-on for the Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) - **Optional when using `-useWinRE`**
- A copy of PCPKsp.dll (found on C:\Windows\System32 on a Windows 11 machine)
- A copy of oa3tool.exe in _DOWNLOAD\SCRIPT (found in [Windows ADK Deployment Tools](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install), run ".\adksetup.exe /installpath C:\temp\adk /features OptionId.DeploymentTools /quiet" and copy C:\Temp\adk\Assessment and Deployment Kit\Deployment Tools\amd64\Licensing\OA30\oa3tool.exe)
- Register an Enterprise app in Entra under App registration with permission DeviceManagementServiceConfig.ReadWrite.All and admin consent, create a client secret for uploading of hashes to intune
![image](https://github.com/user-attachments/assets/1b8c2dce-06ee-4dad-801f-c625c2f7c2e2)

### WinRE Support with WiFi
Use `-useWinRE` to extract and use WinRE (Windows Recovery Environment) from the Windows install.wim instead of WinPE. This provides:
- **Built-in WiFi support** - No manual driver injection needed
- **Automatic WiFi configuration** - Configure SSID and password in GLOBAL_PARAM.json

### WiFi Configuration
When using `-useWinRE`, add these parameters to `_GLOBAL_PARAM\GLOBAL_PARAM.json`:
```json
{
  "wifissid": "YourWiFiNetworkName",
  "wifipwd": "YourWiFiPassword",
  "wifisecuritytype": "WPA2PSK"
}
```
WiFi will automatically connect at boot, allowing wireless deployment without Ethernet cable.

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

**winpe.jpg** - the background image for WinPE/WinRE

**_GLOBAL_PARAM\GLOBAL_PARAM.JSON**

It's possible to configure multiple tenants, if more than one tenant is configured you will be prompted which tenant to use

``` JSON
{
  "tenant": [
    {
      "id": "Microsoft 365 Tenant ID 1",
      "name": "tenant1.com",
      "grouptag": "GROUP TAG 1",
      "graphsecret": "Enterprise App Client Secret 1",
      "graphclientid": "Enterprise App Application ID 1"
    },
    {
      "id": "Microsoft 365 Tenant ID 2",
      "name": "tenant2.com",
      "grouptag": "GROUP TAG 2",
      "graphsecret": "Enterprise App Client Secret 2",
      "graphclientid": "Enterprise App Application ID 2"
    },
    {
      "id": "Microsoft 365 Tenant ID 3",
      "name": "tenant3.com",
      "grouptag": "GROUP TAG 3",
      "graphsecret": "Enterprise App Client Secret 3",
      "graphclientid": "Enterprise App Application ID 3"
    }
  ],
  "iudwelcomebanner": "Banner in Base64",
  "windowsIsoPath": "Path to Windows ISO i.e. C:\\Temp\\Windows.iso",
  "imageIndex": 6,
  "iucversion": 1.0,
  "wifissid": "YourWiFiNetworkName",
  "wifipwd": "YourWiFiPassword",
  "wifisecuritytype": "WPA2PSK"
}
```

**Parameters:**
- `tenant` - Array of tenant configurations for multi-tenant support
- `iudwelcomebanner` - Custom ASCII art banner (base64 encoded)
- `windowsIsoPath` - Path to Windows ISO file
- `imageIndex` - Windows edition to extract
- `iucversion` - Script version tracking
- `wifissid` - WiFi network name (optional, for WinRE WiFi support)
- `wifipwd` - WiFi network password (optional, for WinRE WiFi support)
- `wifisecuritytype` - WiFi Authentication Security (e.g. WPA2PSK, WPA3SAE)
## How to use

### Workflow Overview

The script has two distinct phases:

**Phase 1: Build Deployment Share** (run once)
```powershell
.\Publish-ImageToUSB.ps1 -createDataFolder [-useWinRE]
```
This creates the `_DATA` folder with WinPE/WinRE boot image, extracts install.wim, and prepares all deployment files.

**Phase 2: Create USB Sticks** (run multiple times)
```powershell
.\Publish-ImageToUSB.ps1
```
This formats a USB drive and copies the deployment share to it. The script automatically detects the deployment type (WinPE/WinRE) and configures WiFi if applicable.

---

### Traditional WinPE (requires Windows ADK)
```powershell
# Build deployment share
.\Publish-ImageToUSB.ps1 -createDataFolder

# Create USB sticks (as many as needed)
.\Publish-ImageToUSB.ps1
.\Publish-ImageToUSB.ps1
```

### WinRE with WiFi Support
```powershell
# Build deployment share with WinRE
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE

# Create USB sticks (WiFi automatically configured for each)
.\Publish-ImageToUSB.ps1
.\Publish-ImageToUSB.ps1
```

### Force Rebuild (ignore cache)
```powershell
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE -force
```

**(All commands need to be run as administrator)**

---

### What happens during build:

1. **Extracts install.wim** from Windows ISO (cached if unchanged)
2. **Extracts WinRE.wim** from install.wim if using `-useWinRE` (cached if unchanged)
3. **Builds boot media** with customizations
4. **Downloads latest PowerShell** and adds scripts to deployment share
5. **Saves deployment metadata** to `IUC-log.json`

### What happens during USB creation:

1. **Loads deployment configuration** from `IUC-log.json`
2. **Validates required files** (boot.wim, install.wim, scripts)
3. **Configures WiFi** automatically if WinRE deployment (pulls credentials from GLOBAL_PARAM.json)
4. **Formats USB drive** and creates partitions
5. **Copies deployment files** to USB

---

### After the creation of the DataFolder the _DATA folder will contain:

**Drivers** = Computer model drivers, extract driver cab manually from the manufacturer and name the folder as the model name i.e. Latitude 5350, if you need to add a driver to WinPE after creating the drive you can add a folder here name WinPE and i will load these drivers before starting

**Images** = Windows Wim image

**Packages** = Windows packages, i.e. language packs, dotnet 3.5, need to be copied manual

**WinPE** = WinPE data from WinPE-data folder

**WinPE\Script** = The main script and needed files is stored here (i.e. pwsh 7 and oa3tool.exe to extract autopilot hash)

## Deployment Metadata

The script automatically tracks deployment configuration in `_DATA\IUC-log.json`:

```json
{
  "installdate": "2026-02-10T20:30:00",
  "scriptversion": 1.0,
  "imageindex": 6,
  "deploymentType": "WinRE",
  "isosize": 7754645504,
  "wimsize": 6875518816,
  "winversion": "Windows 11 Enterprise",
  "pwshversion": "v7.5.4"
}
```

This metadata allows the script to:
- Automatically detect WinPE vs WinRE deployment
- Configure WiFi for WinRE USB sticks automatically
- Validate deployment share completeness
- Track build history

**Important:** WiFi credentials are NEVER stored in metadata - they're always pulled from GLOBAL_PARAM.json at USB creation time, allowing you to update WiFi settings without rebuilding the deployment share.

## Performance Optimizations

### Smart Caching
The script caches extracted files to speed up rebuilds:
- **install.wim** - Reused if same ISO and image index
- **WinRE.wim** - Reused if same install.wim and image index
- **WiFi DLLs** - Extracted once from install.wim

### Image Index Detection
Changing `imageIndex` in GLOBAL_PARAM.json automatically triggers:
- Re-extraction of install.wim
- Re-extraction of WinRE.wim
- Cache invalidation

## Troubleshooting

### Force Rebuild
If experiencing issues with cached files:
```powershell
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE -force
```

### WiFi Not Connecting
1. Verify `wifissid` and `wifipwd` in GLOBAL_PARAM.json
2. Ensure deployment was built with `-useWinRE` parameter
3. Check deployment type: Run `.\Publish-ImageToUSB.ps1` and verify it shows "Deployment Type: WinRE"
4. Check WiFi DLLs were extracted: `_DOWNLOAD\WINPEFILES\Windows\System32\`
5. **Custom WiFi security:** If your network uses different authentication (WPA3, Enterprise, etc.), you can export the profile from a connected computer:
   ```powershell
   netsh wlan export profile name="YourNetworkName" key=clear folder=C:\Temp
   ```
   Then copy the authentication settings from the exported XML to `_DOWNLOAD\SCRIPT\wificonf.xml`
6. Test WiFi manually in WinRE (Shift+F10 at boot):
   ```cmd
   net start wlansvc
   netsh wlan show networks
   netsh wlan connect name=YourSSID
   ```

**Note:** WiFi is configured automatically when you create each USB stick. If you update WiFi credentials in GLOBAL_PARAM.json, the next USB you create will use the new credentials - no need to rebuild the deployment share!

## Common Scenarios

### Scenario 1: Creating Multiple USB Sticks
```powershell
# Build deployment share once
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE

# Create as many USB sticks as needed
.\Publish-ImageToUSB.ps1  # USB stick 1
.\Publish-ImageToUSB.ps1  # USB stick 2
.\Publish-ImageToUSB.ps1  # USB stick 3
```
Each USB stick is configured identically with WiFi support.

### Scenario 2: Updating WiFi Credentials
```powershell
# 1. Update GLOBAL_PARAM.json with new WiFi credentials
# 2. Create USB sticks (no rebuild needed)
.\Publish-ImageToUSB.ps1
```
New credentials are automatically applied to each USB stick.

### Scenario 3: Changing Windows Edition
```powershell
# 1. Update imageIndex in GLOBAL_PARAM.json (e.g., 4=Pro, 6=Enterprise)
# 2. Rebuild deployment share
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE

# Script automatically detects index change and re-extracts install.wim and WinRE.wim
```

### Scenario 4: Different Deployment Types
You can maintain multiple deployment shares:
```powershell
# Build WinPE deployment (traditional, no WiFi)
.\Publish-ImageToUSB.ps1 -createDataFolder
# Creates _DATA with deploymentType: "WinPE"

# Build WinRE deployment (WiFi enabled)  
.\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE
# Creates _DATA with deploymentType: "WinRE"
```
The script automatically detects which type when creating USB sticks.

### Cache Location
- install.wim cache: `_DATA\Images\`
- WinRE cache: `_DOWNLOAD\WINRE_EXTRACTED\`
- Cache metadata: `_DOWNLOAD\WINRE_EXTRACTED\extraction.json`
