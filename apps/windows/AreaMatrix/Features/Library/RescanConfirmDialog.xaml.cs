using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Library;

public sealed partial class RescanConfirmDialog : UserControl
{
    private RescanConfirmViewModel? viewModel;

    public RescanConfirmDialog()
    {
        InitializeComponent();
        RefreshState();
    }

    public event Action? CloseRequested;

    public RescanConfirmRequest? Request
    {
        get => viewModel?.Request;
    }

    public RescanConfirmViewModel? ViewModel
    {
        get => viewModel;
        set
        {
            if (viewModel is not null)
            {
                viewModel.PropertyChanged -= ViewModel_PropertyChanged;
            }

            viewModel = value;
            if (viewModel is not null)
            {
                viewModel.PropertyChanged += ViewModel_PropertyChanged;
            }

            RefreshState();
        }
    }

    public void OpenRequest(RescanConfirmRequest rescanRequest)
    {
        if (viewModel is null)
        {
            throw new InvalidOperationException("Rescan confirmation requires an injected view model.");
        }

        viewModel.OpenRequest(rescanRequest);
        RefreshState();
    }

    private void CancelRescanConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }

    private void RescanConfirmCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (viewModel is null)
        {
            return;
        }

        viewModel.UserConfirmed = RescanConfirmCheckBox.IsChecked == true;
        RefreshState();
    }

    private async void RunRescanButton_Click(object sender, RoutedEventArgs e)
    {
        await RunRescanAsync().ConfigureAwait(true);
    }

    public async Task<bool> RunRescanAsync()
    {
        if (viewModel is null)
        {
            return false;
        }

        bool started = await viewModel.RunRescanAsync().ConfigureAwait(true);
        RefreshState();
        return started;
    }

    private void RefreshState()
    {
        if (viewModel?.Request is not { } currentRequest)
        {
            RepositoryTextBlock.Text = "Repository: Unavailable";
            EstimatedItemsTextBlock.Text = "Estimated items: Unknown";
            PreviewSummaryTextBlock.Text = "Preview impact is not available.";
            NeedsReviewTextBlock.Text = string.Empty;
            NeedsReviewTextBlock.Visibility = Visibility.Collapsed;
            StalePreviewTextBlock.Visibility = Visibility.Collapsed;
            PreviewItemsList.ItemsSource = Array.Empty<string>();
            NoPreviewItemsTextBlock.Visibility = Visibility.Visible;
            RescanConfirmCheckBox.IsChecked = false;
            RescanConfirmCheckBox.IsEnabled = false;
            RunRescanButton.IsEnabled = false;
            ProgressTextBlock.Visibility = Visibility.Collapsed;
            ResultTextBlock.Visibility = Visibility.Collapsed;
            ErrorTextBlock.Visibility = Visibility.Collapsed;
            return;
        }

        ManualRescanPreviewReport preview = currentRequest.Preview;
        RepositoryTextBlock.Text = viewModel.RepositoryText;
        EstimatedItemsTextBlock.Text = viewModel.EstimatedItemsText;
        PreviewSummaryTextBlock.Text = viewModel.PreviewSummaryText;
        NeedsReviewTextBlock.Text = viewModel.NeedsReviewText;
        NeedsReviewTextBlock.Visibility = viewModel.HasNeedsReview
            ? Visibility.Visible
            : Visibility.Collapsed;
        StalePreviewTextBlock.Visibility = preview.IsStale
            ? Visibility.Visible
            : Visibility.Collapsed;

        IReadOnlyList<string> itemTexts = PreviewItemTexts(preview);
        PreviewItemsList.ItemsSource = itemTexts;
        NoPreviewItemsTextBlock.Visibility = itemTexts.Count > 0
            ? Visibility.Collapsed
            : Visibility.Visible;
        RescanConfirmCheckBox.IsChecked = viewModel.UserConfirmed;
        RescanConfirmCheckBox.IsEnabled = !viewModel.IsRunning && !viewModel.HasResult;
        RunRescanButton.IsEnabled = viewModel.CanRunRescan;
        ProgressTextBlock.Visibility = viewModel.IsRunning
            ? Visibility.Visible
            : Visibility.Collapsed;
        ResultTextBlock.Text = viewModel.ResultText;
        ResultTextBlock.Visibility = viewModel.HasResult
            ? Visibility.Visible
            : Visibility.Collapsed;
        ErrorTextBlock.Text = viewModel.ErrorText;
        ErrorTextBlock.Visibility = viewModel.HasError
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private static IReadOnlyList<string> PreviewItemTexts(ManualRescanPreviewReport preview)
    {
        return preview.Items
            .Take(5)
            .Select(item => string.IsNullOrWhiteSpace(item.DetailText)
                ? item.DisplayText
                : $"{item.DisplayText}: {item.DetailText}")
            .ToArray();
    }

    private void ViewModel_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        RefreshState();
    }
}
