Install-Module -Name Pester
Import-Module "Pester" -Force
Get-Module Pester | select name,version
exit (Invoke-Pester . -Passthru).FailedCount
