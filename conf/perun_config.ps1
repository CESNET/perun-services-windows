<#
.SYNOPSIS
Config script for the Perun IdM connector for Windows.

.DESCRIPTION
Config script for the Perun IdM connector for Windows.
Runs before the connector.

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

# Fallback if path is not valid
if ($null -eq $INSTALLATION_PATH){
    $global:INSTALLATION_PATH = "C:\Program Files (x86)\PERUN Connector"
}

# Connector name
$SERVICE_NAME = 'perun_connector'
# Perun.Major.Minor data/script version
$SCRIPT_VERSION = '3.0.0'
$global:LOG_DIR_PATH = "$INSTALLATION_PATH\Logs"
$global:LOG_FILE_PATH = "$LOG_DIR_PATH\$(Get-Date -f 'yyyyMMddHHmmss')_$SERVICE_NAME-$PID.log"
$global:LOG_LEVEL = 'DEBUG'
$global:LOG_MODE = 'JSON' #'CSV'
# Log retention
$LOG_FILE_ARCHIVE = 30 # days
$LOG_FILE_RETENTION = 6 # months
$global:TEMP_DIR_PATH = "$INSTALLATION_PATH\Tmp_$(Get-Date -f 'yyyyMMddHHmmss')_$SERVICE_NAME-$PID"
$INPUT_ARCH_FILE_NAME = 'perun-input.tar'
$global:EXTRACT_DIR_PATH = "$TEMP_DIR_PATH\extracted"
$global:PROCESS_SCRIPTS_DIR = "$INSTALLATION_PATH\services"

# Explicitly disable services
$SERVICE_BLACKLIST = @()	# syntax: @('item1','item2','item3')
# Enable services
$SERVICE_WHITELIST = @() # syntax: @('item1','item2','item3')

# Accept configuration only if sent to one of these hostnames
# Prevents someone to configure perun to send malicious configuration via dns alias or ip address
$DNS_ALIAS_WHITELIST = @( [System.Net.Dns]::GetHostEntry([string]$env:computername).HostName )
# If the automatic hostname check fails check manual facility attribute
$FACILITY_WHITELIST = @() # syntax: @('item1','item2','item3')