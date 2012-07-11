$scriptPath = $(Split-Path -parent $MyInvocation.MyCommand.path) 

function Import-LocalModule($path) 
{
    import-Module (Join-Path $scriptPath $path) -Global
}

remove-module [p]sake 
Import-Localmodule .\lib\psake.psm1
Import-LocalModule .\lib\credentials.psm1

$properties = @{}

if($Args.Length) {
    $properties = $Args[0]
}

$config = @{}

if($properties.env) {
    # todo add loading of config
}

$script:context = @{}
$currentContext = $script:context
$currentContext.sessions = @{}
$currentContext.config = $config

function Invoke-Script 
{
    param(
        [Parameter(Position=0,Mandatory=1)][scriptblock]$scriptblock,
        [Parameter(Position=1,Mandatory=0)][string]$machine
    )

    if($machine -eq "") {
        $machine = $currentContext.config.machine
        if($machine -eq "" -or $machine -eq $null) {
            Write-Error "$machine argument not provided and not in config"
            return
        }
    }

    # Run locally if localhost
    if($machine -eq "localhost") {
        $folder = pwd
      
        # change to base path 
        if($config.basePath) {
            cd $config.basePath
        } 

        # Run the script
        $ret = & $scriptblock -config $config

        # Back to original folder
        cd $folder

        return $ret
    }

    # Remote scenario: create ps-session if not there yet
    if(-not($currentContext.sessions[$machine])) {
        $cred = Get-CMCredential $machine
        $newSession = new-pssession $machine -Credential $cred

        $frameworkDirs = Get-FrameworkDirs

        invoke-command -Session $newSession -argumentlist @($frameworkDirs) -ScriptBlock {
            param($dirs)
            $env:path = ($dirs -join ";") + ";$env:path"
        }

        $currentContext.sessions[$machine] = $newSession
    }

    $s = $currentContext.sessions[$machine] 

    # invoke command on remote session
    $ret = invoke-command -Session $s -argumentlist @($config, $scriptblock) -ScriptBlock {
        param([psobject]$config, [string]$script)
    
        $scr = $ExecutionContext.InvokeCommand.NewScriptBlock($script)

        $folder = pwd
    
        if($config.basePath) {
            cd $config.basePath
        }
    
        $ret = & $scr

        cd $folder

        return $ret
    }    

    return $ret
}

function Remove-Sessions
{
    foreach($session in $currentContext.sessions.values) {
        remove-pssession -Session $session
    }
    $currentContext.sessions.Clear()
}

function Import-DefaultTasks
{
    $defaultPath = join-path $scriptPath "tasks.ps1"
    . $defaultPath
}

export-modulemember -function Import-DefaultTasks, Remove-Sessions, Invoke-Script -variable config
