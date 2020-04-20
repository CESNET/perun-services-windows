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

$global:ErrorActionPreference = 'Stop'
$global:ProgressPreference = 'SilentlyContinue'


#--------------------- Set environemt and variables

try {
  
    Import-Module "$PSScriptRoot\libs\7Zip4Powershell\1.9.0\7Zip4PowerShell.psd1" # for TAR support
    Import-Module -Name Microsoft.PowerShell.Archive # for simple log archiving

    . "$PSScriptRoot\conf\perun_config.ps1" # settings variables
    . "$PSScriptRoot\libs\perun_logger.ps1" # logging function
    . "$PSScriptRoot\libs\hooks.ps1" # hooks
    . "$PSScriptRoot\libs\functions.ps1" # functions

    Write-PerunLog -LogLevel 'INFO' -LogMessage "$SERVICE_NAME has started."
    [Environment]::CurrentDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
    
    New-TempFilesDirectory

    #--------------------- Store and check inputs  

    Save-Input $Base64File
    
    $targetHostname = Get-Content "$EXTRACT_DIR_PATH\HOSTNAME" -First 1
    $targetFacility = Get-Content "$EXTRACT_DIR_PATH\FACILITY" -First 1
    $targetService = Get-Content "$EXTRACT_DIR_PATH\SERVICE" -First 1

    Confirm-HostnameAndFacility -TargetHostname $targetHostname -TargetFacility $targetFacility
    if (Confirm-Service -TargetService $targetService -eq 2){
        exit 2
    }
    $PROCESS_SCRIPT_PATH = Confirm-Scripts -TargetService $targetService
  
    #--------------------- Run excution scripts

    $processScriptReturnCode = Invoke-ExecutionScripts -TargetService $targetService -ProcessScript $PROCESS_SCRIPT_PATH

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

    #-------------------- Cleanup
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Releasing mutex $MUTEX_NAME"

    # Release lock
    if (($null -ne $mutex) -and $mutex.WaitOne(1)) {
        $mutex.ReleaseMutex()
    }
    
    Remove-TempFilesDirectory

    try {

        # Archive logs
        Start-PerunLogArchivation
        Start-PerunLogRotation

    } catch {

        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")
        Write-PerunLog -LogLevel 'WARNING' -LogMessage "Failed during log archivation: $_"

    }

}
#}