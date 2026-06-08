using System.ComponentModel;
using System.Runtime.CompilerServices;
using AreaMatrix.Linux.Features.Onboarding;

namespace AreaMatrix.Linux.Features.Library;

public sealed partial class LinuxMainWindowViewModel : INotifyPropertyChanged
{
    private readonly IDesktopMainQueryCoreBridge coreBridge;
    private readonly string locale;
    private string repoPath = string.Empty;
    private string repoName = "AreaMatrix";
    private string searchQuery = string.Empty;
    private string? selectedCategory;
    private bool isLoading;
    private bool isRefreshing;
    private bool isLoadingMore;
    private DesktopMainQuerySnapshot snapshot = DesktopMainQuerySnapshot.Empty;
    private DesktopFileEntry? selectedFile;
    private LinuxRepositoryError? error;

    public LinuxMainWindowViewModel(
        IDesktopMainQueryCoreBridge coreBridge,
        string locale = "en-US")
    {
        this.coreBridge = coreBridge;
        this.locale = locale;
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
                OnPropertyChanged(nameof(LocalFolderText));
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
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public bool IsLoadingMore
    {
        get => isLoadingMore;
        private set
        {
            if (SetProperty(ref isLoadingMore, value))
            {
                OnPropertyChanged(nameof(CanRunQuery));
                OnPropertyChanged(nameof(CanLoadMore));
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
                OnPropertyChanged(nameof(CanLoadMore));
                OnPropertyChanged(nameof(PaginationText));
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
                OnPropertyChanged(nameof(StatusText));
            }
        }
    }

    public IReadOnlyList<DesktopFileEntry> Files => Snapshot.Files;

    public IReadOnlyList<DesktopCategoryNode> Categories => Snapshot.Categories;

    public bool HasFiles => Files.Count > 0;

    public bool CanRunQuery => !IsLoading
        && !IsRefreshing
        && !IsLoadingMore
        && !string.IsNullOrWhiteSpace(RepoPath);

    public bool CanLoadMore => CanRunQuery && Snapshot.HasMore;

    public string PaginationText => Snapshot.PageText;

    public string SelectedFileTitle => SelectedFile?.DisplayName ?? "No file selected";

    public string SelectedFilePath => SelectedFile?.Path ?? "Select a file to view metadata.";

    public string SelectedFileStatus => SelectedFile?.StatusText ?? "Ready";

    public string LocalFolderText => string.IsNullOrWhiteSpace(RepoPath)
        ? "Local folder: not connected"
        : $"Local folder: {RepoPath}";

    public string WatcherStatusText => "Watcher: platform status";

    public string DbStatusText => Error?.Kind == LinuxRepositoryErrorKind.Db
        ? "DB: needs attention"
        : "DB: ready";

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

            if (IsLoadingMore)
            {
                return "Loading more...";
            }

            if (Error is { } currentError)
            {
                return currentError.Message;
            }

            string scope = string.IsNullOrWhiteSpace(Snapshot.Query)
                ? string.IsNullOrWhiteSpace(SelectedCategory) ? "All Files" : SelectedCategory
                : $"Search: {Snapshot.Query}";
            return $"{scope}: {Files.Count} item(s)";
        }
    }

    public async Task OpenRepositoryAsync(
        LinuxRepositoryRoute route,
        CancellationToken cancellationToken = default)
    {
        RepoPath = route.RepoPath;
        RepoName = RepositoryName(route.RepoPath);
        SearchQuery = string.Empty;
        SelectedCategory = null;
        await LoadSnapshotAsync(isInitialLoad: true, cancellationToken);
    }

    public Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        return LoadSnapshotAsync(isInitialLoad: false, cancellationToken);
    }

    public async Task RunSearchAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(SearchQuery))
        {
            await RefreshAsync(cancellationToken);
            return;
        }

        if (string.IsNullOrWhiteSpace(RepoPath))
        {
            return;
        }

        IsRefreshing = true;
        Error = null;
        try
        {
            IReadOnlyList<DesktopCategoryNode> categories = await coreBridge
                .ListCategoriesAsync(RepoPath, locale, cancellationToken)
                .ConfigureAwait(false);
            DesktopSearchResultPage page = await coreBridge.SearchFilesAsync(
                RepoPath,
                SearchQuery.Trim(),
                DesktopSearchFilter.AllRepository(SelectedCategory),
                DesktopSearchSort.Relevance,
                new DesktopSearchPagination(PageSize, 0),
                cancellationToken).ConfigureAwait(false);
            ApplySnapshot(
                page.Results.Select(result => result.Entry).ToArray(),
                categories,
                page.TotalCount,
                page.Query,
                page.IndexStatus,
                offset: 0,
                hasMore: page.Results.Count < page.TotalCount);
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

    public async Task SelectCategoryAsync(
        DesktopCategoryNode? category,
        CancellationToken cancellationToken = default)
    {
        SelectedCategory = CategoryFilterFor(category);
        SearchQuery = string.Empty;
        await LoadSnapshotAsync(isInitialLoad: false, cancellationToken);
    }

    public async Task SelectFileAsync(
        DesktopFileEntry? file,
        CancellationToken cancellationToken = default)
    {
        if (file is null || string.IsNullOrWhiteSpace(RepoPath))
        {
            SelectedFile = null;
            Snapshot = Snapshot with { SelectedFile = null };
            return;
        }

        Error = null;
        try
        {
            SelectedFile = await coreBridge.GetFileAsync(RepoPath, file.Id, cancellationToken)
                .ConfigureAwait(false);
            Snapshot = Snapshot with { SelectedFile = SelectedFile };
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
    }

    public async Task LoadMoreAsync(CancellationToken cancellationToken = default)
    {
        if (!CanLoadMore)
        {
            return;
        }

        IsLoadingMore = true;
        Error = null;
        try
        {
            if (string.IsNullOrWhiteSpace(Snapshot.Query))
            {
                await LoadMoreListAsync(cancellationToken).ConfigureAwait(false);
                return;
            }

            await LoadMoreSearchAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            Error = ErrorFromException(exception);
        }
        finally
        {
            IsLoadingMore = false;
        }
    }

    private LinuxRepositoryError ErrorFromException(Exception exception)
    {
        return exception switch
        {
            DesktopQueryCoreException queryException => queryException.ToRepositoryError(),
            LinuxRepositoryCoreException coreException => ErrorFromCoreException(coreException),
            _ => new LinuxRepositoryError(LinuxRepositoryErrorKind.Unavailable, exception.Message)
        };
    }

    private static LinuxRepositoryError ErrorFromCoreException(LinuxRepositoryCoreException exception)
    {
        return new LinuxRepositoryError(exception.Kind, exception.Message, exception.Path);
    }

    private static string RepositoryName(string path)
    {
        string? name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar));
        return string.IsNullOrWhiteSpace(name) ? "AreaMatrix" : name;
    }

    private static string? CategoryFilterFor(DesktopCategoryNode? category)
    {
        if (category is null
            || string.IsNullOrWhiteSpace(category.Slug)
            || category.Slug == "__root__")
        {
            return null;
        }

        return category.Slug;
    }

    private bool SetProperty<T>(
        ref T storage,
        T value,
        [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
        {
            return false;
        }

        storage = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
