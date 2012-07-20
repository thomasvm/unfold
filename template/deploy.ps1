# Configuration
Set-Config project "<projectname>"

Set-Config scm git
Set-Config repository "<gitrepository>"

# Environment to use when not specified
Set-Config default dev

# For custom apppool name
# Set-Config apppool "your.apppool"

Set-Environment dev {
    Set-Config basePath "<deploypath>" #e.g. c:\inetpub\wwwroot\project

    # machine to deploy to
    Set-Config machine "localhost"
    # For remote machines, specify ip-adres or machine name
    # the credentials must be added to the Windows Credential Manager
    # as a Generic Credential
    # Set-Config machine "123.456.0.78"
    # Set-Config machine "your.machine.name"
}

# Tasks
Import-DefaultTasks

task Default -depends "release"

task ipconfig {
    Invoke-Script {
        ipconfig
    }
}

