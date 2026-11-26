#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$rootDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path $rootDir 'ChatGPT-Switcher.ps1'
$script:Failures = 0
$script:Passed = 0
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:Passed++; Write-Host "PASS $Name" }
    catch { $script:Failures++; Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Body) {
    $threw = $false
    try { & $Body | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw 'Expected rejection' }
}
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
$raw=[IO.File]::ReadAllText($source)
Check 'Syntax' { Assert-True ($errors.Count -eq 0) 'Parser rejected source' }
Check 'No credential handling or shared mode' {
    Assert-True ($raw -notmatch '(?i)auth\.json|shared-auth|SaveAuth|Start-SharedAccount|\$Shared\b') 'Credential sharing remains'
}
Check 'No destructive profile deletion' {
    Assert-True ($raw -notmatch '(?i)Remove-Item|Delete\s*\(') 'Destructive deletion remains'
}
Check 'No remote installer or publisher' {
    foreach ($f in 'install.ps1','publish.ps1','publish.cmd') {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $rootDir $f))) "Unexpected $f"
    }
}
Check 'No execution policy bypass' {
    $cmdPath=Join-Path $rootDir 'ChatGPT-Switcher.cmd'
    $cmd=if(Test-Path -LiteralPath $cmdPath) { Get-Content -Raw -LiteralPath $cmdPath } else { '' }
    Assert-True (($cmd+$raw) -notmatch '(?i)ExecutionPolicy\s+Bypass') 'Bypass remains'
}
Check 'No raw process command-line diagnostics' {
    Assert-True ($raw -notmatch '(?i)Write-Host[^\r\n]*CommandLine') 'Diagnostic leaks process command line'
}
Check 'No shared mutable JSON configuration' {
    Assert-True ($raw -notmatch '(?i)accounts\.json') 'Mutable JSON configuration remains'
}
# Extract only the pure path function for the upstream RED run; never run upstream entrypoint.
if ($raw -notmatch 'SECURE_LAUNCHER_V1') {
    $f=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AccountPaths'},$true)
    . ([scriptblock]::Create($f.Extent.Text))
    $script:Root=Join-Path $rootDir 'not-created'
    Check 'Traversal rejected' { Assert-Throws { Get-AccountPaths '..' } }
    Check 'Reserved name rejected' { Assert-Throws { Get-AccountPaths 'CON' } }
    Write-Host "RESULT $script:Passed passed, $script:Failures failed (upstream)"
    if ($script:Failures) { exit 1 }; exit 0
}
. $source
$script:Root = Join-Path $rootDir ('test-scratch-'+[guid]::NewGuid().ToString('N'))
Check 'Traversal rejected' {
    foreach ($id in @('..','../outside','..\outside','E:\outside','a/b','a\b','a.','a ','','a:b','a"b')) {
        Assert-Throws { Get-AccountPaths $id }
    }
}
Check 'Reserved name rejected' {
    foreach ($id in @('CON','PRN','AUX','NUL','COM1','LPT9','COM0','LPT0')) { Assert-Throws { Get-AccountPaths $id } }
}
Check 'Paths canonical and separate' {
    $p=Get-AccountPaths 'Dot-1'; $q=Get-AccountPaths 'Dot-2'
    Assert-True ($p.Base -eq (Join-Path $script:Root 'profile-dot-1')) 'Wrong base'
    Assert-True ($p.Electron -ne $q.Electron -and $p.Codex -ne $q.Codex) 'Profiles overlap'
}
try {
    Check 'Add and list without authentication' {
        Add-Account 'dot-1' | Out-Null; Add-Account 'dot-2' | Out-Null
        $names=@(Get-ProfileIds)
        Assert-True ($names.Count -eq 2 -and $names -contains 'dot-1' -and $names -contains 'dot-2') 'Profiles missing'
        Add-Account 'DOT-1' | Out-Null
        Assert-True (@(Get-ProfileIds).Count -eq 2) 'Duplicate profile'
    }
    Check 'Unregistered profile fails closed' { Assert-Throws { Get-ExistingProfile 'missing' } }
    Check 'ACL protected and restricted' {
        $p=Get-ExistingProfile 'dot-1'
        foreach ($d in @($script:Root,$p.Base,$p.Electron,$p.Codex)) { Assert-PrivateDirectory $d }
    }
    Check 'Unexpected allow ACL rejected' {
        $p=Get-ExistingProfile 'dot-1'
        $acl=[IO.Directory]::GetAccessControl($p.Electron,[Security.AccessControl.AccessControlSections]::Access)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule ([Security.Principal.SecurityIdentifier]'S-1-1-0'),'ReadAndExecute','Allow'
        $acl.AddAccessRule($rule); [IO.Directory]::SetAccessControl($p.Electron,$acl)
        try { Assert-Throws { Get-ExistingProfile 'dot-1' } }
        finally { $acl.RemoveAccessRuleSpecific($rule); [IO.Directory]::SetAccessControl($p.Electron,$acl) }
    }
    Check 'Junction rejected without following it' {
        $target=Join-Path $script:Root 'target'
        New-PrivateDirectory $target
        $link=Join-Path $script:Root 'profile-evil'
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try { Assert-Throws { Add-Account 'evil' }; Assert-Throws { Get-ExistingProfile 'evil' } }
        finally { [IO.Directory]::Delete($link) }
        Assert-True (Test-Path -LiteralPath $target) 'Junction target affected'
    }
    Check 'Child environment isolated and parent unchanged' {
        $p=Get-ExistingProfile 'dot-1'
        $old=$env:CODEX_HOME; $oldKey=$env:OPENAI_API_KEY
        try {
            $env:CODEX_HOME='sentinel-parent'; $env:OPENAI_API_KEY='dummy-test-key'
            $info=New-LaunchInfo 'C:\dummy\ChatGPT.exe' $p
            Assert-True ($info.EnvironmentVariables['CODEX_HOME'] -eq $p.Codex) 'Wrong CODEX_HOME'
            Assert-True ($info.EnvironmentVariables['CODEX_ELECTRON_USER_DATA_PATH'] -eq $p.Electron) 'Wrong Electron directory'
            Assert-True (-not $info.EnvironmentVariables.ContainsKey('OPENAI_API_KEY')) 'Inherited API key'
            Assert-True ($env:CODEX_HOME -eq 'sentinel-parent' -and $env:OPENAI_API_KEY -eq 'dummy-test-key') 'Parent env changed'
            Assert-True (-not $info.UseShellExecute -and $info.Arguments -eq ('--user-data-dir="'+$p.Electron+'"')) 'Invalid launch arguments'
        } finally { $env:CODEX_HOME=$old; $env:OPENAI_API_KEY=$oldKey }
    }
    Check 'Exact process argument match' {
        $p=Get-ExistingProfile 'dot-1'
        Assert-True (Test-ProfileCommandLine ('"C:\x\ChatGPT.exe" --user-data-dir="'+$p.Electron+'"') $p.Electron) 'Exact match missed'
        Assert-True (-not (Test-ProfileCommandLine ('"C:\x\ChatGPT.exe" --user-data-dir="'+$p.Electron+'-other"') $p.Electron)) 'Prefix match accepted'
        Assert-True (-not (Test-ProfileCommandLine ('"C:\x\ChatGPT.exe" --other="'+$p.Electron+'"') $p.Electron)) 'Wrong flag accepted'
    }
    Check 'Electron and Node injection overrides removed' {
        $p=Get-ExistingProfile 'dot-1'
        $keys=@('NODE_OPTIONS','NODE_PATH','ELECTRON_RUN_AS_NODE','ELECTRON_NO_ASAR','SSLKEYLOGFILE','NODE_EXTRA_CA_CERTS','NODE_TLS_REJECT_UNAUTHORIZED')
        $saved=@{}
        try {
            foreach($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,'dummy-test','Process') }
            $info=New-LaunchInfo 'C:\dummy\ChatGPT.exe' $p
            foreach($key in $keys) {
                Assert-True (-not $info.EnvironmentVariables.ContainsKey($key)) "Inherited injection override: $key"
                Assert-True ([Environment]::GetEnvironmentVariable($key,'Process') -eq 'dummy-test') 'Parent env changed'
            }
        } finally { foreach($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
    }
    Check 'Windows argument serialization variants' {
        $dir='E:\profile with spaces\electron'
        Assert-True (Test-ProfileCommandLine ('ChatGPT.exe "--user-data-dir='+$dir+'"') $dir) 'Whole quoted argument missed'
        Assert-True (Test-ProfileCommandLine ('ChatGPT.exe --user-data-dir "'+$dir+'"') $dir) 'Separate value missed'
        Assert-True (-not (Test-ProfileCommandLine ('ChatGPT.exe "--user-data-dir='+$dir+'-other"') $dir)) 'Prefix match accepted'
    }
    Check 'Untrusted package refused before launch' {
        function Get-AppxPackage { [pscustomobject]@{PackageFamilyName='Untrusted';SignatureKind='Store';Status='Ok';Version='1.0';InstallLocation=$script:Root} }
        Assert-Throws { Get-ChatGptApp }
    }
    Check 'Already-running profile is not launched again' {
        function Test-ProfileRunning { return $true }
        function Get-ChatGptApp { throw 'Unexpected app lookup' }
        Assert-True ((Start-Account 'dot-1') -eq 'Profile dot-1 is already running.') 'Duplicate launch not prevented'
    }
    Check 'Process inspection failure blocks launch' {
        function Test-ProfileRunning { throw 'Synthetic inspection failure' }
        function Get-ChatGptApp { throw 'Unexpected app lookup' }
        $message=$null
        try { Start-Account 'dot-1' | Out-Null } catch { $message=$_.Exception.Message }
        Assert-True ($message -eq 'Synthetic inspection failure') 'Process inspection failure was not preserved'
    }
    Check 'Concurrent profile additions' {
        $jobs=@()
        try {
            foreach ($id in @('parallel-a','parallel-b','parallel-a','parallel-c')) {
                $jobs+=Start-Job -ScriptBlock {param($src,$dir,$id) $ErrorActionPreference='Stop'; . $src; $script:Root=$dir; Add-Account $id | Out-Null} -ArgumentList $source,$script:Root,$id
            }
            $jobs | Wait-Job -Timeout 40 | Out-Null
            foreach($j in $jobs) { Assert-True ($j.State -eq 'Completed') 'Concurrent add failed'; Receive-Job $j -ErrorAction Stop | Out-Null }
            $ids=@(Get-ProfileIds)
            Assert-True ($ids.Count -eq 5) 'Lost or duplicate profile'
        } finally { $jobs | Stop-Job -ErrorAction SilentlyContinue; $jobs | Remove-Job -Force -ErrorAction SilentlyContinue }
    }
} finally {
    # Only the test's unique scratch tree, never a real profile.
    if ((Split-Path -Parent $script:Root) -eq $rootDir -and (Split-Path -Leaf $script:Root) -match '^test-scratch-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $script:Root)) {
        Remove-Item -LiteralPath $script:Root -Recurse -Force
    }
}
Write-Host "RESULT $script:Passed passed, $script:Failures failed"
if ($script:Failures) { exit 1 }
