param(
    [Parameter(Position=0, Mandatory=0)]
    [string]$taskName,
    [Parameter(Position=1, Mandatory=0)]
    [System.Collections.Hashtable]$properties = @{},
    [Parameter(Position=2, Mandatory=0)]
    [switch]$docs = $false

)

$buildFile = "deploy.ps1"
$taskList = @($taskName)
$nologo = $true

$scriptPath = $(Split-Path -parent $MyInvocation.MyCommand.path) 
remove-module unfold -ErrorAction SilentlyContinue

# Prefer local import if exists
$import = ".\unfold\unfold.psm1"

If(-not (Test-Path $import)) {
    $import = "unfold"
}

# reload if already loaded
If(Get-Module unfold) {
    Remove-Module unfold
}

# then from profile
import-module unfold -ArgumentList $properties

invoke-psake $buildFile $taskList "4.0" $docs @{} $properties {} $nologo 

Remove-Sessions
Remove-Module unfold
