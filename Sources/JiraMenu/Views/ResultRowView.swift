import SwiftUI

struct ResultRowView: View {
    let issue: Issue

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(issue.key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.summary)
                    .font(.body)
                    .lineLimit(1)
                Text("\(issue.issueType) · \(issue.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
