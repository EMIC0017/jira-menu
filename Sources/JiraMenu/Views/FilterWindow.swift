import SwiftUI
import AppKit

/// Standalone resizable window for picking which projects to search in.
/// Writes changes through to ProjectFilterStore immediately; the window
/// persists its size automatically (macOS remembers window frames by id).
struct FilterWindow: View {
    @EnvironmentObject private var filter: ProjectFilterStore
    @EnvironmentObject private var projectsStore: ProjectsStore
    @State private var filterText: String = ""

    private var filtered: [Project] {
        guard !filterText.isEmpty else { return projectsStore.projects }
        let q = filterText.lowercased()
        return projectsStore.projects.filter {
            $0.name.lowercased().contains(q) || $0.key.lowercased().contains(q)
        }
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
        .frame(minWidth: 360, minHeight: 320)
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
            Text("Changes apply immediately. Close when you're done.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}
