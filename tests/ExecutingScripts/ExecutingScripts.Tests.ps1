. ".\conf\perun_config.ps1" # settings variables
. ".\libs\functions.ps1" # functions
. ".\libs\perun_logger.ps1" # logging function

$TEMP_DIR_PATH = ".\tests\ExecutingScripts\Tmp_$(Get-Date -f 'yyyyMMddHHmmss')_$SERVICE_NAME-$PID"
$PROCESS_SCRIPTS_DIR = ".\tests\ExecutingScripts\services"
$EXTRACT_DIR_PATH = "$TEMP_DIR_PATH\extracted"


Mock -CommandName Write-PerunLog -MockWith {
    param([string]$LogMessage)
    #Write-Host "Logger: $LogMessage"
}

Describe "Check process scripts" {

    it "previous process" -Pending {
        $targetService = "test"
        $ProcessScript = "$PROCESS_SCRIPTS_DIR\*$targetService.ps1"

        Start-Process "powershell.exe" -ArgumentList "-File .\tests\ExecutingScripts\previousprocess.ps1" -RedirectStandardOutput "test.txt" -RedirectStandardError "test-err.txt"
        Start-sleep -Seconds 1
        Write-Host "ook"
        { Invoke-ExecutionScripts -TargetService $targetService -ProcessScript $ProcessScript; $mutex = New-Object System.Threading.Mutex($false, "Global\$targetService"); Start-sleep 10; $mutex.WaitOne(1); $mutex.ReleaseMutex() } | Should -Throw
    }

    it "Valid processing script" {
        $targetService = "test-new"
        $ProcessScript = "$PROCESS_SCRIPTS_DIR\*$targetService.ps1"
    
        Invoke-ExecutionScripts -TargetService $targetService -ProcessScript $ProcessScript | Should -BeExactly 0

    }
    it "Invalid processing script" {
        $targetService = "test-throw"
        $ProcessScript = "$PROCESS_SCRIPTS_DIR\*$targetService.ps1"
    
        Invoke-ExecutionScripts -TargetService $targetService -ProcessScript $ProcessScript | Should -BeExactly 2

    }
    
}