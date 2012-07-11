task build {
    write-host "Building"

    if(Get-Task "AfterBuild") {
        Invoke-Task "AfterBuild"
    }
}
