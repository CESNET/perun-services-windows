Install-Module -Name Pester -Confirm -AcceptLicense
Import-Module "Pester" -Force
Get-Module Pester | select name,version
exit (Invoke-Pester . -Passthru).FailedCount
