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

        function Download($url, $destination) {
            $webclient = New-Object System.Net.WebClient
            $webclient.DownloadFile($url, $destination)
        }    

        function Unzip($filename, $destination) {
            $shell_app = new-object -com shell.application
            $zip_file = $shell_app.namespace($filename)
            $destinationPath = $shell_app.namespace($destination)
            $destinationPath.Copyhere($zip_file.items())
        }

        $basePath = $config.basePath

        # Download an unzip
        New-Item -type Directory -Name "ravendb"
        Download "http://builds.hibernatingrhinos.com/Download/9537" "$basePath\ravendb\ravendb.zip"
        Unzip "$basePath\ravendb\ravendb.zip" "$basePath\ravendb"

        # TODO: set port

        # Install
        cd .\ravendb\Server
        Exec {
            .\Raven.Server.exe /install
        }
        cd ..
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

Set-BeforeTask setupapppool setupravendb

