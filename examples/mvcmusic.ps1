# Configuration
Set-Config project "mvcmusic"

Set-Config scm git
Set-Config repository "https://github.com/tekpub/mvcmusic.git"

# Environment to use when not specified
Set-Config basePath "c:\inetpub\wwwroot\mvcmusic" #e.g. c:\inetpub\wwwroot\project
Set-Config machine "localhost"

Set-Config apppool "mvcmusic.example"

# Tasks
Import-DefaultTasks

# Set deploy as default task
task Default -depends "deploy"

