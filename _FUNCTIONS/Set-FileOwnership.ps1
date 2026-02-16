            # Helper function to take ownership and set full control
            function Set-FileOwnership {
                param([string]$FilePath, [object]$Owner)
                try {
                    $acl = Get-Acl $FilePath
                    $acl.SetOwner($Owner)
                    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Owner, "FullControl", "Allow")
                    $acl.SetAccessRule($accessRule)
                    Set-Acl $FilePath $acl
                    return $true
                }
                catch {
                    Write-Verbose "Failed to set ownership on $FilePath : $_"
                    return $false
                }
            }