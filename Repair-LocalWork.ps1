#Requires -Version 5.1
# Version-specific workaround for the official Windows Store plugin-copy failure.
[CmdletBinding(DefaultParameterSetName='Help')]
param(
    [Parameter(Mandatory,ParameterSetName='Prepare')][switch]$Prepare,
    [Parameter(Mandatory,ParameterSetName='Launch')][switch]$Launch
)
$mode=$PSCmdlet.ParameterSetName
$invocation=$MyInvocation.InvocationName
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ChatGPT-Switcher.ps1')

function Get-PluginTree([string]$RootPath) {
    $rootFull=[IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $item=Get-Item -LiteralPath $rootFull -Force
    if(!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe plugin tree root.'}
    $pending=New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($rootFull)
    while($pending.Count -gt 0){
        $dir=$pending.Pop()
        foreach($entry in Get-ChildItem -LiteralPath $dir -Force){
            if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in plugin tree.'}
            $relative=$entry.FullName.Substring($rootFull.Length+1)
            [pscustomobject]@{Relative=$relative;Path=$entry.FullName;Directory=$entry.PSIsContainer}
            if($entry.PSIsContainer){$pending.Push($entry.FullName)}
        }
    }
}

function Assert-PluginMirror([string]$Source,[string]$Destination){
    Assert-PrivateDirectory $Destination
    $plugins=Join-Path $Destination 'plugins'
    Assert-PrivateDirectory $plugins
    $rootEntries=@(Get-ChildItem -LiteralPath $Destination -Force)
    if($rootEntries.Count -ne 1 -or $rootEntries[0].Name -cne 'plugins'){throw 'Unexpected resource mirror root contents.'}
    $sourceItems=@(Get-PluginTree $Source)
    $destItems=@(Get-PluginTree $plugins)
    if($sourceItems.Count -ne $destItems.Count){throw 'Plugin tree entry count mismatch.'}
    $index=@{}
    foreach($item in $destItems){$index[$item.Relative]=$item}
    $count=0
    foreach($item in $sourceItems){
        $other=$index[$item.Relative]
        if(!$other -or $other.Relative -cne $item.Relative -or $other.Directory -ne $item.Directory){throw 'Missing or changed plugin tree entry.'}
        if($item.Directory){Assert-PrivateDirectory $other.Path}
        else{
            if((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $other.Path -Algorithm SHA256).Hash){throw 'Plugin content hash mismatch.'}
            $count++
        }
    }
    return $count
}

function New-PluginMirror([string]$Source,[string]$Destination){
    $parent=Split-Path -Parent $Destination
    Assert-PrivateDirectory $parent
    if($null -ne (Get-PathItem $Destination)){return (Assert-PluginMirror $Source $Destination)}
    $entries=@(Get-PluginTree $Source)
    $stage=Join-Path $parent ('resources-stage-'+[guid]::NewGuid().ToString('N'))
    New-PrivateDirectory $stage
    $plugins=Join-Path $stage 'plugins'
    New-PrivateDirectory $plugins
    foreach($item in $entries|Where-Object Directory|Sort-Object {$_.Relative.Length}){
        New-PrivateDirectory (Join-Path $plugins $item.Relative)
    }
    foreach($item in $entries|Where-Object {!$_.Directory}){
        $out=Join-Path $plugins $item.Relative
        $bytes=[IO.File]::ReadAllBytes($item.Path)
        $stream=[IO.File]::Open($out,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
    $count=Assert-PluginMirror $Source $stage
    [IO.Directory]::Move($stage,$Destination)
    return $count
}

function New-OriginalLaunchInfo([string]$Exe,[string]$ResourceMirror){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Exe
    $info.WorkingDirectory=[IO.Path]::GetDirectoryName($Exe)
    $info.UseShellExecute=$false
    # Keep the existing main Codex home; never copy account data or set another profile.
    foreach($key in @($info.EnvironmentVariables.Keys)){
        if($key -match '\A(?:OPENAI|CODEX|CHATGPT|ELECTRON|NODE)_|\ASSLKEYLOGFILE\z'){$info.EnvironmentVariables.Remove($key)}
    }
    $codexHome=[Environment]::GetEnvironmentVariable('CODEX_HOME','User')
    if(![string]::IsNullOrWhiteSpace($codexHome)){$info.EnvironmentVariables['CODEX_HOME']=$codexHome}
    $info.EnvironmentVariables['CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH']=$ResourceMirror
    return $info
}

function Assert-OriginalStopped {
    $profiles=@(Get-ProfileIds|ForEach-Object{Get-ExistingProfile $_})
    $procs=@(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'" -ErrorAction Stop)
    foreach($proc in $procs){
        if([string]::IsNullOrWhiteSpace($proc.CommandLine)){throw 'Cannot inspect existing ChatGPT process.'}
        $argv=@(Get-WindowsArguments $proc.CommandLine)
        if(@($argv|Where-Object{$_ -like '--type=*'}).Count -gt 0){continue}
        $known=$false
        foreach($profile in $profiles){
            if(Test-ProfileCommandLine $proc.CommandLine $profile.Electron){$known=$true;break}
        }
        if(!$known){throw 'Exit the original ChatGPT from its tray menu before launching this repair. Other profiles may remain open.'}
    }
}

if($invocation -eq '.'){return}
try{
    if($mode -notin @('Prepare','Launch')){
        'Usage: Repair-LocalWork.ps1 -Prepare | -Launch'
        return
    }
    $app=Get-ChatGptApp
    if($app.Version -notmatch '\A\d+\.\d+\.\d+\.\d+\z'){throw 'Unexpected package version.'}
    $source=Join-Path ([IO.Path]::GetDirectoryName($app.Exe)) 'resources\plugins'
    $destination=Join-Path $script:Root ('resources-'+$app.Version)
    if($mode -eq 'Prepare'){
        $count=Invoke-WithProfileLock {
            New-PrivateDirectory $script:Root
            New-PluginMirror $source $destination
        }
        "Verified mirror: $count files; package $($app.Version); $destination"
    }else{
        # List/profile checks acquire the launcher lock internally; keep this outside its lock.
        Assert-OriginalStopped
        $count=Assert-PluginMirror $source $destination
        Assert-OriginalStopped
        $info=New-OriginalLaunchInfo $app.Exe $destination
        $proc=[Diagnostics.Process]::Start($info)
        if(!$proc){throw 'Application did not start.'}
        try{"Original ChatGPT launch requested; initial PID $($proc.Id); $count verified plugin files. Verify Local Work in the app."}
        finally{$proc.Dispose()}
    }
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
