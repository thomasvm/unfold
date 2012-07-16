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

function Set-Config 
{
    param(
        [Parameter(Position=0,Mandatory=1)]$key,
        [Parameter(Position=1,Mandatory=1)]$value
    )
    $config[$key] = $value
}

function ValueOrDefault($value, $default) {
    If($value) {
        return $value
    }
    return $default
}

# load shared
If(Test-Path .\config\shared.ps1) {
    . .\config\shared.ps1
}

# loading specifi for env
$env = $properties.env 

if(-not $env) {
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
        [Parameter(Position=1,Mandatory=0)][string]$machine,
        [Parameter(Position=2,Mandatory=0)][psobject]$arguments
    )

    if($machine -eq "") {
        $machine = $currentContext.config.machine
        if($machine -eq "" -or $machine -eq $null) {
            Write-Error "machine argument not provided and not in config"
            return
        }
    }

    # Run locally if localhost
    if($machine -eq "localhost") {
        $folder = pwd
      
        # change to base path 
        if($config.basePath -and (Test-Path $config.basePath)) {
            cd $config.basePath
        } 

        # Run the script
        $ret = &$scriptblock $arguments

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
                & $cmd
                if ($lastexitcode -ne 0) {
                    throw ("Exec: " + $errorMessage)
                }
            }
        }

        $currentContext.sessions[$machine] = $newSession
    }

    $s = $currentContext.sessions[$machine] 

    # invoke command on remote session
    $ret = invoke-command -Session $s -argumentlist @($config, $scriptblock, $arguments) -ScriptBlock {
        param([psobject]$config, [string]$script, [psobject]$arguments)
    
        $scr = $ExecutionContext.InvokeCommand.NewScriptBlock($script)

        $folder = pwd
    
        if($config.basePath -and (Test-Path $config.basePath)) {
            cd $config.basePath
        }
    
        $ret = & $scr $arguments

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

# Transform config
function Convert-Configuration {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$source,
        [Parameter(Position=1,Mandatory=1)][string]$transformation,
        [Parameter(Position=2,Mandatory=1)][string]$destination,
        [Parameter(Position=3,Mandatory=0)][switch]$local
    )

    $vars = @{
        source = $source
        transformation = $transformation
        destination = $destination
    }

    $block = {
        param([psobject]$arguments)

        $msbuild = @"
<Project ToolsVersion="4.0" 
         DefaultTargets="Demo" 
         xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <UsingTask TaskName="TransformXml"
             AssemblyFile="`$(MSBuildExtensionsPath)\Microsoft\VisualStudio\v10.0\Web\Microsoft.Web.Publishing.Tasks.dll"/>

    <Target Name="Demo">
        <TransformXml Source="$($arguments.source)"
                      Transform="$($arguments.transformation)"
                      Destination="$($arguments.destination)"/>
    </Target>
</Project>
"@

        Set-Content "transform.msbuild" $msbuild

        Exec -errormessage "transforming failed" {
            msbuild "transform.msbuild"
        }

        Remove-item "transform.msbuild"
    }

    If($local) {
        & $block $vars
        return
    }

    Invoke-Script -arguments $vars $block
    return
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

function Install-Unfold {
    param([Parameter(Position=0,Mandatory=1)][string]$installPath)

    If(-not $installPath) {
        If(-not (Test-Path "deployment")) {
            New-Item -type Directory "deployment"
        }
        $installPath = ".\deployment"
    }

    $templatePath = "$scriptPath\template\*"

    Copy-Item -Recurse $templatePath -Destination $installPath

    Write-Host "removing unfold module"
    Remove-Module unfold
}

Set-Alias unfoldify Install-Unfold

export-modulemember -function Import-DefaultTasks, Remove-Sessions, Invoke-Script, Set-BeforeTask, Set-AfterTask, Convert-Configuration, Get-CurrentFolder, Get-DeployedFolders, Install-Unfold -variable config
