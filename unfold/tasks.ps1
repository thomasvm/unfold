
function ValueOrDefault($value, $default) {
    If($value) {
        return $value
    }
    return $default
}

task setup -description "creates the folder that will contain the releases" {
    If(-not($config.basePath)) {
        throw "config needs basePath property"
    }

    Invoke-Script {
        If(-not(Test-Path $config.basePath)) {
            New-Item -Type Directory $config.basePath
        }
    }
}

task updatecode -depends setup -description "updates the code from scm" {
    If($config.scm -eq "git") {
        Invoke-Script {
            $branch = $config.branch

            If($branch -eq $null) {
                $branch = "master"
            }

            If(-not(Test-Path "code")) {
                git clone $config.repository code
                git checkout $branch
            } Else {
                cd code
                git checkout $branch
                git pull origin
                git checkout $branch
                cd ..
            }
        }
        return
    }

    throw "Unsupported scm $($config.scm)"
}

task build -depends updatecode -description "Builds the code using msbuild" {
    $customBuild = (Get-Task custombuild)

    If($customBuild) {
        Invoke-Task custombuild
        return
    }

    $buildFiles = $config.msbuild

    # not specified in config? try to locate a proper solution
    if(-not($buildFile)) {
        $buildFiles = Invoke-Script {
            # Try to find web project
            $csprojFiles = Get-ChildItem code -include *.csproj -Recurse

            $buildFiles = @()

            if(-not($csprojFiles)) {
                $csprojFiles = @()
            }

            Foreach($csproj in $csprojFiles) {
                $wapGuids = Get-Content $csproj | Where-Object { $_.Contains($config.wapguid) }

                if($wapGuids) {
                    $buildFiles = $buildFiles + $csproj
                }
            }

            if($buildFiles.Length) {
                return $buildFiles
            }

            # try to find a single solution
            $slnFiles = Get-ChildItem code -include *.sln -Recurse

            if($slnFiles.Length -eq 1) {
                return $slnFiles[0]
            }

            return $null
        }
    }

    if(-not($buildFiles)) {
        Write-Warning "No applicable build file found, skipping."
        return
    }

    $config.msbuild = $buildFiles
    Invoke-Script {
        $target = $config.target 
        If($target -eq $null) {
            $target = "Debug"
        }

        Foreach($file in $config.msbuild) {
            msbuild /p:Configuration=$target /target:Rebuild $file
        }
    }
}

task release -depends build -description "Puts the built code inside a release folder" {
    $customReleaseTask = Get-Task customrelease

    If($customReleaseTask) {
        Invoke-Task customrelease
        return
    }

    $revision = $null

    If($config.scm -eq "git") {
        $revision = Invoke-Script {
            cd code
            $gitLog = git log --oneline -1
            cd ..
            return $gitLog.Split(' ')[0]
        }
    }

    If($revision) {
        $revision = $revision + '_'
    }

    $now = (Get-Date).ToString("yyyyMMdd_HHmm")
    $config.releasepath = "$now`_$revision$($config.project)"

    Write-Host "Releasing towards folder $($config.releasepath)"
    Invoke-Script {
        If(Test-Path $config.releasepath) {
            Write-Warning "$($config.releasepath) already exists, skipping..."
        }
    }
}
