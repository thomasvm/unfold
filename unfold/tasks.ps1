Write-Host "Loading default Tasks"

function ValueOrDefault($value, $default) {
    If($value) {
        return $value
    }
    return $default
}

task setup {
    If(-not($config.basePath)) {
        throw "config needs basePath property"
    }

    Invoke-Script {
        If(-not(Test-Path $config.basePath)) {
            New-Item -Type Directory $config.basePath
        }
    }
}

task updatecode -depends setup {
    If($config.scm -eq "git") {
        $branch = 

        Invoke-Script {
            If(-not(Test-Path "code")) {
                git clone $config.repository code
            } Else {
                cd code
                git checkout master
                git pull origin master
                cd ..
            }
        }
        return
    }

    throw "Unsupported scm $($config.scm)"
}

task build -depends updatecode {
    $customBuild = (Get-Task CustomBuild)

    If($customBuild) {
        Invoke-Task CustomBuild
        return
    }

    $buildFiles = $config.msbuild

    if(-not($buildFile)) {
        $buildFiles = Invoke-Script {
            # Try to find web project
            $csprojFiles = Get-ChildItem code -include *.csproj
        }
    }

    if(-not($buildFiles)) {
        Write-Warning "No applicable build file found, skipping."
        return
    }

    $config.msbuild = $buildFiles
    Invoke-Script {
        $target = ValueOrDefault $config.target "Debug"

        foreach($file in $config.msbuild) {
            msbuild /p:Configuration=$target /target:Clean $file
            msbuild /p:Configuration=$target /target:Build $file
        }
    }
}
