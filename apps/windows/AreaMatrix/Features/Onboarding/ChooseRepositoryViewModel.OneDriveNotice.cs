using System;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public sealed partial class ChooseRepositoryViewModel
{
    private string oneDriveNoticeAcceptedPath = string.Empty;

    public async Task ContinueAfterOneDriveNoticeAsync(
        WindowsCloudStorageState? state,
        CancellationToken cancellationToken = default)
    {
        if (LatestValidation is null)
        {
            return;
        }

        if (state is not null)
        {
            LatestCloudStorageState = state;
        }

        oneDriveNoticeAcceptedPath = LatestValidation.RepoPath;
        Route = WindowsRepositoryRoute.None;
        await ContinueAsync(cancellationToken);
    }

    private bool IsOneDriveNoticeAcceptedFor(WindowsRepositoryValidation validation)
    {
        return string.Equals(
            oneDriveNoticeAcceptedPath,
            validation.RepoPath,
            StringComparison.OrdinalIgnoreCase);
    }
}
