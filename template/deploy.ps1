# Configuration
Set-Config project "<projectname>"

Set-Config scm git
Set-Config repository "<gitrepository>"

# Environment to use when not specified
Set-Config default dev

# Specify a custom set of build files, don't forget
# to prepend with ".\code\" because that is the remote checkout folder
# Set-Config msbuild @('.\code\path\to\build.csproj')

# For custom apppool name
# Set-Config apppool "your.apppool"

Set-Environment dev {
    Set-Config basePath "<deploypath>" #e.g. c:\inetpub\wwwroot\project

    # machine to deploy to
    Set-Config machine "localhost"
    # For remote machines, specify ip-address or machine name
    # the credentials must be added to the Windows Credential Manager
    # as a Generic Credential
    # Set-Config machine "123.456.0.78"
    # Set-Config machine "your.machine.name"
}

# Tasks
Import-DefaultTasks

# Set deploy as default task
task Default -depends "deploy"

# Custom task
# task ipconfig {
#     Invoke-Script {
#         ipconfig
#     }
# }

