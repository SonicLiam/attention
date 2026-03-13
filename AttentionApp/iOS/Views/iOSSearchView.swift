import SwiftUI
import SwiftData

struct iOSSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TodoListViewModel.self) private var todoListViewModel
    @State private var searchViewModel = SearchViewModel()
    @State private var showFilterSheet = false

    var body: some View {
        @Bindable var vm = searchViewModel

        NavigationStack {
            Group {
                if searchViewModel.searchQuery.isEmpty && !searchViewModel.filter.isActive {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Search across all your todos")
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
            .searchable(text: $vm.searchQuery, prompt: "Search todos...")
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: searchViewModel.filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(searchViewModel.filter.isActive ? Color.attentionPrimary : .secondary)
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }
            .navigationDestination(for: Todo.self) { todo in
                iOSTodoDetailView(todo: todo)
            }
            .onAppear {
                searchViewModel.setup(modelContext: modelContext)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(searchViewModel.groupedResults) { group in
                Section {
                    ForEach(group.todos) { todo in
                        NavigationLink(value: todo) {
                            searchResultRow(todo)
                        }
                    }
                } header: {
                    if searchViewModel.filter.groupByProject {
                        Text(group.title)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func searchResultRow(_ todo: Todo) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(priorityColor(for: todo.priority))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
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
                        Text(todo.tags.map(\.title).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.attentionPrimary)
                    }
                }
            }

            Spacer()

            if todo.priority != .none {
                Circle()
                    .fill(priorityColor(for: todo.priority))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                // Priority
                Section("Priority") {
                    Picker("Priority", selection: Binding(
                        get: { searchViewModel.filter.priority },
                        set: { searchViewModel.filter.priority = $0 }
                    )) {
                        Text("Any").tag(nil as Priority?)
                        ForEach(Priority.allCases, id: \.self) { p in
                            Text(p.label).tag(p as Priority?)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Tags
                if !searchViewModel.availableTags.isEmpty {
                    Section("Tags") {
                        ForEach(searchViewModel.availableTags) { tag in
                            let isSelected = searchViewModel.filter.selectedTagIds.contains(tag.id)
                            Button {
                                searchViewModel.toggleTagFilter(tag)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: tag.color))
                                        .frame(width: 12, height: 12)
                                    Text(tag.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.attentionPrimary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Date Range
                Section("Date Range") {
                    Toggle("Start Date", isOn: Binding(
                        get: { searchViewModel.filter.startDate != nil },
                        set: { enabled in
                            searchViewModel.filter.startDate = enabled ? Calendar.current.startOfDay(for: Date()) : nil
                        }
                    ))
                    if let startDate = searchViewModel.filter.startDate {
                        DatePicker("From", selection: Binding(
                            get: { startDate },
                            set: { searchViewModel.filter.startDate = $0 }
                        ), displayedComponents: .date)
                        .tint(Color.attentionPrimary)
                    }

                    Toggle("End Date", isOn: Binding(
                        get: { searchViewModel.filter.endDate != nil },
                        set: { enabled in
                            searchViewModel.filter.endDate = enabled ? Calendar.current.date(byAdding: .month, value: 1, to: Date()) : nil
                        }
                    ))
                    if let endDate = searchViewModel.filter.endDate {
                        DatePicker("To", selection: Binding(
                            get: { endDate },
                            set: { searchViewModel.filter.endDate = $0 }
                        ), displayedComponents: .date)
                        .tint(Color.attentionPrimary)
                    }
                }

                // Grouping
                Section("Display") {
                    Toggle("Group by Project", isOn: Binding(
                        get: { searchViewModel.filter.groupByProject },
                        set: { searchViewModel.filter.groupByProject = $0 }
                    ))
                }

                // Clear
                if searchViewModel.filter.isActive {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            searchViewModel.clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
