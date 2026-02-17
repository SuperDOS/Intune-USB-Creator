<#
.SYNOPSIS
    Intune USB Deployment - Provision Script
.DESCRIPTION
    Provisions a device with Windows installation and/or Autopilot registration
.NOTES
    Version: 1.0
#>

#region variables set by Publish-ImageToUSB.ps1 -createDataFolder from the GLOBAL_PARAM.json
$tenants = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($("@TENANT"))) | ConvertFrom-Json
$welcomebanner = "@WELCOMEBANNER"
$script:GraphTokenCache = @{}
#endregion

#region Classes
class USBImage {
    [string]$winPEDrive
    [string]$winPESource = $env:winPESource
    [PSCustomObject]$volumeInfo
    [string]$installPath
    [string]$installRoot
    [System.IO.DirectoryInfo]$scratch
    [string]$scRoot
    [System.IO.DirectoryInfo]$recovery
    [string]$reRoot
    [System.IO.DirectoryInfo]$driverPath
    [System.IO.DirectoryInfo]$packagePath

    USBImage ([string]$winPEDrive) {
        $this.winPEDrive = $winPEDrive
        $this.volumeInfo = Get-DiskPartVolume -WinPEDrive $winPEDrive
        $this.installRoot = (Find-InstallWim -VolumeInfo $this.volumeInfo).DriveRoot
        $this.installPath = "$($this.installRoot)images"
        $this.driverPath = "$($this.installRoot)Drivers"
        $this.packagePath = "$($this.installRoot)Packages"
    }
    
    [void] SetScratch([System.IO.DirectoryInfo]$scratch) {
        $this.scratch = $scratch
        $this.scRoot = $scratch.Root
    }
    
    [void] SetRecovery([System.IO.DirectoryInfo]$recovery) {
        $this.recovery = $recovery
        $this.reRoot = $recovery.Root
    }
}
#endregion

#region Graph API Functions
function Get-GraphToken {
    <#
    .SYNOPSIS
        Retrieves an access token for Microsoft Graph API using client credentials flow.
    
    .DESCRIPTION
        Authenticates to Azure AD using client credentials and returns an access token
        that can be used for Microsoft Graph API calls. Implements token caching to avoid
        unnecessary authentication requests.
    
    .PARAMETER ClientID
        The Azure AD application (client) ID
    
    .PARAMETER ClientSecret
        The client secret for the Azure AD application
    
    .PARAMETER TenantID
        The Azure AD tenant ID
    
    .PARAMETER Force
        Forces a new token request even if a cached token exists
    
    .EXAMPLE
        $token = Get-GraphToken -ClientID $appId -ClientSecret $secret -TenantID $tenantId
    
    .EXAMPLE
        $token = Get-GraphToken -ClientID $appId -ClientSecret $secret -TenantID $tenantId -Force
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantID,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        # Create a unique cache key based on credentials
        $cacheKey = "$TenantID|$ClientID"
        
        # Check if we have a valid cached token (with 5-minute buffer before expiry)
        if (-not $Force -and $script:GraphTokenCache.ContainsKey($cacheKey)) {
            $cachedEntry = $script:GraphTokenCache[$cacheKey]
            if ($cachedEntry.Expiry -gt (Get-Date).AddMinutes(5)) {
                Write-Verbose "Using cached Graph API token (expires: $($cachedEntry.Expiry))"
                return $cachedEntry.Token
            }
            else {
                Write-Verbose "Cached token expired, requesting new token"
                $script:GraphTokenCache.Remove($cacheKey)
            }
        }
        
        Write-Verbose "Requesting new Graph API token for tenant: $TenantID"
        
        $body = @{
            tenant        = $TenantID
            client_id     = $ClientID
            scope         = 'https://graph.microsoft.com/.default'
            client_secret = $ClientSecret
            grant_type    = 'client_credentials'
        }
        
        $params = @{
            Uri         = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
            Method      = 'Post'
            Body        = $body
            ContentType = 'application/x-www-form-urlencoded'
        }
        
        $response = Invoke-RestMethod @params
        
        # Cache the token with expiry information
        $script:GraphTokenCache[$cacheKey] = @{
            Token   = $response.access_token
            Expiry  = (Get-Date).AddSeconds($response.expires_in)
            Obtained = Get-Date
        }
        
        Write-Verbose "New token obtained, expires in $($response.expires_in) seconds"
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain Graph API token: $($_.Exception.Message)"
        throw
    }
}

