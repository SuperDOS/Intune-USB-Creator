function Get-DiskToUse {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $false)]
        [int32]$diskNum
    )
    $diskList = Get-Disk | Where-Object { $_.Bustype -notin @('SATA', 'NVMe') }
    $disks = $diskList | Select-Object Number, @{Name = 'TotalSize(GB)'; Expression = { [math]::Round($_.Size / 1GB, 2) } }, @{Name = "Name"; Expression = { $_.FriendlyName } } | Sort-Object -Property Number
    if (!$diskNum) {
        $table = $disks | Format-Table | Out-Host
        $diskNum = Read-Host -Prompt "$table`Please select Desired disk number for USB creation or CTRL+C to cancel"
    }
    while ($true) {
        # Validate disk number is in list
        if ($diskNum -notin $diskList.Number) {
            Write-Host "Invalid disk number. Please select from the list." -ForegroundColor Red
            $diskNum = Read-Host -Prompt "Please select Desired disk number for USB creation or CTRL+C to cancel"
            continue
        }
    
        # Get the actual disk object
        $selectedDisk = $diskList | Where-Object { $_.Number -eq $diskNum }
        $sizeGB = [math]::Round($selectedDisk.Size / 1GB, 2)
    
        # Validate size
        if ($sizeGB -lt 8) {
            Write-Host "That disk is only $sizeGB GB. Please use a disk with at least 8GB." -ForegroundColor Red
            $diskNum = Read-Host -Prompt "Please select Desired disk number for USB creation or CTRL+C to cancel"
            continue
        }
    
        # Valid selection
        break
    }
    return $diskNum
}
