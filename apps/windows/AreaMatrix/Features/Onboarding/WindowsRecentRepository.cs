namespace AreaMatrix.Features.Onboarding;

public enum WindowsRecentRepositoryStatus
{
    Available,
    Missing,
    PermissionDenied,
    DriveDisconnected
}

public sealed record WindowsRecentRepository(
    string Name,
    string RepoPath,
    string LastOpenedText,
    WindowsRecentRepositoryStatus Status)
{
    public string StatusReason
    {
        get
        {
            return Status switch
            {
                WindowsRecentRepositoryStatus.Available => LastOpenedText,
                WindowsRecentRepositoryStatus.Missing => "Missing",
                WindowsRecentRepositoryStatus.PermissionDenied => "Permission denied",
                WindowsRecentRepositoryStatus.DriveDisconnected => "Drive disconnected",
                _ => LastOpenedText
            };
        }
    }
}
