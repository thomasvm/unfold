function Start-Download {
    param(
        [Parameter(Position=0,Mandatory=1)]$url,
        [Parameter(Position=1,Mandatory=1)]$destination
    )
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url, $destination)
}

function Expand-Zip {
    param(
        [Parameter(Position=0,Mandatory=1)]$file,
        [Parameter(Position=1,Mandatory=1)]$destination
    )

    $source = (Resolve-Path $file).Path
    $dest = (Resolve-Path $destination).Path

    $shell_app = new-object -com shell.application

    $zip_file = $shell_app.namespace($source)
    $destinationPath = $shell_app.namespace($dest)
    $destinationPath.CopyHere($zip_file.items())
}

function New-Zip {
    param(
       [Parameter(Mandatory=$true, Position=0)]
       [String]$path, 
       [Parameter(Mandatory=$true, Position=1)]
       [String]$zip,
       [Parameter(Mandatory=$false,Position=2)]
       [switch]$force
    )
     
    $Directory = Get-Item $path
    
    If (test-path $zip) { 
      If($force) {
        Remove-Item $zip
      } Else {
        echo "Zip file already exists at $zip" 
        return 
      }
    }
    
    Set-content $zip ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18)) 
    (dir $zip).IsReadOnly = $false

    $fullZipPath = (Resolve-Path $zip).Path
    $shell_app = new-object -com shell.application
    $zip_file = $shell_app.namespace($fullZipPath)
    $zip_file.CopyHere($Directory.FullName)
    Wait-Zipcount $fullZipPath 1
}

function Wait-Zipcount([string] $zipname, [int] $num) {
    $ExplorerShell=NEW-OBJECT -comobject 'Shell.Application'
    $count = count-zipfiles -zipname $zipname -ExplorerShell $ExplorerShell
    while (($count -eq $null) -or ($count -lt $num) ) {
        Write-Host "." -NoNewLine
        Start-Sleep -milliseconds 100
        $count = count-zipfiles -zipname $zipname -ExplorerShell $ExplorerShell
    }
    Write-Host "."
}

function Count-Zipfiles([string] $zipname, [object] $ExplorerShell=$NULL) {
    if ((test-path $zipname) -eq $NULL) {
        return $null
    }
    if ($ExplorerShell -eq $NULL) {
        $ExplorerShell = new-object -comobject 'Shell.Application'
    }
    $zipdirfh = $ExplorerShell.Namespace($zipname)
    $count = $zipdirfh.Items().Count
    return $count
}

# Transform config
function Convert-Configuration {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$source,
        [Parameter(Position=1,Mandatory=1)][string]$transformation,
        [Parameter(Position=2,Mandatory=0)][string]$destination
    )

    If(-not $destination) {
        $destination = $source
    }

    $vars = @{
        source = $source
        transformation = $transformation
        destination = $destination
    }

    $block = {
        param([psobject]$arguments)

        $temp = $arguments.source + ".temp"

        Move-Item $arguments.source $temp

        $msbuild = @"
<Project ToolsVersion="4.0" 
         DefaultTargets="Transform" 
         xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <UsingTask TaskName="TransformXml"
             AssemblyFile="`$(MSBuildExtensionsPath)\Microsoft\VisualStudio\v10.0\Web\Microsoft.Web.Publishing.Tasks.dll"/>

    <Target Name="Transform">
        <TransformXml Source="$temp"
                      Transform="$($arguments.transformation)"
                      Destination="$($arguments.destination)"/>
    </Target>
</Project>
"@

        Set-Content "transform.msbuild" $msbuild

        Exec {
            msbuild "transform.msbuild"
        }

        # Success? remove temp, otherwise move back
        If(Test-Path $arguments.destination) {
            Remove-item $temp
        } Else {
            Move-Item $temp $arguments.source
        }

        Remove-item "transform.msbuild"
    }

    & $block $vars
}

function Convert-Xml {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$path,
        [Parameter(Position=1,Mandatory=1)][scriptblock]$script
    )

    $xmlFile = [xml](Get-Content $path)
    $xml = $xmlFile.get_DocumentElement()

    # Make variables available in scope
    .$script $xmlFile $xml

    # xml save need's fully specified path
    $fullPath = Resolve-Path $path
    $xmlFile.Save($fullPath)
}

function Remove-EmptyFolders {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$path
    )
    $hasDeleted = $false

    Get-ChildItem $path -Recurse | Foreach-Object {
        If(-not $_.PSIsContainer) {
            return
        }
        $subitems = Get-ChildItem -Recurse -Path $_.FullName
        if($subitems -eq $null)
        {
              Write-Host "Remove item: " + $_.FullName
              Remove-Item $_.FullName
              $hasDeleted = $true
        }
        $subitems = $null
    }

    # Loop again until we don't remove any folder anymore
    If($hasDeleted) {
        Remove-EmptyFolders $path
    } 
}

function Copy-WebProject {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$path,
        [Parameter(Position=1,Mandatory=1)][string]$destination
    )
    $sourceLength = (Resolve-Path $path).Path.Length

    Foreach($item in Get-ChildItem $path) {
        if (-not $item.PSIsContainer) {
            Copy-Item -Destination "$destination\$($item.Name)" $item.FullName
            continue
        }

        if ($config.excludeWebFolders) {
            if ($config.excludeWebFolders -contains $item.Name) {
                continue
            }
        }

        New-Item -type Directory -name "$destination\$($item.Name)"
        Write-Host "copying $($item.Name)..." -Fore Yellow

        Get-ChildItem $item.FullName -Recurse -Exclude @('*.cs', '*.csproj') `
            | Copy-Item -Destination {
                $result = Join-Path $destination $_.FullName.Substring($sourceLength)
                return $result
             }
    }
}

function Set-IISSite {
    param(
        [Parameter(Position=0,Mandatory=1)][string]$name,
        [Parameter(Position=1,Mandatory=1)][string]$path,
        [Parameter(Position=2,Mandatory=1)][string]$apppool,
        [Parameter(Position=3,Mandatory=1)]$bindings
    )
    Import-Module WebAdministration

    # Convert to array
    If($bindings.GetType().Name -eq "ArrayList") {
        $arr = @()
        Foreach($b in $bindings) {
            $arr += $b
        }
        $bindings = $arr
    }

    $iisPath    = "iis:\\Sites\$name"

    # Site Already set up?
    If (Test-Path $iisPath) {
        Set-ItemProperty $iisPath -name physicalPath    -value $path
        Set-ItemProperty $iisPath -name bindings        -value $bindings
        Set-ItemProperty $iispath -name applicationPool -value "$apppool"
    } Else {
        New-Item $iisPath -physicalPath $path -bindings $bindings -applicationPool $apppool
    }
}

Export-ModuleMember -function Start-Download, Expand-Zip, New-Zip, `
                              Remove-EmptyFolders, Convert-Configuration, `
                              Convert-Xml, Copy-WebProject, Set-IISSite
