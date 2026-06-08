using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace AreaMatrix.Features.Import;

public sealed partial class WindowsImportViewModel : INotifyPropertyChanged
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

    public WindowsImportViewModel(IDesktopImportCoreBridge coreBridge)
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
                NotifyReplacePreviewStateChanged();
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

    public int ReadableItemCount => PreviewItems.Count(item => item.Status != DesktopImportPreviewStatus.Unreadable);

    public int ImportableItemCount => PreviewItems.Count(CanImportPreviewItem);

    public bool HasFolderSources => sources.Any(source => source.IsFromFolder);

    public bool RequiresMoveConfirmation => Mode == DesktopImportMode.Move;

    public bool CanPrepare => !IsPreparing && !IsImporting && SourcePaths().Count > 0;

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

    public string SourceSummaryText
    {
        get
        {
            if (!HasPreviewItems)
            {
                return "Add files or folders to import.";
            }

            return $"Source: {PreviewItems.Count} item(s)";
        }
    }

    public string MoveConfirmationText
    {
        get
        {
            return $"Items to move: {ImportableItemCount}. Source removal happens after files and database records are safely written.";
        }
    }

    public string MovePreflightText => MovePreflight.StatusText;

    public string ProgressText
    {
        get
        {
            return CurrentStep switch
            {
                DesktopImportStep.Preparing => "Preparing import...",
                DesktopImportStep.Staging => "Staging",
                DesktopImportStep.Hashing => "Hashing",
                DesktopImportStep.WritingFiles => "Writing files",
                DesktopImportStep.UpdatingDatabase => "Updating database",
                DesktopImportStep.RemovingOriginals => "Removing originals",
                DesktopImportStep.Done => "Done",
                _ => "Preparing import..."
            };
        }
    }

    public string ResultSummaryText
    {
        get
        {
            return Results.Count == 0 ? string.Empty : ResultSummaryFor(Results);
        }
    }

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
        ClearReplaceState();
        MovePreflight = DesktopImportMovePreflight.NotEvaluated;
        Error = null;
    }

    public void SetSources(IEnumerable<DesktopImportSource> importSources)
    {
        sources = importSources
            .DistinctBy(source => source.SourcePath, StringComparer.OrdinalIgnoreCase)
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
        ClearReplaceState();
        try
        {
            List<DesktopImportPreviewItem> items = [];
            foreach (DesktopImportSource source in SourcesForPreview())
            {
                DesktopImportPreviewItem item = await coreBridge
                    .PredictImportAsync(RepoPath, source.SourcePath, cancellationToken)
                    .ConfigureAwait(false);
                items.Add(item with
                {
                    ImportSessionId = source.ImportSessionId,
                    ConflictId = source.ConflictId
                });
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
        ReplaceResult = null;
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

    public void UseCopyInstead()
    {
        Mode = DesktopImportMode.Copy;
        MoveConfirmed = false;
    }

    private void RefreshMovePreflight()
    {
        if (!RequiresMoveConfirmation || PreviewItems.Count == 0 || string.IsNullOrWhiteSpace(RepoPath))
        {
            MovePreflight = DesktopImportMovePreflight.NotEvaluated;
            return;
        }

        MovePreflight = coreBridge.CheckMovePreflight(RepoPath, PreviewItems.Where(CanImportPreviewItem).ToArray());
    }

    private bool CanImportPreviewItem(DesktopImportPreviewItem item)
    {
        return item.IsImportable
            || item.Status == DesktopImportPreviewStatus.Duplicate
                && DuplicateStrategy == DesktopImportDuplicateStrategy.KeepBoth;
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
