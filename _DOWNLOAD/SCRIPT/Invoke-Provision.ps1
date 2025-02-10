#region variables set by Publish-ImageToUSB.ps1 -createDataFolder from the GLOBAL_PARAM.json
$graphsecret = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("@GRAPHSECRET"))
$graphclientid = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("@GRAPHCLIENTID"))
$tenantid = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("@TENANTID"))
$welcomebanner = "@WELCOMEBANNER"
$groupTag = "@GROUPTAG"
#end region

#region Classes
class USBImage {
    [string]                    $winPEDrive = $null
    [string]                    $winPESource = $env:winPESource
    [PSCustomObject]            $volumeInfo = $null
    [string]                    $installPath = $null
    [string]                    $installRoot = $null
    [System.IO.DirectoryInfo]   $scratch = $null
    [string]                    $scRoot = $null
    [System.IO.DirectoryInfo]   $recovery = $null
    [string]                    $reRoot = $null
    [System.IO.DirectoryInfo]   $driverPath = $null
    [System.IO.DirectoryInfo]   $packagePath = $null
    [System.IO.DirectoryInfo]   $cuPath = $null
    [System.IO.DirectoryInfo]   $ssuPath = $null

    USBImage ([string]$winPEDrive) {
        $this.winPEDrive = $winPEDrive
        $this.volumeInfo = Get-DiskPartVolume -winPEDrive $winPEDrive
        $this.installRoot = (Find-InstallWim -volumeInfo $($this.volumeInfo)).DriveRoot
        $this.installPath = "$($this.installRoot)images"
        $this.cuPath = "$($this.installPath)\CU"
        $this.ssuPath = "$($this.installPath)\SSU"
        $this.driverPath = "$($this.installRoot)Drivers"
        $this.packagePath = "$($this.installRoot)Packages"
    }
    setScratch ([System.IO.DirectoryInfo]$scratch) {
        $this.scratch = $scratch
        [string]$this.scRoot = $scratch.Root
    }
    setRecovery ([System.IO.DirectoryInfo]$recovery) {
        $this.recovery = $recovery
        [string]$this.reRoot = $recovery.Root
    }
}
#endregion

