function NewCheckout 
{
    git clone $config.repository code

    If($config.branch) {
        cd code
        git checkout $config.branch
        cd ..
    }
}

function UpdateCode 
{
    $branch = "master"

    If($config.branch) {
        $branch = $config.branch
    }

    cd code
    git pull origin $branch
    git checkout $branch
    cd ..
}

function GetCommit
{
    $pwd = pwd
    If(Test-Path "code") {
        cd code
    }
    $gitLog = git log --oneline -1

    If($pwd) {
        cd $pwd 
    }
    return $gitLog.Split(' ')[0]
}

