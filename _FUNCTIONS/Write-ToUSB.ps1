function Write-ToUSB {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        $path,

        [parameter(Mandatory = $true)]
        $destination
    )
    
    $objShell = $null
    try {
        $progressDiag = "&H0&"
        $yesToAll = "&H16&"
        $simpleProgress = "&H100&"
        $opts = $progressDiag + $yesToAll + $simpleProgress
        $objShell = New-Object -ComObject "Shell.Application"
        $objFolder = $objShell.NameSpace($destination)
        $objFolder.CopyHere($path, $opts)
    }
    catch {
        $errorMsg = $_
    }
    finally {
        if ($objShell) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($objShell) | Out-Null
        }
        if ($errorMsg) {
            Write-Host "`n"
            Write-Warning $errorMsg
        }
        else {
            Write-Host $([char]0x221a) -ForegroundColor Green
        }
    }
}