#region Functions
function Get-GraphToken {
    param (
        [Parameter(Mandatory = $false)][string]$ClientID,
        [Parameter(Mandatory = $false)][string]$ClientSecret,
        [Parameter(Mandatory = $false)][string]$TenantID
    )

    # Create a hashtable for the body, the data needed for the token request
    $Body = @{
        'tenant'        = $TenantID;
        'client_id'     = $ClientID;
        'scope'         = 'https://graph.microsoft.com/.default';
        'client_secret' = $ClientSecret;
        'grant_type'    = 'client_credentials'
    }

    # Assemble a hashtable for splatting parameters, for readability
    $Params = @{
        'Uri'         = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
        'Method'      = 'Post'
        'Body'        = $Body
        'ContentType' = 'application/x-www-form-urlencoded'
    }

    $tokenauth = Invoke-RestMethod @Params
    $token = $tokenauth.access_token
    $token
}
function Add-AutopilotImportedDevice {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)] $serialNumber,
        [Parameter(Mandatory = $true)] $hardwareIdentifier
    )

    # Get Token
    $access_token = Get-GraphToken -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid

    # Create required variables
    $URI = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $Body = @{ "serialNumber" = "$serialNumber"; "hardwareIdentifier" = "$hardwareIdentifier" } | ConvertTo-Json

    try {
        Invoke-RestMethod `
            -Uri $URI `
            -Headers @{"Authorization" = "Bearer $access_token" } `
            -ContentType 'application/json' `
            -Body  $Body `
            -Method POST
    }
    catch {
        Write-Error $_.Exception
    }
}
function Set-AutopilotDevice {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $True)] $id,
        [Parameter(Mandatory = $true)] $displayName,
        [Parameter(Mandatory = $false)] [Alias("orderIdentifier")] $groupTag = ""
    )

    # Get Token
    $access_token = Get-GraphToken -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/windowsAutopilotDeviceIdentities"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$id/UpdateDeviceProperties"
    $Body = @{ "displayName" = "$displayName"; "groupTag" = "$groupTag" } | ConvertTo-Json

    try {
        Invoke-RestMethod `
            -Uri $uri `
            -Headers @{"Authorization" = "Bearer $access_token" } `
            -ContentType 'application/json' `
            -Body  $Body `
            -Method POST
    }
    catch {
        Write-Error $_.Exception
    }
}
function Get-windowsAutopilotDevice {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false)] $id,
        [Parameter(Mandatory = $false)] $serialNumber
    )

    # Defining Variables
    $graphApiVersion = "v1.0"

    if ($id) {
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/windowsAutopilotDeviceIdentities/$id"
    }
    elseif ($serialNumber) {
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber, '$serialNumber')"
    }
    else {
        $uri = "https://graph.microsoft.com/$graphApiVersion/deviceManagement/windowsAutopilotDeviceIdentities"
    }

    # Get Token
    $access_token = Get-GraphToken -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid

    try {
        $response = Invoke-RestMethod `
            -Uri $uri `
            -Headers @{"Authorization" = "Bearer $access_token" } `
            -ContentType 'application/json' `
            -Method GET
        if ($id) {
            $response
        }
        else {
            $devices = $response.value
            $devicesNextLink = $response."@odata.nextLink"

            while ($null -ne $devicesNextLink) {
                $devicesResponse = Invoke-RestMethod `
                    -Uri $devicesNextLink `
                    -Headers @{"Authorization" = "Bearer $access_token" } `
                    -Method Get
                $devicesNextLink = $devicesResponse."@odata.nextLink"
                $devices += $devicesResponse.value
            }
            $devices
        }
    }
    catch {
        Write-Error $_.Exception
    }
}
function Set-PowerPolicy {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerSaver', 'Balanced', 'HighPerformance')]
        [string]$powerPlan
    )
    try {
        switch ($powerPlan) {
            PowerSaver {
                Write-Host "Setting power policy to 'Power Saver'.." -ForegroundColor Cyan
                $planGuid = "a1841308-3541-4fab-bc81-f71556f20b4a"
            }
            Balanced {
                Write-Host "Setting power policy to 'Balanced Performance'.." -ForegroundColor Cyan
                $planGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"
            }
            HighPerformance {
                Write-Host "Setting power policy to 'High Performance'.." -ForegroundColor Cyan
                $planGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            }
            default {
                throw "Incorrect selection.."
            }
        }
        Invoke-CmdLine -application powercfg -argumentList "/s $planGuid" -silent
    }
    catch {
        throw $_
    }
}
function Test-IsUEFI {
    try {
        $pft = Get-ItemPropertyValue -Path HKLM:\SYSTEM\CurrentControlSet\Control -Name 'PEFirmwareType'
        switch ($pft) {
            1 {
                Write-Host "BIOS Mode detected.." -ForegroundColor Cyan
                return "BIOS"
            }
            2 {
                Write-Host "UEFI Mode detected.." -ForegroundColor Cyan
                return "UEFI"
            }
            Default {
                Write-Host "BIOS / UEFI undetected.." -ForegroundColor Red
                return $false
            }
        }
    }
    catch {
        throw $_
    }
}
function Invoke-Cmdline {
    [cmdletbinding()]
    param (
        [parameter(mandatory = $true)]
        [string]$application,

        [parameter(mandatory = $true)]
        [string]$argumentList,

        [parameter(Mandatory = $false)]
        [switch]$silent
    )
    if ($silent) {
        cmd /c "$application $argumentList > nul 2>&1"
    }
    else {
        cmd /c "$application $argumentList"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "An error has occurred.."
    }
}
function Get-DiskPartVolume {
    [cmdletbinding()]
    param (
        [parameter(mandatory = $false)]
        [string]$winPEDrive = "X:"
    )
    try {
        #region Map drive letter for install.wim
        $lvTxt = "$winPEDrive\listvol.txt"
        $lv = @"
List volume
exit
"@
        $lv | Out-File $lvTxt -Encoding ascii -Force -NoNewline
        $dpOutput = Invoke-CmdLine -application "diskpart" -argumentList "/s $lvTxt"
        $dpOutput = $dpOutput[6..($dpOutput.length - 3)]
        $vals = $dpOutput[2..($dpOutput.Length - 1)]
        $res = foreach ($val in $vals) {
            $dr = $val.Substring(10, 6).Replace(" ", "")
            [PSCustomObject]@{
                VolumeNum  = $val.Substring(0, 10).Replace(" ", "")
                DriveRoot  = if ($dr -ne "") { "$dr`:\" } else { $null }
                Label      = $val.Substring(17, 13).Replace(" ", "")
                FileSystem = $val.Substring(30, 7).Replace(" ", "")
                Type       = $val.Substring(37, 12).Replace(" ", "")
                Size       = $val.Substring(49, 9).Replace(" ", "")
                Status     = $val.Substring(58, 11).Replace(" ", "")
                Info       = $val.Substring($val.length - 10, 10).Replace(" ", "")
            }
        }
        return $res
        #endregion
    }
    catch {
        throw $_
    }
}
function Get-USBDeviceId {
    try {
        $USBDrives = $drives | ? { $_.BusType -eq "USB" }
        if (@($USBDrives).count -eq 1) {
            $USBDrive = $USBDrives[0].DeviceId
            return $USBDrive
        }
        else {
            throw "Error while getting DeviceId of USB Stick. No additional USB storage devices must be attached"
        }
    }
    catch {
        throw $_
    }
}
function Get-SystemDeviceId {
    try {
        $dataDrives = $drives | ? { $_.BusType -ne "USB" }
        if (@($DataDrives).count -eq 1) {
            $targetDrive = $DataDrives[0].DeviceId
            return $targetDrive
        }
        elseif (@($DataDrives).count -gt 1) {
            Write-Host "More than one disk has been detected. Select disk where Windows should be installed" -ForegroundColor Yellow
            $DataDrives | ft DeviceId, FriendlyName, Size | Out-String | % { Write-Host $_ -ForegroundColor Cyan }
            $targetDrive = Read-Host "Please make a selection..."
            return $targetDrive
        }
        else {
            throw "Error while getting DeviceId of potiential Windows target drives" 
        }
    }
    catch {
        throw $_
    }
}
function Set-DrivePartition {
    [cmdletbinding()]
    param (
        [parameter(mandatory = $false)]
        [string]$winPEDrive = "X:",

        [parameter(mandatory = $false)]
        [string]$targetDrive = "0"
    )
    try {
        $txt = "$winPEDrive\winpart.txt"
        New-Item $txt -ItemType File -Force | Out-Null
        Write-Host "Checking boot system type.." -ForegroundColor Cyan
        $bootType = Test-IsUEFI
        #region Boot type switch
        switch ($bootType) {
            "BIOS" {
                $winpartCmd = @"
select disk $targetDrive
clean
create partition primary size=100
active
format quick fs=fat32 label="System"
assign letter="S"
create partition primary
format quick fs=ntfs label="Windows"
assign letter="W"
shrink desired=450
create partition primary
format quick fs=ntfs label="Recovery"
assign letter="R"
exit
"@
            }
            "UEFI" {
                $winpartCmd = @"
select disk $targetDrive
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label="System"
assign letter="S"
create partition msr size=16
create partition primary
format quick fs=ntfs label="Windows"
assign letter="W"
shrink desired=950
create partition primary
format quick fs=ntfs label="Recovery"
assign letter="R"
set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
gpt attributes=0x8000000000000001
exit
"@
            }
            default {
                throw "Boot type could not be detected.."
            }
        }
        #endregion
        #region Partition disk
        $winpartCmd | Out-File $txt -Encoding ascii -Force -NoNewline
        Write-Host "Setting up partition table.." -ForegroundColor Cyan
        Invoke-Cmdline -application diskpart -argumentList "/s $txt" -silent
        #endregion

    }
    catch {
        throw $_
    }

}
function Find-InstallWim {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        $volumeInfo
    )
    try {
        foreach ($vol in $volumeInfo) {
            if ($vol.DriveRoot) {
                if (Test-Path "$($vol.DriveRoot)images\install.wim" -ErrorAction SilentlyContinue) {
                    Write-Host "Install.wim found on drive: $($vol.DriveRoot)" -ForegroundColor Cyan
                    $res = $vol
                }
            }
        }
    }
    catch {
        Write-Warning $_.Exception.Message
    }
    finally {
        if (!($res)) {
            Write-Warning "Install.wim not found on any drives.."
        }
        else {
            $res
        }
    }
}
function Add-Driver {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$scratchDrive,

        [parameter(Mandatory = $true)]
        [string]$driverPath

    )
    if (!(Get-ChildItem "$driverPath\*.inf" -Recurse -ErrorAction SilentlyContinue)) {
        Write-Host "No drivers found at path: $driverPath" -ForegroundColor Cyan
    }
    else {
        Invoke-Cmdline -application "DISM" -argumentList "/Image:$scratchDrive /Add-Driver /Driver:""$driverPath"" /recurse"
    }
}
function Add-Package {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$scratchDrive,

        [parameter(Mandatory = $true)]
        [string]$scratchPath,

        [parameter(Mandatory = $true)]
        [string]$packagePath
    )
    if (!(Get-ChildItem $packagePath)) {
        Write-Host "No update packages found at path: $packagePath" -ForegroundColor Cyan
    }
    else {
        Invoke-Cmdline -application "DISM" -argumentList "/Image:$scratchDrive /Add-Package /PackagePath:$packagePath /ScratchDir:$scratchPath"
    }
}
function Show-WarningShots {
    [cmdletbinding()]
    param (
        [string]$title = 'Choose an option'
    )
    Write-Host "================ $title ================" -ForegroundColor Yellow

    Write-Host "1: Exit" -ForegroundColor Green
    Write-Host "2: Install Windows 11" -ForegroundColor Green
    Write-Host "3: Install Windows 11 and Register Autopilot" -ForegroundColor Green
    Write-Host "4: Register Autopilot" -ForegroundColor Green

    $userInput = Read-Host "Please make a selection..."
    return $userInput
}
function Show-FinalWarningShots {
    [cmdletbinding()]
    param (
        [string]$title = 'WARNING!!!'
    )
    Write-Host "================ $title ================" -ForegroundColor RED

    Write-Host "This option will cause irreversible changes to your device - are you sure you want to continue? (Y/N)`n" -ForegroundColor Red

    $userInput = Read-Host "Please make a selection (Y/N)"

    switch ($userInput) {
        "Y" {
            return $true
        }
        "N" {
            return $false
        }
        default {
            Clear-Host
            Show-FinalWarningShots
        }
    }
    return $input
}
#endregion
#region Main process
try {
    $PSScriptRoot
    $errorMsg = $null
    $usb = [USBImage]::new($env:SystemDrive)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    #region Bootstrap drivers
    $deviceModel = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty Model
    Write-Host "`nDevice Model: $($deviceModel)" -ForegroundColor Yellow -NoNewline
    $drivers = Get-ChildItem "$($usb.driverPath)\WinPE" -Filter *.inf -Recurse
    if ($drivers) {
        Write-Host "Bootstrapping found drivers into WinPE Environment.." -ForegroundColor Yellow
        foreach ($d in $drivers) {
            . drvload $d.fullName
        }
    }
    else {
        Write-Host "No WinPE drivers detected.." -ForegroundColor Yellow
    }
    #endregion

    #region Set power policy to High Performance
    Set-PowerPolicy -powerPlan HighPerformance
    #endregion
    
    #region Warning shots..
    $userChoice = $null
    while ($userChoice -notin 1, 2, 3, 4) {
        Clear-Host
        Write-Host $([system.text.encoding]::UTF8.GetString([system.convert]::FromBase64String($welcomebanner)))
        Start-Sleep -Seconds 2
        $userChoice = Show-WarningShots
    }
    switch ($userChoice) {
        1 {
            $exitEarly = $true
            throw "Stopping device provision.."
        }
        2 {
            $finalWarning = Show-FinalWarningShots
            if ($finalWarning) {
                $autoPilot = $false
            }
            else {
                $exitEarly = $true
                throw "Stopping device provision.."
            }
        }
        3 {
            $finalWarning = Show-FinalWarningShots
            if ($finalWarning) {
                $autoPilot = $true
            }
            else {
                $exitEarly = $true
                throw "Stopping device provision.."
            }
        }
        4 {
            $finalWarning = $true
            if ($finalWarning) {
                $skipinstall = $true
                $autoPilot = $true
            }
            else {
                $exitEarly = $true
                throw "Stopping device provision.."
            }
        }
    }
    #endregion
    if ($autoPilot) {
        $computerName = $null
        #Register PCPKsp DLL
        If ((Test-Path X:\Windows\System32\PCPKsp.dll)) {
            #Register PCPKsp
            Invoke-CmdLine -application rundll32 -argumentList "X:\Windows\System32\PCPKsp.dll, DllInstall"
        }

        Set-Location $PSScriptRoot

        #Upload Autopilot Data
        "Register Machine to AutoPilot"

        #Delete old Files if exits
        if (Test-Path "$PSScriptRoot\OA3.xml") {
            Remove-Item "$PSScriptRoot\OA3.xml"
        }

        #Get SN from WMI
        $SerialNumber = (Get-CimInstance -Class "Win32_BIOS" -Verbose:$false).SerialNumber
                
        $dev = Get-windowsAutopilotDevice -serialNumber $SerialNumber
        if ($dev) {
            $computerName = $dev.displayName
            "$($computerName) Already Registred in AutoPilot! Skipping!"
        }
        else {
            #Run OA3Tool
            &"$PSScriptRoot\oa3tool.exe" /Report /ConfigFile="$PSScriptRoot\OA3.cfg" /NoKeyCheck

            #Check if Hash was found
            If (Test-Path $PSScriptRoot\OA3.xml) {

                #Read Hash from generated XML File
                [xml]$xmlhash = Get-Content -Path "$PSScriptRoot\OA3.xml"
                $DeviceHashData = $xmlhash.Key.HardwareHash

                #Delete XML File
                Remove-Item "$PSScriptRoot\OA3.xml"
            }
        
            Add-AutopilotImportedDevice -serialNumber $SerialNumber -hardwareIdentifier $DeviceHashData
            "Waiting for AutoPilot Registration"
            Start-Sleep -Seconds 15
        
            while ($null -eq $dev) {
                $dev = Get-windowsAutopilotDevice -serialNumber $SerialNumber
            }
            write-host "Found $($dev.id)" -ForegroundColor Green
        }
        if ($null -ne $computerName) {
            $inputComputerName = Read-Host -Prompt "Enter Computer Name (Current Name $computerName)"
            if ($inputComputerName -ne '') {
                $computerName = $inputComputerName
            }
        }
        else {
            $computerName = Read-Host -Prompt "Enter Computer Name"
        }
        Set-AutopilotDevice -id $dev.id -displayName $computerName -groupTag "EIDPC"
    }

    if (!$skipinstall) {
        #region Configure drive partitions
        Write-Host "`nConfiguring drive partitions.." -ForegroundColor Yellow
        $drives = @(Get-PhysicalDisk)
        $targetDrive = Get-SystemDeviceId
        Set-DrivePartition -winPEDrive $usb.winPEDrive -targetDrive $targetDrive
        #endregion
        #region Set paths
        Write-Host "`nSetting up Scratch & Recovery paths.." -ForegroundColor Yellow
        $usb.setScratch("W:\recycler\scratch")
        $usb.setRecovery("R:\RECOVERY\WINDOWSRE")
        New-Item -Path $usb.scratch.FullName -ItemType Directory -Force | Out-Null
        New-Item -Path $usb.recovery.FullName -ItemType Directory -Force | Out-Null
        #endregion
        #region Applying the windows image from the USB
        Write-Host "`nApplying the windows image from the USB.." -ForegroundColor Yellow
        $imageIndex = Get-Content "$($usb.installPath)\imageIndex.json" -Raw | ConvertFrom-Json -Depth 20
        Invoke-Cmdline -application "DISM" -argumentList "/Apply-Image /ImageFile:$($usb.installPath)\install.wim /Index:$($imageIndex.imageIndex) /ApplyDir:$($usb.scRoot) /EA /ScratchDir:$($usb.scratch)"
        #endregion

        #region Setting the recovery environment
        Write-Host "`nMove WinRE to recovery partition.." -ForegroundColor Yellow
        $reWimPath = "$($usb.scRoot)Windows\System32\recovery\winre.wim"
        if (Test-Path $reWimPath -ErrorAction SilentlyContinue) {
            Write-Host "`nMoving the recovery wim into place.." -ForegroundColor Yellow
        (Get-ChildItem -Path $reWimPath -Force).attributes = "NotContentIndexed"
            Move-Item -Path $reWimPath -Destination "$($usb.recovery.FullName)\winre.wim"

            #region Apply Storage Drivers to WinRE
            if (Get-ChildItem "$($usb.driverPath)\$deviceModel\storage\*.inf" -Recurse -ErrorAction SilentlyContinue) {
                Write-Host "`nApplying drivers to winre.." -ForegroundColor Yellow
                New-Item -ItemType Directory "W:\Temp"
                Invoke-Cmdline -application "DISM" -argumentList "/Mount-Image /ImageFile:$($usb.recovery.FullName)\winre.wim /Index:1 /MountDir:W:\temp"
                Add-Driver -driverPath "$($usb.driverPath)\$deviceModel\storage" -scratchDrive "W:\temp"
                Invoke-Cmdline -application "DISM" -argumentList "/Unmount-Image /MountDir:w:\temp /Commit"
                Remove-Item -path "W:\temp" -Force -Recurse
            }
            #endregion

        (Get-ChildItem -Path "$($usb.recovery.FullName)\winre.wim" -Force).attributes = "ReadOnly", "Hidden", "System", "Archive", "NotContentIndexed"

            Write-Host "`nSetting the recovery environment.." -ForegroundColor Yellow
            Invoke-Cmdline -application "$($usb.scRoot)Windows\System32\reagentc" -argumentList "/SetREImage /Path $($usb.recovery.FullName) /target $($usb.scRoot)Windows" -silent
        }
        #endregion
        #region Setting the boot environment
        Write-Host "`nSetting the boot environment.." -ForegroundColor Yellow
        Invoke-Cmdline -application "$($usb.scRoot)Windows\System32\bcdboot" -argumentList "$($usb.scRoot)Windows /s s: /f all"
        #endregion
        #region Copying over unattended.xml
        Write-Host "`nLooking for unattented.xml.." -ForegroundColor Yellow
        if (Test-Path "$($usb.winPESource)scripts\unattended.xml" -ErrorAction SilentlyContinue) {
            Write-Host "Found it! Copying over to scratch drive.." -ForegroundColor Green
            if (-not (Test-Path "$($usb.scRoot)Windows\Panther" -ErrorAction SilentlyContinue)) {
                New-Item -Path "$($usb.scRoot)Windows\Panther" -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$($usb.winPESource)\scripts\unattended.xml" -Destination "$($usb.scRoot)Windows\Panther\unattended.xml" | Out-Null
        }
        else {
            Write-Host "Nothing found. Moving on.." -ForegroundColor Red
        }
        #endregion
        #region Copying over non scanstate packages
        Write-Host "`nlooking for *.ppkg files.." -ForegroundColor Yellow
        if (Test-Path "$($usb.winPESource)scripts\*.ppkg" -ErrorAction SilentlyContinue) {
            Write-Host "Found them! Copying over to scratch drive.." -ForegroundColor Yellow
            Copy-Item -Path "$($usb.winPESource)\scripts\*.ppkg" -Destination "$($usb.scRoot)Windows\Panther\" | Out-Null
        }
        else {
            Write-Host "Nothing found. Moving on.." -ForegroundColor Yellow
        }
        #endregion
        #region remove public shortcuts
        Write-Host "`nlooking for *.lnk.." -ForegroundColor Yellow
        if (Test-Path "$($usb.scRoot)Users\public\Desktop\*.lnk" -ErrorAction SilentlyContinue) {
            Write-Host "Found shortcuts! removing.." -ForegroundColor Yellow
            Remove-Item -Path "$($usb.scRoot)Users\public\Desktop\*.lnk" -force | Out-Null
        }
        else {
            Write-Host "No shortcuts found. Moving on.." -ForegroundColor Yellow
        }
        #endregion
        #region Applying drivers
        if (Get-ChildItem "$($usb.driverPath)\$deviceModel\*.inf" -Recurse -ErrorAction SilentlyContinue) {
            Write-Host "`nApplying drivers.." -ForegroundColor Yellow
            Add-Driver -driverPath "$($usb.driverPath)\$deviceModel" -scratchDrive $usb.scRoot
        }
        #endregion

        #region Applying packages
        if (Get-ChildItem "$($usb.packagePath)\*.cab" -Recurse -ErrorAction SilentlyContinue) {
            Write-Host "`nApplying Packages.." -ForegroundColor Yellow
            Add-Package -packagePath "$($usb.packagePath)\" -scratchDrive $usb.scRoot -scratchPath $usb.scratch
        }
        #endregion
    }
    $completed = $true
}
catch {
    $errorMsg = $_.Exception.Message
}
finally {
    $sw.stop()
    if (!$skipinstall) {
        $USBDrive = Get-USBDeviceId
    }
    if ($exitEarly) {
        $errorMsg = $null
    }
    if ($errorMsg) {
        Write-Warning $errorMsg
    }
    else {
        if ($completed) {
            Write-Host "`nProvisioning process completed..`nTotal time taken: $($sw.elapsed)" -ForegroundColor Green
        }
        else {
            Write-Host "`nProvisioning process stopped prematurely..`nTotal time taken: $($sw.elapsed)" -ForegroundColor Green
        }
    }
}
#endregion
