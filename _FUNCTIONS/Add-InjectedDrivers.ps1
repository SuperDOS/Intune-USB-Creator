function Add-InjectedDrivers {
    param(
        [Parameter(Mandatory)]
        [string]$MountPath,

        [Parameter(Mandatory)]
        [string]$DriverPath
    )

    if (-not (Test-Path $DriverPath)) {
        Write-Warning "Driver path not found: $DriverPath"
        return
    }

    $drivers = Get-ChildItem $DriverPath -Recurse -Filter *.inf -ErrorAction SilentlyContinue

    if (-not $drivers) {
        Write-Warning "No driver .inf files found in $DriverPath"
        return
    }

    Write-Host "Injecting $($drivers.Count) drivers from $DriverPath..."

    & dism.exe `
        /Image:"$MountPath" `
        /Add-Driver `
        /Driver:"$DriverPath" `
        /Recurse `
        /ForceUnsigned `
        /LogLevel:2
}
