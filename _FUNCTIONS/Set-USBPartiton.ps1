function Set-USBPartition {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        $usbClass,

        [Parameter(Mandatory = $true)]
        [int]$diskNum
    )
    
    # Validate disk exists
    $disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
    if (-not $disk) {
        throw "Disk number $diskNum does not exist."
    }
    
    # Validate it's removable
    if ($disk.BusType -in @('SATA', 'NVMe')) {
        Write-Warning "Disk $diskNum appears to be an internal disk (BusType: $($disk.BusType))."
        $confirm = Read-Host "Are you sure you want to format this disk? Type 'YES' to confirm"
        if ($confirm -ne 'YES') {
            throw "Operation cancelled by user."
        }
    }
    
    try {
        Stop-Service -Name ShellHWDetection
        Write-Host "`nClearing Disk: $diskNum" -ForegroundColor Cyan
        if ((Get-Disk $diskNum).PartitionStyle -eq "RAW") {
            Get-Disk $diskNum | Initialize-Disk -ErrorAction SilentlyContinue -Confirm:$false
        }
        else {
            Get-Disk $diskNum | Clear-Disk -RemoveData -Confirm:$false
            Get-Disk $diskNum | Initialize-Disk -ErrorAction SilentlyContinue -Confirm:$false
        }
        # Wait for the system to recognize the changes
        Start-Sleep -Seconds 3
        Write-Host "Creating New Partions" -ForegroundColor Cyan
        $usbClass.drive = (New-Partition -DiskNumber $diskNum -Size 3GB -AssignDriveLetter | Format-Volume -FileSystem FAT32 -NewFileSystemLabel WINPE -Confirm:$false -Force).DriveLetter
        $usbClass.drive2 = (New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel Images -Confirm:$false -Force).DriveLetter
        $usbClass
    }
    catch {
        Write-Warning $_.Exception.Message
        exit(1)
    }
    finally {
        Start-Service -Name ShellHWDetection
    }
}
