using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public sealed class RescanConfirmViewModel : INotifyPropertyChanged
{
    private readonly IWatcherStatusCoreBridge coreBridge;
    private RescanConfirmRequest? request;
    private ReindexReport? result;
    private WindowsRepositoryError? error;
    private bool isRunning;
    private bool userConfirmed;

    public RescanConfirmViewModel(IWatcherStatusCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public RescanConfirmRequest? Request
    {
        get => request;
        private set
        {
            if (SetProperty(ref request, value))
            {
                NotifyDerivedStateChanged();
            }
        }
    }

    public ReindexReport? Result
    {
        get => result;
        private set
        {
            if (SetProperty(ref result, value))
            {
                NotifyDerivedStateChanged();
            }
        }
    }

    public WindowsRepositoryError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                NotifyDerivedStateChanged();
            }
        }
    }

    public bool IsRunning
    {
        get => isRunning;
        private set
        {
            if (SetProperty(ref isRunning, value))
            {
                NotifyDerivedStateChanged();
            }
        }
    }

    public bool UserConfirmed
    {
        get => userConfirmed;
        set
        {
            if (SetProperty(ref userConfirmed, value))
            {
                NotifyDerivedStateChanged();
            }
        }
    }

    public ManualRescanPreviewReport? Preview => Request?.Preview;

    public string RepositoryText => Request is { } currentRequest
        ? $"Repository: {currentRequest.Route.RepoPath}"
        : "Repository: Unavailable";

    public string EstimatedItemsText => Preview?.EstimatedItemsText ?? "Estimated items: Unknown";

    public string PreviewSummaryText => Preview?.SummaryText ?? "Preview impact is not available.";

    public string NeedsReviewText
    {
        get
        {
            if (Preview?.Unknown > 0)
            {
                return "Some changes could not be classified. They will stay in Needs Review if you run rescan.";
            }

            return Preview?.HasNeedsReview == true
                ? "Missing, unreadable, conflict, or unknown items will remain in Needs Review."
                : string.Empty;
        }
    }

    public string ResultText => Result?.SummaryText ?? string.Empty;

    public string ErrorText => Error?.Message ?? string.Empty;

    public bool HasNeedsReview => Preview?.HasNeedsReview == true || Result?.HasNeedsReview == true;

    public bool HasResult => Result is not null;

    public bool HasError => Error is not null;

    public bool CanRunRescan => Request is not null
        && Preview?.CanRunRescan == true
        && UserConfirmed
        && !IsRunning
        && Result is null;

    public void OpenRequest(RescanConfirmRequest rescanRequest)
    {
        Request = rescanRequest;
        Result = null;
        Error = null;
        UserConfirmed = false;
        IsRunning = false;
    }

    public async Task<bool> RunRescanAsync(CancellationToken cancellationToken = default)
    {
        if (!CanRunRescan || Request is null)
        {
            return false;
        }

        IsRunning = true;
        Error = null;
        try
        {
            Result = await coreBridge
                .ReindexFromFilesystemAsync(Request.Route.RepoPath, cancellationToken)
                .ConfigureAwait(false);
            return true;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
            return false;
        }
        finally
        {
            IsRunning = false;
        }
    }

    private WindowsRepositoryError ErrorFromException(Exception exception)
    {
        if (exception is WatcherStatusCoreException watcherException)
        {
            return new WindowsRepositoryError(
                watcherException.Kind,
                ErrorMessageFor(watcherException.Kind),
                watcherException.Path ?? Request?.Route.RepoPath);
        }

        if (exception is WindowsRepositoryCoreException coreException)
        {
            return new WindowsRepositoryError(
                coreException.Kind,
                ErrorMessageFor(coreException.Kind),
                coreException.Path ?? Request?.Route.RepoPath);
        }

        return new WindowsRepositoryError(
            WindowsRepositoryErrorKind.Unavailable,
            $"Repository rescan failed: {exception.Message}",
            Request?.Route.RepoPath);
    }

    private static string ErrorMessageFor(WindowsRepositoryErrorKind kind)
    {
        return kind switch
        {
            WindowsRepositoryErrorKind.Db => "Repository database could not be updated.",
            WindowsRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read or update repository metadata.",
            WindowsRepositoryErrorKind.InvalidPath or WindowsRepositoryErrorKind.FileNotFound
                => "Repository folder not found.",
            WindowsRepositoryErrorKind.Conflict => "A manual rescan is already running.",
            WindowsRepositoryErrorKind.Config => "Rescan metadata cannot be decoded.",
            _ => "Repository rescan failed."
        };
    }

    private void NotifyDerivedStateChanged()
    {
        OnPropertyChanged(nameof(Preview));
        OnPropertyChanged(nameof(RepositoryText));
        OnPropertyChanged(nameof(EstimatedItemsText));
        OnPropertyChanged(nameof(PreviewSummaryText));
        OnPropertyChanged(nameof(NeedsReviewText));
        OnPropertyChanged(nameof(ResultText));
        OnPropertyChanged(nameof(ErrorText));
        OnPropertyChanged(nameof(HasNeedsReview));
        OnPropertyChanged(nameof(HasResult));
        OnPropertyChanged(nameof(HasError));
        OnPropertyChanged(nameof(CanRunRescan));
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
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
