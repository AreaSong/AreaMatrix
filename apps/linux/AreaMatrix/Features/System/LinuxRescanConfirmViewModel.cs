using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.System;

public sealed class LinuxRescanConfirmViewModel : INotifyPropertyChanged
{
    private readonly ILinuxWatcherStatusCoreBridge coreBridge;
    private LinuxRescanConfirmRequest? request;
    private LinuxReindexReport? result;
    private LinuxRepositoryError? error;
    private bool isRunning;
    private bool userConfirmed;

    public LinuxRescanConfirmViewModel(ILinuxWatcherStatusCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public LinuxRescanConfirmRequest? Request
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

    public LinuxReindexReport? Result
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

    public LinuxRepositoryError? Error
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

    public LinuxManualRescanPreviewReport? Preview => Request?.Preview;

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

    public string ResultText => Result is { } report ? ResultSummaryText(report) : string.Empty;

    public string ErrorText => Error?.Message ?? string.Empty;

    public bool HasNeedsReview => Preview?.HasNeedsReview == true || ResultHasNeedsReview(Result);

    public bool HasResult => Result is not null;

    public bool HasError => Error is not null;

    public bool CanRunRescan => Request is not null
        && Preview?.CanRunRescan == true
        && UserConfirmed
        && !IsRunning
        && Result is null;

    public void OpenRequest(LinuxRescanConfirmRequest rescanRequest)
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

    private LinuxRepositoryError ErrorFromException(Exception exception)
    {
        if (exception is LinuxWatcherStatusCoreException watcherException)
        {
            return new LinuxRepositoryError(
                watcherException.Kind,
                ErrorMessageFor(watcherException.Kind),
                watcherException.Path ?? Request?.Route.RepoPath);
        }

        if (exception is LinuxRepositoryCoreException coreException)
        {
            return new LinuxRepositoryError(
                coreException.Kind,
                ErrorMessageFor(coreException.Kind),
                coreException.Path ?? Request?.Route.RepoPath);
        }

        return new LinuxRepositoryError(
            LinuxRepositoryErrorKind.Unavailable,
            $"Repository rescan failed: {exception.Message}",
            Request?.Route.RepoPath);
    }

    private static string ErrorMessageFor(LinuxRepositoryErrorKind kind)
    {
        return kind switch
        {
            LinuxRepositoryErrorKind.Db => "Repository database could not be updated.",
            LinuxRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read or update repository metadata.",
            LinuxRepositoryErrorKind.InvalidPath or LinuxRepositoryErrorKind.FileNotFound
                => "Repository folder not found.",
            LinuxRepositoryErrorKind.Conflict => "A manual rescan is already running.",
            LinuxRepositoryErrorKind.Config => "Rescan metadata cannot be decoded.",
            _ => "Repository rescan failed."
        };
    }

    private static bool ResultHasNeedsReview(LinuxReindexReport? report)
    {
        return report is not null
            && (report.Missing > 0
                || report.Conflicts > 0
                || report.Unreadable > 0
                || report.Unknown > 0);
    }

    private static string ResultSummaryText(LinuxReindexReport report)
    {
        return "Rescan result: "
            + $"Inserted {report.Inserted.ToString(CultureInfo.CurrentCulture)}, "
            + $"Updated {report.Updated.ToString(CultureInfo.CurrentCulture)}, "
            + $"Missing {report.Missing.ToString(CultureInfo.CurrentCulture)}, "
            + $"Conflicts {report.Conflicts.ToString(CultureInfo.CurrentCulture)}, "
            + $"Unreadable {report.Unreadable.ToString(CultureInfo.CurrentCulture)}, "
            + $"Unknown {report.Unknown.ToString(CultureInfo.CurrentCulture)}, "
            + $"Skipped {report.Skipped.ToString(CultureInfo.CurrentCulture)}.";
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
