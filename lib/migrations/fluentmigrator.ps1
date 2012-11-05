task buildmigrations {
    If(-not $config.fluentmigrator.msbuild) {
        Write-Warning "No migrations msbuild project configured"
        Write-Warning "Please add Set-Config migrationsmsbuild '.\code\path\to\msbuild\msbuild.csproj'"
        Write-Warning "to your deploy.ps1 file"
        return
    }

    Write-Host "Building fluentmigrator project" -Fore Green
    Invoke-Script {
        Exec {
            $buildConfig = $config.buildConfiguration
            if(-not $buildConfig) {
                $buildConfig = "Debug"
            }
            msbuild /p:Configuration="$buildConfig" /target:Rebuild $config.fluentmigrator.msbuild
        }
    }
}

Set-AfterTask build buildmigrations

task releasemigrations {
    $migrationsPath = Split-Path $config.fluentmigrator.msbuild
    $migrationsBuildOutputPath = "$migrationsPath\bin\$($config.buildConfiguration)"

    $config.migrationsdestination = ".\$($config.releasepath)\database"

    # Copy assembly output
    Write-Host "Copying migrations assembly to release folder"
    Invoke-Script -arguments $migrationsBuildOutputPath {
        param($outputPath)

        Copy-Item -Recurse $outputPath $config.migrationsdestination
    }

    # Copy migrate.exe
    Write-Host "Copying Migrate.exe to release folder"
    Invoke-Script {
        param($outputPath)
        $migrate = Get-ChildItem . -Recurse | Where-Object { $_.Name -eq "Migrate.exe" } | Select-Object -last 1

        If(-not $migrate) {
            Write-Warning "Migrate.exe migration tool not found"
            Write-Warning "If you're using NuGet this should be downloaded automatically"
            Write-Warning "Otherwise you should add it to your scm"
            return
        }

        Copy-Item -Force $migrate.FullName $config.migrationsdestination
    }
}

Set-AfterTask release releasemigrations

task runmigrations {
    If($config.rollback) {
        throw "Rollback not supported yet"
    }

    Invoke-Script {
        $migrate = ".\$($config.releasepath)\database\Migrate.exe"

        $migrationsAssembly = $config.fluentmigrator.assembly
        If(-not $migrationsAssembly) {
            $migrationsCsProj = Get-Item $config.fluentmigrator.msbuild
            $name = $migrationsCsProj | Select-Object -expand basename

            $csProjFolder = $(Split-path $config.fluentmigrator.msbuild)

            # derive assembly name from name of csproj and check whether it exists
            $assembly = "$csProjFolder\bin\$($config.buildConfiguration)\$name.dll" 

            If(Test-Path $assembly) {
                $migrationsAssembly = $assembly
            }
        }

        If(-not $migrationsAssembly) {
            throw "Migration error: unable to locate migration assembly"
        }

        $provider = $config.fluentmigrator.provider
        If(-not $provider) {
            $provider = "sqlserver"
        }

        Exec {
            &$migrate --task=migrate --a="$migrationsAssembly" --db=$provider
        }
    }
}

# Only if explicitely disabled automigrate
# we don't hookup to the migrations task
If($config.automigrate -ne $false) {
    Set-BeforeTask setupiis runmigrations
    return
}

