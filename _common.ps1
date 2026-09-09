# _common.ps1 - c-drive-cleaner shared functions
# Dot-source: . (Join-Path (Split-Path -Parent $PSCommandPath) "_common.ps1")
# Or from scanners: . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")

if (-not $Global:CDriveScanResults) {
    $Global:CDriveScanResults = [System.Collections.ArrayList]::new()
}
if ($null -eq $Global:CDriveInventory) {
    $Global:CDriveInventory = [System.Collections.ArrayList]::new()
}
if ($null -eq $Global:CDriveMeasurementCache) {
    $Global:CDriveMeasurementCache = @{}
}
if ($null -eq $Global:CDriveMeasurementCacheHits) { $Global:CDriveMeasurementCacheHits = 0 }
if ($null -eq $Global:CDriveMeasurementCacheMisses) { $Global:CDriveMeasurementCacheMisses = 0 }

function Get-SkillRoot {
    if ($PSCommandPath) {
        $dir = Split-Path -Parent $PSCommandPath
        if (Test-Path (Join-Path $dir "_common.ps1")) { return $dir }
        $parent = Split-Path -Parent $dir
        if (Test-Path (Join-Path $parent "_common.ps1")) { return $parent }
    }
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "_common.ps1"))) {
        return $PSScriptRoot
    }
    throw "Skill root could not be resolved from the script location."
}

# --- Artifact output root ---------------------------------------------------
# All generated artifacts (reports, growth baselines, cleanup sessions, logs)
# default to D:\deepseek\workspace\cleansight so they never accumulate on C:.
# Resolution priority:
#   1. -OutputRoot parameter on analyze.ps1 (sets $Global:CDriveArtifactRoot)
#   2. $Global:CDriveArtifactRoot set by a caller
#   3. CLEANSIGHT_OUTPUT_DIR environment variable
#   4. Built-in default below
function Get-CleanSightArtifactRoot {
    param([string]$Override = "")
    if ($Override) { return $Override }
    if ($Global:CDriveArtifactRoot) { return [string]$Global:CDriveArtifactRoot }
    if ($env:CLEANSIGHT_OUTPUT_DIR) { return $env:CLEANSIGHT_OUTPUT_DIR }
    return 'D:\deepseek\workspace\cleansight'
}

function Get-CleanSightArtifactPath {
    param([string]$Relative = "")
    $root = Get-CleanSightArtifactRoot
    if (-not $Relative) { return $root }
    return (Join-Path $root $Relative)
}

function Initialize-CleanSightArtifactDirectory {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    return $Path
}

function Get-UninstallRegistryEntries {
    <#
    Read the three standard uninstall registry views once per analysis run.
    J and U both consume this inventory, so caching avoids duplicate registry IO.
    #>
    if ($null -ne $Global:CDriveUninstallRegistryEntries) {
        return @($Global:CDriveUninstallRegistryEntries)
    }

    $roots = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $entries = foreach ($root in $roots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
    }
    $Global:CDriveUninstallRegistryEntries = @($entries)
    return @($Global:CDriveUninstallRegistryEntries)
}

