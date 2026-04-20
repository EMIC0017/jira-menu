import SwiftUI

/// In-popover filter view. Replaces the search body when the user taps the
/// filter icon. Writes selections through to ProjectFilterStore immediately,
/// so closing with Back or Done just navigates — nothing to save.
struct FilterPanel: View {
    let onDone: () -> Void

    @EnvironmentObject private var filter: ProjectFilterStore
    @EnvironmentObject private var projectsStore: ProjectsStore
    @State private var filterText: String = ""

    private var filtered: [Project] {
        let base: [Project]
        if filterText.isEmpty {
            base = projectsStore.projects
        } else {
            let q = filterText.lowercased()
            base = projectsStore.projects.filter {
                $0.name.lowercased().contains(q) || $0.key.lowercased().contains(q)
            }
        }
        // Pin selected projects to the top, preserving alphabetical order
        // within each partition. Skip the rearrangement when nothing is
        // selected so the list stays in its natural order.
        guard !filter.selected.isEmpty else { return base }
        let selected = filter.selected
        let (on, off) = base.reduce(into: ([Project](), [Project]())) { acc, project in
            if selected.contains(project.key) {
                acc.0.append(project)
            } else {
                acc.1.append(project)
            }
        }
        return on + off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .task { await projectsStore.loadIfNeeded() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Filter Projects").font(.title3).bold()
                Text(filter.selected.isEmpty
                     ? "Searching all projects"
                     : "Searching \(filter.selected.count) project\(filter.selected.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear All") { filter.clear() }
                .disabled(filter.selected.isEmpty)
            Button {
                Task { await projectsStore.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload project list")
        }
        .padding(12)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter projects by name or code", text: $filterText)
                .textFieldStyle(.plain)
            if !filterText.isEmpty {
                Button { filterText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if projectsStore.isLoading && projectsStore.projects.isEmpty {
            ProgressView("Loading projects…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = projectsStore.errorMessage {
            VStack(spacing: 8) {
                Text(err).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Retry") { Task { await projectsStore.load() } }
            }
            .padding(16)
        } else if filtered.isEmpty {
            Text(filterText.isEmpty ? "No projects found" : "No matches for “\(filterText)”")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { project in
                        projectRow(project)
                        Divider()
                    }
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        Toggle(isOn: Binding(
            get: { filter.selected.contains(project.key) },
            set: { on in
                var next = filter.selected
                if on { next.insert(project.key) } else { next.remove(project.key) }
                filter.set(next)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Button("Back", action: onDone)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Changes apply immediately")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
