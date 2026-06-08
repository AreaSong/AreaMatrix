using System.Collections.Generic;

namespace AreaMatrix.Features.Onboarding;

public enum WindowsCloudStorageProviderKind
{
    Local,
    ICloudDrive,
    OneDrive,
    Unknown
}

public enum WindowsCloudStorageRiskLevel
{
    NoRisk,
    Low,
    Medium,
    High,
    Unknown
}

public enum WindowsCloudPlaceholderState
{
    NotPlaceholder,
    Placeholder,
    Unknown
}

public enum WindowsCloudPermissionState
{
    Accessible,
    PermissionDenied,
    AccessExpired,
    Unknown
}

public enum WindowsCloudStorageRecommendedAction
{
    None,
    AcknowledgeNotice,
    RetryStatusCheck,
    ReconnectFolder,
    ChooseLocalFolder
}

public sealed record WindowsCloudStorageState(
    string RepoPath,
    WindowsCloudStorageProviderKind ProviderKind,
    WindowsCloudStorageRiskLevel Risk,
    WindowsCloudPlaceholderState PlaceholderState,
    WindowsCloudPermissionState PermissionState,
    string StatusSummary,
    IReadOnlyList<string> RiskReasons,
    WindowsCloudStorageRecommendedAction RecommendedAction,
    bool RequiresNoticeAcknowledgement,
    bool NoticeAcknowledged,
    bool CanRetry,
    bool RequiresReconnect)
{
    public bool RequiresOneDriveNotice
    {
        get
        {
            return ProviderKind == WindowsCloudStorageProviderKind.OneDrive
                && RequiresNoticeAcknowledgement
                && !NoticeAcknowledged;
        }
    }
}
