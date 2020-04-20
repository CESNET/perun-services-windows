function Invoke-DataPreparation {
    $Base64 = Get-Content -Path $InputPath
    $byteArray = [System.Convert]::FromBase64String($Base64)
    [System.IO.File]::WriteAllBytes($TarFile, $byteArray)
}

function Remove-PreparedData {
    Remove-item $OutputPath -Force -Recurse 
    Remove-item $TarFile -Force
}