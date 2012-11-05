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
$config.wapguid = "349c5851-65df-11da-9384-00065b846f21"

$configEnvironments = new-object system.collections.stack 
$scmname = $null

function Set-Config 
{
    param(
        [Parameter(Position=0,Mandatory=1)]$key,
        [Parameter(Position=1,Mandatory=1)]$value
    )

    If($configEnvironments.Count) {
        $environment = $configEnvironments.Peek()
        $config[$environment][$key] = $value
    } Else {
        $config[$key] = $value
    }
}

function Set-Environment
{
    param(
        [Parameter(Position=0,Mandatory=1)][string]$name,
        [Parameter(Position=1,Mandatory=1)][scriptblock]$script
    )

    $configEnvironments.Push($name)
    $config[$name] = @{}

    . $script

    $undo = $configEnvironments.Pop()
}

function Initialize-Configuration {
    # loading specifi for env
    $env = $properties.env 
    
    if(-not $env) {
        $env = ValueOrDefault $config.default dev
    }
    $config.environment = $env

    Write-Host "Current environment is $env"

    # Apply specific info
    If($config[$env]) {
        foreach($key in $config[$env].Keys) {
            $val = $config[$env][$key]
            $config[$key] = $val
        }
    }

    $scm = ValueOrDefault $config.scm "git"
    $name = $scm

    # Not local to deploy.ps1 path, check our own
    If(-not (Test-Path $scm)) {
        $unfoldPath = "$scriptPath\lib\scm\$scm.psm1"
        If(Test-Path $unfoldPath) {
            $scm = $unfoldPath
        }
    }

    Write-Host "Using scm $name"
    Add-ScriptModule $scm $name
    Set-Variable -name scmname -Value $name -Scope 1 

    Add-ScriptModule "$scriptPath\lib\scriptfunctions.psm1" "scriptfunctions"

    If($config.localbuild) {
        Add-ScriptModule "$scriptPath\lib\sendfile.psm1" "sendfile"
    }
}

function ValueOrDefault($value, $default) {
    If($value) {
        return $value
    }
    return $default
}

function Get-FileContent($path) {
    $content = Get-Content -path $path
    return [string]::join([environment]::newline, $content)
}

# setup context
$script:context = @{}
$currentContext = $script:context
$currentContext.sessions = @{}
$currentContext.config = $config
$currentContext.scripts = @{}
$currentContext.scriptLoaded = $false

# We only set this to false once build starts,
# otherwise simple Invoke-Script tasks will first
# have to call Set-ForceLocalInvokeScript
$currentContext.forceLocal = $false

# Remote script invocation
function Invoke-Script 
{
    param(
        [Parameter(Position=0,Mandatory=1)][scriptblock]$scriptblock,
        [Parameter(Position=1,Mandatory=0)][string]$machine,
        [Parameter(Position=2,Mandatory=0)][psobject]$arguments,
        [Parameter(Position=3,Mandatory=0)][int]$port
    )

    $basePath = $config.basePath

    if($machine -eq "") {
        If($config.localbuild -and $currentContext.forceLocal) {
            # If configuration asks for local build and release is not 
            # fully executed, then we force machine to localhost
            $machine = "localhost"
            $basePath = $config.localbuildpath

            If(-not $basePath) {
                Write-Error "localbuildpath must be set for localbuild to work"
                return
            }
        } Else {
            # otherwise use remote machine
            $machine = $currentContext.config.machine
        }

        if($machine -eq "" -or $machine -eq $null) {
            Write-Error "machine argument not provided and not in config"
            return
        }
    }

    # Run locally if localhost
    if($machine -eq "localhost") {
        # use silly name so call to script block
        # doesn't overwrite
        $abcdef = pwd

        If(-not $currentContext.scriptLoaded) {
             Foreach($key in $currentContext.scripts.keys) {
                $script = $currentContext.scripts[$key]
                $m = New-Module -name $key -scriptblock $script

                If($key -eq $scmname) {
                    $scmCommands = Get-ScmCommands
                    Set-Variable -name scm -Value $scmCommands -Scope 2
                }
             }
             # Reset, all imports are done
             $currentContext.scriptLoaded = $true
        }

        # change to base path 
        if($basePath -and (Test-Path $basePath)) {
            cd $basePath 
        } 

        # Run the script
        # Simple dot sourcing will not work. We have to force the script block into our
        # module's scope in order to initialize variables properly.
        $ret = . $MyInvocation.MyCommand.Module $scriptblock $arguments

        # Back to original folder
        If(Test-Path $abcdef) {
            cd $abcdef
        }

        return $ret
    }

    $s = Get-DeploymentSession $machine $port

    # invoke command on remote session
    $ret = invoke-command -Session $s -argumentlist @($config, $scriptblock, $arguments) -ScriptBlock {
        param([psobject]$config, [string]$script, [psobject]$arguments)
    
        $scr = $ExecutionContext.InvokeCommand.NewScriptBlock($script)

        # use silly name so call to script block
        # doesn't overwrite
        $abcdef = pwd
    
        if($config.basePath -and (Test-Path $config.basePath)) {
            cd $config.basePath
        }
    
        $r = .$scr $arguments

        If(Test-Path $abcdef) {
            cd $abcdef
        }

        return $r
    }    

    return $ret
}

