<#
.SYNOPSIS
Connector for Perun IdM.

.DESCRIPTION
Connector for Perun IdM.

Saves the input Base64File (ZIP file expected), expands the archive, and starts service scripts

.PARAMETER Base64File
ZIP file in Base64 with Perun data

.EXAMPLE

.\perun_connector -Base64File 'AB32b4...4l'

.EXAMPLE authorized_keys file
command="& c:\scripts\perun\perun_connector.ps1 $input; exit $LASTEXITCODE" ssh-rsa AAAAB3...S

.NOTES
2019/04/15

Uses 7Zip4PowerShell from https://github.com/thoemmi/7Zip4Powershell

.LICENSE
Copyright (C) {2019} {David Štencel https://www.muni.cz/lide/433479-david-stencel}

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
USA
#>

#function perun {
param (
    [parameter(ValueFromPipeline = $true, Mandatory = $true)]
    #[ValidateNotNullOrEmpty]
    [string] $Base64File
)

#--------------------- Functions

function run_pre_hooks {
    if (Test-Path $CUSTOM_SCRIPTS_DIR) {
        Get-ChildItem $CUSTOM_SCRIPTS_DIR -Filter "pre-$targetService-*.ps1" `
        | Sort-Object `
        | Select-Object -ExpandProperty Name `
        | ForEach-Object {
            Write-PerunLog -LogLevel 'INFO' -LogMessage "Running $_"
            $null = . "$CUSTOM_SCRIPTS_DIR\$_"
        }
    }
}

function run_post_hooks {
    if (Test-Path $CUSTOM_SCRIPTS_DIR) {
        Get-ChildItem $CUSTOM_SCRIPTS_DIR -Filter "post-$targetService-*.ps1" `
        | Sort-Object `
        | Select-Object -ExpandProperty Name `
        | ForEach-Object {
            Write-PerunLog -LogLevel 'INFO' -LogMessage "Running $_"
            $null = . "$CUSTOM_SCRIPTS_DIR\$_"
        }
    }
}

$global:ErrorActionPreference = 'Stop'
$global:ProgressPreference = 'SilentlyContinue'


#--------------------- Set environemt and variables

try {
  
    . "$PSScriptRoot\perun_config.ps1" # settings variables
    . "$PSScriptRoot\perun_logger.ps1" # logging function

    Import-Module "$PSScriptRoot\7Zip4Powershell\1.9.0\7Zip4PowerShell.psd1" # for TAR support
    Import-Module -Name Microsoft.PowerShell.Archive # for simple log archiving

    Write-PerunLog -LogLevel 'INFO' -LogMessage "$SERVICE_NAME has started."

    try {
        # Create a directory for temporary files
        if (-not (Test-Path $TEMP_DIR_PATH)) {
            $null = New-Item -ItemType Directory -Path $TEMP_DIR_PATH
        }
    } catch {
        throw "Cannot create temp dir at $TEMP_DIR_PATH."
    }

    #--------------------- Store and check inputs  

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Saving the input file.'
    $byteArray = [System.Convert]::FromBase64String($Base64File)
    [System.IO.File]::WriteAllBytes("$TEMP_DIR_PATH\$INPUT_ARCH_FILE_NAME", $byteArray)

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Starting input extraction.'
    Expand-7Zip "$TEMP_DIR_PATH\$INPUT_ARCH_FILE_NAME" $EXTRACT_DIR_PATH

    $byteArray = $null

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Checking target host DNS or facility.'
    $targetHostname = Get-Content "$EXTRACT_DIR_PATH\HOSTNAME" -First 1
    $targetFacility = Get-Content "$EXTRACT_DIR_PATH\FACILITY" -First 1

    if (-not ($targetHostname -in $DNS_ALIAS_WHITELIST)) {
        if (-not ($targetFacility -in $FACILITY_WHITELIST)) {
            throw "Neither hostname ($targetHostname) nor facility ($targetFacility) on any whitelist."
        }
    }
  
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Checking service type.'
    $targetService = Get-Content "$EXTRACT_DIR_PATH\SERVICE" -First 1

    if (($targetService -in $SERVICE_BLACKLIST) -or `
        (-not ($targetService -in $SERVICE_WHITELIST))) {
        [console]::Error.WriteLine("$targetService not enabled.")
        Write-PerunLog -LogLevel 'ERROR' -LogMessage "$targetService not enabled."

        exit 2
    }

    $PROCESS_SCRIPTS_DIR = "$PSScriptRoot\process-service"
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
  
    #--------------------- Run excution scripts

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
  
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running custom pre_hooks.'
    try {
        run_pre_hooks
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Pre_hook failed: $_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Pre_hook failed: $_"
    }

    #--------------------- Run the main service process script
    #
    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running MAIN service processing'
    $processScriptReturnCode = . $PROCESS_SCRIPT_PATH
    #
    #--------------------- Run the main service process script

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Running custom post_hooks.'
    try {
        run_post_hooks
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|WARNING|Post_hook failed: $_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Post_hook failed: $_"
    }

  
  
    $script:SERVICE_NAME = 'perun_connector' # Might have been overwritten by subsequent scripts
    Write-PerunLog -LogLevel 'INFO' -LogMessage "$SERVICE_NAME has finished."

    if ($processScriptReturnCode -gt 0) {
        exit $processScriptReturnCode
    }

    exit 0
} catch {
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    
    exit 2
} finally {
    #--------------------- Cleanup

    Write-PerunLog -LogLevel 'INFO' -LogMessage "Releasing mutex $MUTEX_NAME"

    # Release lock
    if (($mutex -ne $null) -and $mutex.WaitOne(1)) {
        $mutex.ReleaseMutex()
    }

    Write-PerunLog -LogLevel 'INFO' -LogMessage 'Removing temp files.'

    # Remove temporary files
    if (Test-Path $TEMP_DIR_PATH) {
        Remove-Item -LiteralPath $TEMP_DIR_PATH -Recurse -Force
    }

    # Archive logs
    try {

        # Determine the date of which files older than specific period will be archived
        $dateToArchive = (Get-Date).AddDays(-$LOG_FILE_ARCHIVE)
        $filesToArchive = (Get-ChildItem $Global:LOG_DIR_PATH -Include "*.log" -Recurse | Where-Object { $_.LastWriteTime -le $dateToArchive }).FullName


        if ($filesToArchive -ne $null) {
          
            Compress-Archive -Path $filesToArchive -CompressionLevel Optimal -DestinationPath "$LOG_DIR_PATH\$(Get-Date $dateToArchive -f 'yyyyMMddHHmmss').zip" -ErrorAction Stop

            $filesToArchive | Remove-Item -Force -Confirm:$false
        }

        # Determine the date of which files older than specific period will be deleted
        $dateToDelete = (Get-Date).AddMonths(-$LOG_FILE_RETENTION)
        $filesToDelete = (Get-ChildItem $Global:LOG_DIR_PATH -Include "*.zip" -Recurse | Where-Object { $_.LastWriteTime -le $dateToDelete }).FullName

        if ($filesToDelete -ne $null) {

            $filesToDelete | Remove-Item -Force -Confirm:$false
        }
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Failed during log archiving: $_"
    }
}
#}