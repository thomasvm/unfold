param(
    [Parameter(Position=1, Mandatory=0)]
    [System.Collections.Hashtable]$properties = @{}
)

$buildFile = "deploy.ps1"
$taskList = @()
$nologo = $true

$scriptPath = $(Split-Path -parent $MyInvocation.MyCommand.path) 

remove-module [p]sake
import-module (join-path $scriptPath .\lib\psake.psm1)

invoke-psake $buildFile $taskList "4.0" $null @{} $properties {} $nologo
