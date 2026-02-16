function Get-WinREFromInstallWim {
    <#
    .SYNOPSIS
        Extracts WinRE.wim and WiFi DLLs from a Windows install.wim file
    .DESCRIPTION
        Mounts the specified image index from install.wim and extracts:
        - WinRE.wim from Windows\System32\Recovery\Winre.wim
        - WiFi support DLLs (dmcmnutils.dll, mdmregistration.dll) for WinRE WiFi functionality
    .PARAMETER InstallWimPath
        Path to the install.wim file
    .PARAMETER ImageIndex
        Image index to mount (corresponds to Windows edition)
    .PARAMETER Destination
        Destination folder where WinRE.wim will be extracted
    .PARAMETER WinPEFilesPath
        Path to WINPEFILES folder where WiFi DLLs will be copied
    .EXAMPLE
        Get-WinREFromInstallWim -InstallWimPath "C:\Images\install.wim" -ImageIndex 6 -Destination "C:\Temp" -WinPEFilesPath "C:\Download\WINPEFILES"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InstallWimPath,

        [Parameter(Mandatory = $true)]
        [int]$ImageIndex,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $false)]
        [string]$WinPEFilesPath
    )

    $mountPath = "$($env:TEMP)\mount_install_wim"
    $winrePath = $null

    try {
        # Validate install.wim exists
        if (-not (Test-Path $InstallWimPath)) {
            throw "Install.wim not found at: $InstallWimPath"
        }

        # Validate image index exists in WIM
        Write-Verbose "Checking image index in install.wim..."
        $images = Get-WindowsImage -ImagePath $InstallWimPath -ErrorAction Stop
        $selectedImage = $images | Where-Object { $_.ImageIndex -eq $ImageIndex }
        
        if (-not $selectedImage) {
            throw "Image index $ImageIndex not found in install.wim. Available indexes: $($images.ImageIndex -join ', ')"
        }

        Write-Host "Extracting WinRE.wim and WiFi DLLs from install.wim (Index: $ImageIndex - $($selectedImage.ImageName))..." -ForegroundColor Cyan

        # Create mount directory
        if (Test-Path $mountPath) {
            Write-Verbose "Cleaning up existing mount point..."
            Remove-Item $mountPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item $mountPath -ItemType Directory -Force | Out-Null

        # Mount the install.wim
        Write-Verbose "Mounting install.wim index $ImageIndex..."
        Mount-WindowsImage -Path $mountPath -ImagePath $InstallWimPath -Index $ImageIndex -ReadOnly -ErrorAction Stop | Out-Null

        # Extract WinRE.wim
        $winreSourcePath = Join-Path $mountPath "Windows\System32\Recovery\Winre.wim"
        
        if (-not (Test-Path $winreSourcePath)) {
            throw "WinRE.wim not found in the Windows image at: $winreSourcePath"
        }

        # Ensure destination directory exists
        if (-not (Test-Path $Destination)) {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }

        # Copy WinRE.wim to destination
        $winrePath = Join-Path $Destination "winre.wim"
        
        Write-Verbose "Copying WinRE.wim to $winrePath..."
        Copy-Item -Path $winreSourcePath -Destination $winrePath -Force

        # Verify the copy
        if (Test-Path $winrePath) {
            $winreFile = Get-Item $winrePath
            Write-Host "WinRE.wim extracted successfully ($([math]::Round($winreFile.Length / 1MB, 2)) MB)" -ForegroundColor Green
        }
        else {
            throw "Failed to copy WinRE.wim to destination"
        }

        # Extract WiFi DLLs if WinPEFilesPath is provided
        if ($WinPEFilesPath) {
            Write-Host "Extracting WiFi support DLLs for WinRE..." -ForegroundColor Cyan
            
            # Define WiFi DLLs to extract
            $wifiDlls = @(
                "Windows\System32\dmcmnutils.dll",
                "Windows\System32\mdmregistration.dll"
            )

            # Create destination directory
            $dllDestination = Join-Path $WinPEFilesPath "Windows\System32"
            if (-not (Test-Path $dllDestination)) {
                New-Item -Path $dllDestination -ItemType Directory -Force | Out-Null
            }

            $extractedCount = 0
            foreach ($dll in $wifiDlls) {
                $sourcePath = Join-Path $mountPath $dll
                $fileName = Split-Path $dll -Leaf
                $destPath = Join-Path $dllDestination $fileName

                if (Test-Path $sourcePath) {
                    Copy-Item -Path $sourcePath -Destination $destPath -Force
                    Write-Verbose "Extracted: $fileName"
                    $extractedCount++
                }
                else {
                    Write-Warning "WiFi DLL not found in image: $dll"
                }
            }

            if ($extractedCount -gt 0) {
                Write-Host "WiFi DLLs extracted: $extractedCount/$($wifiDlls.Count)" -ForegroundColor Green
            }
        }

        return $winrePath
    }
    catch {
        Write-Error "Failed to extract WinRE.wim: $($_.Exception.Message)"
        throw
    }
    finally {
        # Always attempt to dismount
        if (Test-Path $mountPath) {
            Write-Verbose "Dismounting install.wim..."
            try {
                Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction Stop | Out-Null
                Start-Sleep -Seconds 2
                Remove-Item $mountPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Failed to dismount install.wim cleanly. You may need to manually clean up: $mountPath"
                Write-Warning "Run: Dismount-WindowsImage -Path '$mountPath' -Discard"
            }
        }
    }
}