function Invoke-GraphRequest {
    <#
    .SYNOPSIS
        Makes a generic Microsoft Graph API request.
    
    .DESCRIPTION
        A wrapper function for making Microsoft Graph API calls with automatic pagination
        support, retry logic, and consistent error handling.
    
    .PARAMETER Uri
        The Graph API endpoint URI (can be relative or absolute)
    
    .PARAMETER Method
        HTTP method (GET, POST, PATCH, DELETE, etc.)
    
    .PARAMETER Body
        Request body (will be converted to JSON if not already a string)
    
    .PARAMETER AccessToken
        The bearer token for authentication
    
    .PARAMETER ApiVersion
        Graph API version to use (v1.0 or beta). Default is v1.0
    
    .PARAMETER ContentType
        Content type for the request. Default is application/json
    
    .PARAMETER MaxRetries
        Maximum number of retry attempts for transient failures. Default is 3
    
    .PARAMETER RetryDelaySeconds
        Initial delay in seconds between retries (uses exponential backoff). Default is 2
    
    .EXAMPLE
        $response = Invoke-GraphRequest -Uri "deviceManagement/windowsAutopilotDeviceIdentities" -Method GET -AccessToken $token
    
    .EXAMPLE
        $body = @{ displayName = "MyDevice"; groupTag = "Finance" }
        $response = Invoke-GraphRequest -Uri "deviceManagement/windowsAutopilotDeviceIdentities/$id/UpdateDeviceProperties" -Method POST -Body $body -AccessToken $token -ApiVersion beta
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',
        
        [Parameter(Mandatory = $false)]
        [object]$Body,
        
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'v1.0',
        
        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/json',
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 2
    )
    
    try {
        # Ensure URI is absolute
        if (-not $Uri.StartsWith('https://')) {
            $Uri = "https://graph.microsoft.com/$ApiVersion/$Uri"
        }
        
        $headers = @{
            Authorization = "Bearer $AccessToken"
        }
        
        $params = @{
            Uri         = $Uri
            Method      = $Method
            Headers     = $headers
            ContentType = $ContentType
        }
        
        # Add body if provided
        if ($Body) {
            if ($Body -is [string]) {
                $params.Body = $Body
            }
            else {
                $params.Body = $Body | ConvertTo-Json -Depth 10
            }
        }
        
        # Retry logic with exponential backoff
        $retryCount = 0
        $completed = $false
        $response = $null
        
        while (-not $completed -and $retryCount -le $MaxRetries) {
            try {
                $response = Invoke-RestMethod @params
                $completed = $true
            }
            catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
                
                # Check if we should retry (429 = Too Many Requests, 503 = Service Unavailable, 504 = Gateway Timeout)
                if ($statusCode -in @(429, 503, 504) -and $retryCount -lt $MaxRetries) {
                    $retryCount++
                    
                    # Check for Retry-After header
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                    if ($retryAfter) {
                        $waitTime = [int]$retryAfter
                    }
                    else {
                        # Exponential backoff: 2s, 4s, 8s, etc.
                        $waitTime = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                    }
                    
                    Write-Warning "Request failed with status $statusCode. Retrying in $waitTime seconds (Attempt $retryCount of $MaxRetries)..."
                    Start-Sleep -Seconds $waitTime
                    
                    # Update URI in case it was a nextLink
                    $params.Uri = $Uri
                }
                else {
                    # Not a retryable error or max retries reached
                    throw
                }
            }
        }
        
        if (-not $completed) {
            throw "Request failed after $MaxRetries retry attempts"
        }
        
        # Handle pagination for GET requests
        if ($Method -eq 'GET' -and $response.PSObject.Properties.Name -contains 'value') {
            $allResults = [System.Collections.Generic.List[object]]::new()
            $allResults.AddRange($response.value)
            
            while ($response.'@odata.nextLink') {
                Write-Verbose "Fetching next page: $($response.'@odata.nextLink')"
                $params.Uri = $response.'@odata.nextLink'
                
                # Apply same retry logic for pagination
                $retryCount = 0
                $completed = $false
                
                while (-not $completed -and $retryCount -le $MaxRetries) {
                    try {
                        $response = Invoke-RestMethod @params
                        $completed = $true
                        $allResults.AddRange($response.value)
                    }
                    catch {
                        $statusCode = $_.Exception.Response.StatusCode.value__
                        if ($statusCode -in @(429, 503, 504) -and $retryCount -lt $MaxRetries) {
                            $retryCount++
                            $retryAfter = $_.Exception.Response.Headers['Retry-After']
                            $waitTime = if ($retryAfter) { [int]$retryAfter } else { $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1) }
                            Write-Warning "Pagination request failed with status $statusCode. Retrying in $waitTime seconds..."
                            Start-Sleep -Seconds $waitTime
                        }
                        else {
                            throw
                        }
                    }
                }
            }
            
            Write-Verbose "Retrieved $($allResults.Count) total items"
            return $allResults.ToArray()
        }
        
        return $response
    }
    catch {
        $errorMessage = "Graph API request failed: $($_.Exception.Message)"
        
        if ($_.ErrorDetails.Message) {
            try {
                $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($errorDetails.error.message) {
                    $errorMessage += "`nGraph API Error: $($errorDetails.error.message)"
                }
                if ($errorDetails.error.code) {
                    $errorMessage += "`nError Code: $($errorDetails.error.code)"
                }
            }
            catch {
                $errorMessage += "`nDetails: $($_.ErrorDetails.Message)"
            }
        }
        
        Write-Error $errorMessage
        throw
    }
}

