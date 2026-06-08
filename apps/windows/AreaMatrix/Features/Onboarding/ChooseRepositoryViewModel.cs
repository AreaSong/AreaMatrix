using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Onboarding;

public sealed class ChooseRepositoryViewModel : INotifyPropertyChanged
{
    private readonly IWindowsRepositoryCoreBridge coreBridge;
    private CancellationTokenSource? checkCancellation;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private WindowsRepositoryValidation? latestValidation;
    private WindowsCloudStorageState? latestCloudStorageState;
    private WindowsRepositoryConfig? latestConfig;
    private WindowsRepositoryError? error;
    private WindowsRepositoryRoute route = WindowsRepositoryRoute.None;

    public ChooseRepositoryViewModel(IWindowsRepositoryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string RepositoryPath
    {
        get => repositoryPath;
        set
        {
            if (SetProperty(ref repositoryPath, value))
            {
                Error = null;
                LatestValidation = null;
                LatestCloudStorageState = null;
                LatestConfig = null;
                Route = WindowsRepositoryRoute.None;
                OnPropertyChanged(nameof(CanContinue));
            }
        }
    }

    public bool IsChecking
    {
        get => isChecking;
        private set
        {
            if (SetProperty(ref isChecking, value))
            {
                OnPropertyChanged(nameof(CanContinue));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public WindowsRepositoryValidation? LatestValidation
    {
        get => latestValidation;
        private set
        {
            if (SetProperty(ref latestValidation, value))
            {
                OnPropertyChanged(nameof(CanContinue));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public WindowsCloudStorageState? LatestCloudStorageState
    {
        get => latestCloudStorageState;
        private set
        {
            if (SetProperty(ref latestCloudStorageState, value))
            {
                OnPropertyChanged(nameof(CanContinue));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public WindowsRepositoryConfig? LatestConfig
    {
        get => latestConfig;
        private set => SetProperty(ref latestConfig, value);
    }

    public WindowsRepositoryError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                OnPropertyChanged(nameof(CanContinue));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public WindowsRepositoryRoute Route
    {
        get => route;
        private set => SetProperty(ref route, value);
    }

    public bool CanContinue
    {
        get
        {
            return !IsChecking
                && Error is null
                && LatestValidation is { } validation
                && (validation.IsInitialized || validation.RecommendedMode is not null);
        }
    }

    public string StatusText
    {
        get
        {
            if (IsChecking)
            {
                return "Checking folder...";
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            if (LatestValidation is { } validation)
            {
                return StatusTextFor(validation);
            }

            return "Select a repository folder.";
        }
    }

    public async Task CheckRepositoryPathAsync(
        string candidatePath,
        CancellationToken cancellationToken = default)
    {
        checkCancellation?.Cancel();
        checkCancellation?.Dispose();
        checkCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        CancellationToken token = checkCancellation.Token;

        RepositoryPath = candidatePath.Trim();
        LatestValidation = null;
        LatestCloudStorageState = null;
        LatestConfig = null;
        Route = WindowsRepositoryRoute.None;

        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidPath,
                "Folder not found");
            return;
        }

        IsChecking = true;
        try
        {
            WindowsRepositoryValidation validation = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, token);
            token.ThrowIfCancellationRequested();

            LatestValidation = validation;
            Error = BlockingErrorFor(validation);
            if (Error is null && IsOneDriveCandidate(validation))
            {
                LatestCloudStorageState = await coreBridge
                    .DetectCloudStorageStateAsync(validation.RepoPath, token);
                token.ThrowIfCancellationRequested();
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                exception.Message);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public async Task ContinueAsync(CancellationToken cancellationToken = default)
    {
        WindowsRepositoryValidation? validation = LatestValidation;
        if (validation is null || Error is not null || IsChecking)
        {
            return;
        }

        bool requiresOneDriveNotice;
        try
        {
            requiresOneDriveNotice = IsOneDriveCandidate(validation)
                && await RequiresOneDriveNoticeAsync(validation, cancellationToken);
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
            return;
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                exception.Message);
            return;
        }

        if (requiresOneDriveNotice)
        {
            Route = new WindowsRepositoryRoute(
                WindowsRepositoryRouteKind.OneDriveNotice,
                validation.RepoPath,
                validation,
                null,
                LatestCloudStorageState);
            return;
        }

        if (validation.IsInitialized)
        {
            await OpenInitializedRepositoryAsync(validation, cancellationToken);
            return;
        }

        RouteUninitializedRepository(validation);
    }

    public void ResetRoute()
    {
        Route = WindowsRepositoryRoute.None;
    }

    private async Task OpenInitializedRepositoryAsync(
        WindowsRepositoryValidation validation,
        CancellationToken cancellationToken)
    {
        try
        {
            WindowsRepositoryConfig config = await coreBridge
                .LoadConfigAsync(validation.RepoPath, cancellationToken);

            LatestConfig = config;
            Route = new WindowsRepositoryRoute(
                WindowsRepositoryRouteKind.MainWindow,
                validation.RepoPath,
                validation,
                config,
                LatestCloudStorageState);
        }
        catch (WindowsRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.Unavailable,
                exception.Message);
        }
    }

    private void RouteUninitializedRepository(WindowsRepositoryValidation validation)
    {
        WindowsRepositoryRouteKind kind = validation.RecommendedMode switch
        {
            WindowsRepositoryInitMode.CreateEmpty => WindowsRepositoryRouteKind.RepositoryInitConfirm,
            WindowsRepositoryInitMode.AdoptExisting => WindowsRepositoryRouteKind.RepositoryAdoptConfirm,
            _ => WindowsRepositoryRouteKind.None
        };

        if (kind == WindowsRepositoryRouteKind.None)
        {
            Error = new WindowsRepositoryError(
                WindowsRepositoryErrorKind.InvalidRepository,
                "This folder is not ready to connect.",
                validation.RepoPath);
            return;
        }

        Route = new WindowsRepositoryRoute(
            kind,
            validation.RepoPath,
            validation,
            null,
            LatestCloudStorageState);
    }

    private async Task<bool> RequiresOneDriveNoticeAsync(
        WindowsRepositoryValidation validation,
        CancellationToken cancellationToken)
    {
        WindowsCloudStorageState state = LatestCloudStorageState
            ?? await coreBridge.DetectCloudStorageStateAsync(validation.RepoPath, cancellationToken);
        LatestCloudStorageState = state;
        return state.RequiresOneDriveNotice
            || state.RecommendedAction == WindowsCloudStorageRecommendedAction.AcknowledgeNotice;
    }

    private static bool IsOneDriveCandidate(WindowsRepositoryValidation validation)
    {
        return validation.IsOneDrivePath
            || validation.HasIssue(WindowsRepositoryPathIssue.OneDrivePath)
            || validation.PlatformPathKind == WindowsPlatformPathKind.OneDrive;
    }

    private static WindowsRepositoryError? BlockingErrorFor(WindowsRepositoryValidation validation)
    {
        return InsideMetadataError(validation)
            ?? MissingPathError(validation)
            ?? SelectedFileError(validation)
            ?? PermissionError(validation)
            ?? ReservedNameError(validation);
    }

    private static WindowsRepositoryError? InsideMetadataError(WindowsRepositoryValidation validation)
    {
        if (!validation.IsInsideAreaMatrix
            && !validation.HasIssue(WindowsRepositoryPathIssue.InsideAreaMatrix))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidPath,
            "Choose the repository folder, not its .areamatrix metadata folder.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? MissingPathError(WindowsRepositoryValidation validation)
    {
        if (validation.Exists && !validation.HasIssue(WindowsRepositoryPathIssue.MissingPath))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidPath,
            "Folder not found",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? SelectedFileError(WindowsRepositoryValidation validation)
    {
        if (validation.IsDirectory && !validation.HasIssue(WindowsRepositoryPathIssue.NotDirectory))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.SelectedFile,
            "Select a folder, not a file.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError? PermissionError(WindowsRepositoryValidation validation)
    {
        if (!validation.IsReadable || validation.HasIssue(WindowsRepositoryPathIssue.NotReadable))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot read this folder.",
                validation.RepoPath);
        }

        if (!validation.IsWritable || validation.HasIssue(WindowsRepositoryPathIssue.NotWritable))
        {
            return new WindowsRepositoryError(
                WindowsRepositoryErrorKind.PermissionDenied,
                "AreaMatrix cannot write repository metadata in this folder.",
                validation.RepoPath);
        }

        return null;
    }

    private static WindowsRepositoryError? ReservedNameError(WindowsRepositoryValidation validation)
    {
        if (!validation.HasIssue(WindowsRepositoryPathIssue.WindowsReservedName))
        {
            return null;
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.InvalidPath,
            "This path contains a reserved Windows name.",
            validation.RepoPath);
    }

    private static WindowsRepositoryError ErrorFromCoreException(WindowsRepositoryCoreException exception)
    {
        string message = exception.Kind switch
        {
            WindowsRepositoryErrorKind.InvalidPath => "Folder not found",
            WindowsRepositoryErrorKind.SelectedFile => "Select a folder, not a file.",
            WindowsRepositoryErrorKind.PermissionDenied => "Choose another folder.",
            WindowsRepositoryErrorKind.Config => "This repository configuration cannot be opened.",
            WindowsRepositoryErrorKind.DiskUnavailable => "Drive disconnected",
            WindowsRepositoryErrorKind.OneDrivePathDetected => "This folder is inside OneDrive.",
            _ => exception.Message
        };

        return new WindowsRepositoryError(exception.Kind, message, exception.Path);
    }

    private string StatusTextFor(WindowsRepositoryValidation validation)
    {
        if (LatestCloudStorageState is { } cloudState
            && cloudState.ProviderKind == WindowsCloudStorageProviderKind.OneDrive)
        {
            return OneDriveStatusText(cloudState);
        }

        if (validation.IsInitialized)
        {
            return "AreaMatrix repository found";
        }

        if (validation.IsOneDrivePath || validation.HasIssue(WindowsRepositoryPathIssue.OneDrivePath))
        {
            return "This folder is inside OneDrive.";
        }

        return validation.RecommendedMode switch
        {
            WindowsRepositoryInitMode.CreateEmpty
                => "Empty folder. AreaMatrix can initialize it after confirmation.",
            WindowsRepositoryInitMode.AdoptExisting
                => "This folder already contains files. AreaMatrix will ask before creating its metadata folder.",
            _ => "This folder is not ready to connect."
        };
    }

    private static string OneDriveStatusText(WindowsCloudStorageState state)
    {
        if (string.IsNullOrWhiteSpace(state.StatusSummary))
        {
            return "This folder is inside OneDrive.";
        }

        return $"This folder is inside OneDrive. {state.StatusSummary}";
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string propertyName = "")
    {
        if (Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
