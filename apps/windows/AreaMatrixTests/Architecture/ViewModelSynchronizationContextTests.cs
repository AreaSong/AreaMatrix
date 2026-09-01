using AreaMatrix.Features.Library;
using AreaMatrix.Features.Onboarding;
using AreaMatrixTests.ChooseRepository;
using AreaMatrixTests.DesktopMainQuery;
using System.ComponentModel;
using System.Diagnostics;

namespace AreaMatrixTests.Architecture;

public static class ViewModelSynchronizationContextTests
{
    public static void RunAll()
    {
        UiFacingViewModelsPreserveTheCallingSynchronizationContext();
        DelayedContinuationRunsThroughTheCapturedContext();
        MainWindowRouteNotificationsStayOnCapturedContext();
        BackgroundNotificationIsRejectedByTheExecutableHarness();
    }

    private static void UiFacingViewModelsPreserveTheCallingSynchronizationContext()
    {
        string featuresDirectory = RepositoryDirectory("apps/windows/AreaMatrix/Features");
        foreach (string path in Directory.EnumerateFiles(
                     featuresDirectory,
                     "*ViewModel*.cs",
                     SearchOption.AllDirectories))
        {
            string source = File.ReadAllText(path);
            string viewModelSource = ViewModelRegion(path, source);
            string relativePath = Path.GetRelativePath(featuresDirectory, path);
            TestAssert.DoesNotContain(
                ".ConfigureAwait(false)",
                viewModelSource,
                $"{relativePath} UI continuation policy");
        }
    }

    private static string ViewModelRegion(string path, string source)
    {
        if (!path.EndsWith("RepositorySettingsViewModel.cs", StringComparison.Ordinal))
        {
            return source;
        }

        const string declaration = "public sealed class RepositorySettingsViewModel";
        int start = source.IndexOf(declaration, StringComparison.Ordinal);
        TestAssert.True(start >= 0, "repository settings ViewModel declaration");
        return source[start..];
    }

    private static void DelayedContinuationRunsThroughTheCapturedContext()
    {
        SynchronizationContextHarness harness = new();
        DelayedNotificationFixture fixture = new(harness.PendingCompletion.Task);
        SynchronizationContext? previousContext = SynchronizationContext.Current;
        SynchronizationContext? notificationContext = null;
        fixture.PropertyChanged += (_, _) => notificationContext = SynchronizationContext.Current;

        SynchronizationContext.SetSynchronizationContext(harness.Context);
        try
        {
            Task operation = fixture.LoadAsync();
            harness.PendingCompletion.SetResult(null);
            harness.RunUntilCompleted(operation);
        }
        finally
        {
            SynchronizationContext.SetSynchronizationContext(previousContext);
        }

        TestAssert.True(
            ReferenceEquals(harness.Context, notificationContext),
            "delayed UI notification stayed on the captured synchronization context");
    }

    private static void BackgroundNotificationIsRejectedByTheExecutableHarness()
    {
        SynchronizationContextHarness harness = new();
        BackgroundNotificationFixture fixture = new();
        SynchronizationContext? previousContext = SynchronizationContext.Current;
        bool rejected = false;

        SynchronizationContext.SetSynchronizationContext(harness.Context);
        try
        {
            Task operation = fixture.LoadAsync();
            harness.RunUntilCompleted(operation);
            try
            {
                harness.AssertNotificationContext(fixture.NotificationContext);
            }
            catch (InvalidOperationException)
            {
                rejected = true;
            }
        }
        finally
        {
            SynchronizationContext.SetSynchronizationContext(previousContext);
        }

        TestAssert.True(rejected, "background notification fixture must fail the context guard");
    }

