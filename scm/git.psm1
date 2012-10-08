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

function Checkout-Branch {
    $branch = Get-Branch
    Run-WithErrorAction "Continue" {
        git checkout $branch 2> $null
    }
}

function Get-ScmCommands
{
    $commands = @{}

    $commands.initialcheckout = {
        Run-WithErrorAction "Continue" {
            git clone $config.repository code 2> $null 
        }

        cd code
        Checkout-Branch
        cd ..
    }

    $commands.updatecode = {
        cd code
        $branch = Get-Branch

        Exec {
            Run-WithErrorAction "Continue" {
                git fetch 2> $null
                git merge "origin/$branch" 2> $null
                git checkout . 2> $null
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
        $count = git log --oneline | wc -l
        cd ..
        return $count.Trim()
    }

    return $commands
}

