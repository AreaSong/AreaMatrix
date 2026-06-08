namespace AreaMatrix.Linux.Features.Import;

internal sealed record LinuxMountInfoEntry(
    string MountPoint,
    string DeviceId)
{
    public bool HasSameDevice(LinuxMountInfoEntry other)
    {
        return string.Equals(DeviceId, other.DeviceId, StringComparison.Ordinal);
    }

    public static IReadOnlyList<LinuxMountInfoEntry> ReadAll(string mountInfoPath)
    {
        if (!File.Exists(mountInfoPath))
        {
            return [];
        }

        try
        {
            return File.ReadLines(mountInfoPath)
                .Select(Parse)
                .Where(entry => entry is not null)
                .Select(entry => entry!)
                .OrderByDescending(entry => entry.MountPoint.Length)
                .ToArray();
        }
        catch (IOException)
        {
            return [];
        }
        catch (UnauthorizedAccessException)
        {
            return [];
        }
    }

    public static LinuxMountInfoEntry? FindForPath(
        IReadOnlyList<LinuxMountInfoEntry> entries,
        string path)
    {
        string fullPath = NormalizePath(path);
        return entries.FirstOrDefault(entry => PathIsUnderMount(fullPath, entry.MountPoint));
    }

    private static LinuxMountInfoEntry? Parse(string line)
    {
        string[] fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 5)
        {
            return null;
        }

        string mountPoint = UnescapeMountField(fields[4]);
        return string.IsNullOrWhiteSpace(mountPoint)
            ? null
            : new LinuxMountInfoEntry(NormalizePath(mountPoint), fields[2]);
    }

    private static bool PathIsUnderMount(string path, string mountPoint)
    {
        if (string.Equals(path, mountPoint, StringComparison.Ordinal))
        {
            return true;
        }

        string prefix = mountPoint == "/"
            ? "/"
            : mountPoint.TrimEnd('/') + "/";
        return path.StartsWith(prefix, StringComparison.Ordinal);
    }

    private static string NormalizePath(string path)
    {
        string fullPath = Path.GetFullPath(path);
        return fullPath.Length > 1 ? fullPath.TrimEnd('/') : fullPath;
    }

    private static string UnescapeMountField(string value)
    {
        return value
            .Replace("\\040", " ", StringComparison.Ordinal)
            .Replace("\\011", "\t", StringComparison.Ordinal)
            .Replace("\\012", "\n", StringComparison.Ordinal)
            .Replace("\\134", "\\", StringComparison.Ordinal);
    }
}