function Get-AutopilotDevice {
    <#
    .SYNOPSIS
        Retrieves Windows Autopilot device(s) from Intune.
    
    .PARAMETER Id
        Specific device ID to retrieve
    
    .PARAMETER SerialNumber
        Filter by serial number (supports partial match)
    
    .PARAMETER ClientID
        Azure AD application (client) ID
    
    .PARAMETER ClientSecret
        Client secret for authentication
    
    .PARAMETER TenantID
        Azure AD tenant ID
    
    .EXAMPLE
        Get-AutopilotDevice -SerialNumber "12345" -ClientID $id -ClientSecret $secret -TenantID $tenant
    
    .EXAMPLE
        Get-AutopilotDevice -Id $deviceId -ClientID $id -ClientSecret $secret -TenantID $tenant
    
    .EXAMPLE
        $allDevices = Get-AutopilotDevice -ClientID $id -ClientSecret $secret -TenantID $tenant
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'BySerial')]
        [string]$SerialNumber,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantID
    )
    
    try {
        $token = Get-GraphToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID
        
        # Build URI based on parameter set
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                $uri = "deviceManagement/windowsAutopilotDeviceIdentities/$Id"
            }
            'BySerial' {
                $uri = "deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$SerialNumber')"
            }
            'All' {
                $uri = "deviceManagement/windowsAutopilotDeviceIdentities"
            }
        }
        
        $params = @{
            Uri         = $uri
            Method      = 'GET'
            AccessToken = $token
            ApiVersion  = 'v1.0'
        }
        
        return Invoke-GraphRequest @params
    }
    catch {
        Write-Error "Failed to retrieve Autopilot device(s): $($_.Exception.Message)"
        throw
    }
}

