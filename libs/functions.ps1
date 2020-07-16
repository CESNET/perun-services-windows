<#
.SYNOPSIS
Stores input base64 string as TAR file.

.DESCRIPTION
Stores input base64 string as TAR file.

.PARAMETER Content
Base64 string

.NOTES 
Uses 7Zip4PowerShell from https://github.com/thoemmi/7Zip4Powershell

#>
function Save-Input {
    Param(
        [String] $Content
    )
    
    Import-Module "$INSTALLATION_PATH\libs\7Zip4Powershell\1.9.0\7Zip4PowerShell.psd1" -ErrorAction SilentlyContinue # for TAR support
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Saving the input file.'
    $byteArray = [System.Convert]::FromBase64String($Content)
    [Environment]::CurrentDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    [System.IO.File]::WriteAllBytes("$TEMP_DIR_PATH\$INPUT_ARCH_FILE_NAME", $byteArray)

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Starting input extraction.'
    Expand-7Zip "$TEMP_DIR_PATH\$INPUT_ARCH_FILE_NAME" $EXTRACT_DIR_PATH

    $byteArray = $null
}

function Remove-TempFilesDirectory {
    try {
        Write-PerunLog -LogLevel 'INFO' -LogMessage 'Removing temp files.'
        # Remove temporary files
        if (Test-Path $TEMP_DIR_PATH) {
            Remove-Item -LiteralPath $TEMP_DIR_PATH -Recurse -Force
        }
        Write-PerunLog -LogLevel 'DEBUG' -LogMessage "Temp dir: $TEMP_DIR_PATH removed."

    } catch {

        Write-PerunLog -LogLevel 'ERROR' -LogMessage "Removing temp files failed."

    }
}

function New-TempFilesDirectory {
    try {
        # Create a directory for temporary files
        if (-not (Test-Path $TEMP_DIR_PATH)) {
            $null = New-Item -ItemType Directory -Path $TEMP_DIR_PATH
        }
    } catch {
        throw "Cannot create temp dir at $TEMP_DIR_PATH."
    }
}
function Confirm-HostnameAndFacility {
    param(
        [string] $TargetHostname,
        [string] $TargetFacility
    )
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Checking target host DNS or facility.'
    if (-not ($TargetHostname -in $DNS_ALIAS_WHITELIST)) {
        if (-not ($TargetFacility -in $FACILITY_WHITELIST)) {
            throw "Neither hostname ($TargetHostname) nor facility ($TargetFacility) on any whitelist."
        }
    }
}

function Confirm-Service {
    param (
        [string] $TargetService
    )

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Checking service type.'
    if (($targetService -in $SERVICE_BLACKLIST) -or `
        (-not ($targetService -in $SERVICE_WHITELIST))) {
        [console]::Error.WriteLine("$targetService not enabled.")
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "$targetService not enabled."
        return 2
    }
    return 0
}
function Confirm-Scripts {
    param(
        [string] $TargetService
    )
    $CUSTOM_SCRIPTS_DIR = "$PROCESS_SCRIPTS_DIR\Custom"      
    $PROCESS_SCRIPT_PATH = "$PROCESS_SCRIPTS_DIR\process-$targetService.ps1"

    # Check if a service process script exists
    if (-not (Test-Path $PROCESS_SCRIPT_PATH)) {
        throw "Cannot find slave script $PROCESS_SCRIPT_PATH."
    }

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Checking script and data version.'
    $thisVersion = $SCRIPT_VERSION -split '\.' # this script
    $processVersion = (Get-Content $PROCESS_SCRIPT_PATH -First 1) -replace '#' -split '\.' # slave process-service script
    $dataVersion = (Get-Content "$EXTRACT_DIR_PATH\VERSION" -First 1) -replace '#' -split '\.' # input data version

    if (($thisVersion[0] -ne $processVersion[0]) -or `
        ($dataVersion[0] -ne $processVersion[0])) {
        throw "Data ($dataVersion), connector ($thisVersion) or service script version ($processVersion) do not match in Perun version."
    }
    if (($thisVersion[1] -ne $processVersion[1]) -or `
        ($dataVersion[1] -ne $processVersion[1])) {
        throw "Data ($dataVersion), connector ($thisVersion) or service script version ($processVersion) do not match in major version."
    }

    if (($thisVersion[2] -ne $processVersion[2]) -or `
        ($dataVersion[2] -ne $processVersion[2])) {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Data, connector or service script version do not match in minor version.")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Data ($dataVersion), connector ($thisVersion) or service script version ($processVersion) do not match in minor version."
    }

    return $PROCESS_SCRIPT_PATH
}

function Invoke-ExecutionScripts {
    param(
        [string] $TargetService,
        [string] $ProcessScript
    )

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Creating service mutex.'

    # Create lock
    $MUTEX_NAME = "Global\$targetService"
    $MUTEX_TIMEOUT = 30000 #ms
    $mutex = New-Object System.Threading.Mutex($false, $MUTEX_NAME)
  
    try {
        if (-not $mutex.WaitOne($MUTEX_TIMEOUT)) {
            throw 'Previous service run did not finish.'
        }
    } catch {
        if ($_.FullyQualifiedErrorId -eq 'AbandonedMutexException') {
            [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Previous service run abandoned its mutex (failed).")
            Write-PerunLog -LogLevel 'WARNING' -LogMessage 'Previous service run abandoned its mutex (failed).'
        } else {
            throw
        }
    }
  
    # Run Pre processing
    Invoke-PreHookScript

    #--------------------- Run the main service process script
    #
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running MAIN service processing'
    $processScriptReturnCode = . $ProcessScript
    #
    #--------------------- Run the main service process script
    
    # Run Post processing
    Invoke-PostHookScript

    return $processScriptReturnCode
}

function Invoke-PreHookScript {
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running custom pre_hooks.'
    try {
        run_pre_hooks
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Pre_hook failed: $_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Pre_hook failed: $_"
    }
}
function Invoke-PostHookScript {
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running custom post_hooks.'
    try {
        run_post_hooks
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Post_hook failed: $_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Post_hook failed: $_"
    }
}