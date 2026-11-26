#Requires -Version 5.1
# SECURE_LAUNCHER_V1
# Derived from ChatGPT Switcher (MIT). See LICENSE.
[CmdletBinding(DefaultParameterSetName='Help')]
param(
    [Parameter(Mandatory,ParameterSetName='Add')][string]$Add,
    [Parameter(Mandatory,ParameterSetName='Launch')][string]$Launch,
    [Parameter(Mandatory,ParameterSetName='Status')][string]$Status,
    [Parameter(Mandatory,ParameterSetName='List')][switch]$List,
    [Parameter(Mandatory,ParameterSetName='Diagnose')][switch]$Diagnose,
    [Parameter(Mandatory,ParameterSetName='Version')][switch]$Version
)

$ErrorActionPreference = 'Stop'
$script:Root = 'E:\ChatGPT-Accounts-Secure'
$script:AppVersion = '1.3.0-secure.2'
$script:PackageFamily = 'OpenAI.Codex_2p2nqsd0c76g0'

function Get-ProfileId([string]$Id) {
    if ($Id -notmatch '\A[a-zA-Z0-9][a-zA-Z0-9-]{0,31}\z' -or
        $Id -match '\A(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])\z') {
        throw 'Invalid profile ID. Use 1-32 ASCII letters, digits or hyphens; no reserved device names.'
    }
    return $Id.ToLowerInvariant()
}

function Get-AccountPaths([string]$Id) {
    $id = Get-ProfileId $Id
    $rootPath = [IO.Path]::GetFullPath($script:Root)
    $base = [IO.Path]::GetFullPath((Join-Path $rootPath ('profile-' + $id)))
    if (-not $base.StartsWith($rootPath.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Profile path escaped its root.'
    }
    return [pscustomobject]@{
        Id = $id
        Base = $base
        Electron = Join-Path $base 'electron'
        Codex = Join-Path $base 'codex'
    }
}

function Get-PathItem([string]$Path) {
    try { Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.Management.Automation.ItemNotFoundException] { return $null }
}

function Assert-NoReparse([string]$Path) {
    $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path))
    while ($null -ne $cursor) {
        $item = Get-PathItem $cursor.FullName
        if ($null -ne $item) {
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Unsafe directory or reparse point.'
            }
        }
        $cursor = $cursor.Parent
    }
}

function Get-UserSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User
}

function Assert-PrivateDirectory([string]$Path) {
    Assert-NoReparse $Path
    $item = Get-PathItem $Path
    if ($null -eq $item -or -not $item.PSIsContainer) { throw 'Profile directory is missing.' }
    $user = (Get-UserSid).Value
    $system = 'S-1-5-18'
    $acl = Get-Acl -LiteralPath $Path
    if (-not $acl.AreAccessRulesProtected -or
        $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $user) {
        throw 'Directory ownership or ACL inheritance is unsafe.'
    }
    $full = [Security.AccessControl.FileSystemRights]::FullControl
    $rights = @{}
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        $sid = $rule.IdentityReference.Value
        if ($sid -notin @($user,$system) -or $rule.AccessControlType -ne 'Allow') {
            throw 'Unexpected directory permission.'
        }
        if ($rule.PropagationFlags -ne 'None' -or
            $rule.InheritanceFlags -ne ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit)) {
            throw 'Unexpected directory permission inheritance.'
        }
        $rights[$sid] = ([int]$rights[$sid]) -bor ([int]$rule.FileSystemRights)
    }
    foreach ($sid in @($user,$system)) {
        if (($rights[$sid] -band $full) -ne $full) { throw 'Required directory permissions are missing.' }
    }
}

