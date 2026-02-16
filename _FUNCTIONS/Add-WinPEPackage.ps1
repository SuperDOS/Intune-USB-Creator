function Add-WinPEPackage {
    param (
        [Parameter(Mandatory)]
        [string]$MountPath,
        
        [Parameter(Mandatory)]
        [string]$Package,
        
        [Parameter(Mandatory)]
        [string]$PackagePath
    )
    
    $cab = Join-Path $PackagePath "$Package.cab"
    $lang = Join-Path $PackagePath "en-us\$Package`_en-us.cab"
    
    # Validate files exist
    if (-not (Test-Path $cab)) {
        throw "Package not found: $cab"
    }
    if (-not (Test-Path $lang)) {
        Write-Warning "Language pack not found: $lang - skipping"
    }
    
    Write-Host "Installing $Package"
    $result = dism /image:$MountPath /Add-Package /PackagePath:$cab /Quiet /NoRestart
    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed to install $Package. Exit code: $LASTEXITCODE"
    }

    if (Test-Path $lang) {
        $result = dism /image:$MountPath /Add-Package /PackagePath:$lang /Quiet /NoRestart
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "DISM failed to install language pack for $Package. Exit code: $LASTEXITCODE"
        }
    }
}