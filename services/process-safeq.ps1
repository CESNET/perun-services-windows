#3.0.0
# Set version on the first line

<#
.SYNOPSIS
Perun provisioning script for a SafeQ Service

.DESCRIPTION
Perun provisioning script for a SafeQ Service

.NOTES
2020/07/08

#>

$safeqWatchdogFolder = "C:\safeqldifs"

try {
    # Data folder path in $global:EXTRACT_DIR_PATH

    # Set service name for logging purposes
    $SERVICE_NAME = 'safeq'

    Copy-Item -Path "$($global:EXTRACT_DIR_PATH)\*" -Destination $safeqWatchdogFolder -Filter "safeq" -Force
    
    # Return value (0 = OK, 0 + Write-Error = Warning, 0< = Error)
    return 0
} catch {
    # Log the error
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}