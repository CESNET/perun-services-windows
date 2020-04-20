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