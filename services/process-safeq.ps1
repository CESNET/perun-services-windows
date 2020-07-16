#3.0.0
# Set version on the first line

<#
.SYNOPSIS
Perun provisioning script for a SafeQ Service

.DESCRIPTION
Perun provisioning script for a SafeQ Service

.NOTES
2020/07/08

Requires LDIFDIFF utility, download here: https://github.com/nxadm/ldifdiff
Variable $LDIFDIFFTOOL specifies the path to the tool.

#>

# Define variables
$safeqWatchdogFolder = "C:\safeqldifs"
$safeqDataFolder = "C:\safeqData"
$perunBackupFolder = Join-Path $safeqDataFolder "perun-backup"
$LDIFDIFFTOOL = "$PSScriptRoot\ldifdiff.exe"

if (-not(Test-Path $LDIFDIFFTOOL)){
    Write-Error "LDIF Utility is not installed, SafeQ ldif files could not be processed, please see notes of the 'process-safeq.ps1'."
    return 2
}
if (-not(Test-Path $safeqWatchdogFolder) -or -not(Test-Path $safeqDataFolder)){
    Write-Error "SafeQ data or watch folders are not set up."
    return 2
}
if (-not(Test-Path $perunBackupFolder)){
    Write-PerunLog -LogLevel 'INFO' -LogMessage "Created folder $perunBackupFolder"
    New-Item -ItemType Directory -Path $perunBackupFolder 
}

try {
    # Set service name for logging purposes
    $SERVICE_NAME = 'safeq'

    $newContent = "safeq"
    $oldContent = "safeq-latest.ldif"
    $actualContent = "safeq.ldif"

    $oldContentPath = Join-Path $safeqDataFolder $oldContent
    $newContentPath = Join-Path $safeqDataFolder $newContent
    $actualContentPath = Join-Path $safeqDataFolder $actualContent

    Copy-Item -Path "$($global:EXTRACT_DIR_PATH)\*" -Destination $safeqDataFolder -Filter "safeq" -Force

    if (-not(Test-Path $newContentPath)){
        Write-Error "No new SafeQ content file was received from Perun."
        return 2
    }

    if (-not(Test-Path $oldContentPath)){
        $null = New-Item -Path $safeqDataFolder -Name $oldContent -ItemType File
    }
    # Create empty LDIF so the LDIFDIFF utility could write in it.
    $null = New-Item -Path $safeqDataFolder -Name $actualContent -ItemType File -Force
    # ldifdiff.exe source target
    #   source - newContent
    #   target - oldContent
    Start-Process -FilePath $LDIFDIFFTOOL -ArgumentList @($newContentPath, $oldContentPath) -RedirectStandardOutput $actualContentPath -NoNewWindow -Wait

    # Moving generated LDIF to hot folder.
    if ((Get-Content $actualContentPath | Measure-Object | Select-Object -ExpandProperty Count) -gt 0){
        Move-Item -Path "$safeqDataFolder\*" -Destination "$safeqWatchdogFolder" -Filter "safeq.ldif" -Force
    } else {
        #Write-PerunLog -LogLevel 'INFO' -LogMessage "Generated LDIF has no changes"
        Remove-Item "$safeqWatchdogFolder\$actualContent" -ErrorAction SilentlyContinue
    }
    # Backing up an actual content ldif.
    Copy-Item -Path $newContentPath -Destination "$perunBackupFolder\safeq-$(Get-Date -format 'yyyy-MM-dd-HH-mm-ss').ldif" -Force
    # Remove old content ldif
    Remove-Item -Path $oldContentPath -Force
    Rename-Item -Path $newContentPath -NewName "$oldContent" -Force

    # Return value (0 = OK, 0 + Write-Error = Warning, 0< = Error)
    return 0
} catch {
    # Log the error
    Write-PerunLog -LogLevel 'ERROR' -LogMessage "$_"
    [console]::Error.WriteLine("$(Get-Date -format 'yyyy-MM-ddTHH-mm')|$SERVICE_NAME|ERROR|$_")

    return 2
}