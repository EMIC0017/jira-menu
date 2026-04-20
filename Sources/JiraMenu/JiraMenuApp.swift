import SwiftUI

@main
struct JiraMenuApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Hello from menubar")
                .padding()
        } label: {
            Image(systemName: "magnifyingglass.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
