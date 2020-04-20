Describe 'Powershell library for archives' {
    Import-Module ".\libs\7Zip4Powershell\1.9.0\*.psd1"
    It 'Successfull import' {
        Get-Module -Name 7Zip4PowerShell | Should -Not -BeNullOrEmpty
    }
    It 'Expand TAR Archive Command' {
        Get-Command -Name Expand-7Zip | Should -Not -BeNullOrEmpty
    }
}

Describe 'Working with data' {
    . ".\tests\test-functions.ps1"

    $InputPath = Join-Path $PSScriptRoot "..\base64"
    $TarFile = Join-Path $PSScriptRoot input.tar
    $OutputPath = Join-Path $PSScriptRoot expanded
    Invoke-DataPreparation

    It 'Expand TAR Archive' {
        { Expand-7Zip $TarFile $OutputPath } | Should -Not -Throw
        Test-Path $TarFile | Should -BeTrue
    }

    It 'Data expanded' {
        Test-Path $outputPath | Should -BeTrue
    }

    Remove-PreparedData
}