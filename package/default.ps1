$config = New-Object PSObject -property @{ 
    version="0.0.1";
    releaseNotes=@"
Initial release
"@
}

task Cleanup {
    Remove-Item -Recurse pkg -ErrorAction silentlycontinue
}

task Setup -depends Cleanup {
    New-Item -type Directory pkg

    $contentFolder = "pkg\content\deployment\unfold"

    New-Item -type Directory $contentFolder
    Copy-Item ..\tasks.ps1 $contentFolder
    Copy-Item ..\unfold.psm1 $contentFolder
    Copy-Item -Recurse ..\lib $contentFolder

    Copy-Item ..\template\* "pkg\content\deployment"

    $toolsFolder = "pkg\tools"
    New-Item -type Directory $toolsFolder
    Copy-Item "Install.ps1" $toolsFolder
}

task Package -depends Setup {
    Copy-Item unfold.nuspec pkg
    cd pkg
    SetNuSpecVersionInfo
    ..\.nuget\NuGet.exe pack
    cd ..
    Copy-Item pkg\Unfold.*.nupkg .
    Remove-Item -Recurse pkg
}

function SetNuSpecVersionInfo {
    (Get-Content "Unfold.nuspec") | Foreach-Object {
        $_ -replace 'PKG_VERSION', $config.version `
           -replace 'PKG_RELEASENOTES', $config.releaseNotes
        } | Set-Content "Unfold.nuspec"
}