function ConvertTo-NonEmptyStringList {
    <# Normalize optional JSON arrays. In PowerShell @($null).Count is 1. #>
    param([object[]]$Values)
    return @($Values | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-RegexListMatch {
    param([string]$Value, [object[]]$Patterns)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    foreach ($pattern in @(ConvertTo-NonEmptyStringList -Values $Patterns)) {
        if ($Value -match $pattern) { return $true }
    }
    return $false
}

function Resolve-UninstallInstallFolder {
    param(
        $Entry,
        [switch]$NoExistenceCheck,
        [switch]$InstallLocationOnly,
        [switch]$TrustDisplayIconPath
    )

    $location = [Environment]::ExpandEnvironmentVariables([string]$Entry.InstallLocation).Trim().Trim('"')
    if ($location -and ($NoExistenceCheck -or (Test-Path -LiteralPath $location -PathType Container -ErrorAction SilentlyContinue))) {
        try { return [IO.Path]::GetFullPath($location).TrimEnd('\') } catch { return $location.TrimEnd('\') }
    }
    if ($InstallLocationOnly) { return "" }

    $icon = [Environment]::ExpandEnvironmentVariables([string]$Entry.DisplayIcon)
    if ($icon) {
        $icon = $icon.Split(',')[0].Trim().Trim('"')
        if ($TrustDisplayIconPath -or (Test-Path -LiteralPath $icon -PathType Leaf -ErrorAction SilentlyContinue)) {
            $parent = Split-Path -Parent $icon
            if ($parent) {
                try { return [IO.Path]::GetFullPath($parent).TrimEnd('\') } catch { return $parent.TrimEnd('\') }
            }
        }
    }
    return ""
}

function Get-FolderSizeFast {
    param([string]$Path)
    $measurement = Get-PathLogicalMeasurement -Path $Path
    return @{
        Size = [int64]$measurement.Bytes
        Count = [int64]$measurement.FileCount
        Found = ($measurement.Status -ne "missing")
        Status = $measurement.Status
        Evidence = $measurement.Evidence
    }
}

function Initialize-NativeFileScanner {
    if ("CleanSight.NativeFileScanner" -as [type]) { return }
    $sourcePath = Join-Path (Get-SkillRoot) "scripts\NativeFileScanner.cs"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Native scanner source not found: $sourcePath"
    }
    $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-MeasurementCacheKey {
    param([Parameter(Mandatory=$true)][string]$Path)
    try { return ([IO.Path]::GetFullPath($Path)).TrimEnd('\').ToLowerInvariant() }
    catch { return $Path.Trim().ToLowerInvariant() }
}

function Convert-NativePathMeasurement {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$NativeMeasurement
    )
    if (-not $NativeMeasurement.Exists) {
        return [pscustomobject]@{
            Path = $Path; Status = "missing"; Bytes = [int64]0; FileCount = [int64]0
            Evidence = "Win32 FindFirstFileExW; path missing or not enumerable"
        }
    }
    if ($NativeMeasurement.ReparsePoint) {
        return [pscustomobject]@{
            Path = $Path; Status = "partial"; Bytes = [int64]0; FileCount = [int64]0
            Evidence = "Win32 FindFirstFileExW; a reparse point exists in the path ancestry and was not followed"
        }
    }
    $status = if (-not $NativeMeasurement.RootAccessible) { "inaccessible" } elseif ($NativeMeasurement.SkippedDirectories -gt 0) { "partial" } else { "ok" }
    return [pscustomobject]@{
        Path = $Path
        Status = $status
        Bytes = [int64]$NativeMeasurement.Bytes
        FileCount = [int64]$NativeMeasurement.FileCount
        Evidence = "Win32 FindFirstFileExW; skipped_directories=$($NativeMeasurement.SkippedDirectories); elapsed_seconds=$($NativeMeasurement.ElapsedSeconds)"
    }
}

function Invoke-PathMeasurementPlan {
    <# Batch-measure exact paths and seed the per-run cache before scanners execute. #>
    param(
        [string[]]$Paths,
        [ValidateRange(1,8)][int]$Parallelism = 4
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $unique = [System.Collections.ArrayList]::new()
    $seen = @{}
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        $key = Get-MeasurementCacheKey -Path ([string]$path)
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$unique.Add([pscustomobject]@{ Path=[string]$path; Key=$key })
    }

    $misses = @($unique | Where-Object { -not $Global:CDriveMeasurementCache.ContainsKey($_.Key) })
    $seeded = 0
    $statusCounts = @{}
    if ($misses.Count -gt 0) {
        Initialize-NativeFileScanner
        $nativeResults = [CleanSight.NativeFileScanner]::MeasurePaths([string[]]@($misses.Path), $Parallelism)
        for ($index = 0; $index -lt $misses.Count; $index++) {
            $measurement = Convert-NativePathMeasurement -Path $misses[$index].Path -NativeMeasurement $nativeResults[$index]
            $Global:CDriveMeasurementCache[$misses[$index].Key] = $measurement
            $seeded++
            $status = [string]$measurement.Status
            if (-not $statusCounts.ContainsKey($status)) { $statusCounts[$status] = 0 }
            $statusCounts[$status]++
        }
    }
    $watch.Stop()
    return [pscustomobject]@{
        Requested = @($Paths).Count
        Unique = $unique.Count
        CachedBefore = $unique.Count - $misses.Count
        Seeded = $seeded
        StatusCounts = $statusCounts
        Parallelism = $Parallelism
        Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3)
    }
}

function Complete-PathLogicalMeasurement {
    param(
        [string]$CacheKey,
        [object]$Measurement,
        [switch]$NoCache
    )
    if ($Global:CDriveMeasurementCacheEnabled -and -not $NoCache -and $CacheKey) {
        $Global:CDriveMeasurementCache[$CacheKey] = $Measurement
    }
    return $Measurement
}

function Get-PathLogicalMeasurement {
    <#
    Measure logical bytes without changing the source. The native Win32 scanner
    does not follow reparse points; robocopy /L /XJ remains a compatibility fallback.
    Status is ok, partial, inaccessible, or missing; callers must not treat a
    partial measurement as a reliable cleanup estimate.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [switch]$NoCache
    )

    $cacheKey = Get-MeasurementCacheKey -Path $Path
    if ($Global:CDriveMeasurementCacheEnabled -and -not $NoCache) {
        if ($Global:CDriveMeasurementCache.ContainsKey($cacheKey)) {
            $Global:CDriveMeasurementCacheHits++
            return $Global:CDriveMeasurementCache[$cacheKey]
        }
        $Global:CDriveMeasurementCacheMisses++
    }

    try {
        Initialize-NativeFileScanner
        $native = [CleanSight.NativeFileScanner]::MeasurePath($Path)
        $result = Convert-NativePathMeasurement -Path $Path -NativeMeasurement $native
        return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
    } catch {
        # Native compilation can be unavailable on constrained hosts; retain the
        # robocopy implementation below as a compatibility fallback.
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        $parent = Split-Path -Parent $Path
        $leaf = Split-Path -Leaf $Path
        if ($parent -and $leaf -and (Test-Path -LiteralPath $parent -PathType Container -ErrorAction SilentlyContinue)) {
            $item = Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $leaf } | Select-Object -First 1
        }
    }
    if (-not $item) {
        $result = [pscustomobject]@{ Path=$Path; Status="missing"; Bytes=[int64]0; FileCount=[int64]0; Evidence="path missing or not enumerable" }
        return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
    }
    if (-not $item.PSIsContainer) {
        $result = [pscustomobject]@{ Path=$Path; Status="ok"; Bytes=[int64]$item.Length; FileCount=[int64]1; Evidence="file length" }
        return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
    }

    try {
        $probe = Join-Path $env:TEMP ("cdrive-size-probe-" + [guid]::NewGuid().ToString("N"))
        $output = @(& robocopy $Path $probe /L /S /XJ /NFL /NDL /NJH /BYTES /R:0 /W:0 2>&1)
        $exitCode = $LASTEXITCODE
        $text = $output | Out-String
        $byteMatch = [regex]::Match($text, '(?im)^\s*Bytes\s*:\s*([\d,]+)')
        $fileMatch = [regex]::Match($text, '(?im)^\s*Files\s*:\s*([\d,]+)')
        if ($byteMatch.Success) {
            $bytes = [int64](($byteMatch.Groups[1].Value -replace ',',''))
            $files = if ($fileMatch.Success) { [int64](($fileMatch.Groups[1].Value -replace ',','')) } else { [int64]0 }
            $partial = ($exitCode -ge 8) -or ($text -match '(?im)Access is denied|ERROR\s+5\s+\(0x00000005\)|拒绝访问')
            $status = if ($partial) { "partial" } else { "ok" }
            $result = [pscustomobject]@{ Path=$Path; Status=$status; Bytes=$bytes; FileCount=$files; Evidence="robocopy /L /XJ; exit=$exitCode" }
            return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
        }
    } catch {
        $result = [pscustomobject]@{ Path=$Path; Status="inaccessible"; Bytes=[int64]0; FileCount=[int64]0; Evidence=$_.Exception.Message }
        return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
    }
    $result = [pscustomobject]@{ Path=$Path; Status="inaccessible"; Bytes=[int64]0; FileCount=[int64]0; Evidence="robocopy summary unavailable" }
    return (Complete-PathLogicalMeasurement -CacheKey $cacheKey -Measurement $result -NoCache:$NoCache)
}

function Initialize-NtfsAllocationProbe {
    if ("CleanSight.NtfsAllocationProbe" -as [type]) { return }
    $source = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CleanSight {
    public sealed class NtfsProbeResult {
        public bool Success;
        public long AllocatedBytes;
        public string Identity;
        public uint LinkCount;
        public int ErrorCode;
    }

    public static class NtfsAllocationProbe {
        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern uint GetCompressedFileSizeW(string fileName, out uint fileSizeHigh);

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode,
            IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION info);

        public static NtfsProbeResult Probe(string path) {
            var result = new NtfsProbeResult();
            uint high;
            uint low = GetCompressedFileSizeW(path, out high);
            int sizeError = Marshal.GetLastWin32Error();
            if (low == 0xFFFFFFFF && sizeError != 0) {
                result.ErrorCode = sizeError;
                return result;
            }
            result.AllocatedBytes = ((long)high << 32) | low;

            const uint share = 1 | 2 | 4;
            const uint openExisting = 3;
            using (SafeFileHandle handle = CreateFileW(path, 0, share, IntPtr.Zero, openExisting, 0, IntPtr.Zero)) {
                if (handle.IsInvalid) {
                    result.ErrorCode = Marshal.GetLastWin32Error();
                    return result;
                }
                BY_HANDLE_FILE_INFORMATION info;
                if (!GetFileInformationByHandle(handle, out info)) {
                    result.ErrorCode = Marshal.GetLastWin32Error();
                    return result;
                }
                result.Identity = info.VolumeSerialNumber.ToString("X8") + ":" + info.FileIndexHigh.ToString("X8") + info.FileIndexLow.ToString("X8");
                result.LinkCount = info.NumberOfLinks;
                result.Success = true;
                return result;
            }
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-NtfsPathMeasurement {
    <#
    Measure directory-entry logical bytes, unique logical bytes, and allocated
    NTFS bytes. Hard links are deduplicated by file identity. This is exact for
    successfully probed files but intentionally bounded by time and file count.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$MaxFiles = 200000,
        [int]$MaxSeconds = 120
    )

    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Path=$Path; Status="missing"; EntryLogicalBytes=[int64]0; UniqueLogicalBytes=[int64]0; AllocatedBytes=[int64]0; FileCount=0; UniqueFileCount=0; HardlinkDuplicates=0; SparseOrCompressedFiles=0; Errors=0; ElapsedSeconds=0 }
    }

    try { Initialize-NtfsAllocationProbe } catch {
        return [pscustomobject]@{ Path=$Path; Status="probe-unavailable"; EntryLogicalBytes=[int64]0; UniqueLogicalBytes=[int64]0; AllocatedBytes=[int64]0; FileCount=0; UniqueFileCount=0; HardlinkDuplicates=0; SparseOrCompressedFiles=0; Errors=1; ElapsedSeconds=0; Evidence=$_.Exception.Message }
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $seen = @{}
    $entryLogical = [int64]0
    $uniqueLogical = [int64]0
    $allocated = [int64]0
    $fileCount = 0
    $uniqueCount = 0
    $hardlinkDuplicates = 0
    $specialCount = 0
    $errors = 0
    $truncated = $false

    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $singleFile = $null
    if (-not $rootItem) { $errors++; $truncated = $true }
    elseif ($rootItem.PSIsContainer) { $stack.Push($rootItem.FullName) }
    else { $singleFile = $rootItem }

    if ($singleFile) {
        $fileCount = 1
        $entryLogical = [int64]$singleFile.Length
        if (($singleFile.Attributes -band [IO.FileAttributes]::SparseFile) -ne 0 -or ($singleFile.Attributes -band [IO.FileAttributes]::Compressed) -ne 0) { $specialCount = 1 }
        $probe = [CleanSight.NtfsAllocationProbe]::Probe($singleFile.FullName)
        if ($probe.Success) {
            $seen[$probe.Identity] = $true
            $uniqueCount = 1
            $uniqueLogical = [int64]$singleFile.Length
            $allocated = [int64]$probe.AllocatedBytes
        } else { $errors++ }
    }

    while ($stack.Count -gt 0 -and -not $truncated) {
        $current = $stack.Pop()
        $enumerationErrors = @()
        $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue -ErrorVariable enumerationErrors)
        if ($enumerationErrors.Count -gt 0) { $errors += $enumerationErrors.Count }
        foreach ($child in $children) {
            if ($watch.Elapsed.TotalSeconds -ge $MaxSeconds -or $fileCount -ge $MaxFiles) { $truncated = $true; break }
            if ($child.PSIsContainer) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $stack.Push($child.FullName) }
                continue
            }
            $fileCount++
            $length = [int64]$child.Length
            $entryLogical += $length
            if (($child.Attributes -band [IO.FileAttributes]::SparseFile) -ne 0 -or ($child.Attributes -band [IO.FileAttributes]::Compressed) -ne 0) { $specialCount++ }
            $probe = [CleanSight.NtfsAllocationProbe]::Probe($child.FullName)
            if (-not $probe.Success) { $errors++; continue }
            if ($seen.ContainsKey($probe.Identity)) { $hardlinkDuplicates++; continue }
            $seen[$probe.Identity] = $true
            $uniqueCount++
            $uniqueLogical += $length
            $allocated += [int64]$probe.AllocatedBytes
        }
    }

    $watch.Stop()
    $status = if ($truncated) { "bounded-partial" } elseif ($errors -gt 0) { "partial" } else { "ok" }
    return [pscustomobject]@{
        Path = $Path
        Status = $status
        EntryLogicalBytes = $entryLogical
        UniqueLogicalBytes = $uniqueLogical
        AllocatedBytes = $allocated
        FileCount = $fileCount
        UniqueFileCount = $uniqueCount
        HardlinkDuplicates = $hardlinkDuplicates
        SparseOrCompressedFiles = $specialCount
        Errors = $errors
        ElapsedSeconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
    }
}

function Expand-EnvPath {
    param([string]$Path)
    return $Path -replace '%USERPROFILE%', $env:USERPROFILE `
        -replace '%LOCALAPPDATA%', $env:LOCALAPPDATA `
        -replace '%APPDATA%', $env:APPDATA `
        -replace '%PROGRAMFILES\(X86\)%', ${env:ProgramFiles(x86)} `
        -replace '%PROGRAMFILES%', $env:ProgramFiles `
        -replace '%PROGRAMDATA%', $env:ProgramData `
        -replace '%DOCUMENTS%', ([Environment]::GetFolderPath("MyDocuments"))
}

function Get-AIFootprintConfig {
    param([string]$ConfigPath = "")
    if (-not $ConfigPath) { $ConfigPath = Join-Path (Get-SkillRoot) "extensions\ai-footprints.json" }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf -ErrorAction SilentlyContinue)) { return $null }
    try { return Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "AI footprint config could not be parsed: $($_.Exception.Message)" }
}

