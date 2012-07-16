# Set project name
Set-Config project "unfold-example"

# Source control
Set-Config scm git
Set-Config repository "git@github.com/<your project here>"
# Set-Config branch "a-branch"

# Default environment to deploy to
Set-Config default dev

# Building, if default selected project is not ok
# Set-Config msbuild ".\code\Unfold.Web\unfold.web.csproj"
# Set-Config buildconfiguration Release # to build in release mode

# IIS
Set-Config apppool "unfoldexample"
# Set-Config apppoolruntime "v4.0" # Or v2.0 default is 4.0
# Set-Config iisname "iiswebsitename" # default is project name
Set-Config bindings @(
                        @{protocol="http";bindingInformation="*:80:my.domain.com"}
                        )
