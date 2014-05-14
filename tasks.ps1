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

    If($config.localbuild) {
        Write-Host "Ensuring local build location"
        If(-not $config.localbuildpath) {
            throw "localbuildpath must be set"
        }

        If(-not(Test-Path $config.localbuildpath)) {
            New-Item $config.localbuildpath -type Directory 
        }
    }
}

task updatecode -depends setup -description "updates the code from scm" {
    Set-ForceLocalInvokeScript $true
    Invoke-Script {
        If(-not (Test-Path code)) {
            Write-Host "Performing initial checkout"
            .$scm.initialcheckout
        } Else {
            Write-Host "Updating source code"
            .$scm.updatecode
        }
    }
    return
}

task build -depends updatecode -description "Builds the code using msbuild" {
    $customBuild = Get-Task custombuild

    If($customBuild) {
        Write-Host "Custom build task defined, using that instead of default build"
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
    If(-not $config.buildconfiguration) {
        $config.buildconfiguration = "Debug"
    }

    Foreach($file in $config.msbuild) {
        Invoke-Script -arguments $file {
            param($file)
            Write-Host "Building file $file" -Fore Green
            # Wrap in exec to stop on failure
            Exec {
                msbuild /p:Configuration="$($config.buildconfiguration)" /target:Rebuild $file
            }
        }
    }
}

task release -depends build -description "Puts the built code inside a release folder" {
    $customReleaseTask = Get-Task customrelease

    If($customReleaseTask) {
        Write-Host "customrelease task defined, overruling default release"
        Invoke-Task customrelease
        return
    }

    $revision = Invoke-Script {
        If($scm.getcommit) {
            return .$scm.getcommit
        }
        return $null
    }
    Write-Host "Revision is: $revision"

    If($revision) {
        $revision = $revision + '_'
    }

    $now = (Get-Date).ToString("yyyyMMdd_HHmm")
    $config.releasepath = "$now`_$revision$($config.project)"

    Write-Host "Releasing towards folder $($config.releasepath)"

    $releaseExists = Invoke-Script {
        return Test-Path $config.releasepath
    }

    If($releaseExists) {
        Write-Warning "$($config.releasepath) already exists, skipping..."
        return
    }

    Invoke-Script {
        New-Item -type Directory $config.releasepath

        Set-Content "$($config.releasepath)\pathinfo.txt" -Value $config.releasepath
    }

    If(Get-Task "customcopytorelease") {
        Invoke-Task customcopytorelease
        return
    }

    # release the project
    Invoke-Script {
        Write-Host "Trying to find web application project in msbuild files"
        Foreach($csproj in $config.msbuild) {
           $wapGuids = Get-Content $csproj | Where-Object { $_.Contains($config.wapguid) }

            if($wapGuids) {
                Write-Host "Web application project found: $csproj"

                $source = "$(Split-Path $csproj)"
                $destination = ".\$($config.releasepath)\web"
                Write-Host "Copying $source to $destination"  -Fore Green
                New-Item -type Directory $destination 

                # copy all items
                Copy-WebProject $source $destination
                Remove-EmptyFolders $config.releasepath

                # remove obj
                Remove-Item "$($config.releasepath)\web\obj" -Recurse
                break
            }
        }
    }
}

task releasefinalize -depends release -description "Marks the release as finalized (ready for configuration)" {
    If($config.localbuild) {
        Write-Host "Using localbuild, copying release to remote machine"
        Invoke-Script {
            New-Zip $config.releasepath "$($config.releasepath).zip"
        }

        $file = Resolve-Path "$($config.localbuildpath)\$($config.releasepath).zip"
        $destination = "$($config.basepath)\$($config.releasepath).zip"
        Write-Host "Copying $file to $destination (on machine $($config.machine))"
        Copy-ToMachine $config.machine $file $destination

        # Now we must specify machine explicitely, otherwise we will extract locally
        Invoke-Script -machine $config.machine -port $config.port -arguments @($destination) {
            param($zipfile)
            Expand-Zip $zipfile $config.basePath
            Remove-Item $zipfile
        }

        # Remove zip on original build
        Invoke-Script {
            Remove-Item -Recurse $config.releasepath
            Remove-Item "$($config.releasepath).zip"
        }

        Write-Host "Release towards $($config.releasepath) complete" -Fore Green
    }

    Set-ForceLocalInvokeScript $false
}

task setupapppool -description "Configures application pool" {
    If(Get-Task customsetupapppool) {
        Write-Host "customsetupapppool task defined, overruling default setupapppool"
        Invoke-Task customsetupapppool
        return
    }

    $apppool = ValueOrDefault $config.apppool $config.project
    $apppoolRuntime = ValueOrDefault $config.apppoolruntime "v4.0"
    $apppoolMode = ValueOrDefault $config.apppoolmode "Integrated"

    If($apppool -eq $null) {
        $msg = @"
"Unable to determine an application pool name. 
If the apppool configuration setting is missing we will take the project name:
- Set-Config apppool nameofpool
- Set-Config project nameofproject"
"@
        throw $msg
    }

    Write-Host "Application pool is $apppool"

    # ensure its on the config
    $config.apppool = $apppool

    # Now create it
    Invoke-Script -arguments @{apppool=$apppool;runtime=$apppoolRuntime;mode=$apppoolMode} {
        param($arguments)
        Import-Module WebAdministration

        $appPool = "iis:\AppPools\$($arguments.apppool)"
        If ((Test-Path $appPool) -eq $false) {
            Write-Host "Creating application pool..."
            New-Item $appPool
        }
        Set-ItemProperty $appPool -name managedRuntimeVersion -value $arguments.runtime

        $pipelineMode = 0 # Integrated

        If($arguments.mode -eq "Classic") {
            $pipelineMode = 1 # Classic
        }

        Set-ItemProperty $appPool -name managedPipelineMode -value $pipelineMode
    }
}

task uninstallcurrentrelease -description "If possible: puts App_Offline in place to stop the application" {
    If(Get-Task customuninstallcurrentrelease) {
        Invoke-Task customuninstallcurrentrelease
        return
    }

    Invoke-Script {
        If(Test-Path ".\current\web\App_Offline.html") {
            Write-Host "Moving App_Offline.html to App_Offline.htm"
            Move-Item ".\current\web\App_Offline.html" ".\current\web\App_Offline.htm"
        } Else {
            Write-Host "No App_Offline.html file found, skipping."
        }
    }
}

task setupiis -description "Creates/updates the IIS website configuration" {
    If(Get-Task customsetupiis) {
        Write-Host "customsetupiis task defined, overruling default setupiis"
        Invoke-Task customsetupiis
        return
    }

    $iisName = ValueOrDefault $config.iisname $config.project
    $config.iisname = $iisName

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

        $iisName = $arguments.iisName
        $bindings = $arguments.bindings
        $outputPath = "$($config.basePath)\$($config.releasepath)\web"

        Write-Host "Configuring IIS site: $iisName"
        Write-Host "  pointing to path: $outputPath"
        Write-Host "  apppool $($config.apppool)"

        Set-IISSite -name $iisName `
                    -path $outputPath `
                    -apppool $config.apppool `
                    -bindings $bindings
    }
}

task finalize -description "Creates a link pointing to current release" {

    Invoke-Script {
        $currentPath = Join-Path $config.basePath "current" 

        If(Test-Path $currentPath) {
            Exec {
                cmd /c rmdir $currentPath
            }
        }

        Exec {
            cmd /c "mklink /d $($currentPath) $($config.releasepath)"
        }

        If(Test-Path "$($currentPath)\web\App_Offline.htm") {
            Write-Host "Moving App_Offline out of the way"
            Move-Item "$($currentPath)\web\App_Offline.htm" "$($currentPath)\web\App_Offline.html"
        } Else {
            Write-Host "No App_Offline.htm file found"
        }
    }

    Invoke-Task purgeoldreleases
}

task deploy -depends @('release', 'releasefinalize','setupapppool','uninstallcurrentrelease','setupiis', 'finalize') -description "Deploys project"

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

    $config.isrollback = $true
    $config.rollback = @{
        from = $current
        to = $releasePath
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

    foreach($remote in $remoteVersions) {
        $cntr = "$counter".PadLeft(2, '0')
        Write-Host "$cntr`: " -Fore Green -NoNewLine
        Write-Host $remote -NoNewLine
        If($remote.Name -eq $current) {
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
        $toRemove = $remoteVersions[$i]

        If($toRemove.Name -eq $current) {
            continue
        }

        Invoke-Script -arguments $toRemove {
            param($toRemove)
            $toRemove = Join-Path $config.basePath $toRemove
            Write-Host "Removing $toRemove"
            Remove-Item $toRemove -Recurse -Force 
        }
    }
}

