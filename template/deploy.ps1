# Import default unfold tasks
Import-DefaultTasks

# set default task to deploy
task Default -depends "deploy"

# Add custom tasks, for example one to
# setup logs folder in root
# task createlogs -description "Creates logs folder in root" {
#     # Execute in remote location
#     Invoke-Script {
#         If(-not(Test-Path $config.basePath)) {
#             New-Item -type Directory -Name logs
#         }
#     }
# }
# 
# # Set it to execute after setup
# Set-AfterTask setup createlogs
