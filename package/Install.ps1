param($installPath, $toolsPath, $package, $project)

$name = $project.Name
$projectPath = Split-Path $project.Filename
$deployFilePath = "$projectPath\deployment\deploy.ps1"

(Get-Content $deployFilePath) | Foreach-Object {
    $_ -replace '<projectname>', $name `
       -replace '<deploypath>', "c:\inetpub\wwwroot\$name"
    } | Set-Content $deployFilePath

