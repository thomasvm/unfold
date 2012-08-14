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

function NewCheckout
{
    Run-Svn co $config.repository code
}

function UpdateCode
{
    cd code
    Run-Svn revert .
    Run-Svn update
    cd ..
}

function GetCommit
{
    $path = ".\code"

    If(-not(Test-Path $path)) {
        $path = "."
    }

    $revisionInfo = Run-Svn info $path | Where-Object { $_.StartsWith("Revision") }
    return $revisionInfo.Split(':')[1].Trim()
}

Export-ModuleMember -function NewCheckout, UpdateCode, GetCommit
