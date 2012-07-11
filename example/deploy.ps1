Import-DefaultTasks

task Default -depends "CustomBuild"

task CustomBuild {
    write-host "override!"
}