function Copy-ToMachine {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$machine,
        [Parameter(Position=1,Mandatory=1)][string]$file,
        [Parameter(Position=2,Mandatory=1)][string]$destination
    )

    # On localhost? Simply perform a copy
    If($machine -eq "localhost") {
        Copy-Item $file -Destination $destination
        return
    }

    # Otherwise, get session and use it to push content
    $session = Get-DeploymentSession $machine
    Send-File $file $destination $session
}

function Get-DeploymentSession {
    param (
        [string]$machine,
        [int]$port
    )

    # Remote scenario: create ps-session if not there yet
    if(-not($currentContext.sessions[$machine])) {
        $cred = Get-CMCredential $machine
        If(-not $port) {
            $port = ValueOrDefault $config.port 5986 
        }
        $newSession = new-pssession $machine -Credential $cred -UseSsl -Port $port

        $frameworkDirs = Get-FrameworkDirs

        invoke-command -Session $newSession -argumentlist @($frameworkDirs) -ScriptBlock {
            param($dirs)
            # enrich path
            $env:path = ($dirs -join ";") + ";$env:path"

            # Intall exec function
            function Exec
            {
                [CmdletBinding()]
                param(
                    [Parameter(Position=0,Mandatory=1)][scriptblock]$cmd,
                    [Parameter(Position=1,Mandatory=0)][string]$errorMessage = ($msgs.error_bad_command -f $cmd)
                )
                &$cmd 

                if ($lastExitCode -ne 0) {
                    throw ("Exec: " + $errorMessage)
                }
            }
        }

        Foreach($name in $currentContext.scripts.keys) {
            $script = $currentContext.scripts[$name]
            invoke-command -Session $newSession -argumentlist @($name,$script) -ScriptBlock {
                param($name,$s)
                $scr = $ExecutionContext.InvokeCommand.NewScriptBlock($s)
                $m = New-Module -Name $name -ScriptBlock $scr
            }

            If($name -eq $scmname) {
                invoke-command -Session $newSession -ScriptBlock {
                    $scmCommands = Get-ScmCommands
                    Set-Variable -name scm -Value $scmCommands
                }
            }
        }

        $currentContext.sessions[$machine] = $newSession
    }

    return $currentContext.sessions[$machine] 
}

function Set-ForceLocalInvokeScript
{
    param(
        [Parameter(Position=0,Mandatory=0)]$executed = $true
    )
    $currentContext.forceLocal = $executed
}

# Remove all open sessions
function Remove-Sessions
{
    foreach($session in $currentContext.sessions.values) {
        remove-pssession -Session $session
    }
    $currentContext.sessions.Clear()
}

function Add-ScriptModule
{
    param(
        [Parameter(Position=0,Mandatory=1)]$script,
        [Parameter(Position=1,Mandatory=0)]$name
    )

    $scr = $null

    If($script.GetType().Name -eq "ScriptBlock") {
        $scr = $script
    } Else {
        $content = $script
        If(Test-Path $script) {
            $content = Get-FileContent $script
        } 
        $scr = $ExecutionContext.InvokeCommand.NewScriptBlock($content)
    }

    If(-not $name) {
        $name = "scriptfunctions_$($currentContext.scripts.Count)"
    }

    $currentContext.scripts[$name] = $scr
}


# Import default tasks
function Import-DefaultTasks
{
    $defaultPath = join-path $scriptPath "tasks.ps1"
    . $defaultPath

    If($config.migrations) {
        Write-Host "Attempt to load database migration tasks"
        foreach($migrationPath in @(".\$($config.migrations).ps1",
                                    "$scriptPath\lib\migrations\$($config.migrations).ps1")) {
            If(Test-Path $migrationPath) {
                .$migrationPath
                break
            }
        }
    }
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

# Get versions
function Get-DeployedFolders {
    return Invoke-Script {
        $items = Get-ChildItem $config.basePath | Where-Object { $_.Name.EndsWith($config.project) -and $_ -ne "current" }
        return $items
    }
}

function Get-CurrentFolder {
    $current = Invoke-Script {
        $currentFolderInfoPath = "$($config.basePath)\current\pathinfo.txt"
        If(Test-Path $currentFolderInfoPath) {
            $current = Get-Content $currentFolderInfoPath
            return $current
        } 
    } 

    return $current
}

# Installing unfold
function Install-Unfold {
    param([Parameter(Position=0,Mandatory=0)][string]$installPath)

    If(-not $installPath) {
        If(-not (Test-Path "deployment")) {
            New-Item -type Directory "deployment"
        }
        $installPath = ".\deployment"
    }

    $templatePath = "$scriptPath\template\*"

    Copy-Item -Recurse $templatePath -Destination $installPath
}

export-modulemember -function Set-Config, Set-Environment, Add-ScriptModule, `
                              Initialize-Configuration, Import-DefaultTasks, Remove-Sessions, `
                              Set-ForceLocalInvokeScript, `
                              Invoke-Script, Set-BeforeTask, Set-AfterTask, Convert-Configuration, `
                              Get-CurrentFolder, Get-DeployedFolders, Install-Unfold -variable config
