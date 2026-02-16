function Get-WimFromIso {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$isoPath,

        [parameter(Mandatory = $true)]
        [string]$wimDestination
    )
    try {
        $mount = Mount-DiskImage -ImagePath $isoPath -PassThru
        if ($mount) {
            $volume = Get-DiskImage -ImagePath $mount.ImagePath | Get-Volume
            if (!(Test-Path $wimDestination -ErrorAction SilentlyContinue)) {
                New-Item -Path $wimDestination -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$($volume.DriveLetter)`:\sources\install.wim" -Destination "$wimDestination\install.wim"
        }
    }
    catch {
        Write-Warning $_
    }
    finally {
        if ($mount) {
            try {
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop | Out-Null
                Write-Host $([char]0x221a) -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to dismount ISO: $_"
            }
        }
    }
}
