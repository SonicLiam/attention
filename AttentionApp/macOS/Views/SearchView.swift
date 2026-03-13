import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TodoListViewModel.self) private var todoListViewModel
    @State private var searchViewModel = SearchViewModel()
    @State private var showFilters = false

    var body: some View {
        @Bindable var vm = searchViewModel

        VStack(spacing: 0) {
            // Filter chips
            if showFilters {
                filterChipsBar
                    .padding(.horizontal, AttentionLayout.padding)
                    .padding(.vertical, AttentionLayout.smallPadding)
                    .background(.bar)
                Divider()
            }

            // Results
            if searchViewModel.searchQuery.isEmpty && !searchViewModel.filter.isActive {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Type to search across all todos, projects, and tags")
                )
            } else if searchViewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchViewModel.results.isEmpty {
                ContentUnavailableView.search(text: searchViewModel.searchQuery)
            } else {
                resultsList
            }
        }
        .searchable(text: $vm.searchQuery, prompt: "Search todos, projects, tags...")
        .navigationTitle("Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(AttentionAnimation.springDefault) {
                        showFilters.toggle()
                    }
                } label: {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Toggle filters")
            }
        }
        .onAppear {
            searchViewModel.setup(modelContext: modelContext)
        }
    }

    // MARK: - Filter Chips

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Priority filter
                Menu {
                    Button("Any Priority") {
                        searchViewModel.filter.priority = nil
                    }
                    Divider()
                    ForEach(Priority.allCases, id: \.rawValue) { priority in
                        Button {
                            searchViewModel.filter.priority = priority
                        } label: {
                            HStack {
                                Text(priority.label)
                                if searchViewModel.filter.priority == priority {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(
                        title: searchViewModel.filter.priority?.label ?? "Priority",
                        isActive: searchViewModel.filter.priority != nil,
                        systemImage: "flag"
                    )
                }

                // Date range filter
                Menu {
                    Button("Any Date") {
                        searchViewModel.filter.startDate = nil
                        searchViewModel.filter.endDate = nil
                    }
                    Divider()
                    Button("Today") {
                        let start = Calendar.current.startOfDay(for: Date())
                        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
                        searchViewModel.filter.startDate = start
                        searchViewModel.filter.endDate = end
                    }
                    Button("This Week") {
                        let start = Calendar.current.startOfDay(for: Date())
                        let end = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: start)!
                        searchViewModel.filter.startDate = start
                        searchViewModel.filter.endDate = end
                    }
                    Button("This Month") {
                        let start = Calendar.current.startOfDay(for: Date())
                        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)!
                        searchViewModel.filter.startDate = start
                        searchViewModel.filter.endDate = end
                    }
                } label: {
                    filterChip(
                        title: dateFilterTitle,
                        isActive: searchViewModel.filter.startDate != nil,
                        systemImage: "calendar"
                    )
                }

                // Tag filters
                ForEach(searchViewModel.availableTags) { tag in
                    let isSelected = searchViewModel.filter.selectedTagIds.contains(tag.id)
                    Button {
                        withAnimation(AttentionAnimation.springSnappy) {
                            searchViewModel.toggleTagFilter(tag)
                        }
                    } label: {
                        filterChip(
                            title: tag.title,
                            isActive: isSelected,
                            color: Color(hex: tag.color)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Group by project toggle
                Button {
                    withAnimation(AttentionAnimation.springDefault) {
                        searchViewModel.filter.groupByProject.toggle()
                    }
                } label: {
                    filterChip(
                        title: "Group by Project",
                        isActive: searchViewModel.filter.groupByProject,
                        systemImage: "list.bullet"
                    )
                }
                .buttonStyle(.plain)

                // Clear filters
                if searchViewModel.filter.isActive {
                    Button {
                        withAnimation(AttentionAnimation.springDefault) {
                            searchViewModel.clearFilters()
                        }
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(Color.attentionDanger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateFilterTitle: String {
        if searchViewModel.filter.startDate != nil {
            return "Date Set"
        }
        return "Date"
    }

    @ViewBuilder
    private func filterChip(title: String, isActive: Bool, systemImage: String? = nil, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isActive ? (color ?? Color.attentionPrimary).opacity(0.15) : Color.clear)
        )
        .foregroundStyle(isActive ? (color ?? Color.attentionPrimary) : .secondary)
        .overlay(
            Capsule()
                .strokeBorder(
                    isActive ? (color ?? Color.attentionPrimary).opacity(0.5) : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(searchViewModel.groupedResults) { group in
                Section {
                    ForEach(group.todos) { todo in
                        searchResultRow(todo)
                    }
                } header: {
                    if searchViewModel.filter.groupByProject {
                        Text(group.title)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func searchResultRow(_ todo: Todo) -> some View {
        Button {
            todoListViewModel.selectedTodo = todo
        } label: {
            HStack(spacing: 10) {
                // Priority indicator
                Circle()
                    .fill(priorityColor(for: todo.priority))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    highlightedText(todo.title, query: searchViewModel.searchQuery)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let project = todo.project {
                            Label(project.title, systemImage: "list.bullet")
                                .font(.caption)
                                .foregroundStyle(Color.attentionPrimary)
                        }

                        if let date = todo.scheduledDate {
                            Label(date.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !todo.tags.isEmpty {
                            ForEach(todo.tags.prefix(2)) { tag in
                                Text(tag.title)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: tag.color).opacity(0.15))
                                    .foregroundStyle(Color(hex: tag.color))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Text(todo.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        guard let range = lowercasedText.range(of: lowercasedQuery) else {
            return Text(text)
        }

        let before = String(text[text.startIndex..<range.lowerBound])
        let matched = String(text[range])
        let after = String(text[range.upperBound...])

        return Text(before) +
            Text(matched).bold().foregroundColor(Color.attentionPrimary) +
            Text(after)
    }

    private func priorityColor(for priority: Priority) -> Color {
        switch priority {
        case .none: .clear
        case .low: .blue
        case .medium: .orange
        case .high: Color.attentionDanger
        }
    }
}
