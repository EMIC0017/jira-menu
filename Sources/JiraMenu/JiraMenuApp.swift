import SwiftUI

@main
struct JiraMenuApp: App {
    @StateObject private var filterStore = ProjectFilterStore()
    @StateObject private var projectsStore = ProjectsStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environmentObject(filterStore)
                .environmentObject(projectsStore)
        } label: {
            Image(systemName: "magnifyingglass.circle")
        }
        .menuBarExtraStyle(.window)

        Window("Project Filter", id: "jiramenu.filter") {
            FilterWindow()
                .environmentObject(filterStore)
                .environmentObject(projectsStore)
        }
        .defaultSize(width: 420, height: 480)
    }
}
