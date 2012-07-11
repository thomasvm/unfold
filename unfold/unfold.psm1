$scriptPath = $(Split-Path -parent $MyInvocation.MyCommand.path) 

function Import-LocalModule($path) 
{
    import-Module (Join-Path $scriptPath $path) -Global
}

# Loading child modules
remove-module [p]sake 
Import-Localmodule .\lib\psake.psm1
Import-LocalModule .\lib\credentials.psm1

$properties = @{}

if($Args.Length) {
    $properties = $Args[0]
}

# Loading configuration
$config = @{}

function Set-Config 
{
    param(
        [Parameter(Position=0,Mandatory=1)]$key,
        [Parameter(Position=1,Mandatory=1)]$value
    )
    $config[$key] = $value
}

# load shared
If(Test-Path .\config\shared.ps1) {
    . .\config\shared.ps1
}

# loading specifi for env
$env = $properties.env 

if(-not($env)) {
    $env = $config.default
}

$envPath = ".\config\$env.ps1"

if($env -and (Test-Path $envPath)) {
    . $envPath
}

# setup context
$script:context = @{}
$currentContext = $script:context
$currentContext.sessions = @{}
$currentContext.config = $config

# Remote script invocation
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

# Remove all open sessions
function Remove-Sessions
{
    foreach($session in $currentContext.sessions.values) {
        remove-pssession -Session $session
    }
    $currentContext.sessions.Clear()
}

# Import default tasks
function Import-DefaultTasks
{
    $defaultPath = join-path $scriptPath "tasks.ps1"
    . $defaultPath
}

# BeforeTask and AfterTask functions
$beforeTasks = @{}

function Set-BeforeTask
{
    param(
        [Parameter(Position=0,Mandatory=1)][string]$beforeTask,
        [Parameter(Position=1,Mandatory=1)][string]$task
    )

    $psakeTask = Get-Task $beforeTask

    If(-not($psakeTask)) {
        throw "Unable to find task $beforeTask"
    }

     $beforeTaskList = $beforeTasks[$beforeTask]

    If(-not($beforeTaskList)) {
        $beforeTaskList = @()

        If($psakeTask.preaction) {
            throw "Cannot overrule existing postactin"
        }

        $psakeTask.preaction = {
            $context = $psake.context.Peek()
            Invoke-BeforeTasks $context.currentTaskName
        }
    }

    $beforeTaskList = $beforeTaskList + $task
    $beforeTasks[$beforeTask] = $beforeTaskList
}

$afterTasks = @{}

function Set-AfterTask
{
    param(
        [Parameter(Position=0,Mandatory=1)][string]$afterTask,
        [Parameter(Position=1,Mandatory=1)][string]$task
    )

    $psakeTask = Get-Task $afterTask

    If(-not($psakeTask)) {
        throw "Unable to find task $afterTask"
    }

    $afterTaskList = $afterTasks[$afterTask]

    If(-not($afterTaskList)) {
        $afterTaskList = @()

        If($psakeTask.postaction) {
            throw "Cannot overrule existing postaction"
        }
    
        $psakeTask.postaction = {
            $context = $psake.context.Peek()
            Invoke-AfterTasks $context.currentTaskName
        }
    }

    $afterTaskList = $afterTaskList + $task
    $afterTasks[$afterTask] = $afterTaskList
}

function Invoke-BeforeTasks($taskName) {
    foreach($beforeTaskName in $beforeTasks[$taskName]) {
        Invoke-Task $beforeTaskName
    }
}

function Invoke-AfterTasks($taskName) {
    foreach($afterTaskName in $afterTasks[$taskName]) {
        Invoke-Task $afterTaskName
    }
}

# Unfoldify


export-modulemember -function Import-DefaultTasks, Remove-Sessions, Invoke-Script, Set-BeforeTask, Set-AfterTask -variable config
