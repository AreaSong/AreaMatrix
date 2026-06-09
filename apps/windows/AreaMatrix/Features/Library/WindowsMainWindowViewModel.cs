using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using AreaMatrix.Features.Conflicts;
using AreaMatrix.Features.Onboarding;

namespace AreaMatrix.Features.Library;

public sealed partial class WindowsMainWindowViewModel : INotifyPropertyChanged
{
    private const long PageSize = 50;

    private readonly IDesktopMainQueryCoreBridge coreBridge;
    private readonly string locale;
    private string repoPath = string.Empty;
    private string repoName = "AreaMatrix";
    private string searchQuery = string.Empty;
    private string? selectedCategory;
    private bool isLoading;
    private bool isRefreshing;
    private DesktopMainQuerySnapshot snapshot = DesktopMainQuerySnapshot.Empty;
    private DesktopFileEntry? selectedFile;
    private WindowsRepositoryRoute? currentRoute;
    private WindowsRepositoryError? error;

    public WindowsMainWindowViewModel(
        IDesktopMainQueryCoreBridge coreBridge,
        ISyncConflictEntryCoreBridge? syncConflictBridge = null,
        string locale = "en-US")
    {
        this.coreBridge = coreBridge;
        this.locale = locale;
        if (syncConflictBridge is not null)
        {
            SyncConflictEntry = new SyncConflictEntryViewModel(syncConflictBridge);
            SyncConflictEntry.PropertyChanged += (_, _) =>
            {
                OnPropertyChanged(nameof(SyncConflictEntry));
                OnPropertyChanged(nameof(SelectedFileSyncConflict));
            };
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string RepoPath
    {
        get => repoPath;
        private set
        {
            if (SetProperty(ref repoPath, value))
            {
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public string RepoName
    {
        get => repoName;
        private set => SetProperty(ref repoName, value);
    }

    public string SearchQuery
    {
        get => searchQuery;
        set => SetProperty(ref searchQuery, value);
    }

    public string? SelectedCategory
    {
        get => selectedCategory;
        private set => SetProperty(ref selectedCategory, value);
    }

    public bool IsLoading
    {
        get => isLoading;
        private set
        {
            if (SetProperty(ref isLoading, value))
            {
                OnPropertyChanged(nameof(CanRunQuery));
                OnPropertyChanged(nameof(CanOpenOneDriveStatus));
                OnPropertyChanged(nameof(CanOpenWatcherStatus));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool IsRefreshing
    {
        get => isRefreshing;
        private set
        {
            if (SetProperty(ref isRefreshing, value))
            {
                OnPropertyChanged(nameof(CanRunQuery));
                OnPropertyChanged(nameof(CanOpenOneDriveStatus));
                OnPropertyChanged(nameof(CanOpenWatcherStatus));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public DesktopMainQuerySnapshot Snapshot
    {
        get => snapshot;
        private set
        {
            if (SetProperty(ref snapshot, value))
            {
                OnPropertyChanged(nameof(Files));
                OnPropertyChanged(nameof(Categories));
                OnPropertyChanged(nameof(HasFiles));
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public DesktopFileEntry? SelectedFile
    {
        get => selectedFile;
        private set
        {
            if (SetProperty(ref selectedFile, value))
            {
                OnPropertyChanged(nameof(SelectedFileTitle));
                OnPropertyChanged(nameof(SelectedFilePath));
                OnPropertyChanged(nameof(SelectedFileStatus));
                OnPropertyChanged(nameof(SelectedFileSyncConflict));
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
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public IReadOnlyList<DesktopFileEntry> Files => Snapshot.Files;

    public SyncConflictEntryViewModel? SyncConflictEntry { get; }

    public SyncConflictEntryConflict? SelectedFileSyncConflict =>
        SyncConflictEntry?.DetailConflictFor(SelectedFile);

    public IReadOnlyList<DesktopCategoryNode> Categories => Snapshot.Categories;

    public bool HasFiles => Files.Count > 0;

    public bool CanRunQuery => !IsLoading && !IsRefreshing && !string.IsNullOrWhiteSpace(RepoPath);

    public bool CanOpenOneDriveStatus
    {
        get
        {
            return !IsLoading
                && !IsRefreshing
                && OneDriveStatusRoute is not null;
        }
    }

    public bool CanOpenWatcherStatus
    {
        get
        {
            return !IsLoading
                && !IsRefreshing
                && WatcherStatusRoute is not null;
        }
    }

    public WindowsRepositoryRoute? OneDriveStatusRoute
    {
        get
        {
            if (currentRoute is not { CloudStorageState.ProviderKind: WindowsCloudStorageProviderKind.OneDrive })
            {
                return null;
            }

            return currentRoute with { Kind = WindowsRepositoryRouteKind.OneDriveNotice };
        }
    }

    public WindowsRepositoryRoute? WatcherStatusRoute
    {
        get
        {
            if (string.IsNullOrWhiteSpace(RepoPath) || currentRoute is null)
            {
                return null;
            }

            return currentRoute with { Kind = WindowsRepositoryRouteKind.WatcherStatus };
        }
    }

    public WindowsRepositoryRoute? ImportRoute
    {
        get
        {
            if (string.IsNullOrWhiteSpace(RepoPath) || currentRoute is null)
            {
                return null;
            }

            return currentRoute with { Kind = WindowsRepositoryRouteKind.ImportFlow };
        }
    }

    public string SelectedFileTitle => SelectedFile?.DisplayName ?? "No file selected";

    public string SelectedFilePath => SelectedFile?.Path ?? "Select a file to view metadata.";

    public string SelectedFileStatus => SelectedFile?.StatusText ?? "Ready";

    public string StatusText
    {
        get
        {
            if (IsLoading)
            {
                return "Loading repository...";
            }

            if (IsRefreshing)
            {
                return "Refreshing...";
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            string scope = string.IsNullOrWhiteSpace(SelectedCategory) ? "All Files" : SelectedCategory;
            return $"{scope}: {Files.Count} item(s)";
        }
    }

    public async Task OpenRepositoryAsync(
        WindowsRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        currentRoute = route;
        RepoPath = route.RepoPath;
        RepoName = RepositoryName(route.RepoPath);
        SearchQuery = string.Empty;
        SelectedCategory = null;
        OnPropertyChanged(nameof(CanOpenOneDriveStatus));
        OnPropertyChanged(nameof(OneDriveStatusRoute));
        OnPropertyChanged(nameof(CanOpenWatcherStatus));
        OnPropertyChanged(nameof(WatcherStatusRoute));
        OnPropertyChanged(nameof(ImportRoute));
        await LoadSnapshotAsync(isInitialLoad: true, cancellationToken);
        if (SyncConflictEntry is not null)
        {
            await SyncConflictEntry.OpenRepositoryAsync(RepoPath, cancellationToken);
            OnPropertyChanged(nameof(SelectedFileSyncConflict));
        }
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        await LoadSnapshotAsync(isInitialLoad: false, cancellationToken);
        if (SyncConflictEntry is not null)
        {
            await SyncConflictEntry.RefreshAsync(cancellationToken);
            OnPropertyChanged(nameof(SelectedFileSyncConflict));
        }
    }

    public async Task RefreshAndSelectFileAsync(
        long fileId,
        CancellationToken cancellationToken = default)
    {
        if (fileId <= 0 || string.IsNullOrWhiteSpace(RepoPath))
        {
            await RefreshAsync(cancellationToken);
            return;
        }

        await LoadSnapshotAsync(isInitialLoad: false, cancellationToken, selectedFileId: fileId);
        if (SyncConflictEntry is not null)
        {
            await SyncConflictEntry.RefreshAsync(cancellationToken);
            OnPropertyChanged(nameof(SelectedFileSyncConflict));
        }
    }

    public async Task SelectCategoryAsync(
        DesktopCategoryNode? category,
        CancellationToken cancellationToken = default)
    {
        SelectedCategory = CategoryFilterFor(category);
        SearchQuery = string.Empty;
        await LoadSnapshotAsync(isInitialLoad: false, cancellationToken);
    }

    public async Task RunSearchAsync(CancellationToken cancellationToken = default)
    {
        if (!CanRunQuery)
        {
            return;
        }

        IsRefreshing = true;
        Error = null;
        try
        {
            string query = SearchQuery.Trim();
            IReadOnlyList<DesktopCategoryNode> categories = await coreBridge
                .ListCategoriesAsync(RepoPath, locale, cancellationToken);

            if (query.Length == 0)
            {
                IReadOnlyList<DesktopFileEntry> files = await coreBridge.ListFilesAsync(
                    RepoPath,
                    DesktopFileFilter.FirstPage(SelectedCategory),
                    cancellationToken);
                ApplySnapshot(files, categories, totalCount: files.Count, query: string.Empty, searchIndexStatus: null);
                return;
            }

            DesktopSearchResultPage page = await coreBridge.SearchFilesAsync(
                RepoPath,
                query,
                DesktopSearchFilter.AllRepository(SelectedCategory),
                DesktopSearchSort.NewestImported,
                new DesktopSearchPagination(PageSize, 0),
                cancellationToken);
            ApplySnapshot(
                page.Results.Select(result => result.Entry).ToArray(),
                categories,
                page.TotalCount,
                page.Query,
                page.IndexStatus);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    public async Task SelectFileAsync(
        DesktopFileEntry? file,
        CancellationToken cancellationToken = default)
    {
        if (file is null || string.IsNullOrWhiteSpace(RepoPath))
        {
            SelectedFile = null;
            return;
        }

        try
        {
            Error = null;
            SelectedFile = await coreBridge.GetFileAsync(RepoPath, file.Id, cancellationToken);
            Snapshot = Snapshot with { SelectedFile = SelectedFile };
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
    }

    private void SetBusy(bool isInitialLoad, bool busy)
    {
        if (isInitialLoad)
        {
            IsLoading = busy;
            return;
        }

        IsRefreshing = busy;
    }

    private static string? CategoryFilterFor(DesktopCategoryNode? category)
    {
        if (category is null || category.Slug == "__root__")
        {
            return null;
        }

        return category.Slug;
    }

    private static WindowsRepositoryError ErrorFromException(Exception exception)
    {
        if (exception is DesktopQueryCoreException queryException)
        {
            return queryException.ToRepositoryError();
        }

        if (exception is WindowsRepositoryCoreException coreException)
        {
            return new WindowsRepositoryError(coreException.Kind, ErrorMessageFor(coreException), coreException.Path);
        }

        return new WindowsRepositoryError(WindowsRepositoryErrorKind.Unavailable, exception.Message);
    }

    private static string ErrorMessageFor(WindowsRepositoryCoreException exception)
    {
        return exception.Kind switch
        {
            WindowsRepositoryErrorKind.Db => "Repository database could not be read.",
            WindowsRepositoryErrorKind.InvalidRepository => "Repository metadata is not initialized.",
            WindowsRepositoryErrorKind.FileNotFound => "The selected file is no longer available.",
            WindowsRepositoryErrorKind.PermissionDenied => "AreaMatrix cannot read this repository.",
            WindowsRepositoryErrorKind.InvalidPath => "Repository folder not found.",
            WindowsRepositoryErrorKind.Config => "Repository configuration cannot be opened.",
            _ => exception.Message
        };
    }

    private static string RepositoryName(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "AreaMatrix";
        }

        string trimmed = path.TrimEnd('\\', '/');
        int separator = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return separator >= 0 && separator < trimmed.Length - 1
            ? trimmed[(separator + 1)..]
            : trimmed;
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
