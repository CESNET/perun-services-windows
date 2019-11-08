#3.0.0

<#
.SYNOPSIS
Perun provisioning script for O365.


.DESCRIPTION
Perun provisioning script for O365.


.NOTES
2019/04/15

https://www.muni.cz/lide/433479-david-stencel
#>

#function Write-PerunLog ($LogLevel, $LogMessage)
#{
#    write-host $LogMessage
#}

<#
.SYNOPSIS
Function handles batch request processing

.PARAMETER Commandlet
PowerShell commandlet to run with each of the input parameters

.PARAMETER ObjectName
Object name to be modified to differentiate it in the log

.PARAMETER ParametersSourceFile
Path to the file with parameters
#>
function handle_batch {
    param (
        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $Commandlet,

        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $ObjectName,

        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $ParametersSourceFile
    )

    $waitTime = 60 * $O365_SYNC_TIMEOUT # sec

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "source file: $ParametersSourceFile"
    
    $perunEntries = Get-Content $ParametersSourceFile -Encoding UTF8 | ConvertFrom-Json

    $perunEntriesCount = ($perunEntries | Measure-Object).Count

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage 'calling send batch'

    # Send set-mailbox for all users
    $respQueue = send_batch -Commandlet $Commandlet -JsonData $perunEntries

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Response queue: $respQueue."

    if ([String]::IsNullOrEmpty($respQueue)) {
        throw "Send batch returned null respQueue."
    }

    # Wait for results
    $waitResult = wait_for_batch -queueName $respQueue -waitTime $waitTime -expectedResponseCount $perunEntriesCount

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Wait result: $waitResult"

    if (($waitResult -le 0) -or ($waitResult -lt $perunEntriesCount)) {
        throw "Batch processing did not returned enough responses."
    }

    # Get the results
    return $(receive_batch $respQueue)
}

<#
.SYNOPSIS
Funcion sends a batch request to the PowerShell web proxy.

.PARAMETER Commandlet
PowerShell commandlet to run with each of the input parameters

.PARAMETER JsonData
An array of parameters to run with the Commandlet
#>
function send_batch {
    param (
        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $Commandlet,

        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [object[]] $JsonData
    )

    $requestTimeOut = 10000 # ms

    try {

        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "jsondata: $JsonData"

        $requestBody = @{command = $Commandlet; parameters = $JsonData } | ConvertTo-Json -Depth 5 -Compress
        
        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Sending batch body: $requestBody."

        # Send-MuniRequestBatch
        $PSWSresult = Invoke-RestMethod -Method Put -Uri "$PSWS_API_URI/Set-MuniRequestBatch" -Body $requestBody -ContentType 'application/json' -CertificateThumbprint $($remoteHostCert.Thumbprint)
        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "result: $PSWSresult"
    } catch {

        # Cannot access PSWS, bad request, internal error
        throw "send_batch: PSWS REST request failed: $($_.Exception)"
    }
    
    #timeout?

    return $PSWSresult.respQueue
}

<#
.SYNOPSIS
Funcion waits for a batch request to process by the PowerShell web proxy.
It counts the number of responses in the response queue till it matches the expected amount.

.PARAMETER QueueName
Response queue name where the results should be expected

.PARAMETER WaitTime
Timeout for a batch request

.PARAMETER ExpectedResponseCount
Expected number of responses in the response queue
#>
function wait_for_batch {
    param (
        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $QueueName,

        [parameter(Mandatory = $true)]
        [int] $WaitTime, # sec

        [parameter(Mandatory = $true)]
        [int] $ExpectedResponseCount
    )
    
    $requestTimeOut = 10000 #ms
    
    $waitEndTime = $(Get-Date).AddSeconds($WaitTime)

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Waiting for batch till $waitEndTime."

    $currentCount = 0

    while ($(Get-Date) -lt $waitEndTime) {

        try {

            # Get-MuniMRQMessageCount
            $PSWSresult = Invoke-RestMethod -Method Get -Uri "$PSWS_API_URI/Get-MuniRMQMessageCount/$QueueName" -CertificateThumbprint $($remoteHostCert.Thumbprint)
        } catch {

            # Cannot access PSWS, bad request, internal error
            throw "wait_for_batch: PSWS REST request failed: $($_.Exception)"
        }

        if ([int]$PSWSresult -ge $ExpectedResponseCount) {
                
            # Expected number of messages in the response queue
            return [int]$PSWSresult
        }

        # Update current number of messages in the response queue
        $currentCount = [int]$PSWSresult

        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Current count of responses: $currentCount."

        Start-Sleep -Seconds 20
    }

    return $currentCount
}

<#
.SYNOPSIS
Funcion collects all responses from the response queue.

