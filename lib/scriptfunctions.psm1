function Start-Download {
    param(
        [Parameter(Position=0,Mandatory=1)]$url,
        [Parameter(Position=1,Mandatory=1)]$destination
    )
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url, $destination)
}

function Expand-File {
    param(
        [Parameter(Position=0,Mandatory=1)]$file,
        [Parameter(Position=1,Mandatory=1)]$destination
    )
    $shell_app = new-object -com shell.application
    $zip_file = $shell_app.namespace($file)
    $destinationPath = $shell_app.namespace($destination)
    $destinationPath.Copyhere($zip_file.items())
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

        msbuild "transform.msbuild"

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

