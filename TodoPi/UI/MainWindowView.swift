import SwiftUI

struct MainWindowView: View {
    var body: some View {
        HSplitView {
            placeholderPanel(
                title: "Todos",
                systemImage: "checklist",
                description: "Lists and tasks will live here."
            )
            .frame(minWidth: 320)

            placeholderPanel(
                title: "Chat with pi",
                systemImage: "message",
                description: "This panel will host the conversation UI and input box."
            )
            .frame(minWidth: 320)
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func placeholderPanel(title: String, systemImage: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.title2)
                .fontWeight(.semibold)

            Text(description)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    MainWindowView()
}
