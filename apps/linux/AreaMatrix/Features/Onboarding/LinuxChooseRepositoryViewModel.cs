using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace AreaMatrix.Linux.Features.Onboarding;

public sealed class LinuxChooseRepositoryViewModel : INotifyPropertyChanged
{
    private readonly ILinuxRepositoryCoreBridge coreBridge;
    private CancellationTokenSource? checkCancellation;
    private string repositoryPath = string.Empty;
    private bool isChecking;
    private LinuxRepositoryValidation? latestValidation;
    private LinuxRepositoryError? error;
    private LinuxRepositoryRoute route = LinuxRepositoryRoute.None;

    public LinuxChooseRepositoryViewModel(ILinuxRepositoryCoreBridge coreBridge)
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
                Route = LinuxRepositoryRoute.None;
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

    public LinuxRepositoryValidation? LatestValidation
    {
        get => latestValidation;
        private set
        {
            if (SetProperty(ref latestValidation, value))
            {
                OnPropertyChanged(nameof(CanContinue));
                OnPropertyChanged(nameof(StatusText));
                OnPropertyChanged(nameof(RiskText));
            }
        }
    }

    public LinuxRepositoryError? Error
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

    public LinuxRepositoryRoute Route
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
                return LinuxRepositoryDisplayText.CheckingFolder;
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            return LatestValidation is { } validation
                ? LinuxRepositoryDisplayText.StatusTextFor(validation)
                : LinuxRepositoryDisplayText.SelectRepositoryFolder;
        }
    }

    public string RiskText
    {
        get
        {
            return LatestValidation is { } validation
                ? LinuxRepositoryDisplayText.RiskTextFor(validation)
                : string.Empty;
        }
    }

    public async Task CheckRepositoryPathAsync(
        string candidatePath,
        CancellationToken cancellationToken = default)
    {
        CancellationToken token = ResetCancellation(cancellationToken);

        RepositoryPath = candidatePath.Trim();
        LatestValidation = null;
        Route = LinuxRepositoryRoute.None;

        if (string.IsNullOrWhiteSpace(RepositoryPath))
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                LinuxRepositoryDisplayText.FolderNotFound);
            return;
        }

        IsChecking = true;
        try
        {
            LinuxRepositoryValidation validation = await coreBridge
                .ValidateRepoPathAsync(RepositoryPath, token);
            token.ThrowIfCancellationRequested();
            LatestValidation = validation;
            Error = BlockingErrorFor(validation);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (LinuxRepositoryCoreException exception)
        {
            Error = ErrorFromCoreException(exception);
        }
        catch (Exception exception)
        {
            Error = new LinuxRepositoryError(
                LinuxRepositoryErrorKind.Unavailable,
                exception.Message);
        }
        finally
        {
            IsChecking = false;
        }
    }

    public Task ContinueAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        LinuxRepositoryValidation? validation = LatestValidation;
        if (validation is null || Error is not null || IsChecking)
        {
            return Task.CompletedTask;
        }

        Route = RouteFor(validation);
        return Task.CompletedTask;
    }

    public void ResetRoute()
    {
        Route = LinuxRepositoryRoute.None;
    }

    public void ReportFolderPickerError(string message)
    {
        Error = new LinuxRepositoryError(
            LinuxRepositoryErrorKind.Unavailable,
            message);
        LatestValidation = null;
        Route = LinuxRepositoryRoute.None;
    }

    private CancellationToken ResetCancellation(CancellationToken cancellationToken)
    {
        checkCancellation?.Cancel();
        checkCancellation?.Dispose();
        checkCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        return checkCancellation.Token;
    }

    private static LinuxRepositoryRoute RouteFor(LinuxRepositoryValidation validation)
    {
        if (LinuxRepositoryDisplayText.RequiresLocalFolderNotice(validation))
        {
            return new LinuxRepositoryRoute(
                LinuxRepositoryRouteKind.LocalFolderNotice,
                validation.RepoPath,
                validation);
        }

        if (validation.IsInitialized)
        {
            return new LinuxRepositoryRoute(
                LinuxRepositoryRouteKind.MainWindow,
                validation.RepoPath,
                validation);
        }

        LinuxRepositoryRouteKind kind = validation.RecommendedMode switch
        {
            LinuxRepositoryInitMode.CreateEmpty => LinuxRepositoryRouteKind.RepositoryInitConfirm,
            LinuxRepositoryInitMode.AdoptExisting => LinuxRepositoryRouteKind.RepositoryAdoptConfirm,
            _ => LinuxRepositoryRouteKind.None
        };
        return new LinuxRepositoryRoute(kind, validation.RepoPath, validation);
    }

    private static LinuxRepositoryError? BlockingErrorFor(LinuxRepositoryValidation validation)
    {
        return InsideMetadataError(validation)
            ?? MissingPathError(validation)
            ?? SelectedFileError(validation)
            ?? PermissionError(validation)
            ?? RecoveryError(validation);
    }

    private static LinuxRepositoryError? InsideMetadataError(LinuxRepositoryValidation validation)
    {
        return validation.IsInsideAreaMatrix || validation.HasIssue(LinuxRepositoryPathIssue.InsideAreaMatrix)
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                "Choose the repository root folder.",
                validation.RepoPath)
            : null;
    }

    private static LinuxRepositoryError? MissingPathError(LinuxRepositoryValidation validation)
    {
        return validation.HasIssue(LinuxRepositoryPathIssue.MissingPath)
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidPath,
                LinuxRepositoryDisplayText.FolderNotFound,
                validation.RepoPath)
            : null;
    }

    private static LinuxRepositoryError? SelectedFileError(LinuxRepositoryValidation validation)
    {
        return validation.HasIssue(LinuxRepositoryPathIssue.NotDirectory)
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.SelectedFile,
                "Select a folder, not a file.",
                validation.RepoPath)
            : null;
    }

    private static LinuxRepositoryError? PermissionError(LinuxRepositoryValidation validation)
    {
        if (validation.IsInitialized && validation.IsReadable)
        {
            return null;
        }

        return validation.HasIssue(LinuxRepositoryPathIssue.NotReadable)
            || validation.HasIssue(LinuxRepositoryPathIssue.NotWritable)
            || !validation.IsReadable
            || !validation.IsWritable
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.PermissionDenied,
                LinuxRepositoryDisplayText.PermissionDenied,
                validation.RepoPath)
            : null;
    }

    private static LinuxRepositoryError? RecoveryError(LinuxRepositoryValidation validation)
    {
        return validation.HasIssue(LinuxRepositoryPathIssue.UnfinishedScanSession)
            ? new LinuxRepositoryError(
                LinuxRepositoryErrorKind.InvalidRepository,
                "This repository needs recovery before it can be connected.",
                validation.RepoPath)
            : null;
    }

    private static LinuxRepositoryError ErrorFromCoreException(LinuxRepositoryCoreException exception)
    {
        return new LinuxRepositoryError(
            exception.Kind,
            LinuxRepositoryDisplayText.ErrorMessageFor(exception),
            exception.Path);
    }

    private bool SetProperty<T>(ref T field, T value, [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string propertyName = "")
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
