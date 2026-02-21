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
  
  You also will need to get a Windows 11 iso for extraction of install.wim, path to the iso can be defined in GLOBAL_PARAM.json if not you will be prompted.
  This script will download latest powershell
  
  In the \_GLOBAL_PARAM\GLOBAL_PARAM.json you will need do define infromation from your enterprise app  GraphSecret, GraphClientID, TenantID
  Optional is to define the USB-welcomescreen which is the banner that is shown when the Intune USB Deployment is starting
  If you want to use you own welcome banner you can use [https://www.asciiart.eu/text-to-ascii-art](https://www.asciiart.eu/text-to-ascii-art) and then encode it to base64
  
  For WiFi support with WinRE (when using -useWinRE), configure these optional parameters in GLOBAL_PARAM.json:
  - wifissid: Your WiFi network SSID
  - wifipwd: Your WiFi network password
  - wifisecuritytype: Your WiFi security type (e.g. WPA2PSK, WPA3SAE)
  WiFi configuration is automatically applied when using WinRE boot media.
  
.PARAMETER createDataFolder
  Prepares the data folder with WinPE/WinRE customizations before creating the USB stick
.PARAMETER force
  Forces rebuild of WinPE media and re-extraction of files even if they already exist
.PARAMETER useWinRE
  Extract and use WinRE.wim from the Windows install.wim instead of using WinPE.wim from ADK.
  WinRE will be extracted from the same image index specified in GLOBAL_PARAM.json
  
.NOTES
  Version:       1.0
  Credits:        SuperDOS / Ben R. / CloudOSD
  Creation Date:  2026-02-09
  Purpose/Change: Added WinRE support as alternative to WinPE
.EXAMPLE
  .\Publish-ImageToUSB.ps1 -createDataFolder
  Creates the data folder using default WinPE from Windows ADK
.EXAMPLE
  .\Publish-ImageToUSB.ps1 -createDataFolder -useWinRE
  Creates the data folder using WinRE.wim extracted from the Windows install.wim
.EXAMPLE
  .\Publish-ImageToUSB.ps1
  Creates the USB stick from previously prepared data
#>
[CmdletBinding(PositionalBinding = $false)]
param (
    [Parameter(Mandatory = $false)][switch]$createDataFolder,
    [Parameter(Mandatory = $false)][switch]$force,
    [Parameter(Mandatory = $false)][switch]$useWinRE
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

#region Validate and load deployment share for USB creation
if (!$createDataFolder) {
    # Check if data folder exists and is not empty
    if ($(Test-IsDirectoryEmpty $dataPath).IsEmpty -eq $true) {
        Write-Host "`nNo Intune USB Creator Data Found" -ForegroundColor Red
        Write-Host "Please run: .\Publish-ImageToUSB.ps1 -createDataFolder" -ForegroundColor Yellow
        Return
    }
    
    # Load deployment metadata
    Write-Host "`n=== Loading Deployment Configuration ===" -ForegroundColor Magenta
    
    $iucLogPath = Join-Path $dataPath "IUC-log.json"
    if (Test-Path $iucLogPath) {
        try {
            $IUClog = Get-Content -Path $iucLogPath | ConvertFrom-Json -Depth 20
            
            # Determine deployment type
            if ($IUClog.PSObject.Properties.Match('deploymentType') -and $IUClog.deploymentType) {
                if ($IUClog.deploymentType -eq "WinRE") {
                    $useWinRE = $true
                }
                
                Write-Host "Deployment Type: $($IUClog.deploymentType)" -ForegroundColor Cyan
                if ($IUClog.imageindex) {
                    Write-Host "Windows Edition: Index $($IUClog.imageindex)" -ForegroundColor Cyan
                }
                if ($IUClog.winversion) {
                    Write-Host "Version: $($IUClog.winversion)" -ForegroundColor Cyan
                }
                Write-Host "Built: $($IUClog.installdate)" -ForegroundColor Cyan
            }
            else {
                # Legacy deployment (before deploymentType was added)
                Write-Warning "Legacy deployment detected (no type metadata)"
                Write-Warning "Assuming WinPE deployment"
                $useWinRE = $false
            }
        }
        catch {
            Write-Error "Failed to load deployment metadata: $_"
            Write-Error "Deployment share may be corrupted"
            Return
        }
    }
    else {
        Write-Error "Deployment metadata not found: $iucLogPath"
        Write-Error "Please rebuild deployment share with -createDataFolder"
        Return
    }
    
    # Validate required files
    Write-Host "`nValidating deployment files..." -ForegroundColor Cyan
    
    $requiredFiles = @(
        @{ Path = "WinPE\sources\boot.wim"; Name = "Boot image" },
        @{ Path = "Images\install.wim"; Name = "Windows install image" },
        @{ Path = "WinPE\Scripts\Invoke-Provision.ps1"; Name = "Deployment script" },
        @{ Path = "WinPE\Scripts\Main.cmd"; Name = "Startup script" }
    )
    
    $missingFiles = @()
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $dataPath $file.Path
        if (-not (Test-Path $fullPath)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Error "`nDeployment share is incomplete! Missing files:"
        $missingFiles | ForEach-Object { Write-Error "  - $($_.Name): $($_.Path)" }
        Write-Error "`nPlease rebuild: .\Publish-ImageToUSB.ps1 -createDataFolder"
        Return
    }
    
    Write-Host "All required files present" -ForegroundColor Green
}
#endregion

if ($createDataFolder) {

    #region IUD Data folder - Create folder structure first
    
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
    
    # CHECK IUC CONFIG
    if (Test-Path "$dataPath\IUC-log.json") {
        $IUClog = Get-Content -Path "$dataPath\IUC-log.json" | ConvertFrom-Json -Depth 20
    
        # Verify all required properties exist and add them if missing
        $requiredProperties = @('installdate', 'scriptversion', 'isosize', 'winversion', 'wimdate', 'wimsize', 'pwshversion', 'pwshid', 'imageindex', 'deploymentType')
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
            installdate    = get-date
            scriptversion  = $iucversion
            isosize        = ""
            winversion     = ""
            wimdate        = ""
            wimsize        = ""
            pwshversion    = ""
            pwshid         = ""
            imageindex     = ""
            deploymentType = ""
        }
    }
    
    #endregion

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

    #region STEP 1: Get Windows ISO and extract install.wim
    Write-Host "`n=== STEP 1: Getting Windows install.wim ===" -ForegroundColor Magenta
    
    # Find Windows ISO Path
    $validIsoFound = $false
    while (-not $validIsoFound) {
        if (-not $windowsIsoPath) {
            Write-Host "Enter the path to the Windows ISO: " -ForegroundColor Yellow -NoNewLine
            $windowsIsoPath = Read-Host
        }

        # Remove quotes from path
        $windowsIsoPath = $windowsIsoPath.Trim('"').Trim("'")

        # Validate path exists
        if (-not (Test-Path -Path $windowsIsoPath -ErrorAction SilentlyContinue)) {
            Write-Host "The path '$windowsIsoPath' does not exist. Please enter a valid path." -ForegroundColor Red
            $windowsIsoPath = $null
            continue
        }

        # Validate it's an ISO file
        if (-not ($windowsIsoPath -like "*.iso")) {
            Write-Host "The file '$windowsIsoPath' is not an ISO file. Please provide a valid Windows ISO." -ForegroundColor Red
            $windowsIsoPath = $null
            continue
        }

        # Test ISO integrity by attempting to mount it
        try {
            Write-Host "Validating ISO file..." -ForegroundColor Cyan
            $testMount = Mount-DiskImage -ImagePath $windowsIsoPath -Access ReadOnly -PassThru -ErrorAction Stop
            Dismount-DiskImage -ImagePath $windowsIsoPath -ErrorAction Stop
            $validIsoFound = $true
            Write-Host "ISO validation successful" -ForegroundColor Green
        }
        catch {
            Write-Host "The ISO file appears to be corrupt or invalid: $($_.Exception.Message)" -ForegroundColor Red
            $windowsIsoPath = $null
            continue
        }
    }

    # Get the ISO size
    $isosize = Get-Item -Path $windowsIsoPath

    # Get wim and imageindex from ISO
    $needsReExtraction = $false
    
    # Check if we need to re-extract based on ISO size, missing file, force, or changed image index
    if ($force) {
        $needsReExtraction = $true
        Write-Verbose "Force flag set - will re-extract install.wim"
    }
    elseif (!(Test-Path "$($iuc.WIMPath)\install.wim")) {
        $needsReExtraction = $true
        Write-Verbose "install.wim not found - will extract"
    }
    elseif ($isosize.Length -ne $IUClog.isosize) {
        $needsReExtraction = $true
        Write-Verbose "ISO size changed - will re-extract install.wim"
    }
    elseif (Test-Path "$($iuc.WIMPath)\imageIndex.json") {
        # Check if image index has changed
        $currentIndex = (Get-Content "$($iuc.WIMPath)\imageIndex.json" | ConvertFrom-Json).ImageIndex
        if ($imageIndex -and $currentIndex -ne $imageIndex) {
            $needsReExtraction = $true
            Write-Host "Image index changed ($currentIndex → $imageIndex) - will re-extract install.wim" -ForegroundColor Yellow
        }
    }
    
    if ($needsReExtraction) {

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
        Write-Host "Using existing install.wim (same ISO and image index)" -ForegroundColor Yellow
        $wimfile = Get-Item -Path "$($iuc.WIMPath)\install.wim"
    }
    
    # Read the selected image index for WinRE extraction
    $selectedImageIndex = (Get-Content "$($iuc.WIMPath)\imageIndex.json" | ConvertFrom-Json).ImageIndex
    Write-Host "Selected Windows Image Index: $selectedImageIndex" -ForegroundColor Cyan
    
    #endregion

    #region STEP 2: Extract WinRE from install.wim if requested
    $extractedWinREPath = $null
    
    if ($useWinRE) {
        Write-Host "`n=== STEP 2: Extracting WinRE.wim from install.wim ===" -ForegroundColor Magenta
        
        # Create temp directory for WinRE extraction
        $winreTempPath = Join-Path $downloadPath "WINRE_EXTRACTED"
        if (-not (Test-Path $winreTempPath)) {
            New-Item -Path $winreTempPath -ItemType Directory -Force | Out-Null
        }
        
        # Check if WinRE was already extracted from the same install.wim
        $winreExtractedPath = Join-Path $winreTempPath "winre.wim"
        $winreLogPath = Join-Path $winreTempPath "extraction.json"
        $needsExtraction = $true
        
        if ((Test-Path $winreExtractedPath) -and (Test-Path $winreLogPath) -and -not $force) {
            try {
                $extractionLog = Get-Content $winreLogPath | ConvertFrom-Json
                
                # Check if it's from the same install.wim, image index, and WIM hasn't changed
                if ($extractionLog.wimsize -eq $wimfile.Length -and 
                    $extractionLog.wimdate -eq $wimfile.CreationTime -and
                    $extractionLog.imageindex -eq $selectedImageIndex) {
                    
                    Write-Host "Using previously extracted WinRE.wim (same source and index)" -ForegroundColor Green
                    $extractedWinREPath = $winreExtractedPath
                    $needsExtraction = $false
                }
                else {
                    # Log why we're re-extracting
                    if ($extractionLog.imageindex -ne $selectedImageIndex) {
                        Write-Host "Image index changed ($($extractionLog.imageindex) → $selectedImageIndex) - re-extracting WinRE.wim" -ForegroundColor Yellow
                    }
                    elseif ($extractionLog.wimsize -ne $wimfile.Length) {
                        Write-Host "install.wim size changed - re-extracting WinRE.wim" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "install.wim date changed - re-extracting WinRE.wim" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Verbose "Could not read extraction log, will re-extract: $_"
            }
        }
        
        if ($needsExtraction) {
            try {
                # Ensure WINPEFILES directory exists for WiFi DLLs
                $peFiles = Join-Path -Path $downloadPath -ChildPath "WINPEFILES"
                if (-not (Test-Path $peFiles)) {
                    New-Item -Path $peFiles -ItemType Directory -Force | Out-Null
                }
                
                # Extract WinRE from install.wim (also extracts WiFi DLLs)
                $extractedWinREPath = Get-WinREFromInstallWim `
                    -InstallWimPath "$($iuc.WIMPath)\install.wim" `
                    -ImageIndex $selectedImageIndex `
                    -Destination $winreTempPath `
                    -WinPEFilesPath $peFiles
                
                if ($extractedWinREPath -and (Test-Path $extractedWinREPath)) {
                    # Save extraction log for caching
                    $extractionInfo = @{
                        wimsize     = $wimfile.Length
                        wimdate     = $wimfile.CreationTime
                        imageindex  = $selectedImageIndex
                        extractdate = Get-Date
                    }
                    $extractionInfo | ConvertTo-Json | Set-Content -Path $winreLogPath
                    
                    Write-Host "WinRE.wim successfully extracted and will be used for boot media" -ForegroundColor Green
                }
                else {
                    Write-Warning "Failed to extract WinRE.wim - falling back to WinPE"
                    $useWinRE = $false
                }
            }
            catch {
                Write-Warning "Error extracting WinRE.wim: $($_.Exception.Message)"
                Write-Host "Falling back to WinPE.wim..." -ForegroundColor Yellow
                $useWinRE = $false
            }
        }
    }
    else {
        Write-Host "`n=== STEP 2: Skipping WinRE extraction (using WinPE) ===" -ForegroundColor Magenta
    }
    
    #endregion

    #region STEP 3: Build WinPE or WinRE boot media
    Write-Host "`n=== STEP 3: Building boot media ===" -ForegroundColor Magenta

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
            Remove-item -Path $pePath -Recurse -Force
        }
    }
    else {
        $buildwinpemedia = $true
    }
    
    if ($buildwinpemedia) {
           
        #region Check for WinRE.wim - use extracted if available
        $sourceWimPath = $null
        
        if ($useWinRE -and $extractedWinREPath -and (Test-Path $extractedWinREPath)) {
            Write-Host "`nUsing extracted WinRE.wim from install.wim" -ForegroundColor Green
            $sourceWimPath = $extractedWinREPath
        }
        #endregion
           
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
            $winpemedia = "$winPEpath\Media\"
            $packagepath = "$winPEpath\WinPE_OCs\"
            
            if ($useWinRE) {
                Write-Host "ADK found - using WinRE.wim with optional components available" -ForegroundColor Green
            }
            else {
                $sourceWimPath = "$winPEpath\en-us\winpe.wim"
                Write-Host "ADK found - using WinPE.wim from ADK" -ForegroundColor Green
            }
        }
        else {
            Write-Warning "Windows PE ADK Not Found, Please Install"
            return
        }
        #endregion

        #These are needed for Intune USB Deployment
        $OptionalComponents = @("WinPE-WDS-Tools", "WinPE-Scripting", "WinPE-WMI", "WinPE-SecureStartup", "WinPE-NetFx", "WinPE-PowerShell", "WinPE-StorageWMI", "WinPE-DismCmdlets")
        
        # Copy the winpe media (copy only essential boot files for both WinPE and WinRE)
        if ($winpemedia -and (Test-Path $winpemedia)) {
            Write-Host "Copying boot files..." -ForegroundColor Cyan
            
            # Create destination if it doesn't exist
            if (-not (Test-Path $pePath)) {
                New-Item -Path $pePath -ItemType Directory -Force | Out-Null
            }
            
            # Copy only essential boot files (bootmgr, bootmgr.efi, boot folder)
            # No need to copy language files and other media that aren't needed
            $bootFiles = @("bootmgr", "bootmgr.efi", "boot", "EFI")
            $copiedFiles = 0
            
            foreach ($bootFile in $bootFiles) {
                $sourcePath = Join-Path $winpemedia $bootFile
                if (Test-Path $sourcePath) {
                    Copy-Item -Path $sourcePath -Destination $pePath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Verbose "  Copied: $bootFile"
                    $copiedFiles++
                }
            }
            
            if ($copiedFiles -gt 0) {
                if ($useWinRE) {
                    Write-Host "Essential boot files copied for WinRE ($copiedFiles/$($bootFiles.Count))" -ForegroundColor Green
                }
                else {
                    Write-Host "Essential boot files copied for WinPE ($copiedFiles/$($bootFiles.Count))" -ForegroundColor Green
                }
            }
            else {
                Write-Warning "No boot files found in ADK media - USB may not be bootable"
            }
        }
        else {
            Write-Warning "ADK media not found at $winpemedia"
        }
        
        new-item -Path $pePath -Name "sources" -ItemType Directory -ErrorAction:Ignore

        # Validate source WIM path
        if (-not (Test-Path $sourceWimPath)) {
            if ($useWinRE) {
                Write-Error "WinRE.wim file does not exist at: $sourceWimPath" -ErrorAction "Stop"
            }
            else {
                Write-Error "WinPE.wim file does not exist at: $sourceWimPath" -ErrorAction "Stop"
            }
        }

        # Copy the source wim (either WinRE or WinPE)
        if ($useWinRE) {
            Write-Host "Copying WinRE.wim to boot.wim..." -ForegroundColor Cyan
        }
        else {
            Write-Host "Copying WinPE.wim to boot.wim..." -ForegroundColor Cyan
        }
        $peNew = Copy-Item -Path $sourceWimPath -Destination $newWIMPath -Force -PassThru

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
        try {
            Mount-WindowsImage -Path $peMount -ImagePath $newWIMPath -Index 1 | Out-Null
    
            # Delete winpeshl.ini if using WinRE (allows normal boot process)
            if ($useWinRE) {
                $winpeshlPath = Join-Path $peMount "Windows\System32\winpeshl.ini"
                if (Test-Path $winpeshlPath) {
                    Write-Host "Removing winpeshl.ini from WinRE for proper boot..." -ForegroundColor Cyan
                    Remove-Item -Path $winpeshlPath -Force
                }
            }
           
            # Add PE Files
            
            # Define the well-known SID for the Administrators group
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $adminAccount = $adminSid.Translate([System.Security.Principal.NTAccount])

            # Copy PE files with ownership handling
            Get-ChildItem $peFiles -Recurse | ForEach-Object {
                if ($_.PSIsContainer) { return }  # Skip directories
                
                # Calculate destination path
                $relativePath = $_.FullName.Substring((Get-Item $peFiles).FullName.Length)
                $destFilePath = Join-Path -Path $peMount -ChildPath $relativePath
                
                # Ensure destination directory exists
                $destDir = Split-Path -Path $destFilePath -Parent
                if (-not (Test-Path -Path $destDir)) {
                    New-Item -Path $destDir -ItemType Directory -Force | Out-Null
                }
                
                # Take ownership if file exists, then copy
                if (Test-Path -Path $destFilePath) {
                    Set-FileOwnership -FilePath $destFilePath -Owner $adminAccount | Out-Null
                }
                
                Copy-Item -Path $_.FullName -Destination $destFilePath -Force | Out-Null
            }
            
            # Configure custom background for WinRE
            if ($useWinRE) {
                $winpeJpgPath = "$peMount\Windows\System32\winpe.jpg"
                $winreJpgPath = "$peMount\Windows\System32\winre.jpg"
                
                if (Test-Path $winpeJpgPath) {
                    Write-Host "Configuring custom WinRE background..." -ForegroundColor Cyan
                    
                    # Remove existing winre.jpg (WinRE has a default one)
                    if (Test-Path $winreJpgPath) {
                        if (Set-FileOwnership -FilePath $winreJpgPath -Owner $adminAccount) {
                            Remove-Item -Path $winreJpgPath -Force -ErrorAction SilentlyContinue
                        }
                    }
                    
                    # Rename custom winpe.jpg to winre.jpg
                    Rename-Item -Path $winpeJpgPath -NewName "winre.jpg" -Force
                    Write-Host "Custom background configured for WinRE" -ForegroundColor Green
                }
            }

            #Registry modifications    
            try {
                Write-Host "Modifying WinPE registry settings..." -ForegroundColor Yellow
    
                # Load WinPE SYSTEM hive
                $regLoadResult = Reg Load HKLM\WinPE "$peMount\Windows\System32\config\DEFAULT" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to load registry hive: $regLoadResult"
                }
    
                try {
                    # Show hidden files
                    Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v Hidden /t REG_DWORD /d 1 /f > $null 2>&1
                    Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v ShowSuperHidden /t REG_DWORD /d 1 /f > $null 2>&1
                    
                    # Show file extensions
                    Reg Add HKLM\WinPE\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced /v HideFileExt /t REG_DWORD /d 0 /f > $null 2>&1
                }
                finally {
                    # Always attempt to unload
                    [gc]::Collect()
                    Start-Sleep -Milliseconds 500
                    $unloadResult = Reg Unload HKLM\WinPE 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Failed to unload registry hive on first attempt: $unloadResult"
                        # Retry after delay
                        Start-Sleep -Seconds 2
                        Reg Unload HKLM\WinPE 2>&1
                    }
                }
            }
            catch {
                Write-Error "Registry modification failed: $_"
                throw
            }

            # Add the needed components to it (only if we have package path)
            if ($packagepath -and (Test-Path $packagepath)) {
                foreach ($Component in $OptionalComponents) {
                    Write-Host "Adding $Component..." -ForegroundColor Cyan
                    Add-WinPEPackage -MountPath $peMount -Package $Component -PackagePath $packagepath
                }
            }
            elseif ($useWinRE) {
                Write-Host "Skipping optional components - ADK not available or WinRE already has required components" -ForegroundColor Yellow
            }
            else {
                Write-Warning "Package path not found - skipping optional components"
            }
        
            # Inject any needed drivers
            if ($(Test-IsDirectoryEmpty $winPEdrivers)) {
                "Adding Drivers..."
                Add-InjectedDrivers -MountPath $peMount -DriverPath $winPEdrivers
            }

            # Inject any needed update
            if ($(Test-IsDirectoryEmpty $winPEupdates)) {
                "Adding Updates..."
                Get-ChildItem $winPEupdates | ForEach-Object { 
                    Add-WinPEPackage -Path $peMount -PackagePath $_.FullName
                }
            }

            # Unmount and commit    
            Dismount-WindowsImage -Path $peMount -Save
        }
        catch {
            Write-Error "WinPE customization failed: $_"
            # Attempt cleanup
            try {
                Dismount-WindowsImage -Path $peMount -Discard -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Failed to dismount WinPE image. Manual cleanup may be required."
            }
            throw
        }
        finally {
            if (Test-Path $peMount) {
                Remove-Item $peMount -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
       
        # Report completion
        if ($useWinRE) {
            Write-Host "Boot image generated from WinRE.wim: $peNew" -ForegroundColor Green
        }
        else {
            Write-Host "Boot image generated from WinPE.wim: $peNew" -ForegroundColor Green
        }

        #endregion
    }

    #region STEP 4: Copy WinPE data and scripts
    Write-Host "`n=== STEP 4: Copying WinPE data and scripts ===" -ForegroundColor Magenta
    
    #COPY WINPE Data
    Write-Host "Copying WinPE media to data folder..." -ForegroundColor Cyan
    copy-item -Path "$pePath\*" -Destination $iuc.WinPEPath -Recurse -ErrorAction:Ignore

    #COPY Scripts Data
    Write-Host "Copying deployment scripts..." -ForegroundColor Cyan
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
    $scriptContent = $scriptContent.Replace("@TENANT", [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($tenant | ConvertTo-Json -Compress))))
    $scriptContent = $scriptContent.Replace("@WELCOMEBANNER", $iudwelcomebanner)

    # Save the updated content back to the script
    Set-Content -Path "$($iuc.ScriptsPath)\Invoke-Provision.ps1" -Value $scriptContent
    Write-Host "Scripts configured successfully" -ForegroundColor Green

    #endregion

    # Update deployment metadata in IUC-log
    $IUClog.imageindex = $selectedImageIndex
    $IUClog.deploymentType = if ($useWinRE) { "WinRE" } else { "WinPE" }
    
    #We are done - save IUC-log
    $IUClog | ConvertTo-Json | Set-Content -Path "$dataPath\IUC-log.json" -Encoding utf8
    Write-Host "`nDeployment share created: $($IUClog.deploymentType)" -ForegroundColor Green
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
    New-Item -Path "$($usb.drive):\WINPE.tag" -ItemType File -Force | Out-Null
    #endregion

    # Configure WiFi if this is a WinRE deployment
    if ($useWinRE) {
        Write-Host "`nConfiguring WiFi for WinRE deployment..." -ForegroundColor Cyan
        
        $scriptsPath = "$($usb.drive):\Scripts"
        
        # Configure Main.cmd - uncomment WiFi lines and replace SSID
        $mainCmdPath = Join-Path $scriptsPath "Main.cmd"
        if (Test-Path $mainCmdPath) {
            $mainCmdContent = Get-Content -Path $mainCmdPath -Raw
            
            # Replace WiFi SSID placeholder
            if (![string]::IsNullOrWhiteSpace($wifissid)) {
                # Update the WiFiEnabled variable
                $mainCmdContent = $mainCmdContent -replace 'SET WiFiEnabled=FALSE', 'SET WiFiEnabled=TRUE'

                # Uncomment WiFi lines (remove REM from start of lines)
                $mainCmdContent = $mainCmdContent -replace '(?m)^REM (net start wlansvc)', '$1'
                $mainCmdContent = $mainCmdContent -replace '(?m)^REM (netsh wlan add profile)', '$1'
                $mainCmdContent = $mainCmdContent -replace '(?m)^REM (netsh wlan connect)', '$1'
                $mainCmdContent = $mainCmdContent -replace '(?m)^REM (ping localhost)', '$1'
            
                # Replace SSID
                $mainCmdContent = $mainCmdContent.Replace("@WIFISSID", $wifissid)
            
                # Save changes
                Set-Content -Path $mainCmdPath -Value $mainCmdContent
                Write-Host "  - Main.cmd configured with WiFi SSID" -ForegroundColor Green
            }
            else {
                Write-Warning "  - WiFi SSID not configured in GLOBAL_PARAM.json"
                Write-Warning "    WiFi will not connect automatically"
            }
        
        }
        else {
            Write-Warning "  - Main.cmd not found - WiFi configuration skipped"
        }
        
        # Configure wificonf.xml - replace SSID and password
        $wifiConfPath = Join-Path $scriptsPath "wificonf.xml"
        if (Test-Path $wifiConfPath) {
            $wifiConfContent = Get-Content -Path $wifiConfPath -Raw
            
            # Replace WiFi placeholders    
            $replacements = @{
                "@WIFISSID" = $wifissid
                "@WIFIPWD"  = $wifipwd
                "@WIFISEC"  = if ($wifisecuritytype) { $wifisecuritytype } else { "WPA2PSK" }
            }

            $missing = @()
            $changed = $false

            foreach ($key in $replacements.Keys) {
                $value = $replacements[$key]

                if ([string]::IsNullOrWhiteSpace($value)) {
                    $missing += $key
                    continue
                }

                $wifiConfContent = $wifiConfContent.Replace($key, $value)
                $changed = $true
            }

            if ($missing.Count -gt 0) {
                Write-Warning "  - Missing WiFi parameters: $($missing -join ', ') in GLOBAL_PARAM.json"
            }

            if ($changed) {
                Set-Content -Path $wifiConfPath -Value $wifiConfContent
                Write-Host "  - wificonf.xml configured with credentials" -ForegroundColor Green
            }
            else {
                Write-Warning "  - WiFi configuration not updated (no valid values provided)"
            }

        }
        else {
            Write-Warning "  - wificonf.xml not found - WiFi may not work"
        }

    }

    #region write Install.wim to USB
    Write-Host "`nWriting Install.wim to USB..." -ForegroundColor Yellow -NoNewline
    Write-ToUSB -Path $usb.WIMPath -Destination "$($usb.drive2):\"
    #endregion
      
    #region Create drivers folder
    Write-Host "`nSetting up folder structures for Drivers..." -ForegroundColor Yellow -NoNewline
    New-Item -Path "$($usb.drive2):\Drivers" -ItemType Directory -Force | Out-Null
    New-Item -Path "$($usb.drive2):\DRIVERS.tag" -ItemType File -Force | Out-Null

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
