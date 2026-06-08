using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AreaMatrix.Features.Library;

public sealed partial class RescanConfirmDialog : UserControl
{
    private RescanConfirmRequest? request;

    public RescanConfirmDialog()
    {
        InitializeComponent();
        RefreshState();
    }

    public event Action? CloseRequested;

    public RescanConfirmRequest? Request
    {
        get => request;
        private set
        {
            request = value;
            RefreshState();
        }
    }

    public void OpenRequest(RescanConfirmRequest rescanRequest)
    {
        Request = rescanRequest;
    }

    private void CancelRescanConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        CloseRequested?.Invoke();
    }

    private void RefreshState()
    {
        if (Request is null)
        {
            RepositoryTextBlock.Text = "Repository: Unavailable";
            EstimatedItemsTextBlock.Text = "Estimated items: Unknown";
            PreviewSummaryTextBlock.Text = "Preview impact is not available.";
            NeedsReviewTextBlock.Text = string.Empty;
            NeedsReviewTextBlock.Visibility = Visibility.Collapsed;
            StalePreviewTextBlock.Visibility = Visibility.Collapsed;
            PreviewItemsList.ItemsSource = Array.Empty<string>();
            NoPreviewItemsTextBlock.Visibility = Visibility.Visible;
            return;
        }

        ManualRescanPreviewReport preview = Request.Preview;
        RepositoryTextBlock.Text = $"Repository: {Request.Route.RepoPath}";
        EstimatedItemsTextBlock.Text = preview.EstimatedItemsText;
        PreviewSummaryTextBlock.Text = preview.SummaryText;
        NeedsReviewTextBlock.Text = preview.HasNeedsReview
            ? "Some results may need review after rescan."
            : string.Empty;
        NeedsReviewTextBlock.Visibility = preview.HasNeedsReview
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
}
