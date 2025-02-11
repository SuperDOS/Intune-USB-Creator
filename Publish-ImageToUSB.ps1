<#
.SYNOPSIS
  Creates Bootable USB stick with Intune USB Deployment
.DESCRIPTION
  Will format and write the needed data to a USB stick
  #Instructions
  Before creating a USB stick you need to run Publish-ImageToUSB.ps1 -createDataFolder to prepare all the data to be written.
  If want to add drivers or packages like language packs you will need to add them to the folders In the folder _DATA folder
  Drivers = Computer model drivers, extract driver cab from the manufacturer and name the folder as the model name i.e. Latitude 5350
  Packages = Windows packages, i.e. language packs, dotnet 3.5
  To be able to create WINPE boot media download adkwinpesetup.exe from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install and install it
  
  If you need winpe drivers for certain machines you can download them from the manufacturer
  Dell: https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs
  Lenovo: https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index
  HP: https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html
  
  These need to be added to _DOWNLOAD\WINPEDRIVERS
  
  You also will need to get a Windows 10/11 iso for extraction of install.wim, path to the iso can be defined in GLOBAL_PARAM.json if not you will be prompted.
  This script will download latest powershell
  
  In the \_GLOBAL_PARAM\GLOBAL_PARAM.json you will need do define infromation from your enterprise app  GraphSecret, GraphClientID, TenantID
  Optional is to define the USB-welcomescreen which is the banner that is shown when the Intune USB Deployment is starting
  If you want to use you own welcome banner you can use [https://www.asciiart.eu/text-to-ascii-art](https://www.asciiart.eu/text-to-ascii-art) and then encode it to base64
  
.NOTES
  Version:        0.1
  Credits:        SuperDOS / Ben R. / CloudOSD
  Creation Date:  2025-02-24
  Purpose/Change: First complete version
.EXAMPLE
  .\Publish-ImageToUSB.ps1
#>
[CmdletBinding(PositionalBinding = $false)]
param (
    [Parameter(Mandatory = $false)][switch]$createDataFolder,
    [Parameter(Mandatory = $false)][switch]$force
)

#Region Start Block

#Create dataPath
if (-not (Test-Path ".\_DATA")) {
    $dataPath = (New-Item ".\_DATA" -ItemType Directory).FullName
}
else {
    $dataPath = $(Get-Item -Path ".\_DATA").FullName
}

#Import functions
try {
    # Ensure the folder exists
    $FunctionsFolder = Join-Path -Path $PSScriptRoot -ChildPath "_FUNCTIONS"
    if (-not (Test-Path -Path $FunctionsFolder)) {
        Write-Error "The folder '_FUNCTIONS' was not found at '$FunctionsFolder'."
    }

    # Get all PS1 files in the folder
    $Functions = Get-ChildItem -Path $FunctionsFolder -Filter *.ps1
    
    # Import each function file
    foreach ($Function in $Functions) {
        . $Function.FullName
    }
}
catch {
    Write-Error "Failed to import functions: $_"
    exit 1
}

#Get Download Path
$downloadPath = Join-Path -Path $PSScriptRoot -ChildPath "_DOWNLOAD" 
if (-not (Test-Path -Path $downloadPath)) {
    Write-Error "The folder '_DOWNLOAD' was not found at '$downloadPath'."
    exit 1
}

if (!(Test-Admin)) {
    Write-Error "Exiting -- need admin right to execute"
    exit 1
}


# Load Global Parameters
try {
    $GlobalParamFilePath = Join-Path -Path $PSScriptRoot -ChildPath "_GLOBAL_PARAM\GLOBAL_PARAM.json"

    # Check if the file exists before attempting to read it
    if (-not (Test-Path -Path $GlobalParamFilePath -ErrorAction SilentlyContinue)) {
        Write-Error "The global parameters file was not found at: '$GlobalParamFilePath'."
        exit 1
    }

    # Read and parse the JSON file
    $GlobalParamTable = Get-Content -Path $GlobalParamFilePath | ConvertFrom-Json
}
catch {
    Write-Error "Failed to read or parse the global parameters file. Details: $_"
    exit 1
}

# Get the list of properties
$varNames = $GlobalParamTable.PSObject.Properties.name
    
# For each property, create a var with its name and corresponding value
ForEach ($variable in $varNames) {
    New-Variable -Name $variable -Value $GlobalParamTable.$variable -Force
}

#Endregion

if (!$createDataFolder -and $(Test-IsDirectoryEmpty $dataPath).IsEmpty -eq $true) {
    Write-Host "`nNo Intune USB Creator Data Found, run with -createDataFolder" -ForegroundColor Red
    Return
}

if ($createDataFolder) {

    #region WinPE Data Paths
     
    $pePath = Join-Path -Path $downloadPath -ChildPath "WINPEMEDIA"
    $newWIMPath = Join-Path -Path $pePath -ChildPath "sources\boot.wim"
    $peFiles = Join-Path -Path $downloadPath -ChildPath "WINPEFILES"

    # optional set in global_param.json
    $winPEdrivers = Join-Path -Path $downloadPath -ChildPath "WINPEDRIVERS"
    $winPEupdates = Join-Path -Path $downloadPath -ChildPath "WINPEUPDATES"
    #endregion

    if (!$force -and $(Test-IsDirectoryEmpty $pePath).IsEmpty -eq $false) {

        do {
            $response = $(Write-Host "$pePath is not empty. Do you want to rebuild WINPEMEDIA? (Y/N) " -ForegroundColor Yellow -NoNewLine; Read-Host)
            $response = $response.ToLower()
        } until ($response -eq "y" -or $response -eq "n" -or $response -eq "yes" -or $response -eq "no")
        
        if ($response -eq "n" -or $response -eq "no") {
            $buildwinpemedia = $false
            Write-Host "Skipping rebuilding WINPEPMEDIA" -ForegroundColor Yellow       
        }
        else {
            $buildwinpemedia = $true
        }
    }
    else {
        $buildwinpemedia = $true
    }
    
    if ($buildwinpemedia) {
           
        #region Get Windows ADK information from the Registry - Credits CloudOSD

        $InstalledRoots = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
        $RegistryValue = 'KitsRoot10'
        $KitsRoot10 = $null
 
        if (Test-Path -Path $InstalledRoots) {
            $RegistryKey = Get-Item -Path $InstalledRoots
            if ($null -ne $RegistryKey.GetValue($RegistryValue)) {
                $KitsRoot10 = Get-ItemPropertyValue -Path $InstalledRoots -Name $RegistryValue -ErrorAction SilentlyContinue
            }
        }

        if ($KitsRoot10) {
            $winPEPath = Join-Path $KitsRoot10 'Assessment and Deployment Kit\Windows Preinstallation Environment\amd64'
            $wimpath = "$winPEpath\en-us\winpe.wim"
            $winpemedia = "$winPEpath\Media\"
            $packagepath = "$winPEpath\WinPE_OCs\"
    
        }
        else {
            Write-Warning "Windows PE Addon Not Found, Please Install"
            return
        }
    
        #endregion

        #These are needed for Intune USB Deployment
        $OptionalComponents = @("WinPE-WDS-Tools", "WinPE-Scripting", "WinPE-WMI", "WinPE-SecureStartup", "WinPE-NetFx", "WinPE-PowerShell", "WinPE-StorageWMI", "WinPE-DismCmdlets")
        
        # Copy the winpe media
        copy-item -Path $winpemedia -Destination $pePath -Recurse -ErrorAction:Ignore
        new-item -Path $pePath -Name "sources" -ItemType Directory -ErrorAction:Ignore

        # Copy the winpe.wim
        if (-not (Test-Path $wimpath)) {
            Write-Error "Windows PE file does not exist." -ErrorAction "Stop"
        }

        #Copy winpe.wim
        $peNew = Copy-Item -Path $wimpath -Destination $newWIMPath -Force

        # Mount the winpe.wim
        $peMount = "$($env:TEMP)\mount_winpe"
        if (-not (Test-Path $peMount)) {
            New-Item $peMount -ItemType Directory | Out-Null
        }
        else {
            Remove-Item $peMount -Recurse
            New-Item $peMount -ItemType Directory | Out-Null
        }

        #Mounting...
        Mount-WindowsImage -Path $peMount -ImagePath $newWIMPath -Index 1 | Out-Null

        # Add PE Files

        # Define the well-known SID for the Administrators group
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $adminAccount = $adminSid.Translate([System.Security.Principal.NTAccount])

        Get-ChildItem $peFiles -Recurse | ForEach-Object {
    
            # Get the relative path of the current file
            $relativePath = $_.FullName.Substring((Get-Item $peFiles).FullName.Length)

            # Define the destination path for the current file
            $destFilePath = Join-Path -Path $peMount -ChildPath $relativePath

            # Ensure the destination directory exists
            $destDir = Split-Path -Path $destFilePath -Parent
            if (-not (Test-Path -Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory -Force
            }
    
            #Set Acl for each file if exists
            if ((Test-Path -Path $destFilePath) -and (-not $_.PSIsContainer)) {
                $acl = Get-Acl $destFilePath
                $acl.SetOwner($adminAccount)
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($adminAccount, "FullControl", "Allow")
                $acl.SetAccessRule($accessRule)
                Set-Acl $destFilePath $acl | Out-Null
                copy-item -Path $_.FullName -Destination $destFilePath -Force | Out-Null
            }
            elseif (-not $_.PSIsContainer) {
                copy-item -Path $_.FullName -Destination $destFilePath -Force | Out-Null
            }
    
        }
  
        #Add registry keys
        Write-Host "Modifying WinPE registry settings..." -ForegroundColor Yellow
        # Load WinPE SYSTEM hive:
        Reg Load HKLM\WinPE "$peMount\Windows\System32\config\DEFAULT" > $null 2>&1

        # Show hidden files:
        Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v Hidden /t REG_DWORD /d 1 /f > $null 2>&1
        Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v ShowSuperHidden /t REG_DWORD /d 1 /f > $null 2>&1

        # Show file extensions:
        Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v HideFileExt /t REG_DWORD /d 0 /f > $null 2>&1

        # Unload Hive:
        Reg Unload HKLM\WinPE > $null 2>&1

        # Add the needed components to it
        foreach ($Component in $OptionalComponents) {
            $Path = "{0}.cab" -f (Join-Path -Path $PackagePath -ChildPath $Component)
            "Adding $Component"
            Add-WindowsPackage -Path $peMount -PackagePath $Path
        }

        # Inject any needed drivers
        if ($(Test-IsDirectoryEmpty $winPEdrivers)) {
            Add-WindowsDriver -Path $peMount -Driver $winPEdrivers -Recurse
        }

        # Inject any needed update
        if ($(Test-IsDirectoryEmpty $winPEupdates)) {
            Get-ChildItem $winPEupdates | ForEach-Object { 
                Add-WindowsPackage -Path $peMount -PackagePath $_.FullName
            }
        }

        # Unmount and commit
        Dismount-WindowsImage -Path $peMount -Save
        Remove-Item $peMount -Recurse

        # Report completion
        Write-Host "Windows PE generated: $peNew" -ForegroundColor Green

        #endregion
    }

    #region IUD Data folder

    # Create the initial $iuc object with DownloadPath
    $iuc = [PSCustomObject]@{
        DataPath = $dataPath
    }

    # Update the $iuc object with additional paths
    $iuc | Add-Member -MemberType NoteProperty -Name "WinPEPath" -Value (Join-Path -Path $iuc.DataPath -ChildPath "WinPE")
    $iuc | Add-Member -MemberType NoteProperty -Name "ScriptsPath" -Value (Join-Path -Path $iuc.DataPath -ChildPath "WinPE\Scripts")
    $iuc | Add-Member -MemberType NoteProperty -Name "DriversPath" -Value (Join-Path -Path $iuc.DataPath -ChildPath "Drivers")
    $iuc | Add-Member -MemberType NoteProperty -Name "PackagesPath" -Value (Join-Path -Path $iuc.DataPath -ChildPath "Packages")
    $iuc | Add-Member -MemberType NoteProperty -Name "WIMPath" -Value (Join-Path -Path $iuc.DataPath -ChildPath "Images")


    foreach ($property in $iuc.PSObject.Properties) {
        $path = $property.Value
        if (!(Test-Path $path -ErrorAction SilentlyContinue)) {
            New-Item $path -ItemType Directory -Force | Out-Null
        }
    }

    #COPY WINPE Data
    copy-item -Path "$pePath\*" -Destination $iuc.WinPEPath -Recurse -ErrorAction:Ignore

    #COPY Scripts Data
    copy-item -Path "$downloadPath\SCRIPT\*" -Destination $iuc.ScriptsPath -Recurse -ErrorAction:Ignore

    # Define the main script file path
    $scriptPath = Join-Path -Path $iuc.ScriptsPath -ChildPath "Invoke-Provision.ps1"

    # Check if the file exists
    if (-not (Test-Path -Path $scriptPath)) {
        Write-Error "The file 'Invoke-Provision.ps1' does not exist at the specified path: $scriptPath"
        exit 1
    }

    # Read the file content if it exists
    $scriptContent = Get-Content -Path $scriptPath -Raw

    # Replace the placeholder values with the new values
    $scriptContent = $scriptContent.Replace("@GRAPHSECRET", [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($graphsecret)))
    $scriptContent = $scriptContent.Replace("@GRAPHCLIENTID", [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($graphclientid)))
    $scriptContent = $scriptContent.Replace("@TENANTID", [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($tenantid)))
    $scriptContent = $scriptContent.Replace("@WELCOMEBANNER", $iudwelcomebanner)
    $scriptContent = $scriptContent.Replace("@GROUPTAG", $grouptag)

    # Save the updated content back to the script
    Set-Content -Path "$($iuc.ScriptsPath)\Invoke-Provision.ps1" -Value $scriptContent

    # CHECK IUC CONFIG
    if (Test-Path "$dataPath\IUC-log.json") {
        $IUClog = Get-Content -Path "$dataPath\IUC-log.json" | ConvertFrom-Json -Depth 20
    
        # Verify all required properties exist and add them if missing
        $requiredProperties = @('installdate', 'scriptversion', 'isosize', 'winversion', 'wimdate', 'wimsize', 'pwshversion', 'pwshid')
        foreach ($property in $requiredProperties) {
            if (-not $IUClog.PSObject.Properties.Match($property)) {
                $IUClog | Add-Member -MemberType NoteProperty -Name $property -Value ""
            }
        }
    
        # Update properties
        $IUClog.installdate = get-date
        $IUClog.scriptversion = $iucversion
    }
    else {
        $IUClog = [PSCustomObject]@{
            installdate   = get-date
            scriptversion = $iucversion
            isosize       = ""
            winversion    = ""
            wimdate       = ""
            wimsize       = ""
            pwshversion   = ""
            pwshid        = ""
        }
    }

    #region download powershell
    try {
        #Find latest Powershell Version
        $latestpwsh = Invoke-RestMethod -Uri "https://api.github.com/repos/powershell/powershell/releases/latest"
        $pwshPath = "$($iuc.ScriptsPath)\pwsh"
        $pwshZip = "$env:Temp\pwsh.zip"

        #Do we already have the lastest version?
        if (!(Test-Path -Path $pwshPath) -or $IUClog.pwshid -ne $latestpwsh.id -or $force) {
            $IUClog.pwshversion = $latestpwsh.tag_name
            $IUClog.pwshid = $latestpwsh.id
            $latestpwshUrl = Invoke-RestMethod -Uri $latestpwsh.assets_url | ForEach-Object { $_.browser_download_url -like "*-win-x64.zip" }

            Write-Host "`nGrabbing PowerShell... " -ForegroundColor Yellow -NoNewline
            if (Test-Path -Path $pwshPath) {
                Remove-Item -Path $pwshPath -Recurse
            }
            Invoke-RestMethod -Method Get -Uri $latestpwshUrl -OutFile $pwshZip
            Expand-Archive -Path $pwshZip -DestinationPath $pwshPath
            Remove-Item -Path $pwshZip
            Write-Host $([char]0x221a) -ForegroundColor Green
        }
        else {
            Write-Host "`nPowerShell version the same" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "No PowerShell version found" -ForegroundColor Red
        $IUClog.pwshversion = ""
        $IUClog.pwshid = ""
    }
    #endregion

    #region get iso
    # Find Windows ISO Path
    while (-not $windowsIsoPath -or -not (Test-Path -Path $windowsIsoPath.Trim('"') -ErrorAction SilentlyContinue)) {
        if (!$windowsIsoPath) {
            Write-Host "Enter the path to the Windows ISO: " -ForegroundColor Yellow -NoNewLine
            $windowsIsoPath = Read-Host
        }
        else {
            Write-Host "The path '$windowsIsoPath' does not exist. Please enter a valid path." -ForegroundColor Red
            Write-Host "Enter the path to the Windows ISO: " -ForegroundColor Yellow -NoNewLine
            $windowsIsoPath = Read-Host
        }
    }

    # Get the ISO size
    $isosize = Get-Item -Path $windowsIsoPath.Trim('"')
    #endregion

    #region get wim and imageindex from ISO

    if (($isosize.Length -ne $IUClog.isosize) -or !(Test-Path "$($iuc.WIMPath)\install.wim") -or $force) {

        Write-Host "`nGetting install.wim from windows media... " -ForegroundColor Yellow -NoNewline
    
        if (Test-Path "$($iuc.WIMPath)\install.wim") {
            Remove-Item -Path "$($iuc.WIMPath)\install.wim" -Force
        }

        Get-WimFromIso -isoPath $windowsIsoPath -wimDestination $iuc.WIMPath
    
        #get image index from wim
        if ($imageIndex) {
            @{
                "ImageIndex" = $imageIndex
            } | ConvertTo-Json -Depth 20 | Out-File "$($iuc.WIMPath)\imageIndex.json"
        }
        else {
            Write-Host "`nGetting image index from install.wim... " -ForegroundColor Yellow
            Get-ImageIndexFromWim -wimPath "$($iuc.WIMPath)\install.wim" -destination $iuc.WIMPath
            $IUClog.winversion = Get-Content "$($iuc.WIMPath)\imageIndex.json" | ConvertFrom-Json -Depth 100 | Select-Object $_.ImageName
        }
        $IUClog.isosize = Get-Item -Path $windowsIsoPath
        $wimfile = Get-Item -Path "$($iuc.WIMPath)\install.wim"
        $IUClog.wimdate = $wimfile.CreationTime
        $IUClog.wimsize = $wimfile.Length
        $IUClog.isosize = $isosize.Length
    }
    else {
        Write-Host "Same Windows image" -ForegroundColor Yellow
    }
    #endregion

    #We are done
    $IUClog | ConvertTo-Json | Set-Content -Path "$dataPath\IUC-log.json" -Encoding utf8
    #end region

    do {
        $response = $(Write-Host "Ready to Create USB Stick (Y/N) " -ForegroundColor Yellow -NoNewLine; Read-Host)
        $response = $response.ToLower()
    } until ($response -eq "y" -or $response -eq "n" -or $response -eq "yes" -or $response -eq "no")
    
    if ($response -eq "n" -or $response -eq "no") {
        Write-Host "Skipping creating USB stick" -ForegroundColor Yellow       
        Exit
    }
    else {
        #Continue
    }

}
#region usb class
class ImageUSBClass {
    [string]$DataPath = $null
    [string]$Drive = $null
    [string]$DirName = "WinPE"
    [string]$Drive2 = $null
    [string]$DirName2 = "Images"
    [string]$WinPEPath = $null
    [string]$WIMPath = $null
    [string]$WIMFilePath = $null
    [string]$ImageIndexFilePath = $null
    [string]$DriversPath = $null
    [string]$PackagesPath = $null
    ImageUSBClass ([string]$dataPath = $null) {
        $this.DataPath = (Get-Item -Path $dataPath).FullName
        if (!(Test-Path $this.DataPath -ErrorAction SilentlyContinue)) {
            Write-Error -Message "Failed to find Intune USB Deployment Data!, run Publish-ImageToUSB.ps1 -createDataFolder"
            Exit
        }
        $this.WinPEPath = Join-Path $this.DataPath -ChildPath "WinPE"
        $this.DriversPath = Join-Path $this.DataPath -ChildPath "Drivers"
        $this.PackagesPath = Join-Path $this.DataPath -ChildPath "Packages"
        $this.WIMPath = Join-Path $this.DataPath -ChildPath "Images"
        $this.WIMFilePath = "$($this.DataPath)\Images\install.wim"
        $this.ImageIndexFilePath = "$($this.DataPath)\Images\imageIndex.json"
    }
}

#endregion

#region Main Process
try {
    #region start // show welcome
    Clear-Host
    $errorMsg = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $welcomebanner = "ICAgIOKWiOKWiOKVl+KWiOKWiOKWiOKVlyAgIOKWiOKWiOKVl+KWiOKWiOKWiOKWiOKWiOKWiOKWiOKWiOKVl+KWiOKWiOKVlyAgIOKWiOKWiOKVl+KWiOKWiOKWiOKVlyAgIOKWiOKWiOKVl+KWiOKWiOKWiOKWiOKWiOKWiOKWiOKVlyAgICAgCiAgICDilojilojilZHilojilojilojilojilZcgIOKWiOKWiOKVkeKVmuKVkOKVkOKWiOKWiOKVlOKVkOKVkOKVneKWiOKWiOKVkSAgIOKWiOKWiOKVkeKWiOKWiOKWiOKWiOKVlyAg4paI4paI4pWR4paI4paI4pWU4pWQ4pWQ4pWQ4pWQ4pWdICAgICAKICAgIOKWiOKWiOKVkeKWiOKWiOKVlOKWiOKWiOKVlyDilojilojilZEgICDilojilojilZEgICDilojilojilZEgICDilojilojilZHilojilojilZTilojilojilZcg4paI4paI4pWR4paI4paI4paI4paI4paI4pWXICAgICAgIAogICAg4paI4paI4pWR4paI4paI4pWR4pWa4paI4paI4pWX4paI4paI4pWRICAg4paI4paI4pWRICAg4paI4paI4pWRICAg4paI4paI4pWR4paI4paI4pWR4pWa4paI4paI4pWX4paI4paI4pWR4paI4paI4pWU4pWQ4pWQ4pWdICAgICAgIAogICAg4paI4paI4pWR4paI4paI4pWRIOKVmuKWiOKWiOKWiOKWiOKVkSAgIOKWiOKWiOKVkSAgIOKVmuKWiOKWiOKWiOKWiOKWiOKWiOKVlOKVneKWiOKWiOKVkSDilZrilojilojilojilojilZHilojilojilojilojilojilojilojilZcgICAgIAogICAg4pWa4pWQ4pWd4pWa4pWQ4pWdICDilZrilZDilZDilZDilZ0gICDilZrilZDilZ0gICAg4pWa4pWQ4pWQ4pWQ4pWQ4pWQ4pWdIOKVmuKVkOKVnSAg4pWa4pWQ4pWQ4pWQ4pWd4pWa4pWQ4pWQ4pWQ4pWQ4pWQ4pWQ4pWdICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAg4paI4paI4pWXICAg4paI4paI4pWX4paI4paI4paI4paI4paI4paI4paI4pWX4paI4paI4paI4paI4paI4paI4pWXICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICDilojilojilZEgICDilojilojilZHilojilojilZTilZDilZDilZDilZDilZ3ilojilojilZTilZDilZDilojilojilZcgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAg4paI4paI4pWRICAg4paI4paI4pWR4paI4paI4paI4paI4paI4paI4paI4pWX4paI4paI4paI4paI4paI4paI4pWU4pWdICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgIOKWiOKWiOKVkSAgIOKWiOKWiOKVkeKVmuKVkOKVkOKVkOKVkOKWiOKWiOKVkeKWiOKWiOKVlOKVkOKVkOKWiOKWiOKVlyAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICDilZrilojilojilojilojilojilojilZTilZ3ilojilojilojilojilojilojilojilZHilojilojilojilojilojilojilZTilZ0gICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgIOKVmuKVkOKVkOKVkOKVkOKVkOKVnSDilZrilZDilZDilZDilZDilZDilZDilZ3ilZrilZDilZDilZDilZDilZDilZ0gICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAog4paI4paI4paI4paI4paI4paI4pWX4paI4paI4paI4paI4paI4paI4pWXIOKWiOKWiOKWiOKWiOKWiOKWiOKWiOKVlyDilojilojilojilojilojilZcg4paI4paI4paI4paI4paI4paI4paI4paI4pWXIOKWiOKWiOKWiOKWiOKWiOKWiOKVlyDilojilojilojilojilojilojilZcgCuKWiOKWiOKVlOKVkOKVkOKVkOKVkOKVneKWiOKWiOKVlOKVkOKVkOKWiOKWiOKVl+KWiOKWiOKVlOKVkOKVkOKVkOKVkOKVneKWiOKWiOKVlOKVkOKVkOKWiOKWiOKVl+KVmuKVkOKVkOKWiOKWiOKVlOKVkOKVkOKVneKWiOKWiOKVlOKVkOKVkOKVkOKWiOKWiOKVl+KWiOKWiOKVlOKVkOKVkOKWiOKWiOKVlwrilojilojilZEgICAgIOKWiOKWiOKWiOKWiOKWiOKWiOKVlOKVneKWiOKWiOKWiOKWiOKWiOKVlyAg4paI4paI4paI4paI4paI4paI4paI4pWRICAg4paI4paI4pWRICAg4paI4paI4pWRICAg4paI4paI4pWR4paI4paI4paI4paI4paI4paI4pWU4pWdCuKWiOKWiOKVkSAgICAg4paI4paI4pWU4pWQ4pWQ4paI4paI4pWX4paI4paI4pWU4pWQ4pWQ4pWdICDilojilojilZTilZDilZDilojilojilZEgICDilojilojilZEgICDilojilojilZEgICDilojilojilZHilojilojilZTilZDilZDilojilojilZcK4pWa4paI4paI4paI4paI4paI4paI4pWX4paI4paI4pWRICDilojilojilZHilojilojilojilojilojilojilojilZfilojilojilZEgIOKWiOKWiOKVkSAgIOKWiOKWiOKVkSAgIOKVmuKWiOKWiOKWiOKWiOKWiOKWiOKVlOKVneKWiOKWiOKVkSAg4paI4paI4pWRCiDilZrilZDilZDilZDilZDilZDilZ3ilZrilZDilZ0gIOKVmuKVkOKVneKVmuKVkOKVkOKVkOKVkOKVkOKVkOKVneKVmuKVkOKVnSAg4pWa4pWQ4pWdICAg4pWa4pWQ4pWdICAgIOKVmuKVkOKVkOKVkOKVkOKVkOKVnSDilZrilZDilZ0gIOKVmuKVkOKVnQ=="
    Write-Host `n$([system.text.encoding]::UTF8.GetString([system.convert]::FromBase64String($welcomebanner)))

    #endregion
    #region set usb class
    Write-Host "`nSetting up configuration paths..." -ForegroundColor Yellow
    $usb = [ImageUSBClass]::new($dataPath)
    #endregion
    #region choose and partition USB
    Write-Host "`nConfiguring USB..." -ForegroundColor Yellow

    $chooseDisk = Get-DiskToUse
    
    $usb = Set-USBPartition -usbClass $usb -diskNum $chooseDisk

    #endregion
    #region write WinPE to USB
    Write-Host "`nWriting WinPE to USB..." -ForegroundColor Yellow -NoNewline
    Write-ToUSB -Path "$($usb.winPEPath)\*" -Destination "$($usb.drive):\"
    #endregion
    #region write Install.wim to USB
    Write-Host "`nWriting Install.wim to USB..." -ForegroundColor Yellow -NoNewline
    Write-ToUSB -Path $usb.WIMPath -Destination "$($usb.drive2):\"
    #endregion
      
    #region Create drivers folder
    Write-Host "`nSetting up folder structures for Drivers..." -ForegroundColor Yellow -NoNewline
    New-Item -Path "$($usb.drive2):\Drivers" -ItemType Directory -Force | Out-Null

    Write-Host "`nWriting Drivers to USB..." -ForegroundColor Yellow -NoNewline
    Write-ToUSB -Path "$($usb.DriversPath)\*" -Destination "$($usb.drive2):\Drivers"
    #endregion
		
    #region Create packages folder
    Write-Host "`nSetting up folder structures for Packages..." -ForegroundColor Yellow -NoNewline
    New-Item -Path "$($usb.drive2):\Packages" -ItemType Directory -Force | Out-Null

    Write-Host "`nWriting Packages to USB..." -ForegroundColor Yellow -NoNewline
    Write-ToUSB -Path "$($usb.PackagesPath)\*" -Destination "$($usb.drive2):\Packages"
    #endregion
		
    $completed = $true
}
catch {
    $errorMsg = $_.Exception.Message
}
finally {
    $sw.Stop()
    if ($errorMsg) {
        Write-Warning $errorMsg
    }
    else {
        if ($completed) {
            Write-Host "`nUSB Image built successfully..`nTime taken: $($sw.Elapsed)" -ForegroundColor Green
        }
        else {
            Write-Host "`nScript stopped before completion..`nTime taken: $($sw.Elapsed)" -ForegroundColor Green
        }
    }
}
#endregion