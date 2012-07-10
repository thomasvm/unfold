Import-Module .\lib\credentials.psm1

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

