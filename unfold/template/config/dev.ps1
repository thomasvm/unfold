Set-Config basePath "<a folder somewhere>"

# local machine
Set-Config machine "localhost"

# For remotes, credentials are taken out of Windows Credential Manager
# and should be added as a Generic Credentials
# Set-Config machine "123.456.0.1" # can be ip adress
# Set-Config machine "machinename" # can be machine name

