## A deployment example for RaccoonBlog, the blog engine that's powering
## blogs like Ayende's
## This deployment recipe not only builds and installs RaccoonBlog
## it also takes care of installing RavenDb as a service, and has extra
## tasks for uninstalling and restarting RavenDb

# Configuration
Set-Config project "raccoonblog"

Set-Config scm git
Set-Config repository "https://github.com/fitzchak/RaccoonBlog.git"

# Environment to use when not specified
Set-Config default dev

Set-Config msbuild @('.\code\RaccoonBlog.Web\RaccoonBlog.Web.csproj', `
                     '.\code\RaccoonBlog.Migrations\RaccoonBlog.Migrations.csproj')

# For custom apppool name
Set-Config apppool "raccoonblog"

Set-Config ravenport "8080"

# Environments
Set-Environment dev {
    Set-Config basePath "c:\inetpub\wwwroot\raccoon"

    # machine to deploy to
    Set-Config machine "localhost"
}

# Tasks
Import-DefaultTasks

# Set deploy as default task
task Default -depends "deploy"

task releasemigrations {
    Invoke-Script {
        Copy-Item -Recurse ".\code\RaccoonBlog.Migrations\bin\Debug" `
                           "$($config.releasePath)\migrations"
   }
}

Set-AfterTask release releasemigrations

task setupravendb {
    Invoke-Script {
        If(Test-Path "$($config.basePath)\ravendb") {
            return
        }

        $basePath = $config.basePath

        # Download an unzip, these functions come from scriptfunctions.psm1
        New-Item -type Directory -Name "ravendb"
        Start-Download "http://builds.hibernatingrhinos.com/Download/9537" "$basePath\ravendb\ravendb.zip"
        Expand-File "$basePath\ravendb\ravendb.zip" "$basePath\ravendb"
    }

    # Change port to 8080
    Invoke-Script {
        $transform = @"
<?xml version="1.0"?>
<configuration xmlns:xdt="http://schemas.microsoft.com/XML-Document-Transform">
  <appSettings>
    <add key="Raven/Port" 
      value="$($config.ravenport)" 
      xdt:Transform="SetAttributes" xdt:Locator="Match(key)"/>
  </appSettings>
</configuration>
"@
        Set-Content -Path ".\ravendb\Server\setport.config" -Value $transform

        Convert-Configuration ".\ravendb\Server\Raven.Server.exe.config" `
                              ".\ravendb\Server\setport.config" 
    }

    # Install
    Invoke-Script {
        # Install
        cd .\ravendb\Server
        Exec {
            .\Raven.Server.exe /install
        }
        cd ..
    }
}

Set-BeforeTask setupapppool setupravendb

task restartraven {
    Invoke-Script {
        Exec {
            .\ravendb\Server\Raven.Server.exe /restart
        }
    }
}

task uninstallraven {
    Invoke-Script {
        # test ravendb installed?
        If(-not (Test-Path .\ravendb\Server)) {
            return
        }

        # Got into directory and uninstall
        cd .\ravendb\Server
        Exec {
            .\Raven.Server.exe /uninstall
        }
        cd ..
    }
}

