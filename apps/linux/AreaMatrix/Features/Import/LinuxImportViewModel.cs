using System.ComponentModel;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Library;

namespace AreaMatrix.Linux.Features.Import;

public sealed partial class LinuxImportViewModel : INotifyPropertyChanged
{
    private readonly IDesktopImportCoreBridge coreBridge;
    private string repoPath = string.Empty;
    private string sourcePathsText = string.Empty;
    private string targetDirectory = string.Empty;
    private string targetCategory = string.Empty;
    private DesktopImportMode mode = DesktopImportMode.Copy;
    private DesktopImportDuplicateStrategy duplicateStrategy = DesktopImportDuplicateStrategy.Skip;
    private bool preserveFolderStructure;
    private bool moveConfirmed;
    private bool isPreparing;
    private bool isImporting;
    private DesktopImportStep currentStep = DesktopImportStep.Preparing;
    private IReadOnlyList<DesktopImportSource> sources = [];
    private IReadOnlyList<DesktopImportPreviewItem> previewItems = [];
    private IReadOnlyList<DesktopImportResult> results = [];
    private DesktopImportMovePreflight movePreflight = DesktopImportMovePreflight.NotEvaluated;
    private DesktopImportError? error;

    public LinuxImportViewModel(IDesktopImportCoreBridge coreBridge)
    {
        this.coreBridge = coreBridge;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string RepoPath
    {
        get => repoPath;
        private set
        {
            if (SetProperty(ref repoPath, value))
            {
                OnPropertyChanged(nameof(CanPrepare));
                OnPropertyChanged(nameof(CanImport));
            }
        }
    }

    public string SourcePathsText
    {
        get => sourcePathsText;
        set
        {
            if (SetProperty(ref sourcePathsText, value))
            {
                OnPropertyChanged(nameof(CanPrepare));
                OnPropertyChanged(nameof(CanImport));
            }
        }
    }

    public string TargetDirectory
    {
        get => targetDirectory;
        set
        {
            if (SetProperty(ref targetDirectory, value))
            {
                OnPropertyChanged(nameof(CanImport));
            }
        }
    }

    public string TargetCategory
    {
        get => targetCategory;
        set => SetProperty(ref targetCategory, value);
    }

    public DesktopImportMode Mode
    {
        get => mode;
        set
        {
            if (SetProperty(ref mode, value))
            {
                if (value == DesktopImportMode.Copy)
                {
                    MoveConfirmed = false;
                }

                OnPropertyChanged(nameof(RequiresMoveConfirmation));
                OnPropertyChanged(nameof(CanImport));
                OnPropertyChanged(nameof(MoveConfirmationText));
                OnPropertyChanged(nameof(MovePreflightText));
                RefreshMovePreflight();
            }
        }
    }

    public DesktopImportDuplicateStrategy DuplicateStrategy
    {
        get => duplicateStrategy;
        set
        {
            if (SetProperty(ref duplicateStrategy, value))
            {
                OnPropertyChanged(nameof(ImportableItemCount));
                OnPropertyChanged(nameof(CanImport));
                RefreshMovePreflight();
            }
        }
    }

    public bool PreserveFolderStructure
    {
        get => preserveFolderStructure;
        set => SetProperty(ref preserveFolderStructure, value);
    }

    public bool MoveConfirmed
    {
        get => moveConfirmed;
        set
        {
            if (SetProperty(ref moveConfirmed, value))
            {
                OnPropertyChanged(nameof(CanImport));
            }
        }
    }

    public bool IsPreparing
    {
        get => isPreparing;
        private set
        {
            if (SetProperty(ref isPreparing, value))
            {
                OnPropertyChanged(nameof(CanPrepare));
                OnPropertyChanged(nameof(CanImport));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool IsImporting
    {
        get => isImporting;
        private set
        {
            if (SetProperty(ref isImporting, value))
            {
                OnPropertyChanged(nameof(CanPrepare));
                OnPropertyChanged(nameof(CanImport));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public DesktopImportStep CurrentStep
    {
        get => currentStep;
        private set
        {
            if (SetProperty(ref currentStep, value))
            {
                OnPropertyChanged(nameof(ProgressText));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public IReadOnlyList<DesktopImportPreviewItem> PreviewItems
    {
        get => previewItems;
        private set
        {
            if (SetProperty(ref previewItems, value))
            {
                OnPropertyChanged(nameof(HasPreviewItems));
                OnPropertyChanged(nameof(ReadableItemCount));
                OnPropertyChanged(nameof(ImportableItemCount));
                OnPropertyChanged(nameof(SourceSummaryText));
                OnPropertyChanged(nameof(MoveConfirmationText));
                OnPropertyChanged(nameof(CanImport));
                RefreshMovePreflight();
            }
        }
    }

    public IReadOnlyList<DesktopImportResult> Results
    {
        get => results;
        private set
        {
            if (SetProperty(ref results, value))
            {
                OnPropertyChanged(nameof(ResultSummaryText));
                OnPropertyChanged(nameof(StatusText));
                OnPropertyChanged(nameof(HasSuccessfulResults));
                OnPropertyChanged(nameof(HasFailedResults));
                OnPropertyChanged(nameof(ImportedFileIds));
            }
        }
    }

    public DesktopImportMovePreflight MovePreflight
    {
        get => movePreflight;
        private set
        {
            if (SetProperty(ref movePreflight, value))
            {
                OnPropertyChanged(nameof(MovePreflightText));
                OnPropertyChanged(nameof(CanImport));
            }
        }
    }

    public DesktopImportError? Error
    {
        get => error;
        private set
        {
            if (SetProperty(ref error, value))
            {
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool HasPreviewItems => PreviewItems.Count > 0;

    public IReadOnlyList<DesktopImportSource> Sources => sources;

    public int ReadableItemCount => PreviewItems.Count(item =>
        item.Status is not DesktopImportPreviewStatus.Unreadable and not DesktopImportPreviewStatus.PermissionDenied);

    public int ImportableItemCount => PreviewItems.Count(CanImportPreviewItem);

    public bool HasFolderSources => sources.Any(source => source.IsFromFolder);

    public bool RequiresMoveConfirmation => Mode == DesktopImportMode.Move;

    public bool CanPrepare => !IsPreparing && !IsImporting && SourcePaths().Count > 0;

    public bool CanImport
    {
        get
        {
            return !IsPreparing
                && !IsImporting
                && !string.IsNullOrWhiteSpace(RepoPath)
                && ImportableItemCount > 0
                && (!RequiresMoveConfirmation || MoveConfirmed && MovePreflight.CanMove);
        }
    }

    public bool HasSuccessfulResults => Results.Any(result => result.HasImportedFile);

    public bool HasFailedResults => Results.Any(result => result.IsFailure);

    public IReadOnlyList<long> ImportedFileIds => Results
        .Where(result => result is { Entry.Id: > 0, IsFailure: false })
        .Select(result => result.Entry?.Id ?? 0)
        .Distinct()
        .ToArray();

    public string SourceSummaryText => HasPreviewItems
        ? $"Source: {PreviewItems.Count} item(s)"
        : "Add files or folders to import.";

    public string MoveConfirmationText
    {
        get
        {
            return "AreaMatrix will not remove originals until the imported files and database records are safely written. "
                + $"Items to move: {ImportableItemCount}. File system: {MovePreflight.MountText}.";
        }
    }

    public string MovePreflightText => MovePreflight.StatusText;

    public string ProgressText
    {
        get
        {
            return CurrentStep switch
            {
                DesktopImportStep.Preparing => "Reading selected items...",
                DesktopImportStep.Staging => "Staging",
                DesktopImportStep.Hashing => "Hashing",
                DesktopImportStep.WritingFiles => "Writing files",
                DesktopImportStep.UpdatingDatabase => "Updating database",
                DesktopImportStep.RemovingOriginals => "Removing originals",
                DesktopImportStep.Done => "Done",
                _ => "Reading selected items..."
            };
        }
    }

    public string ResultSummaryText => Results.Count == 0 ? string.Empty : ResultSummaryFor(Results);

    public string StatusText
    {
        get
        {
            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            if (IsPreparing || IsImporting)
            {
                return ProgressText;
            }

            if (Results.Count > 0)
            {
                return ResultSummaryText;
            }

            return SourceSummaryText;
        }
    }

    public void OpenRepository(string path)
    {
        RepoPath = path;
        Clear();
    }

    public void Clear()
    {
        SourcePathsText = string.Empty;
        TargetDirectory = string.Empty;
        TargetCategory = string.Empty;
        Mode = DesktopImportMode.Copy;
        DuplicateStrategy = DesktopImportDuplicateStrategy.Skip;
        PreserveFolderStructure = false;
        MoveConfirmed = false;
        CurrentStep = DesktopImportStep.Preparing;
        sources = [];
        PreviewItems = [];
        Results = [];
        MovePreflight = DesktopImportMovePreflight.NotEvaluated;
        Error = null;
    }

    public void SetSources(IEnumerable<DesktopImportSource> importSources)
    {
        sources = importSources
            .DistinctBy(source => source.SourcePath, StringComparer.Ordinal)
            .ToArray();
        SourcePathsText = string.Join(Environment.NewLine, sources.Select(source => source.SourcePath));
        MovePreflight = DesktopImportMovePreflight.NotEvaluated;
        OnPropertyChanged(nameof(HasFolderSources));
        OnPropertyChanged(nameof(CanPrepare));
        OnPropertyChanged(nameof(CanImport));
    }

    public async Task PreparePreviewAsync(CancellationToken cancellationToken = default)
    {
        if (!CanPrepare)
        {
            return;
        }

        IsPreparing = true;
        CurrentStep = DesktopImportStep.Preparing;
        Error = null;
        Results = [];
        try
        {
            List<DesktopImportPreviewItem> items = [];
            foreach (DesktopImportSource source in SourcesForPreview())
            {
                DesktopImportPreviewItem item = await coreBridge
                    .PredictImportAsync(RepoPath, source.SourcePath, cancellationToken)
                    .ConfigureAwait(false);
                items.Add(item);
            }

            PreviewItems = items;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = DesktopImportError.FromException(exception);
        }
        finally
        {
            IsPreparing = false;
        }
    }

    public async Task ImportAsync(CancellationToken cancellationToken = default)
    {
        if (!CanImport)
        {
            return;
        }

        IsImporting = true;
        Error = null;
        Results = [];
        try
        {
            List<DesktopImportResult> imported = [];
            foreach (DesktopImportPreviewItem item in PreviewItems.Where(CanImportPreviewItem))
            {
                imported.Add(await ImportPreviewItemAsync(item, cancellationToken).ConfigureAwait(false));
            }

            CurrentStep = Mode == DesktopImportMode.Move
                ? DesktopImportStep.RemovingOriginals
                : DesktopImportStep.WritingFiles;
            Results = imported;
            CurrentStep = DesktopImportStep.Done;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = DesktopImportError.FromException(exception);
        }
        finally
        {
            IsImporting = false;
        }
    }

    public async Task RetryFailedAsync(
        DesktopImportResult failedResult,
        CancellationToken cancellationToken = default)
    {
        if (!failedResult.CanRetry)
        {
            return;
        }

        DesktopImportPreviewItem? item = PreviewItems.FirstOrDefault(candidate =>
            string.Equals(candidate.SourcePath, failedResult.SourcePath, StringComparison.Ordinal));
        if (item is null || !CanImportPreviewItem(item))
        {
            return;
        }

        IsImporting = true;
        Error = null;
        try
        {
            ReplaceResultForSource(
                item.SourcePath,
                await ImportPreviewItemAsync(item, cancellationToken).ConfigureAwait(false));
            CurrentStep = DesktopImportStep.Done;
        }
        finally
        {
            IsImporting = false;
        }
    }

    public void UseCopyInstead()
    {
        Mode = DesktopImportMode.Copy;
        MoveConfirmed = false;
    }

    public LinuxImportCloseRequest CreateCloseRequest()
    {
        return ImportedFileIds.Count == 0
            ? LinuxImportCloseRequest.None
            : new LinuxImportCloseRequest(ImportedFileIds);
    }
}