.PARAMETER QueueName
Response queue name where the results should be expected
#>
function receive_batch {
    param (
        [parameter(Mandatory = $true)]
        #[ValidateNotNullOrEmpty]
        [string] $QueueName
    )

    $requestTimeOut = 60000 # ms

    try {

        Write-PerunLog -LogLevel 'DEBUG' -LogMessage 'Get resp batch.'

        # Get-MuniResponseBatch
        $PSWSresult = Invoke-RestMethod -Method Get -Uri "$PSWS_API_URI/Get-MuniResponseBatch/$QueueName" -CertificateThumbprint $($remoteHostCert.Thumbprint)
        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "batch resp: $PSWSresult"
    } catch {

        # Cannot access PSWS, bad request, internal error
        throw "receive_batch: PSWS REST request failed: $($_.Exception)"
    }

    #timeout?

    return $PSWSresult
}

<#
.SYNOPSIS
Funcion runs handle_batch and process the results for mailboxes
#>
function process_users {

    $updateResults = handle_batch -Commandlet 'Set-MuniMailbox' -ObjectName 'User' -ParametersSourceFile "$EXTRACT_DIR_PATH\$($SERVICE_NAME)_users.json"
    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Update result: $updateResults."

    if ([String]::IsNullOrEmpty($updateResults)) {

        throw "Received batch returned null results."
    }

    # Validate the results
    $updateResultsCount = ($updateResults.psStatus | Measure-Object).Count

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "resp count: $($updateResultsCount)"

    for ($i = 0; $i -lt $updateResultsCount; ++$i) {
        if ($updateResults.psStatus[$i] -eq 'Error') {
            
            ++$script:COUNTER_USERS_FAILED
            Write-PerunLog -LogLevel 'WARNING' -LogMessage "User update failed: $($updateResults.psOutput[$i])"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|User update failed: $($updateResults.psOutput[$i])")
        } else {

            ++$script:COUNTER_USERS_UPDATED
            Write-PerunLog -LogLevel 'DEBUG' -LogMessage "updated: $($updateResults.psOutput[$i])"
        }
    }
}

<#
.SYNOPSIS
Funcion runs handle_batch and process the results for groups
#>
function process_groups {
    
    $updateResults = handle_batch -Commandlet 'Set-MuniGroup' -ObjectName 'Group' -ParametersSourceFile "$EXTRACT_DIR_PATH\$($SERVICE_NAME)_groups.json"

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Update result: $updateResults."

    if ([String]::IsNullOrEmpty($updateResults)) {

        throw "Received batch returned null results."
    }

    # Validate the results
    $updateResultsCount = ($updateResults.psStatus | Measure-Object).Count

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "resp count: $($updateResultsCount)"

    for ($i = 0; $i -lt $updateResultsCount; ++$i) {
        if ($updateResults.psStatus[$i] -eq 'Error') {
            
            ++$script:COUNTER_GROUPS_FAILED
            Write-PerunLog -LogLevel 'WARNING' -LogMessage "Group update failed: $($updateResults.psOutput[$i])"
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARN|Group update failed: $($updateResults.psOutput[$i])")
        } else {

            ++$script:COUNTER_GROUPS_UPDATED
            Write-PerunLog -LogLevel 'DEBUG' -LogMessage "updated: $($updateResults.psOutput[$i])"
        }
    }
}


#---------------- Main


try {
    
    # Variables from process-o365_full.ps1
    # $PSWS_API_URI
    # $remoteHostCert        

    # $TEMP_DIR_PATH
    # $EXTRACT_DIR_PATH
    #$EXTRACT_DIR_PATH = 'C:\Scripts\perun\debug'
    
    $SERVICE_NAME = 'o365_mu'

    $script:COUNTER_USERS_UPDATED = 0
    $script:COUNTER_USERS_FAILED = 0

    $script:COUNTER_GROUPS_UPDATED = 0
    $script:COUNTER_GROUPS_FAILED = 0


    Write-PerunLog -LogLevel 'DEBUG' -LogMessage "O365 started."

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage 'Process groups.'
    process_groups

    Write-PerunLog -LogLevel 'DEBUG' -LogMessage 'Process users.'
    process_users


    Write-PerunLog -LogLevel 'INFO' -LogMessage "Users`tUpdated: $script:COUNTER_USERS_UPDATED, Failed: $script:COUNTER_USERS_FAILED"
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Groups`tUpdated: $script:COUNTER_GROUPS_UPDATED, Failed: $script:COUNTER_GROUPS_FAILED"

    if ($script:COUNTER_USERS_FAILED -or $script:COUNTER_GROUPS_FAILED) {
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Some O365 updates failed."

        return 2
    }

    return 0

} catch {
    
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}