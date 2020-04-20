. '.\conf\perun_config.ps1'
. '.\libs\functions.ps1'
. '.\libs\perun_logger.ps1'
$PROCESS_SCRIPTS_DIR = '.\tests\ExecutingScripts\services'
$targetService = 'test'
$ProcessScript = "$PROCESS_SCRIPTS_DIR\*$targetService.ps1"
$MUTEX_NAME = "Global\$targetService"
$MUTEX_TIMEOUT = 30000 #ms
$mutex = New-Object System.Threading.Mutex($false, $MUTEX_NAME)
$mutex.WaitOne()
start-sleep -Seconds 40