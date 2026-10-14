import SwiftUI

struct AgentView: View {
    @Bindable var viewModel: AgentViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let note = viewModel.availabilityNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.yellow.opacity(0.15))
                }
                messageList
                if let proposal = viewModel.pendingNotificationProposal {
                    proposalCard(for: proposal)
                }
                if let proposal = viewModel.pendingReminderCreationProposal {
                    reminderCreationCard(for: proposal)
                }
                Divider()
                inputBar
            }
            .navigationTitle("PersonalAgent")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                viewModel.refreshAvailability()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if viewModel.isResponding {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Denkt nach…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func proposalCard(for proposal: NotificationProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Erinnerung bestätigen?")
                .font(.headline)
            Text(proposal.body)
            Text(
                "\(GermanDateText.dayText(for: proposal.fireDate, calendar: .current)), \(GermanDateText.timeText(proposal.fireDate, calendar: .current)) Uhr"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack {
                Button("Ablehnen") {
                    viewModel.declinePendingNotificationTapped()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Bestätigen") {
                    viewModel.confirmPendingNotificationTapped()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func reminderCreationCard(for proposal: ReminderCreationProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aufgabe anlegen?")
                .font(.headline)
            Text(proposal.title)
            if let notes = proposal.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let dueDate = proposal.dueDate {
                Text(
                    "Fällig: \(GermanDateText.dayText(for: dueDate, calendar: .current)), \(GermanDateText.timeText(dueDate, calendar: .current)) Uhr"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            HStack {
                Button("Ablehnen") {
                    viewModel.declinePendingReminderCreation()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Bestätigen") {
                    viewModel.confirmPendingReminderCreationTapped()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Nachricht…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    viewModel.sendCurrentInput()
                }
            Button("Senden") {
                viewModel.sendCurrentInput()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSend)
        }
        .padding()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            Text(message.displayText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(.tint.opacity(0.2))
                        : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: message.role == .user ? .trailing : .leading
                )
            if message.role == .agent {
                Spacer(minLength: 40)
            }
        }
    }
}
