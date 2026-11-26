#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$scriptPath=Join-Path $repo 'Repair-LocalWork.ps1'
if(!(Test-Path -LiteralPath $scriptPath)){Write-Host 'RED: resource mirror helper missing';exit 1}
. $scriptPath
$script:Root=Join-Path $repo ('repair-test-'+[guid]::NewGuid().ToString('N'))
$src=Join-Path $script:Root 'source'
$dst=Join-Path $script:Root 'resources'
$n=0
function Test-Check([string]$Name,[scriptblock]$Body){& $Body; $script:n++;Write-Host "PASS $Name"}
function Require($Value,[string]$Message){if(!$Value){throw $Message}}
function Expect-Reject([scriptblock]$Body){$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Require $failed 'Expected rejection'}
try{
 New-PrivateDirectory $script:Root
 New-PrivateDirectory $src
 New-PrivateDirectory (Join-Path $src 'nested')
 [IO.File]::WriteAllBytes((Join-Path $src 'sample.bin'),[byte[]](0,1,255,42))
 [IO.File]::WriteAllText((Join-Path $src 'nested\sample.txt'),'test')
 Test-Check 'Byte stream mirror is complete' {
  $count=New-PluginMirror $src $dst
  Require ($count -eq 2) 'Wrong count'
  Require ((Assert-PluginMirror $src $dst) -eq 2) 'Verification failed'
 }
 Test-Check 'Mirror preparation is idempotent' {Require ((New-PluginMirror $src $dst) -eq 2) 'Reuse failed'}
 Test-Check 'Changed file rejected' {
  $f=Join-Path $dst 'plugins\sample.bin'
  [IO.File]::WriteAllText($f,'different')
  Expect-Reject {Assert-PluginMirror $src $dst}
  [IO.File]::WriteAllBytes($f,[IO.File]::ReadAllBytes((Join-Path $src 'sample.bin')))
 }
 Test-Check 'Unexpected files rejected' {
  $f=Join-Path $dst 'plugins\unexpected.txt';[IO.File]::WriteAllText($f,'test')
  try{Expect-Reject {Assert-PluginMirror $src $dst}}finally{[IO.File]::Delete($f)}
 }
 Test-Check 'Missing files rejected' {
  $f=Join-Path $dst 'plugins\nested\sample.txt';[IO.File]::Delete($f)
  try{Expect-Reject {Assert-PluginMirror $src $dst}}finally{[IO.File]::WriteAllText($f,'test')}
 }
 Test-Check 'Junction refused' {
  $p=Join-Path $dst 'plugins\junction'
  New-Item -ItemType Junction -Path $p -Target $src|Out-Null
  try{Expect-Reject {Assert-PluginMirror $src $dst}}finally{[IO.Directory]::Delete($p)}
 }
 Test-Check 'Launch override is process scoped' {
  $before=$env:CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH
  $info=New-OriginalLaunchInfo 'C:\Program Files\WindowsApps\Example\ChatGPT.exe' $dst
  Require ($info.EnvironmentVariables['CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH'] -eq $dst) 'Wrong mirror override'
  Require ($env:CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH -eq $before) 'Parent environment mutated'
  Require (!$info.EnvironmentVariables.ContainsKey('CODEX_ELECTRON_USER_DATA_PATH')) 'Unexpected profile override'
  Require ([string]::IsNullOrEmpty($info.Arguments)) 'Unexpected launch flags'
 }
 Write-Host "RESULT $n passed"
}finally{
 if((Split-Path -Parent $script:Root) -eq $repo -and (Split-Path -Leaf $script:Root) -match '^repair-test-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $script:Root)){Remove-Item -LiteralPath $script:Root -Recurse -Force}
}
