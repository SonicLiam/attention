import SwiftUI
import SwiftData

struct QuickEntryView: View {
    @Environment(TodoListViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedDate: Date = Date()
    @State private var hasDate = false
    @State private var selectedProject: Project?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Title bar
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.attentionPrimary)
                    .font(.title3)

                Text("Quick Entry")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Title field
            TextField("What do you need to do?", text: $title)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isTitleFocused)
                .onSubmit { createAndDismiss() }

            Divider()

            // Options row
            HStack(spacing: 16) {
                // Date toggle
                Toggle(isOn: $hasDate) {
                    Label("Date", systemImage: "calendar")
                        .font(.callout)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)

                if hasDate {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .controlSize(.small)
                }

                Spacer()

                // Project picker
                Picker(selection: $selectedProject) {
                    Text("No Project").tag(nil as Project?)
                    ForEach(viewModel.projects) { project in
                        Text(project.title).tag(project as Project?)
                    }
                } label: {
                    Label("Project", systemImage: "list.bullet")
                        .font(.callout)
                }
                .controlSize(.small)
                .frame(maxWidth: 200)
            }

            // Action buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Add To-Do") {
                    createAndDismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color.attentionPrimary)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            isTitleFocused = true
        }
    }

    private func createAndDismiss() {
        guard !title.isEmpty else { return }
        let date = hasDate ? selectedDate : nil
        viewModel.createTodoWithDetails(
            title: title,
            scheduledDate: date,
            project: selectedProject
        )
        dismiss()
    }
}
