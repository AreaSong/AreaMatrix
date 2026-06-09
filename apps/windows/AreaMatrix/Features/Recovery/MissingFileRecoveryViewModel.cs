using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Recovery;

public sealed class MissingFileRecoveryViewModel : INotifyPropertyChanged
{
    private readonly IMissingFileRecoveryCoreBridge coreBridge;
    private string repoPath = string.Empty;
    private long fileId;
    private MissingFileRecoveryState? state;
    private MissingFileRecoveryReport? report;
    private MissingFileRecoveryError? error;
    private bool isLoading;
    private bool isWorking;
    private bool removeRecordConfirmed;
    private string selectedRelinkPath = string.Empty;

    public MissingFileRecoveryViewModel(IMissingFileRecoveryCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public MissingFileRecoveryState? State
    {
        get => state;
        private set
        {
            if (SetProperty(ref state, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public MissingFileRecoveryReport? Report
    {
        get => report;
        private set
        {
            if (SetProperty(ref report, value))
            {
                OnPropertyChanged(nameof(ResultText));
            }
        }
    }

    public MissingFileRecoveryError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public bool IsLoading
    {
        get => isLoading;
        private set
        {
            if (SetProperty(ref isLoading, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public bool IsWorking
    {
        get => isWorking;
        private set
        {
            if (SetProperty(ref isWorking, value))
            {
                OnDerivedStateChanged();
            }
        }
    }

    public bool RemoveRecordConfirmed
    {
        get => removeRecordConfirmed;
        set
        {
            if (SetProperty(ref removeRecordConfirmed, value))
            {
                OnPropertyChanged(nameof(CanRemoveRecord));
            }
        }
    }

    public string SelectedRelinkPath
    {
        get => selectedRelinkPath;
        set
        {
            if (SetProperty(ref selectedRelinkPath, value))
            {
                OnPropertyChanged(nameof(CanRelink));
            }
        }
    }

    public string Title => State?.DisplayName ?? "File is missing";

    public string SummaryText => Error?.Message
        ?? State?.ReasonText
        ?? "Checking file...";

    public string ResultText => Report?.DisplayMessage ?? string.Empty;

    public bool CanTryAgain => State?.CanTryAgain == true && !IsWorking && !IsLoading;

    public bool CanRelink => State?.CanLocate == true
        && !string.IsNullOrWhiteSpace(SelectedRelinkPath)
        && !IsWorking
        && !IsLoading;

    public bool CanRemoveRecord
    {
        get
        {
            if (State is not { CanRemoveRecord: true } currentState || IsWorking || IsLoading)
            {
                return false;
            }

            return !currentState.RemoveRecordRequiresConfirmation || RemoveRecordConfirmed;
        }
    }

    public async Task OpenAsync(
        string repositoryPath,
        long missingFileId,
        CancellationToken cancellationToken = default)
    {
        repoPath = repositoryPath;
        fileId = missingFileId;
        RemoveRecordConfirmed = false;
        await RefreshAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        IsLoading = true;
        Error = null;
        try
        {
            State = await coreBridge
                .GetMissingFileStateAsync(repoPath, fileId, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (System.Exception exception) when (exception is not OperationCanceledException)
        {
            Error = MissingFileRecoveryError.FromException(exception);
        }
        finally
        {
            IsLoading = false;
        }
    }

    public async Task RelinkSelectedFileAsync(CancellationToken cancellationToken = default)
    {
        if (!CanRelink)
        {
            return;
        }

        await RunActionAsync(
            () => coreBridge.RelinkMissingFileAsync(
                repoPath,
                new MissingFileRelinkRequest(fileId, SelectedRelinkPath.Trim(), true),
                cancellationToken))
            .ConfigureAwait(false);
    }

    public async Task RemoveRecordAsync(CancellationToken cancellationToken = default)
    {
        if (!CanRemoveRecord)
        {
            return;
        }

        await RunActionAsync(
            () => coreBridge.RemoveMissingFileRecordAsync(
                repoPath,
                new MissingFileRemoveRecordRequest(fileId, true),
                cancellationToken))
            .ConfigureAwait(false);
    }

    private async Task RunActionAsync(System.Func<Task<MissingFileRecoveryReport>> action)
    {
        IsWorking = true;
        Error = null;
        try
        {
            Report = await action().ConfigureAwait(false);
            if (Report.Status == MissingFileRecoveryStatus.HashMismatch)
            {
                Error = new MissingFileRecoveryError(
                    MissingFileRecoveryErrorKind.Unavailable,
                    Report.DisplayMessage,
                    "Choose a different file.");
            }
        }
        catch (System.Exception exception) when (exception is not OperationCanceledException)
        {
            Error = MissingFileRecoveryError.FromException(exception);
        }
        finally
        {
            IsWorking = false;
        }
    }

    private void OnDerivedStateChanged()
    {
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(SummaryText));
        OnPropertyChanged(nameof(CanTryAgain));
        OnPropertyChanged(nameof(CanRelink));
        OnPropertyChanged(nameof(CanRemoveRecord));
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