    private static void MainWindowRouteNotificationsStayOnCapturedContext()
    {
        const string path = @"C:\Repos\Context";
        SynchronizationContextHarness harness = new();
        DelayedDesktopMainQueryCoreBridge bridge = new(path);
        WindowsMainWindowViewModel model = new(bridge);
        SynchronizationContext? previousContext = SynchronizationContext.Current;
        SynchronizationContext? notificationContext = null;
        model.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(model.Snapshot) && model.Files.Count > 0)
            {
                notificationContext = SynchronizationContext.Current;
            }
        };

        SynchronizationContext.SetSynchronizationContext(harness.Context);
        try
        {
            WindowsRepositoryRoute route = new(
                WindowsRepositoryRouteKind.MainWindow,
                path,
                WindowsRepositoryValidationSamples.Initialized(path),
                new WindowsRepositoryConfig(path, "Copied", "en-US"));
            Task operation = model.OpenRepositoryAsync(route);
            bridge.CompleteCategories(path);
            harness.RunUntilCompleted(operation);
        }
        finally
        {
            SynchronizationContext.SetSynchronizationContext(previousContext);
        }

        harness.AssertNotificationContext(notificationContext);
    }

    private static string RepositoryDirectory(string relativePath)
    {
        string? current = Directory.GetCurrentDirectory();
        while (!string.IsNullOrWhiteSpace(current))
        {
            string candidate = Path.Combine(current, relativePath);
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            current = Directory.GetParent(current)?.FullName;
        }

        throw new DirectoryNotFoundException($"Repository directory `{relativePath}` was not found.");
    }

    private sealed class SynchronizationContextHarness
    {
        public SynchronizationContextHarness()
        {
            Context = new QueueSynchronizationContext();
            PendingCompletion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        public QueueSynchronizationContext Context { get; }

        public TaskCompletionSource<object?> PendingCompletion { get; }

        public void RunUntilCompleted(Task operation)
        {
            Stopwatch timeout = Stopwatch.StartNew();
            while (!operation.IsCompleted)
            {
                if (!Context.DrainOne())
                {
                    Thread.Yield();
                }

                if (timeout.Elapsed >= TimeSpan.FromSeconds(5))
                {
                    throw new TimeoutException(
                        $"Synchronization-context operation did not complete; "
                        + $"pending callbacks: {Context.PendingCount}.");
                }
            }

            Context.DrainAll();
            operation.GetAwaiter().GetResult();
        }

        public void AssertNotificationContext(SynchronizationContext? notificationContext)
        {
            if (!ReferenceEquals(Context, notificationContext))
            {
                throw new InvalidOperationException(
                    "UI notification was raised outside the captured synchronization context.");
            }
        }
    }

    private sealed class QueueSynchronizationContext : SynchronizationContext
    {
        private readonly Queue<(SendOrPostCallback Callback, object? State)> callbacks = new();

        public int PendingCount
        {
            get
            {
                lock (callbacks)
                {
                    return callbacks.Count;
                }
            }
        }

        public override void Post(SendOrPostCallback callback, object? state)
        {
            lock (callbacks)
            {
                callbacks.Enqueue((callback, state));
            }
        }

        public bool DrainOne()
        {
            (SendOrPostCallback Callback, object? State) work;
            lock (callbacks)
            {
                if (callbacks.Count == 0)
                {
                    return false;
                }

                work = callbacks.Dequeue();
            }

            SynchronizationContext? previous = Current;
            SetSynchronizationContext(this);
            try
            {
                work.Callback(work.State);
            }
            finally
            {
                SetSynchronizationContext(previous);
            }

            return true;
        }

        public void DrainAll()
        {
            while (DrainOne())
            {
            }
        }
    }

    private sealed class DelayedNotificationFixture : INotifyPropertyChanged
    {
        private readonly Task completion;

        public DelayedNotificationFixture(Task completion)
        {
            this.completion = completion;
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        public async Task LoadAsync()
        {
            await completion;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(LoadAsync)));
        }
    }

    private sealed class BackgroundNotificationFixture : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;

        public SynchronizationContext? NotificationContext { get; private set; }

        public async Task LoadAsync()
        {
            await Task.Run(() =>
            {
                NotificationContext = SynchronizationContext.Current;
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(LoadAsync)));
            });
        }
    }
}