function New-PrivateDirectory([string]$Path) {
    Assert-NoReparse $Path
    if ($null -eq (Get-PathItem $Path)) {
        $parent = [IO.Directory]::GetParent($Path)
        if ($null -eq $parent -or $null -eq (Get-PathItem $parent.FullName)) {
            throw 'Parent directory does not exist.'
        }
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $user = Get-UserSid
        $acl.SetOwner($user)
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($sid in @($user,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new(
                $sid,[Security.AccessControl.FileSystemRights]::FullControl,
                ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
        }
        [void][IO.Directory]::CreateDirectory($Path,$acl)
    }
    Assert-PrivateDirectory $Path
}

function Invoke-WithProfileLock([scriptblock]$Body) {
    # Global mutex serializes launcher operations for this Windows user.
    $name = 'Global\ChatGPTSwitcherSecure-' + (Get-UserSid).Value
    $mutex = [Threading.Mutex]::new($false,$name)
    $held = $false
    try {
        try { $held = $mutex.WaitOne([TimeSpan]::FromSeconds(20)) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'Another launcher operation is busy.' }
        & $Body
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Add-Account([string]$Id) {
    $p = Get-AccountPaths $Id
    Invoke-WithProfileLock {
        foreach ($dir in @($script:Root,$p.Base,$p.Electron,$p.Codex)) {
            New-PrivateDirectory $dir
        }
        return $p.Id
    }
}

function Get-ExistingProfile([string]$Id) {
    $p = Get-AccountPaths $Id
    foreach ($dir in @($script:Root,$p.Base,$p.Electron,$p.Codex)) {
        Assert-PrivateDirectory $dir
    }
    return $p
}

function Get-ProfileIds {
    Invoke-WithProfileLock {
        Assert-NoReparse $script:Root
        if ($null -eq (Get-PathItem $script:Root)) { return }
        Assert-PrivateDirectory $script:Root
        foreach ($dir in Get-ChildItem -LiteralPath $script:Root -Directory -Force) {
            if ($dir.Name -notmatch '\Aprofile-([a-z0-9][a-z0-9-]{0,31})\z') { continue }
            $id = $Matches[1]
            $p = Get-ExistingProfile $id
            $p.Id
        }
    }
}

function Get-ChatGptApp {
    $pkg = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop |
        Where-Object { $_.PackageFamilyName -eq $script:PackageFamily -and $_.SignatureKind -eq 'Store' -and $_.Status -eq 'Ok' } |
        Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if (-not $pkg -or -not $pkg.InstallLocation) { throw 'Trusted Microsoft Store ChatGPT package not found.' }
    # Do not search arbitrary folders, PATH, or user-writable installer locations.
    $exe = $null
    foreach ($relative in @('app\ChatGPT.exe','ChatGPT.exe','app\Codex.exe','Codex.exe')) {
        $candidate = Join-Path $pkg.InstallLocation $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $exe=$candidate; break }
    }
    if (-not $exe) { throw 'Expected executable missing from the Store package.' }
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or
        $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false) -ne 'OpenAI OpCo, LLC') {
        throw 'Executable signature or publisher is not trusted.'
    }
    return [pscustomobject]@{ Exe=$exe; Version=[string]$pkg.Version; Signature=[string]$sig.Status }
}

function New-LaunchInfo([string]$Exe,$Profile) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.WorkingDirectory = [IO.Path]::GetDirectoryName($Exe)
    $info.UseShellExecute = $false
    $info.Arguments = '--user-data-dir="' + $Profile.Electron + '"'
    # Never modify the parent environment or inherit another provider/session override.
    foreach ($key in @($info.EnvironmentVariables.Keys)) {
        if ($key -match '\A(?:OPENAI|CODEX|CHATGPT|ELECTRON|NODE)_|\ASSLKEYLOGFILE\z') { $info.EnvironmentVariables.Remove($key) }
    }
    $info.EnvironmentVariables['CODEX_HOME'] = $Profile.Codex
    $info.EnvironmentVariables['CODEX_ELECTRON_USER_DATA_PATH'] = $Profile.Electron
    return $info
}

function Get-WindowsArguments([string]$CommandLine) {
    if (-not ('SwitcherNative.Arguments' -as [type])) {
        # Compile only this embedded, auditable interop source, using Windows' own argument parser.
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace SwitcherNative {
    public static class Arguments {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern IntPtr CommandLineToArgvW(string commandLine, out int argc);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Parse(string commandLine) {
            int count;
            IntPtr ptr = CommandLineToArgvW(commandLine, out count);
            if (ptr == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                string[] values = new string[count];
                for (int i = 0; i < count; i++)
                    values[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(ptr, i * IntPtr.Size));
                return values;
            } finally { LocalFree(ptr); }
        }
    }
}
'@
    }
    [SwitcherNative.Arguments]::Parse($CommandLine)
}

