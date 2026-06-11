using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Core;

public sealed partial class AreaMatrixNativeCoreClient
{
    public Task<CoreCloudStorageState> AcknowledgeOneDriveRiskNoticeAsync(
        string repoPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CoreCloudStorageState state = CallWithResult(
            (ref RustCallStatus status) => native.AcknowledgeOneDriveRiskNotice(LowerString(repoPath), ref status),
            ReadCloudStorageState);
        return Task.FromResult(state);
    }
}
