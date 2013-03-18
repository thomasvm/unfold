function Run-WithErrorAction {
    param(
        [string]$action,
        [scriptblock]$script
    )

    $prev = $global:ErrorActionPreference
    $global:ErrorActionPreference = $action
    .$script
    $global:ErrorActionPreference = $prev
}


function Get-Branch {
    $branch = "master"

    If($config.branch) {
        $branch = $config.branch
    }

    return $branch
}

function Ensure-OnDeployBranch {
    $branch = Get-Branch
    $deployBranch = git branch | `
                        where-object { $_.Split()[1] -eq 'deploy' } | `
                        select-object { $_ } 
# @{ branch='deploy'; iscurrent = $($_.Split()[0] -eq '*') } }

    write-host $deployBranch

    If(-not $deployBranch) {
        git checkout -b deploy
    } ElseIf(-not $deployBranch.iscurrent) {
        write-host "checking out existing"
        git checkout deploy
    }

    git reset --hard "origin/$branch" 2> $null
}

function Get-ScmCommands
{
    $commands = @{}

    $commands.initialcheckout = {
        $branch = Get-Branch

        Run-WithErrorAction "Continue" {
            git clone $config.repository code 2> $null 
             
            # checkout in local 'deploy' branch
            cd code
            Ensure-OnDeployBranch
            cd ..
        }
    }

    $commands.updatecode = {
        cd code
        $branch = Get-Branch

        Exec {
            Run-WithErrorAction "Continue" {
                git fetch 2> $null
                git fetch --tags origin 2> $null

                # Point local deploy branch to origin
                Ensure-OnDeployBranch
            }
        }
        cd ..
    }

    $commands.getcommit = {
        cd code
        $gitLog = git log --oneline -1
        cd ..
        return $gitLog.Split(' ')[0]
    }

    $commands.getcommitnumber = {
        cd code
        $count = (git log --oneline | Measure-Object -l).Lines
        cd ..
        return $count
    }

    return $commands
}