function Add-AutopilotImportedDevice {
    <#
    .SYNOPSIS
        Imports a Windows Autopilot device identity to Intune.
    
    .PARAMETER SerialNumber
        The device serial number
    
    .PARAMETER HardwareIdentifier
        The device hardware hash
    
    .PARAMETER ClientID
        Azure AD application (client) ID
    
    .PARAMETER ClientSecret
        Client secret for authentication
    
    .PARAMETER TenantID
        Azure AD tenant ID
    
    .EXAMPLE
        Add-AutopilotImportedDevice -SerialNumber "12345" -HardwareIdentifier $hash -ClientID $id -ClientSecret $secret -TenantID $tenant
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SerialNumber,
        
        [Parameter(Mandatory = $true)]
        [string]$HardwareIdentifier,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantID
    )
    
    try {
        $token = Get-GraphToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID
        
        $body = @{
            serialNumber       = $SerialNumber
            hardwareIdentifier = $HardwareIdentifier
        }
        
        $params = @{
            Uri         = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
            Method      = 'POST'
            Body        = $body
            AccessToken = $token
            ApiVersion  = 'beta'
        }
        
        return Invoke-GraphRequest @params
    }
    catch {
        Write-Error "Failed to import Autopilot device: $($_.Exception.Message)"
        throw
    }
}

function Set-AutopilotDevice {
    <#
    .SYNOPSIS
        Updates an Autopilot device's properties (display name and group tag).
    
    .PARAMETER Id
        The Autopilot device ID
    
    .PARAMETER DisplayName
        The device display name
    
    .PARAMETER GroupTag
        The device group tag (optional)
    
    .PARAMETER ClientID
        Azure AD application (client) ID
    
    .PARAMETER ClientSecret
        Client secret for authentication
    
    .PARAMETER TenantID
        Azure AD tenant ID
    
    .EXAMPLE
        Set-AutopilotDevice -Id $deviceId -DisplayName "DESKTOP-001" -GroupTag "Finance" -ClientID $id -ClientSecret $secret -TenantID $tenant
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Id,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [Alias("OrderIdentifier")]
        [string]$GroupTag = "",
        
        [Parameter(Mandatory = $true)]
        [string]$ClientID,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory = $true)]
        [string]$TenantID
    )
    
    try {
        $token = Get-GraphToken -ClientID $ClientID -ClientSecret $ClientSecret -TenantID $TenantID
        
        $body = @{
            displayName = $DisplayName
            groupTag    = $GroupTag
        }
        
        $params = @{
            Uri         = "deviceManagement/windowsAutopilotDeviceIdentities/$Id/UpdateDeviceProperties"
            Method      = 'POST'
            Body        = $body
            AccessToken = $token
            ApiVersion  = 'beta'
        }
        
        return Invoke-GraphRequest @params
    }
    catch {
        Write-Error "Failed to update Autopilot device: $($_.Exception.Message)"
        throw
    }
}
#endregion

#region System Functions
function Invoke-CmdLine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Application,
        [Parameter(Mandatory = $true)][string]$ArgumentList,
        [Parameter(Mandatory = $false)][switch]$Silent
    )
    
    $output = if ($Silent) {
        cmd /c "$Application $ArgumentList 2>&1"
    } else {
        cmd /c "$Application $ArgumentList"
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE"
    }
    
    return $output
}

function Set-PowerPolicy {
    [CmdletBinding()]
    param ([Parameter(Mandatory = $true)][ValidateSet('PowerSaver', 'Balanced', 'HighPerformance')][string]$PowerPlan)
    
    $planGuids = @{
        PowerSaver      = "a1841308-3541-4fab-bc81-f71556f20b4a"
        Balanced        = "381b4222-f694-41f0-9685-ff5bb260df2e"
        HighPerformance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    }
    
    Write-Host "Setting power policy to '$PowerPlan'.." -ForegroundColor Cyan
    Invoke-CmdLine -Application powercfg -ArgumentList "/s $($planGuids[$PowerPlan])" -Silent
}

function Test-IsUEFI {
    [CmdletBinding()]
    param()
    
    $pft = Get-ItemPropertyValue -Path HKLM:\SYSTEM\CurrentControlSet\Control -Name 'PEFirmwareType' -ErrorAction SilentlyContinue
    
    switch ($pft) {
        1 { Write-Host "BIOS Mode detected.." -ForegroundColor Cyan; return "BIOS" }
        2 { Write-Host "UEFI Mode detected.." -ForegroundColor Cyan; return "UEFI" }
        default { Write-Host "BIOS / UEFI undetected.." -ForegroundColor Red; return $null }
    }
}
#endregion

