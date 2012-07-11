param(
    [Parameter(Position=0, Mandatory=0)]
    [string]$taskName,
    [Parameter(Position=1, Mandatory=0)]
    [System.Collections.Hashtable]$properties = @{}
)

$buildFile = "deploy.ps1"
$taskList = @($taskName)
$nologo = $true

$scriptPath = $(Split-Path -parent $MyInvocation.MyCommand.path) 
remove-module capsistrano -ErrorAction SilentlyContinue
import-module (join-path $scriptPath ..\src\capsistrano.psm1) -ArgumentList $properties

invoke-psake $buildFile $taskList "4.0" $null @{} $properties {} $nologo 

Remove-Sessions