function Test-ProfileCommandLine([string]$CommandLine,[string]$Directory) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $argv = @(Get-WindowsArguments $CommandLine)
    $values = @()
    for ($i=1; $i -lt $argv.Count; $i++) {
        $arg = $argv[$i]
        if ($arg -ceq '--') { break }
        if ($arg.StartsWith('--user-data-dir=',[StringComparison]::Ordinal)) {
            $values += $arg.Substring('--user-data-dir='.Length)
        } elseif ($arg -ceq '--user-data-dir') {
            if ($i+1 -ge $argv.Count) { return $false }
            $i++
            $values += $argv[$i]
        }
    }
    return ($values.Count -eq 1 -and [string]::Equals($values[0],$Directory,[StringComparison]::OrdinalIgnoreCase))
}

function Test-ProfileRunning($Profile) {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe' OR Name = 'Codex.exe'" -ErrorAction Stop)
    foreach ($proc in $procs) {
        if ([string]::IsNullOrWhiteSpace($proc.CommandLine)) {
            throw 'Cannot verify all ChatGPT process arguments. Launch stopped to avoid a duplicate session.'
        }
        if (Test-ProfileCommandLine $proc.CommandLine $Profile.Electron) { return $true }
    }
    return $false
}

function Wait-ProfileRunning($Profile,$Process,[int]$TimeoutMilliseconds=8000) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $seen = $false
    do {
        if (Test-ProfileRunning $Profile) {
            if ($seen) { return }
            $seen = $true
        } else {
            $seen = $false
            if ($Process.HasExited) { throw 'Application exited before a separate profile process was observed.' }
        }
        if ($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds) { break }
        Start-Sleep -Milliseconds 250
    } while ($clock.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    throw 'Could not verify a separate profile process. Inspect the application before retrying.'
}

function Start-Account([string]$Id) {
    Invoke-WithProfileLock {
        $p = Get-ExistingProfile $Id
        if (Test-ProfileRunning $p) { return "Profile $($p.Id) is already running." }
        $app = Get-ChatGptApp
        $info = New-LaunchInfo $app.Exe $p
        # Revalidate immediately before starting the executable.
        $null = Get-ExistingProfile $Id
        $proc = [Diagnostics.Process]::Start($info)
        if ($null -eq $proc) { throw 'App launch returned no process.' }
        try {
            Wait-ProfileRunning $p $proc
            return "Profile $($p.Id) process observed; initial PID $($proc.Id). Verify the account inside the app."
        }
        finally { $proc.Dispose() }
    }
}

# Dot-sourcing defines functions only, used by the regression suite.
if ($MyInvocation.InvocationName -eq '.') { return }
try {
    switch ($PSCmdlet.ParameterSetName) {
        'Add' { "Profile ready: $(Add-Account $Add)" }
        'Launch' { Start-Account $Launch }
        'Status' {
            Invoke-WithProfileLock {
                $p = Get-ExistingProfile $Status
                if (Test-ProfileRunning $p) { "Profile $($p.Id): process observed." }
                else { "Profile $($p.Id): no process observed." }
            }
        }
        'List' { Get-ProfileIds }
        'Diagnose' {
            $app = Get-ChatGptApp
            "ChatGPT package: $($app.Version); signature: $($app.Signature)"
            "Registered profiles: $(@(Get-ProfileIds).Count)"
            'Local profiles share the Windows user; this is not a security sandbox.'
        }
        'Version' { "ChatGPT Switcher Secure $script:AppVersion" }
        default {
            'Usage: ChatGPT-Switcher.ps1 -Add dot-1 | -Launch dot-1 | -Status dot-1 | -List | -Diagnose | -Version'
            'Sign in separately inside each official ChatGPT window.'
        }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
