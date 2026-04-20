import SwiftUI

@main
struct JiraMenuApp: App {
    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
        } label: {
            Image(systemName: "magnifyingglass.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
