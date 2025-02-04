<#
.SYNOPSIS
  Prepare and creates WinPE media and WinPE Image
.DESCRIPTION
 
#Instructions

Download adkwinpesetup.exe from https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
run for example .\adkwinpesetup.exe /quiet /installpath C:\temp\adk\adkoffline\
this will give you these paths
"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\Media\winpe.wim"
"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us"
"C:\Temp\adk\adkoffline\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"

If you need winpe drivers for certain machines there is available
Dell: https://www.dell.com/support/kbdoc/en-us/000107478/dell-command-deploy-winpe-driver-packs
Lenovo: https://support.lenovo.com/us/en/solutions/ht074984-microsoft-system-center-configuration-manager-sccm-and-microsoft-deployment-toolkit-mdt-package-index
HP: https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HP_WinPE_DriverPack.html

If you need to include drivers and updates specify paths

.NOTES
  Version:        0.1
  Author:         SuperDOS
  Creation Date:  2025-02-04
  Purpose/Change: Initial script development
.EXAMPLE
New-WinPEMedia.ps1 -wimpath "...\winpe.wim" -packagepath "...\WinPE_OCs" -winpemedia "...\Media" -driverspath "...\winpedrivers"
#>

param (
    [Parameter(Mandatory = $false)][string]$wimpath,
    [Parameter(Mandatory = $false)][string]$packagepath,
    [parameter(Mandatory = $false)][string]$winpemedia,
    [Parameter(Mandatory = $false)][string]$driverspath,
    [Parameter(Mandatory = $false)][string]$updatespath
)

$newWIMPath = ".\WinPE-Media\sources\boot.wim"
$pePath = ".\WinPE-Media"
$peFiles = ".\pe-files"

#These are needed for IUC
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
        Set-Acl $destFilePath $acl
        copy-item -Path $_.FullName -Destination $destFilePath -Force
    }
    elseif (-not $_.PSIsContainer) {
        copy-item -Path $_.FullName -Destination $destFilePath -Force
    }
    
}
  
# Add the needed components to it
foreach ($Component in $OptionalComponents) {
    $Path = "{0}.cab" -f (Join-Path -Path $PackagePath -ChildPath $Component)
    "Adding $Component"
    Add-WindowsPackage -Path $peMount -PackagePath $Path
}

# Inject any needed drivers
if ($PSBoundParameters.ContainsKey("DriversDirectory")) {
    Add-WindowsDriver -Path $peMount -Driver $driverspath -Recurse
}

# Inject any needed update
if ($PSBoundParameters.ContainsKey("UpdatesDirectory")) {
    Get-ChildItem $updatespath | ForEach-Object { 
        Add-WindowsPackage -Path $peMount -PackagePath $_.FullName
    }
}

# Unmount and commit
Dismount-WindowsImage -Path $peMount -Save
Remove-Item $peMount -Recurse

# Report completion
Write-Host "Windows PE generated: $peNew" -ForegroundColor Green