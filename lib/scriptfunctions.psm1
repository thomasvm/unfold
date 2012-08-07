function Start-Download {
    param(
        [Parameter(Position=0,Mandatory=1)]$url,
        [Parameter(Position=1,Mandatory=1)]$destination,
    )
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url, $destination)
}

function Extract-File {
    param(
        [Parameter(Position=0,Mandatory=1)]$file,
        [Parameter(Position=1,Mandatory=1)]$destination,
    )
    $shell_app = new-object -com shell.application
    $zip_file = $shell_app.namespace($file)
    $destinationPath = $shell_app.namespace($destination)
    $destinationPath.Copyhere($zip_file.items())
}
