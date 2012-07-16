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
remove-module unfold -ErrorAction SilentlyContinue

try {
    #first load locally
    import-module (join-path $scriptPath .\unfold\unfold.psm1) -ArgumentList $properties
} catch {
    # then from profile
    import-module unfold -ArgumentList $properties
}

invoke-psake $buildFile $taskList "4.0" $null @{} $properties {} $nologo 

Remove-Sessions
remove-module unfold
