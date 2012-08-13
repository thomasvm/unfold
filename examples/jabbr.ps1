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
    $config.releasepath = "$now`_$revision$($config.project)"

    # simply copy built site to web
    Invoke-Script {
        New-Item -type Directory -Name $config.releasepath
        Copy-Item -Recurse .\code\target\site "$($config.releasepath)\web"
    }

    $config.releaseTime = $now

    # Populate web.config values
    Invoke-Script {
$transform = @"
<configuration xmlns:xdt="http://schemas.microsoft.com/XML-Document-Transform">
  <appSettings>
    <add key="releaseTime" value="$($config.releaseTime)" xdt:Transform="SetAttributes" xdt:Locator="Match(key)"/>
    <add key="releaseBranch" value="master" xdt:Transform="SetAttributes" xdt:Locator="Match(key)"/>
    <add key="googleAnalytics" value="$($config.googleAnalytics)" xdt:Transform="SetAttributes" xdt:Locator="Match(key)"/>
  </appSettings>
  <connectionStrings>
    <add name="Jabbr" connectionString="$($config.connectionString)" xdt:Transform="SetAttributes" xdt:Locator="Match(name)"/>
  </connectionStrings>
</configuration>
"@
        $transformPath = ".\$($config.releasepath)\web\transform.config"

        Set-Content $transformPath $transform
        Convert-Configuration ".\$($config.releasepath)\web\Web.config" $transformPath
    }
}

