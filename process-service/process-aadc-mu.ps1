#0.1

<#
.SYNOPSIS
Perun provisioning script to run AADC sync.


.DESCRIPTION
Perun provisioning script to run AADC sync.


.NOTES
2019/04/15

https://www.muni.cz/lide/433479-david-stencel
#>

function Start-MuniAADCSync {

    $requestTimeOut = 10000 # ms

    $waitEndTime = $(Get-Date).AddMinutes($AADC_SYNC_TIMEOUT)

    while ($(Get-Date) -lt $waitEndTime) {

        try {
            Write-PerunLog -LogLevel 'DEBUG' -LogMessage "procAADC-start: $(whoami)/$($remoteHostCert.Thumbprint)"

            # Start-MuniAADCSync
            $PSWSresult = Invoke-RestMethod -Method Put -Uri "$PSWS_API_URI/Start-MuniAADCSync/$($AADC_HOST_NAME)?waitTime=$($requestTimeOut)" -CertificateThumbprint $($remoteHostCert.Thumbprint)
            Write-PerunLog -LogLevel 'DEBUG' -LogMessage $($PSWSresult)
        } catch {

            # Cannot access PSWS, bad request, internal error
            throw "PSWS REST request failed: $($_.Exception)"
        }
        
        # Got some results
        if ($PSWSresult.Status -eq 'Completed') {

            # PSWS script errors
            if ($PSWSresult.PSStatus -eq 'Error') {
                throw "Starting AADC sync failed: $($PSWSresult.PSOutput.Exception)"
            }

            if ([String]::IsNullOrEmpty($PSWSresult.PSOutput)) {
                throw "Start AADC sync request returned no data."
            }

            $requestResult = $PSWSresult.PSOutput
            if (-not $requestResult.StartedNewSync) {

                Write-PerunLog -LogLevel 'DEBUG' -LogMessage 'Waiting for previous AADC sync to finish.'

                Start-Sleep -Seconds 20

                continue

            } else {
                    
                # new AADC sync started
                return 0
            }
        } else {

            # Request is still being executed
            throw "Start AADC sync request timeouted."
        }
    }
}

function Wait-MuniAADCSync {

    $requestTimeOut = 10000 #ms
        
    $waitEndTime = $(Get-Date).AddMinutes($AADC_SYNC_TIMEOUT)

    while ($(Get-Date) -lt $waitEndTime) {

        try {

            # Get-MuniAADCSyncRunStatus
            $PSWSresult = Invoke-RestMethod -Method Get -Uri "$PSWS_API_URI/Get-MuniAADCSyncRunStatus/$($AADC_HOST_NAME)?waitTime=$($requestTimeOut)" -CertificateThumbprint $($remoteHostCert.Thumbprint)
            Write-PerunLog -LogLevel 'DEBUG' -LogMessage $($PSWSresult)
        } catch {

            # Cannot access PSWS, bad request, internal error
            throw "PSWS REST request failed: $($_.Exception)"
        }
            
        # Got some results
        if ($PSWSresult.Status -eq 'Completed') {

            # PSWS script errors
            if ($PSWSresult.PSStatus -eq 'Error') {
                throw "Checking AADC sync status failed: $($PSWSresult.PSOutput.Exception)"
            }
    
            if ([String]::IsNullOrEmpty($PSWSresult.PSOutput)) {
                throw "Checking AADC sync status request returned no data."
            }
    
            $requestResult = $PSWSresult.PSOutput
            if (-not $requestResult.ADSyncCycleInProgress) {
                # AADC sync finished
                return 0
            }
        }

        Start-Sleep -Seconds 20
    }

    throw "AADC sync did not finish in $AADC_SYNC_TIMEOUT minutes."
}


#-------------------- Main

try {

    # Used variables from process-o365_full.ps1
    # $PSWS_API_URI
    # $remoteHostCert
    # $AADC_SYNC_TIMEOUT

    $SERVICE_NAME = 'aadc-mu'

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "AADC processing started."

    # Run the sync
    $returnCode = Start-MuniAADCSync

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Start AADC return code: $returnCode."

    if ($returnCode -gt 0) {
        return $returnCode
    }

    # Wait for the sync to complete
    return Wait-MuniAADCSync

} catch {

    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    Write-Error "$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_"

    return 2
}