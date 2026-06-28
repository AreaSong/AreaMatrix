import SwiftUI

struct SearchFacetPicker: View {
    var title: String
    var allLabel: String
    @Binding var selection: String?
    var options: [SearchFacetCountSnapshot]
    var isLoading: Bool
    var emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: Binding(
                get: { selection ?? "" },
                set: { selection = SearchFilterEditing.optionalFacetValue($0) }
            )) {
                Text(allLabel).tag("")
                ForEach(options) { option in
                    Text(option.displayTitle).tag(option.value)
                }
            }
            .disabled(options.isEmpty)
            .accessibilityLabel("\(title) filter")
            if options.isEmpty {
                Text(isLoading ? "Loading..." : emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SearchDateFilterSection: View {
    var title: String
    var field: SearchFilterDateField
    var bounds: SearchDateFacetBoundsSnapshot?
    @Binding var filters: SearchFilterStateSnapshot
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Menu(dateSummary) {
                    Button("Any") { applyPreset(.any) }
                    Button("Last 7 days") { applyPreset(.last7Days) }
                    Button("Last 30 days") { applyPreset(.last30Days) }
                    Button("This year") { applyPreset(.thisYear) }
                    Button("Custom...") {
                        applyCustomRange(from: customFromDate, until: customToDate)
                    }
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) date filter, \(dateSummary)")
            if field.hasCustomRange(in: filters) {
                customDatePickers
            }
            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(title) date error, \(validationError)")
            }
        }
    }

    private var dateSummary: String {
        field.summary(in: filters)
    }

    private var customDatePickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            DatePicker("From", selection: fromBinding, in: allowedDateRange, displayedComponents: [.date])
            DatePicker("To", selection: toBinding, in: allowedDateRange, displayedComponents: [.date])
        }
    }

    private var fromBinding: Binding<Date> {
        Binding(
            get: { customFromDate },
            set: { applyCustomRange(from: $0, until: customToDate) }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { customToDate },
            set: { applyCustomRange(from: customFromDate, until: $0) }
        )
    }

    private var customFromDate: Date {
        field.afterTimestamp(in: filters).map { Date(timeIntervalSince1970: TimeInterval($0)) } ??
            Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    private var customToDate: Date {
        field.beforeTimestamp(in: filters).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    }

    private var allowedDateRange: ClosedRange<Date> {
        field.allowedDateRange(from: bounds)
    }

    private func applyPreset(_ preset: SearchDateFilterPreset) {
        validationError = nil
        filters = SearchFilterEditing.settingDatePreset(preset, field: field, in: filters)
    }

    private func applyCustomRange(from: Date, until: Date) {
        let result = SearchFilterEditing.settingCustomDateRange(from: from, until: until, field: field, in: filters)
        if let updated = result.updatedFilters {
            validationError = nil
            filters = updated
            return
        }
        validationError = result.errorMessage
    }
}

struct SearchStorageFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var options: [SearchStorageModeFacetCountSnapshot]

    var body: some View {
        Picker("Storage", selection: Binding(
            get: { filters.storageMode?.rawValue ?? "" },
            set: { filters = SearchFilterEditing.settingStorage($0, in: filters) }
        )) {
            Text("All storage modes").tag("")
            ForEach(storageOptions) { option in
                Text(option.displayTitle).tag(option.value.rawValue)
            }
        }
        .accessibilityLabel("Storage filter")
    }

    private var storageOptions: [SearchStorageModeFacetCountSnapshot] {
        options.isEmpty ? SearchStorageModeFacetCountSnapshot.defaultOptions : options
    }
}

extension MainSearchFacetsState {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension SearchFacetCountSnapshot {
    var displayTitle: String {
        disabled ? "\(label) (0)" : "\(label) (\(count))"
    }
}

extension SearchStorageModeFacetCountSnapshot {
    static var defaultOptions: [SearchStorageModeFacetCountSnapshot] {
        SearchStorageModeSnapshot.allCases.map {
            SearchStorageModeFacetCountSnapshot(
                value: $0,
                label: $0.displayName,
                count: 0,
                selected: false,
                disabled: false
            )
        }
    }

    var displayTitle: String {
        disabled ? "\(label) (0)" : "\(label) (\(count))"
    }
}
