function ValueOrDefault($value, $default) {
    If($value) {
        return $value
    }
    return $default
}

task setup -description "creates the folder that will contain the releases" {
    If(-not $config.basePath) {
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
    if(-not $buildFiles) {
        $buildFiles = Invoke-Script {
            # Try to find web project
            $csprojFiles = Get-ChildItem code -include *.csproj -Recurse

            $buildFiles = @()

            if(-not $csprojFiles) {
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

    if(-not $buildFiles) {
        Write-Warning "No applicable build file found, skipping."
        return
    }

    $config.msbuild = $buildFiles
    Invoke-Script {
        $target = $config.buildconfiguration
        If($target -eq $null) {
            $target = "Debug"
        }

        Foreach($file in $config.msbuild) {
            Write-Host "Building file $file" -Fore Green
            # Wrap in exec to stop on failure
            Exec {
                msbuild /p:Configuration=$target /target:Rebuild $file
            }
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
                    $sourceLength = (Resolve-Path $source).Path.Length
                    Get-ChildItem $source -Recurse -Exclude @('*.cs', '*.csproj') | Copy-Item -Destination {
                        $result = Join-Path $destination $_.FullName.Substring($sourceLength)
                        return $result
                    }

                    # remove empty folders
                    Get-ChildItem -Recurse | Foreach-Object {
                        If(-not $_.PSIsContainer) {
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

task setupapppool -description "Configures application pool" {
    If(Get-Task customsetupapppool) {
        Invoke-Task customsetupapppool
        return
    }

    Import-Module WebAdministration
    $apppool = ValueOrDefault $config.apppool $config.project
    $apppoolRuntime = ValueOrDefault $config.apppoolruntime "v4.0"

    If($apppool -eq $null) {
        $msg = @"
"Unable to determine an application pool name. 
If the apppool configuration setting is missing we will take the project name:
- Set-Config apppool nameofpool
- Set-Config project nameofproject"
"@
        throw $msg
    }

    # ensure its on the config
    $config.apppool = $apppool

    # Now create it
    Invoke-Script -arguments @{apppool=$apppool;runtime=$apppoolRuntime} {
        param($arguments)

        $appPool = "iis:\AppPools\$($arguments.apppool)"
        If ((Test-Path $appPool) -eq $false) {
            New-Item $appPool
        }
        Set-ItemProperty $appPool -name managedRuntimeVersion -value $arguments.runtime
    }
}

task uninstallcurrentrelease -description "If possible: puts App_Offline in place to stop the application" {
    If(Get-Task customdisablecurrentrelease) {
        Invoke-Task customdisablecurrentrelease
        return
    }

    If(Test-Path "$($config.basePath)\current\App_Offline.html") {
        Move-Item "$($config.basePath)\current\App_Offline.html" "$($config.basePath)\current\App_Offline.htm"
    }
}

task setupiis -description "Creates/updates the IIS website configuration" {
    If(Get-Task customsetupiis) {
        Invoke-Task customsetupiis
        return
    }

    $iisName = ValueOrDefault $config.iisname $config.project

    If (-not $iisName) {
        Write-Error "Unable to determine name to use in IIS"
        Write-Error "Either set iisname or project configuration variables"
        Write-Error "e.g. Set-Config iisname `"my.website.com`""
        throw "Invalid configuration"
    }

    If (-not $config.apppool) {
        Write-Error "Unable to determine application pool"
        Write-Error "Either invoke setupapppool task or set configuration variable"
        Write-Error "e.g. Set-Config apppool `"myapppool`""
        throw "Invalid configuration"
    }

    If (-not $config.releasepath) {
        Write-Error "Current release path is not set"
        Write-Error "Please invoke release task or set releasepath config variable"
        Write-Error "yourself in case you are performing a custom operation"
        throw "Invalid configuration"
    }

    $bindings = $config.bindings

    If(-not $bindings) {
        Write-Warning "It is not recommended to install website without bindings"
        Write-Warning "Please set bindings in configuration file"
        Write-Warning "e.g. Set-Config bindings @("
        Write-Warning  "                          @{protocol=`"http`";bindingInformation=`"*:80:your.domain.com`"}"
        Write-Warning  "                          )"
        Write-Warning  "Now defaulting to port 8967"
        $bindings = @(
                        @{protocol="http";bindingInformation="*:8967:"}
                     )
    }

    Invoke-Script -arguments @{iisName=$iisName;bindings=$bindings} {
        param($arguments)
        $iisPath    = "iis:\\Sites\$($arguments.iisName)"
        $outputPath = "$($config.basePath)\$($config.releasepath)\web"

        If(Test-Path "$outputPath\App_Offline.html") {
            Move-Item "$outputPath\App_Offline.html" -Destination "$outputPath\App_Offline.htm"
        } 

        $iisName = $arguments.iisName
        $bindings = $arguments.bindings 

        $apppool = $config.apppool

        # Site Already set up?
        If (Test-Path $iisPath) {
            Set-ItemProperty $iisPath -name physicalPath    -value $outputPath
            Set-ItemProperty $iisPath -name bindings        -value $bindings
            Set-ItemProperty $iispath -name applicationPool -value "$apppool"
        } Else {
            New-Item $iisPath -physicalPath $outputPath -bindings $bindings -applicationPool $apppool
        }
    }
}

task finalize -description "Creates a link pointing to current release" {
    $currentPath = Join-Path $config.basePath "current" 

    Invoke-Script -arguments @{currentPath=$currentPath} {
        param($arguments) 

        If(Test-Path $arguments.currentPath) {
            Exec {
                cmd /c rmdir $arguments.currentPath
            }
        }

        Exec {
            cmd /c "mklink /d $($arguments.currentPath) $($config.releasepath)"
        }
        Set-Content "$($arguments.currentPath)\pathinfo.txt" -Value $config.releasepath
    }

    Invoke-Task purgeoldreleases
}

task deploy -depends @('release','setupapppool','uninstallcurrentrelease','setupiis', 'finalize') -description "Deploys project"

task rollback -description "Rolls back to a previous version" {
    # Index in versions is 1-based
    $rollbackTo = $properties.to
    $versions = Get-DeployedFolders

    If(-not($versions) -or $versions.Length -le 1) {
        Write-Error "Unable to rollback, not enough versions deployed"
        throw "Operation not supported"
    }

    $current = Get-CurrentFolder

    # parameter not provided? current - 1
    If(-not $rollbackTo) {
        $currentIndex = 1..($versions.Length) | Where-Object { $versions[$_].Name -eq $current }

        If($currentIndex) {
            $rollbackTo = $currentIndex
        } Else {
            Write-Error "Unable to determine version to rollback to"
            Write-Error "Current version can not be determined"
        }
    } 

    $releasePath = $versions[$rollbackTo - 1].Name

    If($current -eq $releasePath) {
        Write-Warning "Target version is same as current $current, skipping..." 
        return
    }
    Write-Host "Rolling back to $releasePath" -Fore Green

    Invoke-Task setupapppool
    Invoke-Task uninstallcurrentrelease

    $config.releasepath = $releasePath

    Invoke-Task setupiis
    Invoke-Task finalize
}

task listremoteversions -description "Lists all versions available on the target" {
    $remoteVersions = Get-DeployedFolders
    $counter = 1

    $current = Get-CurrentFolder

    foreach($folder in $remoteVersions) {
        $cntr = "$counter".PadLeft(2, '0')
        Write-Host "$cntr`: " -Fore Green -NoNewLine
        Write-Host $folder -NoNewLine
        If($folder.Name -eq $current) {
            Write-Host " (current)" -NoNewLine -Fore Yellow
        }
        Write-Host ""
        $counter++
    }
}

task purgeoldreleases -description "Removes old releases" {
    $current = Get-CurrentFolder
    $remoteVersions = Get-DeployedFolders 

    $keep = ValueOrDefault $config.keep 5
    $itemsToKeep = $remoteVersions.Length - $keep

    for($i = 0; $i -lt $itemsToKeep; $i++) {
        $folder = $remoteVersions[$i]

        If($folder.Name -eq $current) {
            continue
        }

        Write-Host "Removing $folder"
        Invoke-Script -arguments $folder {
            param($folder)
            Remove-Item $folder -Recurse -Force
        }
    }
}