#region Disk Functions
function Get-DiskPartVolume {
    [CmdletBinding()]
    param ([Parameter(Mandatory = $false)][string]$WinPEDrive = "X:")
    
    $lvTxt = "$WinPEDrive\listvol.txt"
    "List volume`nexit" | Out-File $lvTxt -Encoding ascii -Force -NoNewline
    $dpOutput = Invoke-CmdLine -Application "diskpart" -ArgumentList "/s $lvTxt"
    
    $dpOutput[8..($dpOutput.length - 3)] | ForEach-Object {
        $dr = $_.Substring(10, 6).Trim()
        [PSCustomObject]@{
            VolumeNum  = $_.Substring(0, 10).Trim()
            DriveRoot  = if ($dr) { "$dr`:\" } else { $null }
            Label      = $_.Substring(17, 13).Trim()
            FileSystem = $_.Substring(30, 7).Trim()
            Type       = $_.Substring(37, 12).Trim()
            Size       = $_.Substring(49, 9).Trim()
            Status     = $_.Substring(58, 11).Trim()
        }
    }
}

function Find-InstallWim {
    [CmdletBinding()]
    param ([Parameter(Mandatory = $true)][PSCustomObject[]]$VolumeInfo)
    
    foreach ($vol in $VolumeInfo) {
        if ($vol.DriveRoot -and (Test-Path "$($vol.DriveRoot)images\install.wim")) {
            Write-Host "Install.wim found on drive: $($vol.DriveRoot)" -ForegroundColor Cyan
            return $vol
        }
    }
    throw "Install.wim not found on any drives"
}

function Get-SystemDeviceId {
    $dataDrives = $drives | Where-Object { $_.BusType -ne "USB" }
    
    if ($dataDrives.Count -eq 1) {
        return $dataDrives[0].DeviceId
    }
    elseif ($dataDrives.Count -gt 1) {
        Write-Host "Multiple disks detected. Select installation target:" -ForegroundColor Yellow
        $dataDrives | Format-Table DeviceId, FriendlyName, Size | Out-Host
        
        do {
            $selection = Read-Host "Enter Device ID"
        } while ($selection -notin $dataDrives.DeviceId)
        
        return $selection
    }
    else {
        throw "No non-USB drives found for Windows installation"
    }
}

function Set-DrivePartition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)][string]$WinPEDrive = "X:",
        [Parameter(Mandatory = $true)][string]$TargetDrive
    )
    
    $bootType = Test-IsUEFI
    if (-not $bootType) { throw "Unable to detect boot type" }
    
    $winpartCmd = if ($bootType -eq "UEFI") {
        @"
select disk $TargetDrive
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
    } else {
        @"
select disk $TargetDrive
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
    
    $txt = "$WinPEDrive\winpart.txt"
    $winpartCmd | Out-File $txt -Encoding ascii -Force -NoNewline
    Write-Host "Setting up partition table.." -ForegroundColor Cyan
    Invoke-CmdLine -Application diskpart -ArgumentList "/s $txt" -Silent
}

