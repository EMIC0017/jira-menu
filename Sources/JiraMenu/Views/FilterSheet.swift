import SwiftUI

/// Modal sheet for picking which projects the app should search in.
/// No selection = search all projects.
struct FilterSheet: View {
    let projects: [Project]
    let initialSelection: Set<String>
    let isLoading: Bool
    let errorMessage: String?
    let onApply: (Set<String>) -> Void
    let onCancel: () -> Void

    @State private var selection: Set<String> = []
    @State private var filterText: String = ""

    private var filtered: [Project] {
        guard !filterText.isEmpty else { return projects }
        let q = filterText.lowercased()
        return projects.filter {
            $0.name.lowercased().contains(q) || $0.key.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filter Projects").font(.title3).bold()
                Spacer()
                Button("Clear All") { selection = [] }
                    .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Text(selection.isEmpty
                 ? "Searching all projects"
                 : "Searching \(selection.count) project\(selection.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter projects", text: $filterText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Group {
                if isLoading && projects.isEmpty {
                    ProgressView("Loading projects…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorMessage {
                    Text(err).foregroundStyle(.red).padding(16)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filtered) { project in
                                Toggle(isOn: Binding(
                                    get: { selection.contains(project.key) },
                                    set: { on in
                                        if on { selection.insert(project.key) }
                                        else { selection.remove(project.key) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                        Text(project.key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply(selection) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 440)
        .onAppear { selection = initialSelection }
    }
}
