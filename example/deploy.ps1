Import-DefaultTasks

task Default -depends "unfold:build"

task PostCustom {
    write-host "before"
}

task PostCustom2 {
    write-host "after"
}

Set-BeforeTask unfold:build PostCustom
Set-AfterTask unfold:build PostCustom2

