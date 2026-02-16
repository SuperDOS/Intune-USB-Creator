function Test-IsDirectoryEmpty {

    [CmdletBinding()]
    [OutputType([Management.Automation.PSCustomObject])]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [IO.DirectoryInfo[]] $Path
    )

    process {
        foreach ($dir in $Path) {
            $dir.Refresh()

            if (!$dir.Exists) {
                Write-Warning ("'{0}' directory not found." -f $dir.FullName)
                continue
            }

            $isEmpty = $true
            try {
                # Check files in root directory first
                if (@($dir.EnumerateFiles()).Count -gt 0) {
                    $isEmpty = $false
                }
                else {
                    # Check subdirectories
                    foreach ($subDir in $dir.EnumerateDirectories('*', [IO.SearchOption]::AllDirectories)) {
                        if (@($subDir.EnumerateFiles()).Count) {
                            $isEmpty = $false
                            break
                        }
                    }
                }
            }
            catch [UnauthorizedAccessException] {
                $isEmpty = $false
                Write-Warning ('{0} Cannot reliably determine if empty.' -f $_.Exception.Message)
            }
            catch {
                # Generically handle other exceptions.
                $isEmpty = $false
                $PSCmdlet.WriteError($_)
            }

            [pscustomobject] @{
                Path    = $dir.FullName
                IsEmpty = $isEmpty
            }
        }
    }
}
