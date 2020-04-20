. ".\conf\perun_config.ps1" # settings variables
. ".\libs\functions.ps1" # functions
. ".\libs\perun_logger.ps1" # logging function

$TEMP_DIR_PATH = ".\tests\InputChecks\Tmp_$(Get-Date -f 'yyyyMMddHHmmss')_$SERVICE_NAME-$PID"
$PROCESS_SCRIPTS_DIR = ".\tests\InputChecks\services"
$EXTRACT_DIR_PATH = "$TEMP_DIR_PATH\extracted"


Mock -CommandName Write-PerunLog -MockWith {
    param([string]$LogMessage)
    #Write-Host "Logger: $LogMessage"
}
Write-Host $PSScriptRoot
Write-Host $(pwd)
Write-Host "TEMP" + $TEMP_DIR_PATH
Write-Host "PROCESS" + $PROCESS_SCRIPTS_DIR
Write-Host "EXTRACT" + $EXTRACT_DIR_PATH

Describe 'Validate Hostname And Facility check' {
    $FACILITY_WHITELIST = @("test-facility.local")
    $hostname = [System.Net.Dns]::GetHostEntry([string]$env:computername).HostName

    It 'Valid Hostname and facility' {
        { Confirm-HostnameAndFacility -TargetHostname $hostname -TargetFacility "test-facility.local" } | Should -Not -Throw
    }
    It 'Valid Hostname and invalid facility' {
        { Confirm-HostnameAndFacility -TargetHostname $hostname -TargetFacility "test-facility.invalid.local" } | Should -Not -Throw
    }
    It 'Invalid Hostname and valid facility' {
        { Confirm-HostnameAndFacility -TargetHostname "invalid-$hostname" -TargetFacility "test-facility.local" } | Should -Not -Throw
    }
    It 'Invalid Hostname and facility' {
        { Confirm-HostnameAndFacility -TargetHostname "invalid-$hostname" -TargetFacility "test-facility.invalid.local" } | Should -Throw
    }
}

Describe 'Validate Service check' {
    $SERVICE_BLACKLIST = @("aad-filler", "share")	# syntax: @('item1','item2','item3')
    $SERVICE_WHITELIST = @("ad-fill", "process-app", "rwaa", "n\\nsad")
    
    It "Valid service check '<service>'" -TestCases @($SERVICE_WHITELIST | ForEach-Object {@{Service = $_}}){
        param(
            $service
        )
        { Confirm-Service -TargetService $service } | Should -Not -Throw
    }

    It "Invalid service check '<service>'" -TestCases @($SERVICE_BLACKLIST | ForEach-Object {@{Service = $_}}){
        param(
            $service
        )
        Confirm-Service -TargetService $service | Should -BeExactly 2
    }
}

Describe 'Validate process scripts' {
    New-TempFilesDirectory
    Save-Input (Get-Content ".\tests\base64")

    it 'Process script not found' {
        {Confirm-Scripts -TargetService "invalid-test"} | Should -Throw
    }

    it 'Process script found and is valid' {
        {Confirm-Scripts -TargetService "test"} | Should -Not -Throw
        Confirm-Scripts -TargetService "test" | Should -BeLike "*services\process-test.ps1"
    }

    it 'Process script data missmatch on Perun version' {
        {Confirm-Scripts -TargetService "perun"} | Should -Throw
    }

    it 'Process script data valid on Perun version' {
        {Confirm-Scripts -TargetService "perun-valid"} | Should -Not -Throw
    }
    it 'Process script data invalid on Major version' {
        {Confirm-Scripts -TargetService "major"} | Should -Throw
    }
    it 'Process script data invalid on Minor version' {
        {Confirm-Scripts -TargetService "minor"} | Should -Not -Throw
        Confirm-Scripts -TargetService "minor" | Should -BeLike "*services\process-minor.ps1" 
    }

    Remove-TempFilesDirectory
}