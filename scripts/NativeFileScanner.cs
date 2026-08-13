using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace CleanSight
{
    public sealed class FastFileRecord
    {
        public string Path { get; set; }
        public long Length { get; set; }
    }

    public sealed class FastDirectoryTotal
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public long Bytes { get; set; }
        public long FileCount { get; set; }
    }

    public sealed class FastPathTotalSpec
    {
        public string Id { get; set; }
        public string Path { get; set; }
    }

    public sealed class FastPathTotalRecord
    {
        public string Id { get; set; }
        public string Path { get; set; }
        public long Bytes { get; set; }
        public long FileCount { get; set; }
        public bool Seen { get; set; }
        public bool Partial { get; set; }
    }

    public sealed class FastFileScanSpec
    {
        public string Root { get; set; }
        public string[] ExcludedDirectories { get; set; }
        public string[] PartialDirectories { get; set; }
        public string AggregateRoot { get; set; }
        public FastPathTotalSpec[] AggregatePaths { get; set; }
    }

    public sealed class FastRootScanRecord
    {
        public string Root { get; set; }
        public long EnumeratedFiles { get; set; }
        public long EnumeratedDirectories { get; set; }
        public long SkippedDirectories { get; set; }
        public double ElapsedSeconds { get; set; }
    }

    public sealed class FastFileScanResult
    {
        public List<FastFileRecord> TopFiles { get; private set; }
        public List<FastDirectoryTotal> RootChildTotals { get; private set; }
        public List<FastRootScanRecord> Roots { get; private set; }
        public List<FastPathTotalRecord> PathTotals { get; private set; }
        public long EnumeratedFiles { get; set; }
        public long EnumeratedDirectories { get; set; }
        public long SkippedDirectories { get; set; }
        public double ElapsedSeconds { get; set; }

        public FastFileScanResult()
        {
            TopFiles = new List<FastFileRecord>();
            RootChildTotals = new List<FastDirectoryTotal>();
            Roots = new List<FastRootScanRecord>();
            PathTotals = new List<FastPathTotalRecord>();
        }
    }

    public sealed class RuntimeAppRecord
    {
        public string Root { get; set; }
        public string Path { get; set; }
        public string DirectoryName { get; set; }
        public long TotalBytes { get; set; }
        public long RuntimeBytes { get; set; }
        public long FileCount { get; set; }
        public long PakCount { get; set; }
        public bool HasCefIndicator { get; set; }
        public long SkippedDirectories { get; set; }
        public string[] ExecutableNames { get; set; }
    }

    public sealed class RuntimeScanResult
    {
        public List<RuntimeAppRecord> Apps { get; private set; }
        public long CandidateDirectories { get; set; }
        public long EnumeratedFiles { get; set; }
        public long SkippedDirectories { get; set; }
        public double ElapsedSeconds { get; set; }

        public RuntimeScanResult()
        {
            Apps = new List<RuntimeAppRecord>();
        }
    }

    internal sealed class DirectoryNode
    {
        public string Path;
        public string RootChild;
    }

    internal sealed class ChildAccumulator
    {
        public string Name;
        public string Path;
        public long Bytes;
        public long FileCount;
    }

    internal sealed class SingleFileScanResult
    {
        public List<FastFileRecord> TopFiles = new List<FastFileRecord>();
        public Dictionary<string, ChildAccumulator> RootChildren = new Dictionary<string, ChildAccumulator>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, FastPathTotalRecord> PathTotals = new Dictionary<string, FastPathTotalRecord>(StringComparer.OrdinalIgnoreCase);
        public FastRootScanRecord RootRecord = new FastRootScanRecord();
    }

    public static class NativeFileScanner
    {
        private const int FindExInfoBasic = 1;
        private const int FindExSearchNameMatch = 0;
        private const int FindFirstExLargeFetch = 2;
        private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Win32FindData
        {
            public FileAttributes FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint Reserved0;
            public uint Reserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string FileName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)]
            public string AlternateFileName;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFileExW(
            string fileName,
            int infoLevel,
            out Win32FindData findData,
            int searchOperation,
            IntPtr searchFilter,
            int additionalFlags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindNextFileW(IntPtr findHandle, out Win32FindData findData);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FindClose(IntPtr findHandle);

        public static FastFileScanResult ScanLargeFiles(FastFileScanSpec[] specs, int topN, int parallelism)
        {
            var result = new FastFileScanResult();
            if (specs == null || specs.Length == 0 || topN <= 0) return result;

            topN = Math.Max(1, Math.Min(topN, 1000));
            parallelism = Math.Max(1, Math.Min(parallelism, 8));
            var gate = new object();
            var aggregateChildren = new Dictionary<string, FastDirectoryTotal>(StringComparer.OrdinalIgnoreCase);
            var aggregatePaths = new Dictionary<string, FastPathTotalRecord>(StringComparer.OrdinalIgnoreCase);
            var watch = Stopwatch.StartNew();
            var options = new ParallelOptions { MaxDegreeOfParallelism = parallelism };

            Parallel.ForEach(specs, options, spec =>
            {
                var part = ScanLargeFilesSingle(spec, topN);
                lock (gate)
                {
                    result.EnumeratedFiles += part.RootRecord.EnumeratedFiles;
                    result.EnumeratedDirectories += part.RootRecord.EnumeratedDirectories;
                    result.SkippedDirectories += part.RootRecord.SkippedDirectories;
                    result.Roots.Add(part.RootRecord);
                    foreach (var file in part.TopFiles) AddTop(result.TopFiles, file.Path, file.Length, topN);
                    foreach (var child in part.RootChildren.Values)
                    {
                        FastDirectoryTotal total;
                        if (!aggregateChildren.TryGetValue(child.Path, out total))
                        {
                            total = new FastDirectoryTotal
                            {
                                Name = child.Name,
                                Path = child.Path
                            };
                            aggregateChildren[child.Path] = total;
                        }
                        total.Bytes += child.Bytes;
                        total.FileCount += child.FileCount;
                    }
                    foreach (var pathTotal in part.PathTotals.Values)
                    {
                        var key = pathTotal.Id + "\0" + pathTotal.Path;
                        FastPathTotalRecord total;
                        if (!aggregatePaths.TryGetValue(key, out total))
                        {
                            total = new FastPathTotalRecord
                            {
                                Id = pathTotal.Id,
                                Path = pathTotal.Path
                            };
                            aggregatePaths[key] = total;
                        }
                        total.Bytes += pathTotal.Bytes;
                        total.FileCount += pathTotal.FileCount;
                        total.Seen = total.Seen || pathTotal.Seen;
                        total.Partial = total.Partial || pathTotal.Partial;
                    }
                }
            });

            watch.Stop();
            result.RootChildTotals.AddRange(aggregateChildren.Values);
            result.PathTotals.AddRange(aggregatePaths.Values);
            result.ElapsedSeconds = Math.Round(watch.Elapsed.TotalSeconds, 3);
            return result;
        }

        public static RuntimeScanResult ScanRuntimeApps(string[] roots, string[] excludedDirectories, string[] expandContainerNames, int parallelism)
        {
            var result = new RuntimeScanResult();
            if (roots == null || roots.Length == 0) return result;

            parallelism = Math.Max(1, Math.Min(parallelism, 8));
            var excluded = BuildExclusions(excludedDirectories);
            var expandContainers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (expandContainerNames != null)
            {
                foreach (var name in expandContainerNames)
                {
                    if (!String.IsNullOrWhiteSpace(name)) expandContainers.Add(name.Trim());
                }
            }
            var candidates = new List<KeyValuePair<string, string>>();
            foreach (var root in roots)
            {
                if (String.IsNullOrWhiteSpace(root)) continue;
                foreach (var directory in EnumerateImmediateDirectories(root))
                {
                    if (IsExcluded(directory, excluded)) continue;
                    var directoryName = Path.GetFileName(directory);
                    if (!expandContainers.Contains(directoryName))
                    {
                        candidates.Add(new KeyValuePair<string, string>(Normalize(root), directory));
                        continue;
                    }

                    var childCount = 0;
                    foreach (var child in EnumerateImmediateDirectories(directory))
                    {
                        if (IsExcluded(child, excluded)) continue;
                        candidates.Add(new KeyValuePair<string, string>(directory, child));
                        childCount++;
                    }
                    if (childCount == 0) candidates.Add(new KeyValuePair<string, string>(Normalize(root), directory));
                }
            }

            result.CandidateDirectories = candidates.Count;
            var gate = new object();
            var watch = Stopwatch.StartNew();
            var options = new ParallelOptions { MaxDegreeOfParallelism = parallelism };
            Parallel.ForEach(candidates, options, candidate =>
            {
                var app = ScanRuntimeCandidate(candidate.Key, candidate.Value, excluded);
                lock (gate)
                {
                    result.EnumeratedFiles += app.FileCount;
                    result.SkippedDirectories += app.SkippedDirectories;
                    if (app.HasCefIndicator && app.PakCount >= 3) result.Apps.Add(app);
                }
            });
            watch.Stop();
            result.ElapsedSeconds = Math.Round(watch.Elapsed.TotalSeconds, 3);
            return result;
        }

        private static SingleFileScanResult ScanLargeFilesSingle(FastFileScanSpec spec, int topN)
        {
            var result = new SingleFileScanResult();
            var root = spec == null ? null : Normalize(spec.Root);
            result.RootRecord.Root = root;
            if (String.IsNullOrWhiteSpace(root)) return result;

            var watch = Stopwatch.StartNew();
            var excluded = BuildExclusions(spec.ExcludedDirectories);
            var partialDirectories = BuildExclusions(spec.PartialDirectories);
            if (spec.AggregatePaths != null)
            {
                foreach (var aggregatePath in spec.AggregatePaths)
                {
                    if (aggregatePath == null || String.IsNullOrWhiteSpace(aggregatePath.Path)) continue;
                    var targetPath = Normalize(aggregatePath.Path);
                    if (!PathsOverlap(root, targetPath)) continue;
                    var key = (aggregatePath.Id ?? targetPath) + "\0" + targetPath;
                    if (!result.PathTotals.ContainsKey(key))
                    {
                        result.PathTotals[key] = new FastPathTotalRecord
                        {
                            Id = aggregatePath.Id ?? targetPath,
                            Path = targetPath
                        };
                    }
                }
            }
            var pending = new Stack<DirectoryNode>();
            pending.Push(new DirectoryNode { Path = root, RootChild = null });

            while (pending.Count > 0)
            {
                var node = pending.Pop();
                if (IsExcluded(node.Path, excluded)) continue;
                result.RootRecord.EnumeratedDirectories++;
                foreach (var total in result.PathTotals.Values)
                {
                    if (node.Path.Equals(total.Path, StringComparison.OrdinalIgnoreCase)) total.Seen = true;
                }

                Win32FindData data;
                var handle = OpenFind(node.Path, out data);
                if (handle == InvalidHandleValue)
                {
                    result.RootRecord.SkippedDirectories++;
                    foreach (var total in result.PathTotals.Values)
                    {
                        if (PathsOverlap(node.Path, total.Path)) total.Partial = true;
                    }
                    continue;
                }

                try
                {
                    do
                    {
                        var name = data.FileName;
                        if (name == "." || name == "..") continue;
                        var path = Combine(node.Path, name);
                        var isDirectory = (data.FileAttributes & FileAttributes.Directory) != 0;
                        if (isDirectory)
                        {
                            if ((data.FileAttributes & FileAttributes.ReparsePoint) != 0) continue;
                            if (IsExcluded(path, excluded))
                            {
                                if (IsExcluded(path, partialDirectories))
                                {
                                    foreach (var total in result.PathTotals.Values)
                                    {
                                        if (PathsOverlap(path, total.Path)) total.Partial = true;
                                    }
                                }
                                continue;
                            }
                            pending.Push(new DirectoryNode
                            {
                                Path = path,
                                RootChild = node.RootChild ?? name
                            });
                            continue;
                        }

                        var length = ((long)data.FileSizeHigh << 32) | data.FileSizeLow;
                        result.RootRecord.EnumeratedFiles++;
                        AddTop(result.TopFiles, path, length, topN);

                        foreach (var total in result.PathTotals.Values)
                        {
                            if (IsSameOrDescendant(path, total.Path))
                            {
                                total.Seen = true;
                                total.Bytes += length;
                                total.FileCount++;
                            }
                        }

                        var aggregateChild = GetAggregateChild(spec.AggregateRoot, path);
                        if (!String.IsNullOrEmpty(aggregateChild))
                        {
                            ChildAccumulator child;
                            if (!result.RootChildren.TryGetValue(aggregateChild, out child))
                            {
                                var aggregateRoot = Normalize(spec.AggregateRoot);
                                child = new ChildAccumulator
                                {
                                    Name = aggregateChild,
                                    Path = Combine(aggregateRoot, aggregateChild)
                                };
                                result.RootChildren[aggregateChild] = child;
                            }
                            child.Bytes += length;
                            child.FileCount++;
                        }
                    }
                    while (FindNextFileW(handle, out data));
                }
                finally
                {
                    FindClose(handle);
                }
            }

            watch.Stop();
            result.RootRecord.ElapsedSeconds = Math.Round(watch.Elapsed.TotalSeconds, 3);
            return result;
        }

        private static RuntimeAppRecord ScanRuntimeCandidate(string root, string candidate, HashSet<string> excluded)
        {
            var record = new RuntimeAppRecord
            {
                Root = root,
                Path = candidate,
                DirectoryName = Path.GetFileName(candidate),
                ExecutableNames = new string[0]
            };
            var executables = new List<string>();
            var pending = new Stack<string>();
            pending.Push(candidate);

            while (pending.Count > 0)
            {
                var current = pending.Pop();
                if (IsExcluded(current, excluded)) continue;
                Win32FindData data;
                var handle = OpenFind(current, out data);
                if (handle == InvalidHandleValue)
                {
                    record.SkippedDirectories++;
                    continue;
                }

                try
                {
                    do
                    {
                        var name = data.FileName;
                        if (name == "." || name == "..") continue;
                        var path = Combine(current, name);
                        if ((data.FileAttributes & FileAttributes.Directory) != 0)
                        {
                            if ((data.FileAttributes & FileAttributes.ReparsePoint) == 0 && !IsExcluded(path, excluded)) pending.Push(path);
                            continue;
                        }

                        var length = ((long)data.FileSizeHigh << 32) | data.FileSizeLow;
                        record.TotalBytes += length;
                        record.FileCount++;
                        var lower = name.ToLowerInvariant();
                        var isPak = lower.EndsWith(".pak", StringComparison.Ordinal);
                        if (isPak) record.PakCount++;
                        if (lower == "libcef.dll" || lower == "chrome_elf.dll" || lower == "v8_context_snapshot.bin") record.HasCefIndicator = true;
                        if (IsRuntimeFile(lower, path, isPak)) record.RuntimeBytes += length;
                        if (lower.EndsWith(".exe", StringComparison.Ordinal) && executables.Count < 3 && !IsIgnoredExecutable(lower))
                        {
                            var exe = Path.GetFileNameWithoutExtension(name);
                            if (!executables.Contains(exe)) executables.Add(exe);
                        }
                    }
                    while (FindNextFileW(handle, out data));
                }
                finally
                {
                    FindClose(handle);
                }
            }
            record.ExecutableNames = executables.ToArray();
            return record;
        }

        private static bool IsRuntimeFile(string lowerName, string path, bool isPak)
        {
            if (isPak) return true;
            if (lowerName == "libcef.dll" || lowerName == "chrome_elf.dll" || lowerName == "v8_context_snapshot.bin") return true;
            if (lowerName == "libegl.dll" || lowerName == "libglesv2.dll") return true;
            if (lowerName.StartsWith("d3dcompiler_", StringComparison.Ordinal) && lowerName.EndsWith(".dll", StringComparison.Ordinal)) return true;
            if (lowerName.StartsWith("vk_swiftshader", StringComparison.Ordinal) && lowerName.EndsWith(".dll", StringComparison.Ordinal)) return true;
            return path.IndexOf("\\swiftshader\\", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static bool IsIgnoredExecutable(string lowerName)
        {
            return lowerName.StartsWith("uninstall", StringComparison.Ordinal) ||
                   lowerName.StartsWith("setup", StringComparison.Ordinal) ||
                   lowerName.StartsWith("update", StringComparison.Ordinal) ||
                   lowerName.StartsWith("crash_reporter", StringComparison.Ordinal);
        }

        private static string GetAggregateChild(string aggregateRoot, string filePath)
        {
            if (String.IsNullOrWhiteSpace(aggregateRoot)) return null;
            var root = Normalize(aggregateRoot);
            if (!filePath.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase)) return null;
            var relative = filePath.Substring(root.Length + 1);
            var separator = relative.IndexOf('\\');
            if (separator <= 0) return null;
            return relative.Substring(0, separator);
        }

        private static IEnumerable<string> EnumerateImmediateDirectories(string root)
        {
            var normalized = Normalize(root);
            Win32FindData data;
            var handle = OpenFind(normalized, out data);
            if (handle == InvalidHandleValue) yield break;
            try
            {
                do
                {
                    var name = data.FileName;
                    if (name == "." || name == "..") continue;
                    if ((data.FileAttributes & FileAttributes.Directory) == 0) continue;
                    if ((data.FileAttributes & FileAttributes.ReparsePoint) != 0) continue;
                    yield return Combine(normalized, name);
                }
                while (FindNextFileW(handle, out data));
            }
            finally
            {
                FindClose(handle);
            }
        }

        private static IntPtr OpenFind(string directory, out Win32FindData data)
        {
            var pattern = ToExtendedPath(directory) + "\\*";
            var handle = FindFirstFileExW(pattern, FindExInfoBasic, out data, FindExSearchNameMatch, IntPtr.Zero, FindFirstExLargeFetch);
            if (handle == InvalidHandleValue)
            {
                handle = FindFirstFileExW(pattern, FindExInfoBasic, out data, FindExSearchNameMatch, IntPtr.Zero, 0);
            }
            return handle;
        }

        private static HashSet<string> BuildExclusions(string[] excludedDirectories)
        {
            var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (excludedDirectories == null) return excluded;
            foreach (var path in excludedDirectories)
            {
                if (!String.IsNullOrWhiteSpace(path)) excluded.Add(Normalize(path));
            }
            return excluded;
        }

        private static bool IsExcluded(string path, HashSet<string> excluded)
        {
            var normalized = Normalize(path);
            foreach (var item in excluded)
            {
                if (normalized.Equals(item, StringComparison.OrdinalIgnoreCase)) return true;
                if (normalized.StartsWith(item + "\\", StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static bool IsSameOrDescendant(string path, string parent)
        {
            if (path.Equals(parent, StringComparison.OrdinalIgnoreCase)) return true;
            return path.StartsWith(parent.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
        }

        private static bool PathsOverlap(string first, string second)
        {
            return IsSameOrDescendant(first, second) || IsSameOrDescendant(second, first);
        }

        private static void AddTop(List<FastFileRecord> top, string path, long length, int topN)
        {
            if (top.Count < topN)
            {
                top.Add(new FastFileRecord { Path = path, Length = length });
                return;
            }

            var minIndex = 0;
            for (var index = 1; index < top.Count; index++)
            {
                if (top[index].Length < top[minIndex].Length) minIndex = index;
            }
            if (length > top[minIndex].Length) top[minIndex] = new FastFileRecord { Path = path, Length = length };
        }

        private static string Normalize(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) return String.Empty;
            var full = Path.GetFullPath(path);
            if (full.Length == 3 && full[1] == ':') return full.TrimEnd('\\') + "\\";
            return full.TrimEnd('\\');
        }

        private static string Combine(string parent, string child)
        {
            if (parent.EndsWith("\\", StringComparison.Ordinal)) return parent + child;
            return parent + "\\" + child;
        }

        private static string ToExtendedPath(string path)
        {
            if (path.StartsWith("\\\\?\\", StringComparison.Ordinal)) return path.TrimEnd('\\');
            if (path.StartsWith("\\\\", StringComparison.Ordinal)) return "\\\\?\\UNC\\" + path.Substring(2).TrimEnd('\\');
            return "\\\\?\\" + path.TrimEnd('\\');
        }
    }
}
