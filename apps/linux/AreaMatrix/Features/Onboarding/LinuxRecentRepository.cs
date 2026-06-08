namespace AreaMatrix.Linux.Features.Onboarding;

public enum LinuxRecentRepositoryStatus
{
    Available,
    Missing,
    PermissionDenied,
    DiskUnavailable
}

public sealed record LinuxRecentRepository(
    string Name,
    string RepoPath,
    string LastOpenedLabel,
    LinuxRecentRepositoryStatus Status)
{
    public string StatusReason
    {
        get
        {
            return Status switch
            {
                LinuxRecentRepositoryStatus.Available => "Available",
                LinuxRecentRepositoryStatus.Missing => "Missing",
                LinuxRecentRepositoryStatus.PermissionDenied => "Permission denied",
                LinuxRecentRepositoryStatus.DiskUnavailable => "Disk unavailable",
                _ => "Unknown"
            };
        }
    }
}
