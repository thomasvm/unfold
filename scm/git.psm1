function Get-Branch {
    $branch = "master"

    If($config.branch) {
        $branch = $config.branch
    }

    return $branch
}

function Checkout-Branch {
    $branch = Get-Branch
    git checkout $branch 2> $null
}

function Get-ScmCommands
{
    $commands = @{}

    $commands.initialcheckout = {
        git clone $config.repository code 2> $null 
        cd code
        Checkout-Branch
        cd ..
    }

    $commands.updatecode = {
        cd code
        $branch = Get-Branch

        Exec {
            git fetch
            git merge "origin/$branch"
            Checkout-Branch
        }
        cd ..
    }

    $commands.getcommit = {
        Write-Host "Getting git commit"
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