function Add-Driver {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ScratchDrive,
        [Parameter(Mandatory = $true)][string]$DriverPath
    )
    
    if (Get-ChildItem "$DriverPath\*.inf" -Recurse -ErrorAction SilentlyContinue) {
        Write-Host "Adding drivers from: $DriverPath" -ForegroundColor Cyan
        Invoke-CmdLine -Application "DISM" -ArgumentList "/Image:$ScratchDrive /Add-Driver /Driver:`"$DriverPath`" /Recurse"
    } else {
        Write-Host "No drivers found at: $DriverPath" -ForegroundColor Cyan
    }
}

function Add-Package {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$ScratchDrive,
        [Parameter(Mandatory = $true)][string]$ScratchPath,
        [Parameter(Mandatory = $true)][string]$PackagePath
    )
    
    if (Get-ChildItem $PackagePath -ErrorAction SilentlyContinue) {
        Write-Host "Adding packages from: $PackagePath" -ForegroundColor Cyan
        Invoke-CmdLine -Application "DISM" -ArgumentList "/Image:$ScratchDrive /Add-Package /PackagePath:$PackagePath /ScratchDir:$ScratchPath"
    } else {
        Write-Host "No packages found at: $PackagePath" -ForegroundColor Cyan
    }
}
#endregion

#region UI Functions
function Show-Menu {
    [CmdletBinding()]
    param ([string]$Title = 'Choose an option')
    
    do {
        Write-Host "`n================ $Title ================" -ForegroundColor Yellow
        Write-Host "1: Exit" -ForegroundColor Green
        Write-Host "2: Install Windows 11" -ForegroundColor Green
        Write-Host "3: Install Windows 11 and Register Autopilot" -ForegroundColor Green
        Write-Host "4: Register Autopilot" -ForegroundColor Green
        
        $input = Read-Host "`nEnter a number (1-4)"
        if ($input -match '^[1-4]$') { return [int]$input }
        
        Write-Host "`nInvalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 2
    } while ($true)
}

function Show-TenantSelection {
    [CmdletBinding()]
    param ([PSCustomObject[]]$Tenants)
    
    Write-Host "`n================ Choose a Tenant ================" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Tenants.Count; $i++) {
        Write-Host "$($i + 1): $($Tenants[$i].name) ($($Tenants[$i].id))" -ForegroundColor Green
    }
    
    do {
        $input = Read-Host "`nEnter a number (1-$($Tenants.Count))"
        if ($input -match "^\d+$" -and [int]$input -ge 1 -and [int]$input -le $Tenants.Count) {
            return $Tenants[[int]$input - 1]
        }
        Write-Host "Invalid selection." -ForegroundColor Red
    } while ($true)
}

function Show-WarningPrompt {
    [CmdletBinding()]
    param ([string]$Title = 'WARNING!!!')
    
    do {
        Clear-Host
        Write-Host "`n================ $Title ================" -ForegroundColor Red
        Write-Host "`nThis will cause irreversible changes to your device!" -ForegroundColor Red
        Write-Host "Continue? (Y/N)`n" -ForegroundColor Yellow
        
        $input = (Read-Host).Trim().ToUpper()
        if ($input -eq 'Y') { return $true }
        if ($input -eq 'N') { return $false }
        
        Write-Host "`nInvalid selection." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    } while ($true)
}
#endregion

