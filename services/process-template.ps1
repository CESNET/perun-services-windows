#3.0.0
# Set version on the first line

<#
.SYNOPSIS
Perun provisioning script for a template service

.DESCRIPTION
Perun provisioning script for a template service

.NOTES
2019/04/15

https://www.muni.cz/lide/433479-david-stencel
#>

try {
    # Data folder path in $global:EXTRACT_DIR_PATH
    
    # Set service name for logging purposes
    $SERVICE_NAME = 'templateService'
    
    # Return value (0 = OK, 0 + Write-Error = Warning, 0< = Error)
    return $templateReturnCode
} catch {
    # Log the error
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}