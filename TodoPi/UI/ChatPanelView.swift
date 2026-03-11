import SwiftUI

struct ChatPanelView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Chat with pi", systemImage: "message")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                statusPill
            }

            transcript

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask pi to help manage your todos", text: $viewModel.draftMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit {
                        viewModel.sendDraft()
                    }

                Button("Send") {
                    viewModel.sendDraft()
                }
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.messages.isEmpty {
                    Text("The chat transcript will appear here once you start talking to pi.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(authorLabel(for: message.role))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(backgroundColor(for: message.role))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusPill: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusBackgroundColor)
            .clipShape(Capsule())
    }

    private func authorLabel(for role: ChatMessage.Role) -> String {
        switch role {
        case .user:
            return "You"
        case .assistant:
            return "TodoPi"
        case .system:
            return "System"
        }
    }

    private func backgroundColor(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user:
            return Color.accentColor.opacity(0.12)
        case .assistant:
            return Color.secondary.opacity(0.12)
        case .system:
            return Color.red.opacity(0.12)
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .offline:
            return "Offline"
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .busy:
            return "Busy"
        case .failed:
            return "Failed"
        }
    }

    private var statusBackgroundColor: Color {
        switch viewModel.status {
        case .offline:
            return Color.secondary.opacity(0.15)
        case .starting:
            return Color.orange.opacity(0.2)
        case .ready:
            return Color.green.opacity(0.2)
        case .busy:
            return Color.blue.opacity(0.2)
        case .failed:
            return Color.red.opacity(0.2)
        }
    }
}