#region Main Process
try {
    $errorMsg = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $usb = [USBImage]::new($env:SystemDrive)
    
    # Bootstrap WinPE drivers
    $deviceModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
    Write-Host "`nDevice Model: $deviceModel" -ForegroundColor Yellow
    
    $drivers = Get-ChildItem "$($usb.driverPath)\WinPE" -Filter *.inf -Recurse -ErrorAction SilentlyContinue
    if ($drivers) {
        Write-Host "Bootstrapping WinPE drivers..." -ForegroundColor Yellow
        $drivers | ForEach-Object { drvload $_.FullName }
    }
    
    # Set power policy
    Set-PowerPolicy -PowerPlan HighPerformance
    
    # Show welcome banner
    Clear-Host
    Write-Host $([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($welcomebanner)))
    
    # Tenant selection
    if ($tenants.Count -gt 1) {
        $tenant = Show-TenantSelection -Tenants $tenants
    } else {
        $tenant = $tenants[0]
    }
    
    $tenantid = $tenant.id
    $groupTag = $tenant.groupTag
    $graphclientid = $tenant.graphclientid
    $graphsecret = $tenant.graphsecret
    
    # Show menu
    Clear-Host
    Write-Host $([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($welcomebanner)))
    $userChoice = Show-Menu
    
    $autoPilot = $false
    $skipInstall = $false
    $exitEarly = $false
    
    switch ($userChoice) {
        1 {
            $exitEarly = $true
            throw "User cancelled operation"
        }
        2 {
            if (-not (Show-WarningPrompt)) {
                $exitEarly = $true
                throw "User cancelled operation"
            }
        }
        3 {
            if (Show-WarningPrompt) {
                $autoPilot = $true
            } else {
                $exitEarly = $true
                throw "User cancelled operation"
            }
        }
        4 {
            $skipInstall = $true
            $autoPilot = $true
        }
    }
    
    # Autopilot registration
    if ($autoPilot) {
        if (Test-Path X:\Windows\System32\PCPKsp.dll) {
            Invoke-CmdLine -Application rundll32 -ArgumentList "X:\Windows\System32\PCPKsp.dll, DllInstall"
        }
        
        Set-Location $PSScriptRoot
        Write-Host "`nRegistering device to Autopilot..." -ForegroundColor Cyan
        
        if (Test-Path "$PSScriptRoot\OA3.xml") {
            Remove-Item "$PSScriptRoot\OA3.xml" -Force
        }
        
        $SerialNumber = (Get-CimInstance -Class Win32_BIOS).SerialNumber
        Write-Host "Serial Number: $SerialNumber" -ForegroundColor Cyan
        
        $dev = Get-AutopilotDevice -SerialNumber $SerialNumber -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid
        
        if ($dev) {
            $computerName = $dev.displayName
            Write-Host "$computerName already registered in Autopilot!" -ForegroundColor Yellow
        } else {
            & "$PSScriptRoot\oa3tool.exe" /Report /ConfigFile="$PSScriptRoot\OA3.cfg" /NoKeyCheck
            
            if (Test-Path "$PSScriptRoot\OA3.xml") {
                [xml]$xmlhash = Get-Content "$PSScriptRoot\OA3.xml"
                $DeviceHashData = $xmlhash.Key.HardwareHash
                Remove-Item "$PSScriptRoot\OA3.xml" -Force
                
                Add-AutopilotImportedDevice -SerialNumber $SerialNumber -HardwareIdentifier $DeviceHashData -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid
                
                Write-Host "Waiting for Autopilot registration..." -ForegroundColor Cyan
                Start-Sleep -Seconds 15
                
                while ($null -eq $dev) {
                    $dev = Get-AutopilotDevice -SerialNumber $SerialNumber -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid
                    if ($null -eq $dev) { Start-Sleep -Seconds 5 }
                }
                Write-Host "Device registered: $($dev.id)" -ForegroundColor Green
            }
        }
        
        if ($computerName) {
            $input = Read-Host "Enter Computer Name (Current: $computerName, press Enter to keep)"
            if ($input) { $computerName = $input }
        } else {
            $computerName = Read-Host "Enter Computer Name"
        }
        
        Set-AutopilotDevice -Id $dev.id -DisplayName $computerName -GroupTag $groupTag -ClientID $graphclientid -ClientSecret $graphsecret -TenantID $tenantid
        Write-Host "Device name set to: $computerName" -ForegroundColor Green
    }
    
    # Windows installation
    if (-not $skipInstall) {
        $drives = @(Get-PhysicalDisk)
        $targetDrive = Get-SystemDeviceId
        Set-DrivePartition -WinPEDrive $usb.winPEDrive -TargetDrive $targetDrive
        
        Write-Host "`nSetting up paths..." -ForegroundColor Yellow
        $usb.SetScratch("W:\recycler\scratch")
        $usb.SetRecovery("R:\RECOVERY\WINDOWSRE")
        New-Item -Path $usb.scratch.FullName -ItemType Directory -Force | Out-Null
        New-Item -Path $usb.recovery.FullName -ItemType Directory -Force | Out-Null
        
        Write-Host "`nApplying Windows image..." -ForegroundColor Yellow
        $imageIndex = Get-Content "$($usb.installPath)\imageIndex.json" | ConvertFrom-Json
        Invoke-CmdLine -Application "DISM" -ArgumentList "/Apply-Image /ImageFile:$($usb.installPath)\install.wim /Index:$($imageIndex.imageIndex) /ApplyDir:$($usb.scRoot) /EA /ScratchDir:$($usb.scratch)"
        
        # Recovery environment
        $reWimPath = "$($usb.scRoot)Windows\System32\recovery\winre.wim"
        if (Test-Path $reWimPath) {
            Write-Host "`nConfiguring recovery environment..." -ForegroundColor Yellow
            (Get-ChildItem $reWimPath -Force).Attributes = "NotContentIndexed"
            Move-Item $reWimPath "$($usb.recovery.FullName)\winre.wim"
            
            if (Get-ChildItem "$($usb.driverPath)\$deviceModel\storage\*.inf" -Recurse -ErrorAction SilentlyContinue) {
                New-Item "W:\Temp" -ItemType Directory | Out-Null
                Invoke-CmdLine -Application "DISM" -ArgumentList "/Mount-Image /ImageFile:$($usb.recovery.FullName)\winre.wim /Index:1 /MountDir:W:\temp"
                Add-Driver -DriverPath "$($usb.driverPath)\$deviceModel\storage" -ScratchDrive "W:\temp"
                Invoke-CmdLine -Application "DISM" -ArgumentList "/Unmount-Image /MountDir:w:\temp /Commit"
                Remove-Item "W:\temp" -Force -Recurse
            }
            
            (Get-ChildItem "$($usb.recovery.FullName)\winre.wim" -Force).Attributes = "ReadOnly", "Hidden", "System", "Archive", "NotContentIndexed"
            Invoke-CmdLine -Application "$($usb.scRoot)Windows\System32\reagentc" -ArgumentList "/SetREImage /Path $($usb.recovery.FullName) /target $($usb.scRoot)Windows" -Silent
        }
        
        # Boot environment
        Write-Host "`nConfiguring boot environment..." -ForegroundColor Yellow
        Invoke-CmdLine -Application "$($usb.scRoot)Windows\System32\bcdboot" -ArgumentList "$($usb.scRoot)Windows /s s: /f all"
        
        # Copy unattended.xml
        if (Test-Path "$($usb.winPESource)scripts\unattended.xml") {
            Write-Host "Copying unattended.xml..." -ForegroundColor Cyan
            if (-not (Test-Path "$($usb.scRoot)Windows\Panther")) {
                New-Item "$($usb.scRoot)Windows\Panther" -ItemType Directory -Force | Out-Null
            }
            Copy-Item "$($usb.winPESource)\scripts\unattended.xml" "$($usb.scRoot)Windows\Panther\unattended.xml"
        }
        
        # Copy provisioning packages
        if (Test-Path "$($usb.winPESource)scripts\*.ppkg") {
            Write-Host "Copying provisioning packages..." -ForegroundColor Cyan
            Copy-Item "$($usb.winPESource)\scripts\*.ppkg" "$($usb.scRoot)Windows\Panther\"
        }
        
        # Remove public shortcuts
        Remove-Item "$($usb.scRoot)Users\public\Desktop\*.lnk" -Force -ErrorAction SilentlyContinue
        
        # Apply drivers
        if (Get-ChildItem "$($usb.driverPath)\$deviceModel\*.inf" -Recurse -ErrorAction SilentlyContinue) {
            Write-Host "`nApplying device drivers..." -ForegroundColor Yellow
            Add-Driver -DriverPath "$($usb.driverPath)\$deviceModel" -ScratchDrive $usb.scRoot
        }
        
        # Apply packages
        if (Get-ChildItem "$($usb.packagePath)\*.cab" -Recurse -ErrorAction SilentlyContinue) {
            Write-Host "`nApplying packages..." -ForegroundColor Yellow
            Add-Package -PackagePath "$($usb.packagePath)\" -ScratchDrive $usb.scRoot -ScratchPath $usb.scratch
        }
    }
    
    $completed = $true
}
catch {
    $errorMsg = $_.Exception.Message
}
finally {
    $sw.Stop()
    
    if ($exitEarly) {
        $errorMsg = $null
    }
    
    if ($errorMsg) {
        Write-Host "`nERROR: $errorMsg" -ForegroundColor Red
    } else {
        $status = if ($completed) { "completed" } else { "stopped prematurely" }
        Write-Host "`nProvisioning $status. Time taken: $($sw.Elapsed)" -ForegroundColor Green
    }
}
#endregion
