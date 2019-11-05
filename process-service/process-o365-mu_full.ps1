#3.0.0

<#
.SYNOPSIS
Perun provisioning script for the Office 365 service including AD, AAD, and O365.

Requires process-o365_full.config file.


.DESCRIPTION
Perun provisioning script for the Office 365 service including AD, AAD, and O365.


.NOTES
2019/04/15

https://www.muni.cz/lide/433479-david-stencel
#>

try {
    $config = Get-Content $($PSCommandPath -replace '.ps1', '.config') -Encoding UTF8 | ConvertFrom-Json

    $PSWS_API_URI = $config.pswsApiUri
    $PSWS_ACCOUNT_DN = $config.pswsAccountDN
    $CERT_STORAGE_PATH = $config.certStoragePath
    $CERT_EXPIRATION_WARNING_DAYS = $config.certExpirationWarningDays

    $AADC_HOST_NAME = $config.aadcHostName
    $AADC_SYNC_TIMEOUT = $config.aadcSyncTimeoutInMinutes
    $O365_SYNC_TIMEOUT = $config.o365SyncTimeoutInMinutes



    #------------- Get a certificate thumbprint to call PSWS REST API

    # Get the newest $remoteAccount certificate hash from the local store
    $remoteHostCert = (Get-ChildItem -Path $CERT_STORAGE_PATH `
        | Where-Object { $_.Subject -match $PSWS_ACCOUNT_DN } `
        | Sort-Object -Property NotAfter -Descending) | Select-Object -First 1 #[0] # Cannot use 'Select-obejct -First 1' because of JEA???

    # Check the certificate validity
    if ($remoteHostCert -eq $null) {
        throw "Cannot get private key cert from $CERT_STORAGE_PATH for $PSWS_ACCOUNT_DN."
    }
        
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Remote host client cert valid to $($remotehostcert.notafter)"

    if ($remoteHostCert.NotAfter -lt $(Get-Date)) {
        throw "Private key cert from $CERT_STORAGE_PATH for subject $PSWS_ACCOUNT_DN has expired."
    }

    if ($remoteHostCert.NotAfter -lt $(Get-Date).AddDays(-$CERT_EXPIRATION_WARNING_DAYS)) {
        Write-PerunLog -LogLevel 'WARN' -LogMessage "Private key cert from $CERT_STORAGE_PATH for subject $PSWS_ACCOUNT_DN is going to expire."
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Private key cert from $CERT_STORAGE_PATH for subject $PSWS_ACCOUNT_DN is going to expire.")
    }


    #------------- Run AD processing

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running process AD.'

    $adReturnCode = . "$PROCESS_SCRIPTS_DIR\process-ad-mu.ps1"

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "AD return code: $adReturnCode."

    if ($adReturnCode -gt 0) {
        return $adReturnCode
    }
        

    #------------- Run AADC sync

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running process AADC.'

    $aadcReturnCode = . "$PROCESS_SCRIPTS_DIR\process-aadc-mu.ps1"

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "ADDC return code: $aadcReturnCode."

    if ($aadcReturnCode -gt $adReturnCode) {
        return $aadcReturnCode
    }

    #------------- Run O365 processing

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running process O365.'

    $o365ReturnCode = . "$PROCESS_SCRIPTS_DIR\process-o365-mu.ps1"

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "o365 return code: $o365ReturnCode."
    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "$((($adReturnCode,$aadcReturnCode,$o365ReturnCode) | Sort-Object -Descending)[0])"

    return $o365ReturnCode
} catch {
    
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}