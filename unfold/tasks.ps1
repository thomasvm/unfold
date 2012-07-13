
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
            Write-Host "Building file $file" -Fore Green
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
            return
        }

        New-Item -type Directory $config.releasepath

        # release the web project
        If(Get-Task "customcopytorelease") {
            Invoke-Task customcopytorelease
        } Else {
            Foreach($csproj in $config.msbuild) {
               $wapGuids = Get-Content $csproj | Where-Object { $_.Contains($config.wapguid) }

                if($wapGuids) {
                    $source = "$(Split-Path $csproj)"
                    $destination = ".\$($config.releasepath)\web"
                    Write-Host "Copying $source to $destination"  -Fore Green
                    New-Item -type Directory $destination 

                    # copy all items
                    Get-ChildItem $source -Recurse -Exclude @('*.cs', '*.csproj') | Copy-Item -Destination {Join-Path $destination $_.FullName.Substring($source.Length)}

                    # remove empty folders
                    Get-ChildItem -Recurse | Foreach-Object {
                        If(-not($_.PSIsContainer)) {
                            return
                        }
                        $subitems = Get-ChildItem -Recurse -Path $_.FullName
                        if($subitems -eq $null)
                        {
                              Write-Host "Remove item: " + $_.FullName
                              Remove-Item $_.FullName
                        }
                        $subitems = $null
                    }
                    # remove obj
                    Remove-Item "$($config.releasepath)\web\obj" -Recurse
                    break
                }
            }
        }
    }
}
