function Run-Svn {
    $svn = "svn"

    If($config.svnpath) {
        $svn = "$($config.svnpath)"
    }

    If($config.scmuser) {
        $args = $args + "--username=$($config.scmuser)"
        If($config.scmpassword) {
            $args = $args + "--password=$($config.scmpassword)"
        }
    }

    &$svn $args
}

function Get-ScmCommands
{
    return @{
        initialcheckout = {
            Run-Svn co $config.repository code
        }
        updatecode = {
            cd code
            Run-Svn revert .
            Run-Svn update
            cd ..
        }
        getcommit = {
            $revisionInfo = Run-Svn info .\code | Where-Object { $_.StartsWith("Revision") }
            return $revisionInfo.Split(':')[1].Trim()
        }
        help = {
            Run-Svn help commit
        }
    }
}

Export-ModuleMember -function Get-ScmCommands
