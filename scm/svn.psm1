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
    $getcommit = {
       If(Test-Path code) {
           $restore = $true
           cd code
       }
       $revisionInfo = Run-Svn info . | Where-Object { $_.StartsWith("Revision") }

       If($restore) {
           cd ..
       }

       return $revisionInfo.Split(':')[1].Trim()
    }

    return @{
        initialcheckout = {
            Run-Svn co $config.repository code
        }
        updatecode = {
            If(Test-Path code) {
                $restore = $true
                cd code
            }
            Run-Svn revert .
            Run-Svn update

            If($restore) {
                cd ..
            }
        }
        getcommit = $getcommit
        getcommitnumber = $getcommit
        help = {
            Run-Svn help commit
        }
    }
}

Export-ModuleMember -function Get-ScmCommands
