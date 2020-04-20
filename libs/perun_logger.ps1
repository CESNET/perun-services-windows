<#
.SYNOPSIS
Logger for Perun connector.

.DESCRIPTION
Logger for Perun connector.

.PARAMETER LogLevel
.PARAMETER LogMessage
.PARAMETER LogSufix
Extra note written at the end of a log line

.NOTES
2019/04/15

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

function Write-PerunLog {
    Param (
        [Parameter(Position = 0)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$LogLevel = 'INFO',

        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$LogMessage,

        [Parameter(Position = 2)]
        [string]$LogSufix = ''
    )

    try {

        #------- Set variables

        $global:logLevelDebug = 'DEBUG'
        $global:logLevelError = 'ERROR'
        $global:logLevelWarning = 'WARNING'
        $global:logLevelInfo = 'INFO'

        # Variable defined in perun_connector.ps1
        # LOG_DIR_PATH
        # LOG_FILE_PATH
        # LOG_LEVEL
        # LOG_MODE

        $global:LogLevelSwitch = $LOG_LEVEL

        $AvailableLogLevels = @($logLevelInfo, $logLevelWarning, $logLevelError, $logLevelDebug)

        if ($global:LogLevelSwitch -notin $AvailableLogLevels) {
            $global:LogLevelSwitch = $logLevelDebug
        }

        $sourceScriptName = (New-Object System.IO.FileInfo($MyInvocation.PSCommandPath)).name
        $sourceScriptLine = $MyInvocation.ScriptLineNumber


        #------- Check log level

        # End if current logLevel is lower than global logLevelSwitch
        switch ($global:LogLevelSwitch) {
            $logLevelInfo {
                if (($LogLevel -eq $logLevelDebug)) {
                    return
                }
            }
		
            $logLevelWarning {
                if (($LogLevel -eq $logLevelDebug) -or ($LogLevel -eq $logLevelInfo)) {
                    return
                }
            }
		
            $logLevelError {
                if (($LogLevel -eq $logLevelDebug) -or ($LogLevel -eq $logLevelWarning) -or ($LogLevel -eq $logLevelInfo)) {
                    return
                }
            }
        }

        #------- Write log    

        $timestamp = $(Get-Date -format 'yyyy-MM-ddTHH:mm:ss.ffffffZ')
	
        $LogMessage = $LogMessage -replace [environment]::NewLine, '' -replace '  ', ''

        if (-not (Test-Path $LOG_DIR_PATH)) {
            $null = New-Item $LOG_DIR_PATH -Type Directory
        }

        if (-not $global:logFileStream) {
            $LogPathFileStream = New-Object IO.FileStream $LOG_FILE_PATH, 'Append', 'Write', 'Read'
            $global:logFileStream = [System.IO.StreamWriter]$LogPathFileStream
            $global:logFileStream.AutoFlush = $true
            Write-PerunLog -LogLevel $logLevelDebug -LogMessage "Create new log file, powershell process id $PID"
        }
    
        $logObject = ''

        switch ($global:LOG_MODE) {
            'CSV' { $logObject = "$timestamp|$LogLevel|$PID|$sourceScriptName|$sourceScriptLine|$LogMessage|$LogSufix"; break }
            'JSON' {
                $logObject = @{
                    'timestamp'        = $timestamp; 
                    'level'            = $LogLevel;
                    'host'             = $env:COMPUTERNAME;
                    'pid'              = $PID; 
                    'sourceScriptName' = $sourceScriptName; 
                    'sourceScriptLine' = $sourceScriptLine; 
                    'guid'             = $global:Guid;
                    'objectID'         = $global:ProcessedObjectID;
                    'message'          = $LogMessage; 
                    'suffix'           = $LogSufix 
                } | ConvertTo-Json -Compress 
            }
        }
        
        $global:logFileStream.WriteLine($logObject)
    } catch {
        [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$PSCommandPath|ERROR|$_")
    }
}

function Start-PerunLogArchivation {

    # Determine the date of which files older than specific period will be archived
    $dateToArchive = (Get-Date).AddDays(-$LOG_FILE_ARCHIVE)
    $filesToArchive = (Get-ChildItem $Global:LOG_DIR_PATH -Include "*.log" -Recurse | Where-Object { $_.LastWriteTime -le $dateToArchive }).FullName

    if ($null -ne $filesToArchive) {
        Compress-Archive -Path $filesToArchive -CompressionLevel Optimal -DestinationPath "$LOG_DIR_PATH\$(Get-Date $dateToArchive -f 'yyyyMMddHHmmss').zip" -ErrorAction Stop
        $filesToArchive | Remove-Item -Force -Confirm:$false
    }
}

function Start-PerunLogRotation {
    # Determine the date of which files older than specific period will be deleted
    $dateToDelete = (Get-Date).AddMonths(-$LOG_FILE_RETENTION)
    $filesToDelete = (Get-ChildItem $Global:LOG_DIR_PATH -Include "*.zip" -Recurse | Where-Object { $_.LastWriteTime -le $dateToDelete }).FullName

    if ($null -ne $filesToDelete) {

        $filesToDelete | Remove-Item -Force -Confirm:$false
    }
}