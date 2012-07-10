Import-Module .\core

task Default -depends Build

task Build {
    Write-Host "building"

    Remove-Sessions
}
