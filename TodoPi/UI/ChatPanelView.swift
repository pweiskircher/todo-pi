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
                            Text(message.role == .user ? "You" : "TodoPi")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(message.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
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
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch viewModel.status {
        case .offline:
            return "Offline"
        }
    }
}
