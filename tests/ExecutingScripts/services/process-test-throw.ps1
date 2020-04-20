#3.0.0
# Set version on the first line

try {

    $SERVICE_NAME = 'test-throw'
    throw "Oops, something is wrong."
    # Return value (0 = OK, 0 + Write-Error = Warning, 0< = Error)
    return 0
} catch {
    # Log the error
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}