function Get-EffectiveEnvironmentValue {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    foreach ($scope in @("Process", "User", "Machine")) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return [Environment]::ExpandEnvironmentVariables($value.Trim().Trim('"')) }
    }
    return ""
}

function Resolve-AIFootprintConfiguredRoots {
    <# Resolve only declared roots. Registry and AppX install roots are added by AF at scan time. #>
    param([object]$Config = $null)
    if (-not $Config) { $Config = Get-AIFootprintConfig }
    if (-not $Config) { return @() }

    $rows = [System.Collections.ArrayList]::new()
    foreach ($app in @($Config.applications)) {
        foreach ($root in @($app.roots)) {
            $envValue = Get-EffectiveEnvironmentValue -Name ([string]$root.pathEnv)
            $configuredPath = if ($envValue) { $envValue } else { Expand-EnvPath ([string]$root.path) }
            if ([string]::IsNullOrWhiteSpace($configuredPath)) { continue }
            $matches = if ($configuredPath -match '[*?]') {
                @(Get-Item -Path $configuredPath -Force -ErrorAction SilentlyContinue)
            } else {
                @([pscustomobject]@{ FullName=$configuredPath })
            }
            foreach ($match in $matches) {
                $fullPath = try { [IO.Path]::GetFullPath([string]$match.FullName).TrimEnd('\') } catch { continue }
                [void]$rows.Add([pscustomobject]@{
                    AppId = [string]$app.id
                    AppName = [string]$app.name
                    RootId = [string]$root.id
                    Path = $fullPath
                    Kind = [string]$root.kind
                    Policy = [string]$root.policy
                    Relocation = [string]$root.relocation
                    MigrationKey = [string]$root.migrationKey
                    InspectCommand = [string]$root.inspectCommand
                    CleanupCommand = [string]$root.cleanupCommand
                    PathEnvironment = [string]$root.pathEnv
                    EnvironmentOverride = [bool]$envValue
                    Source = "configured"
                })
            }
        }
    }
    return @($rows)
}

function Test-PathAtOrBelow {
    param([string]$Path, [string]$Root)
    try {
        $pathFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return $pathFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
            $pathFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Select-TopLevelPathItems {
    param(
        [AllowEmptyCollection()][object[]]$Items = @(),
        [string]$PathProperty = 'Path'
    )

    $selected = [System.Collections.ArrayList]::new()
    $seen = @{}
    $ordered = @($Items | Where-Object {
        $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.$PathProperty)
    } | Sort-Object @{ Expression = { ([string]$_.$PathProperty).TrimEnd('\').Length } }, @{ Expression = { [string]$_.$PathProperty } })

    foreach ($item in $ordered) {
        $path = ([string]$item.$PathProperty).TrimEnd('\')
        $key = $path.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $covered = @($selected | Where-Object {
            Test-PathAtOrBelow -Path $path -Root (([string]$_.$PathProperty).TrimEnd('\'))
        }).Count -gt 0
        if (-not $covered) { [void]$selected.Add($item) }
    }
    return @($selected)
}

function Load-SignatureDb {
    param([string]$Category)
    $sigFile = Join-Path (Get-SkillRoot) "extensions\app-signatures.json"
    if (-not (Test-Path $sigFile)) { return @() }
    try {
        $sigs = Get-Content $sigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $catApps = $sigs.categories.$Category.apps
        if ($catApps) { return @($catApps) } else { return @() }
    } catch { return @() }
}

function Load-CustomSigs {
    $customFile = Join-Path (Get-SkillRoot) "extensions\user-custom.json"
    if (-not (Test-Path $customFile)) { return @() }
    try {
        $cust = Get-Content $customFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cust.apps -and @($cust.apps).Count -gt 0) { return @($cust.apps) } else { return @() }
    } catch { return @() }
}

function Resolve-AppSignatureTargets {
    <# Resolve detect/sub paths once so the planner and scanner use identical targets. #>
    param([PSObject]$App)

    $foundPath = ""
    $candidates = [System.Collections.ArrayList]::new()
    foreach ($dp in @($App.detect_paths)) {
        $expanded = Expand-EnvPath ([string]$dp)
        $roots = try {
            if ($expanded -match '[*?]') {
                @(Get-Item -Path $expanded -Force -ErrorAction Stop | Where-Object { $_.PSIsContainer })
            } else {
                @(Get-Item -LiteralPath $expanded -Force -ErrorAction Stop | Where-Object { $_.PSIsContainer })
            }
        } catch { @() }

        foreach ($rootItem in $roots) {
            $rootPath = [string]$rootItem.FullName
            if (-not $foundPath) { $foundPath = $rootPath }
            $subPatterns = if ($App.sub_paths) {
                @($App.sub_paths)
            } elseif ($App.sub_cleanable) {
                @(([string]$App.sub_cleanable) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else { @() }

            if ($subPatterns.Count -eq 0) {
                [void]$candidates.Add($rootPath)
                continue
            }
            foreach ($sub in $subPatterns) {
                $subFull = Join-Path $rootPath ([string]$sub)
                if ([string]$sub -match '[*?]') {
                    foreach ($match in @(try { Get-Item -Path $subFull -Force -ErrorAction Stop } catch { @() })) {
                        [void]$candidates.Add($match.FullName)
                    }
                } else {
                    $match = try { Get-Item -LiteralPath $subFull -Force -ErrorAction Stop } catch { $null }
                    if ($match) { [void]$candidates.Add($match.FullName) }
                }
            }
        }
    }

    # Keep unique non-overlapping paths. Measuring a parent and its child would
    # double count the child's bytes in the same app finding.
    $selected = [System.Collections.ArrayList]::new()
    foreach ($candidate in @($candidates | Sort-Object { ([string]$_).Length })) {
        try { $candidateFull = [IO.Path]::GetFullPath([string]$candidate).TrimEnd('\') } catch { continue }
        $covered = $false
        foreach ($parent in @($selected)) {
            if ($candidateFull.Equals([string]$parent, [StringComparison]::OrdinalIgnoreCase) -or
                $candidateFull.StartsWith(([string]$parent).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $covered = $true
                break
            }
        }
        if (-not $covered) { [void]$selected.Add($candidateFull) }
    }
    return [pscustomobject]@{ Found=[bool]$foundPath; FoundPath=$foundPath; Paths=@($selected) }
}

function Get-SignatureMeasurementPlanPaths {
    param([string[]]$Categories)
    $paths = [System.Collections.ArrayList]::new()
    $apps = [System.Collections.ArrayList]::new()
    foreach ($category in @($Categories | Select-Object -Unique)) {
        foreach ($app in @(Load-SignatureDb -Category $category)) { [void]$apps.Add($app) }
    }
    foreach ($app in @(Load-CustomSigs)) { [void]$apps.Add($app) }
    foreach ($app in @($apps)) {
        $resolved = Resolve-AppSignatureTargets -App $app
        foreach ($path in @($resolved.Paths)) { [void]$paths.Add($path) }
    }
    return @($paths)
}

function Test-AppSignature {
    param([PSObject]$App)
    $resolved = Resolve-AppSignatureTargets -App $App
    $totalSize = 0L
    $measurements = [System.Collections.ArrayList]::new()
    foreach ($candidate in @($resolved.Paths)) {
        $r = Get-FolderSizeFast $candidate
        if (-not $r.Found -or $r.Size -le 0) { continue }
        $totalSize += [int64]$r.Size
        [void]$measurements.Add([pscustomobject]@{
            Path = $candidate
            Bytes = [int64]$r.Size
            Status = $r.Status
            Evidence = $r.Evidence
        })
    }
    return @{ Found=$resolved.Found; Size=$totalSize; Path=$resolved.FoundPath; Measurements=@($measurements) }
}

function Convert-RiskLevel {
    param($Cleanable)
    if ($Cleanable -eq $true) { return "safe" }
    if ($Cleanable -eq "cautious") { return "cautious" }
    if ($Cleanable -eq $false) { return "forbidden" }
    return "cautious"
}

function Write-ScanResult {
    param(
        [string]$Category,
        [string]$Name,
        [long]$Size,
        [string]$Risk,
        [string]$Path,
        [string]$Advice,
        [string]$Migration,
        [string]$Note,
        [string]$Source = "",
        [object[]]$Measurements = @()
    )
    $sizeMB = [math]::Round($Size / 1MB, 2)
    $sizeGB = [math]::Round($Size / 1GB, 2)
    $sizeStr = if ($sizeGB -ge 1) { "$sizeGB GB" } else { "$sizeMB MB" }
    $riskIcon = switch ($Risk) {
        "safe"      { "✅" }
        "cautious"  { "⚠️" }
        "dangerous" { "❌" }
        "forbidden" { "🔴" }
        default     { "⚠️" }
    }
    $color = switch ($Risk) {
        "safe"      { "Green" }
        "cautious"  { "Yellow" }
        "dangerous" { "Red" }
        "forbidden" { "Red" }
        default     { "Yellow" }
    }
    if ($sizeMB -gt 0) {
        $srcTag = if ($Source) { " [$Source]" } else { "" }
        Write-Host "  $riskIcon ${Name}${srcTag}: $sizeStr" -ForegroundColor $color
        if ($Path) { Write-Host "     路径: $Path" -ForegroundColor DarkGray }
        if ($Advice) { Write-Host "     建议: $Advice" -ForegroundColor DarkGray }
        if ($Migration) { Write-Host "     迁移: $Migration" -ForegroundColor DarkGray }
        if ($Note) { Write-Host "     备注: $Note" -ForegroundColor DarkGray }
    }
    $measurementRows = @($Measurements)
    if ($measurementRows.Count -eq 0 -and $Path -and $Size -gt 0) {
        $measurementRows = @([pscustomobject]@{ Path = $Path; Bytes = [int64]$Size; Status = "reported"; Evidence = $Source })
    }
    [void]$Global:CDriveScanResults.Add(@{
        Category = $Category
        Name     = $Name
        SizeMB   = $sizeMB
        Risk     = $Risk
        Path     = $Path
        Advice   = $Advice
        Migration = $Migration
        Note     = $Note
        Source   = $Source
        Measurements = $measurementRows
    })
}

function Write-InventoryResult {
    param(
        [string]$Category,
        [string]$Name,
        [long]$Size,
        [string]$Path,
        [string]$Kind = "inventory",
        [string]$Evidence = "",
        [string]$Access = "ok"
    )
    if ($null -eq $Global:CDriveInventory) {
        $Global:CDriveInventory = [System.Collections.ArrayList]::new()
    }
    $sizeMB = [math]::Round($Size / 1MB, 2)
    $sizeGB = [math]::Round($Size / 1GB, 2)
    $sizeStr = if ($sizeGB -ge 1) { "$sizeGB GB" } elseif ($sizeMB -ge 1) { "$sizeMB MB" } else { "$([math]::Round($Size / 1KB, 1)) KB" }
    $icon = switch ($Access) {
        "inaccessible" { "🔒" }
        "partial" { "⚠️" }
        "bounded-partial" { "⚠️" }
        default { "ℹ️" }
    }
    Write-Host "  $icon ${Name}: $sizeStr" -ForegroundColor DarkCyan
    if ($Path) { Write-Host "     路径: $Path" -ForegroundColor DarkGray }
    if ($Evidence) { Write-Host "     证据: $Evidence" -ForegroundColor DarkGray }
    [void]$Global:CDriveInventory.Add(@{
        Category = $Category
        Name = $Name
        SizeMB = $sizeMB
        SizeBytes = $Size
        Path = $Path
        Kind = $Kind
        Evidence = $Evidence
        Access = $Access
    })
}

function Get-DriveSpace {
    try {
        $drive = New-Object System.IO.DriveInfo("C:\")
        if (-not $drive.IsReady -or $drive.TotalSize -le 0) { return $null }
        $totalBytes = [double]$drive.TotalSize
        $freeBytes = [double]$drive.AvailableFreeSpace
        $usedBytes = $totalBytes - $freeBytes
        $totalGB = [math]::Round($totalBytes / 1GB, 2)
        $usedGB = [math]::Round($usedBytes / 1GB, 2)
        $freeGB = [math]::Round($freeBytes / 1GB, 2)
        $usedPercent = [math]::Round($usedBytes / $totalBytes * 100, 1)
    } catch {
        return $null
    }
    return @{
        TotalGB     = $totalGB
        UsedGB      = $usedGB
        FreeGB      = $freeGB
        UsedPercent = $usedPercent
    }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProgressBar {
    param([int]$Current, [int]$Total, [int]$Width = 30)
    if ($Total -le 0) { return "" }
    $pct = [math]::Min(100, [math]::Max(0, [int]($Current / $Total * 100)))
    $filled = [math]::Max(0, [math]::Min($Width, [int]($pct * $Width / 100)))
    $empty = $Width - $filled
    $bar = "[" + ("=" * $filled) + (">" * [math]::Min(1, $filled - [math]::Max(0, $filled - 1))) + (" " * $empty) + "]"
    return "$bar $pct%"
}

function Test-CleanupTargetSafety {
    <#
    Fail-closed deletion gate. It validates lexical containment, volume, protected
    roots, object type, and every ancestor for junctions/symlinks/mount points.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$AllowedRoots,
        [string]$ExpectedDrive = "C",
        [ValidateSet("Any","Directory","File")][string]$TargetType = "Any"
    )

    function New-SafetyResult([bool]$safe, [string]$reason, [string]$fullPath = "") {
        return [pscustomobject]@{ Safe=$safe; Reason=$reason; Path=$fullPath; ExpectedDrive=$ExpectedDrive }
    }

    if ([string]::IsNullOrWhiteSpace($Path)) { return (New-SafetyResult $false "目标路径为空") }
    if (-not [IO.Path]::IsPathRooted($Path)) { return (New-SafetyResult $false "拒绝相对路径: $Path") }
    if (-not $AllowedRoots -or @($AllowedRoots).Count -eq 0) { return (New-SafetyResult $false "调用方未提供允许根目录") }

    try { $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch { return (New-SafetyResult $false "目标路径无法规范化: $($_.Exception.Message)") }

    $pathRoot = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    $expectedRoot = ([string]$ExpectedDrive).Trim().TrimEnd(':') + ':'
    if (-not $pathRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return (New-SafetyResult $false "目标位于 $pathRoot，清理器只允许 $expectedRoot" $fullPath)
    }

    $protectedRoots = @(
        "$expectedRoot\",
        (Join-Path "$expectedRoot\" "Windows"),
        (Join-Path "$expectedRoot\" "Users"),
        $env:USERPROFILE,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        $env:APPDATA
    ) | Where-Object { $_ } | ForEach-Object {
        try { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') } catch { [string]$_ }
    }
    foreach ($protected in $protectedRoots) {
        if ($fullPath.Equals($protected, [StringComparison]::OrdinalIgnoreCase)) {
            return (New-SafetyResult $false "拒绝删除受保护根目录: $protected" $fullPath)
        }
    }

    $withinAllowedRoot = $false
    foreach ($allowed in @($AllowedRoots)) {
        if ([string]::IsNullOrWhiteSpace([string]$allowed) -or -not [IO.Path]::IsPathRooted([string]$allowed)) { continue }
        try { $allowedFull = [IO.Path]::GetFullPath([string]$allowed).TrimEnd('\') } catch { continue }
        if ($fullPath.Equals($allowedFull, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($allowedFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $withinAllowedRoot = $true
            break
        }
    }
    if (-not $withinAllowedRoot) { return (New-SafetyResult $false "目标不在调用方声明的允许根目录内" $fullPath) }

    try {
        Initialize-NativeFileScanner
        $inspection = [CleanSight.NativeFileScanner]::InspectPathSafety($fullPath)
    } catch {
        return (New-SafetyResult $false "原生路径安全检查不可用: $($_.Exception.Message)" $fullPath)
    }
    if ($inspection.Error) { return (New-SafetyResult $false "路径安全检查失败: $($inspection.Error)" $fullPath) }
    if (-not $inspection.Exists) { return (New-SafetyResult $false "目标不存在或不可访问" $fullPath) }
    if ($inspection.ReparsePointInAncestry) { return (New-SafetyResult $false "目标或其祖先含重解析点，拒绝跨卷/链接删除" $fullPath) }
    if ($TargetType -eq "Directory" -and -not $inspection.IsDirectory) { return (New-SafetyResult $false "目标不是目录" $fullPath) }
    if ($TargetType -eq "File" -and $inspection.IsDirectory) { return (New-SafetyResult $false "目标不是文件" $fullPath) }
    return (New-SafetyResult $true "通过统一安全门禁" $fullPath)
}

function Remove-SafeFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$AllowedRoots,
        [string]$ExpectedDrive = "C"
    )
    try { $exists = Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop }
    catch {
        Write-Host "  ⛔ 安全门禁无法检查目标: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    if (-not $exists) { return $true }
    $gate = Test-CleanupTargetSafety -Path $Path -AllowedRoots $AllowedRoots -ExpectedDrive $ExpectedDrive -TargetType File
    if (-not $gate.Safe) {
        Write-Host "  ⛔ 安全门禁拒绝删除: $($gate.Reason)" -ForegroundColor Red
        Write-Host "     $($gate.Path)" -ForegroundColor DarkGray
        return $false
    }
    try {
        Remove-Item -LiteralPath $gate.Path -Force -ErrorAction Stop
        return (-not (Test-Path -LiteralPath $gate.Path -ErrorAction Stop))
    } catch {
        Write-Host "  ❌ 文件删除失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Remove-Directory {
    <#
    .SYNOPSIS
    高性能递归删除目录，带进度反馈、超时控制和多级回退。
    主方案: cmd /c rmdir（快 10-100 倍）+ 每 5 秒进度反馈
    回退A: robocopy /MIR 快速清空后再 rmdir（比 .NET Delete 快数倍）
    回退B: .NET API 作为最后手段
    .PARAMETER Path
    要删除的目录路径
    .PARAMETER ShowTimer
    是否显示耗时
    .PARAMETER TimeoutSec
    超时秒数（默认 120，大目录 30-60 秒通常足够）
    .PARAMETER ShowProgress
    删除过程中是否定期输出进度（耗时+剩余大小检查）
    #>
    param(
        [string]$Path,
        [Parameter(Mandatory=$true)][string[]]$AllowedRoots,
        [string]$ExpectedDrive = "C",
        [switch]$ShowTimer,
        [int]$TimeoutSec = 120,
        [switch]$ShowProgress
    )
    try { $exists = Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop }
    catch {
        Write-Host "  ⛔ 安全门禁无法检查目标: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    if (-not $exists) { return $true }
    $gate = Test-CleanupTargetSafety -Path $Path -AllowedRoots $AllowedRoots -ExpectedDrive $ExpectedDrive -TargetType Directory
    if (-not $gate.Safe) {
        Write-Host "  ⛔ 安全门禁拒绝删除: $($gate.Reason)" -ForegroundColor Red
        Write-Host "     $($gate.Path)" -ForegroundColor DarkGray
        return $false
    }
    $Path = $gate.Path

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # 预先计算大小（用于进度估计）
    $initialSize = 0L
    $initialSizeStr = ""
    if ($ShowProgress) {
        $r = Get-FolderSizeFast $Path
        if ($r.Found) {
            $initialSize = $r.Size
            $sizeMB = [math]::Round($initialSize / 1MB, 2)
            $initialSizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB/1024,2)) GB" } else { "$sizeMB MB" }
        }
        Write-Host "  删除中 ($initialSizeStr)..." -ForegroundColor DarkGray
    } elseif ($ShowTimer) {
        Write-Host "  删除中..." -NoNewline -ForegroundColor DarkGray
    }

    # 方案 A: cmd /c rmdir 带超时保护和进度反馈
    $processExited = $true
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd"
        $psi.Arguments = "/c rmdir /s /q `"$Path`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)

        if ($ShowProgress) {
            $progressInterval = 5
            $prevRemainingStr = ""
            $cursorLeft = [Console]::CursorLeft
            while (-not $p.WaitForExit($progressInterval * 1000)) {
                $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
                $remainingSize = 0L
                $remainingStr = ""
                try {
                    if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
                        $rr = Get-FolderSizeFast $Path
                        if ($rr.Found) { $remainingSize = $rr.Size }
                    }
                } catch {}
                if ($remainingSize -gt 0 -and $initialSize -gt 0) {
                    $cleaned = $initialSize - $remainingSize
                    $cleanedMB = [math]::Round($cleaned / 1MB, 2)
                    $totalMB = [math]::Round($initialSize / 1MB, 2)
                    $pctDone = [math]::Min(99, [int]($cleaned / $initialSize * 100))
                    $remainingStr = " 已删 ${cleanedMB}MB/${totalMB}MB"
                    $bar = Get-ProgressBar -Current $cleaned -Total $initialSize -Width 20
                    # 用 \r 回到行首覆盖输出
                    Write-Host "`r  [${elapsed}s]$bar$remainingStr  " -NoNewline -ForegroundColor DarkGray
                } else {
                    Write-Host "`r  [${elapsed}s] 删除中...  " -NoNewline -ForegroundColor DarkGray
                }
            }
            $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
            Write-Host "`r  [${elapsed}s] 等待完成...     " -NoNewline -ForegroundColor DarkGray
            $processExited = $true
        } else {
            $processExited = $p.WaitForExit($TimeoutSec * 1000)
        }

        if (-not $processExited) {
            $p.Kill()
            if ($ShowTimer -or $ShowProgress) { Write-Host " 超时..." -NoNewline -ForegroundColor Yellow }
        }
    } catch {
        $processExited = $false
    }

    $stillExists = $true
    try { $stillExists = Test-Path -LiteralPath $Path -ErrorAction Stop } catch { $stillExists = $true }
    if ($stillExists) {
        if ($ShowProgress -or $ShowTimer) {
            Write-Host " 回退(robocopy)..." -NoNewline -ForegroundColor Yellow
        }
        try {
            $emptyDir = Join-Path $env:TEMP "_empty_$(Get-Random)"
            $null = New-Item -ItemType Directory -Path $emptyDir -Force
            & robocopy $emptyDir $Path /MIR /R:1 /W:1 > $null 2>&1
            Remove-Item $emptyDir -Force -ErrorAction SilentlyContinue
            & cmd /c "rmdir /s /q `"$Path`"" 2>$null
        } catch {
            try { [System.IO.Directory]::Delete($Path, $true) } catch {}
        }
    }

    $sw.Stop()
    $stillExists = $true
    try { $stillExists = Test-Path -LiteralPath $Path -ErrorAction Stop } catch { $stillExists = $true }
    if ($ShowTimer -or $ShowProgress) {
        $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
        if ($ShowProgress) {
            $icon = if (-not $stillExists) { "✅" } else { "❌" }
            Write-Host ""
            Write-Host "    $icon 耗时 ${elapsed}s" -ForegroundColor $(if (-not $stillExists) { "Green" } else { "Red" })
        } else {
            $msg = if (-not $stillExists) { " 完成($($elapsed)s)" } else { " 失败($($elapsed)s)" }
            Write-Host $msg -ForegroundColor $(if (-not $stillExists) { "Green" } else { "Red" })
        }
    }
    return (-not $stillExists)
}

function Invoke-SignatureScan {
    param(
        [string]$Category,
        [string]$CategoryLabel,
        [string[]]$AlreadyScanned = @()
    )
    $apps = Load-SignatureDb -Category $Category
    foreach ($app in $apps) {
        if ($app.name -in $AlreadyScanned) { continue }
        $result = Test-AppSignature $app
        if ($result.Found -and $result.Size -gt 1MB) {
            $risk = Convert-RiskLevel $app.cleanable
            $advice = ""
            if ($app.cleanable -eq $true) { $advice = "可安全清理" }
            elseif ($app.cleanable -eq "cautious") { $advice = "确认后可操作" }
            elseif ($app.cleanable -eq $false) { $advice = "不可删除" }
            if ($app.sub_cleanable) { $advice += " (可清理: $($app.sub_cleanable))" }
            $migration = ""
            if ($app.migratable -eq $true) {
                $migration = "可迁移"
                if ($app.migration_method) {
                    $methodLabel = switch -wildcard ($app.migration_method) {
                        'env_var*' { "设环境变量" }
                        'symlink*' { "符号链接" }
                        'config*'  { "改配置文件" }
                        'yarn_config*' { "yarn config set" }
                        'pnpm_config*' { "pnpm config set" }
                        'wsl_export*' { "wsl export/import" }
                        default { $app.migration_method }
                    }
                    $migration += " ($methodLabel)"
                    if ($app.migration_key) { $migration += " | key: $($app.migration_key)" }
                }
            }
            Write-ScanResult -Category $CategoryLabel -Name $app.name `
                -Size $result.Size -Risk $risk -Path $result.Path `
                -Advice $advice -Migration $migration -Note $app.note -Source "DB" `
                -Measurements $result.Measurements
        }
    }
    $customApps = Load-CustomSigs
    foreach ($app in $customApps) {
        if ($app.name -in $AlreadyScanned) { continue }
        $result = Test-AppSignature $app
        if ($result.Found -and $result.Size -gt 1MB) {
            $risk = Convert-RiskLevel $app.cleanable
            Write-ScanResult -Category $CategoryLabel -Name $app.name `
                -Size $result.Size -Risk $risk -Path $result.Path `
                -Note $app.note -Source "自定义" -Measurements $result.Measurements
        }
    }
}
