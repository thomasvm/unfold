param($installPath, $toolsPath, $package, $project)

$name = $project.Name
$projectPath = Split-Path $project.Filename
$deployFilePath = "$projectPath\deployment\deploy.ps1"

function Detect-RemoteOrigin($folder) {
    while($folder) {
        Write-Host $folder
        If(Test-Path "$folder\.git") {
            # read config
            $config = Get-Content "$folder\.git\config" -ErrorAction SilentlyContinue
    
            $inOriginSection = $false
    
            # detect remote origin section, and read url
            foreach($line in $config) {
                If ($inOriginSection) {
                  $parts = $line.Split('=') | ForEach-Object { $_.Trim() }
    
                  If($parts[0] -eq "url") {
                    return $parts[1]
                  }
    
                } ElseIf($line -eq '[remote "origin"]') {
                    $inOriginSection = $true
                } ElseIf ($line.StartsWith("[")) {
                    $inOriginSection = $false
                }
            }
    
            break
        }
    
        # Top-level? break
        If(-not(Split-Path $folder).Length) {
            break
        }
        $folder = Get-Item "$folder\.."
    }
}


$remoteOrigin = Detect-RemoteOrigin $projectPath

If(-not $remoteOrigin) {
    $remoteOrigin = "<gitrepository>"
}

(Get-Content $deployFilePath) | Foreach-Object {
    $_ -replace '<projectname>', $name `
       -replace '<deploypath>', "c:\inetpub\wwwroot\$name" `
       -replace '<gitrepository>', $remoteOrigin
    } | Set-Content $deployFilePath

