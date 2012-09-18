## Deployment recipe for Jabbr, the SignalR based 
## web chat application. 
## Because Jabbr has such a good build script, we can
## override the default build step and simply call the
## build script that's provided by Jabbr itself.

# Configuration
Set-Config project "jabbr"

Set-Config scm git
Set-Config repository "https://github.com/davidfowl/JabbR.git"

# Environment to use when not specified
Set-Config basePath "c:\inetpub\wwwroot\jabbr" #e.g. c:\inetpub\wwwroot\project
Set-Config machine "localhost"

# Web.config values
Set-Environment dev {
    Set-Config googleAnalytics "your dev analytics key"
    Set-Config connectionString "your dev connection string"
}

Set-Environment staging {
    Set-Config googleAnalytics "your staging analytics key"
    Set-Config connectionString "your staging connection string"
}

Set-Config bindings @(
                     @{protocol="http";bindingInformation="*:8001:"}
                       )

# Tasks
Import-DefaultTasks

# Set deploy as default task
task Default -depends "deploy"

# Override build
task custombuild {
    Invoke-Script {
        $target = $config.target
    
        if(-not $target) {
            $target = "Debug"
        }

        .\code\build.cmd $target
    }
}

# Custom release, build prepares this
task customrelease {
    $now = (Get-Date).ToString("yyyyMMdd_HHmm")
    $revision = Invoke-Script {
        .$scm.getcommit
    }
    $config.releasepath = "$now`_$revision`_$($config.project)"

    # simply copy built site to web
    Invoke-Script {
        New-Item -type Directory -Name $config.releasepath
        Copy-Item -Recurse .\code\target\site "$($config.releasepath)\web"
    }

    $config.releaseTime = $now

    # Populate web.config values
    Invoke-Script {
        Convert-Xml ".\$($config.releasepath)\web\Web.config" {
            param($xmlFile, $xml) 

            # create function for setting appsettings
            function Set-Appsetting($xml, $name, $value) {
                $item = $xml.appSettings.add | Where-Object { $_.key -eq $name }
                $item.value = $value
            }

            Set-Appsetting $xml "releaseTime" $config.releaseTime
            Set-Appsetting $xml "releaseBranch" "master"
            Set-Appsetting $xml "googleAnalytics" $config.googleAnalytics

            $conn = $xml.connectionStrings.add | Where-Object { $_.name -eq "Jabbr" }
            $conn.connectionString = $config.connectionString
        }
    }
}

