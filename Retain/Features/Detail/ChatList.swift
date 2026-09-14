import SwiftUI

/// Board 04's rail: one conversation about one recording.
///
/// It is only worth anything because of the chips under an answer. A small
/// model reading a transcript with recognition errors in it will be wrong
/// sometimes; a citation is what turns that from a confident lie into a claim
/// the reader can click and check.
struct ChatList: View {

    @Bindable var model: RecordingDetailModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: RetainMetrics.chatMessageGap) {
                        Text(verbatim: intro)
                            .retainStyle(RetainTypography.chatIntro)
                            .foregroundStyle(RetainPalette.inkLabel)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(model.turns) { turn in
                            ChatTurnView(turn: turn, width: contentWidth) { model.follow($0) }
                                .id(turn.id)
                        }

                        if model.isAnswering {
                            TypingIndicator()
                                .id(typingID)
                        }

                        if let failure = model.chatFailure {
                            Text(verbatim: failure)
                                .retainStyle(RetainTypography.chatMessageModel)
                                .foregroundStyle(RetainPalette.redInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(RetainMetrics.chatRailBody)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: model.turns.count) { scrollToEnd(scroll) }
                .onChange(of: model.isAnswering) { scrollToEnd(scroll) }
            }

            composer
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - What the rail says before it can be used

    /// The export draws the chat only in its ready state. The owner's decision
    /// is that it cannot be used until the recording has stopped *and* the
    /// summary is written, and the rail is on screen throughout both — so it
    /// says which of the two is still outstanding rather than failing when a
    /// question is sent.
    private var intro: String {
        model.chatAvailability == .ready
            ? DetailCopy.chatIntro
            : DetailCopy.chatNotReady(model.chatAvailability)
    }

    private var isReady: Bool { model.chatAvailability == .ready }

    /// `86%` and `92%` are fractions of the rail's own text column.
    private var contentWidth: CGFloat {
        RetainMetrics.chaptersRailWidth
            - RetainMetrics.chatRailBody.leading
            - RetainMetrics.chatRailBody.trailing
    }

    private let typingID = "typing"

    /// A new question, and the dots that follow it, both belong at the bottom
    /// of the rail — a conversation that answers off-screen has not answered.
    private func scrollToEnd(_ scroll: ScrollViewProxy) {
        if model.isAnswering {
            scroll.scrollTo(typingID, anchor: .bottom)
        } else if let last = model.turns.last {
            scroll.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Asking

    private var composer: some View {
        HStack(spacing: RetainMetrics.chatComposerGap) {
            TextField(text: $model.question) {
                Text(verbatim: DetailCopy.askPlaceholder)
            }
            .textFieldStyle(.plain)
            .retainStyle(RetainTypography.captionLarge)
            .foregroundStyle(RetainPalette.inkPrimary)
            .onSubmit { send() }
            .disabled(!isReady || model.isAnswering)

            Button(action: send) {
                Text(verbatim: "⏎")
                    .retainStyle(RetainTypography.enterHint)
                    .foregroundStyle(RetainPalette.inkLabel)
            }
            .buttonStyle(RetainSurfaceButtonStyle())
            .disabled(!isReady || model.isAnswering)
            .accessibilityLabel(Text(verbatim: DetailCopy.send))
        }
        .padding(RetainMetrics.chatComposerPadding)
        .background {
            RoundedRectangle(cornerRadius: RetainMetrics.radiusChatComposer, style: .continuous)
                .fill(RetainPalette.surfaceInsetControl)
        }
        .overlay {
            RoundedRectangle(cornerRadius: RetainMetrics.radiusChatComposer, style: .continuous)
                .strokeBorder(RetainPalette.lineControlBorder, lineWidth: 1)
        }
        .opacity(isReady ? 1 : RetainInteraction.disabledOpacity)
        .padding(RetainMetrics.chatComposerMargin)
    }

    private func send() {
        Task { await model.ask() }
    }
}

// MARK: - One turn

struct ChatTurnView: View {

    let turn: ChatTurn
    let width: CGFloat
    let follow: (ChatReference) -> Void

    var body: some View {
        switch turn.author {
        case .you: question
        case .model: answer
        }
    }

    /// A bubble with one corner cut — `12px 12px 4px 12px`, the short corner
    /// pointing back at the person who typed it.
    private var question: some View {
        Text(verbatim: turn.text)
            .retainStyle(RetainTypography.chatMessageYours)
            .foregroundStyle(RetainPalette.inkPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(RetainMetrics.chatBubblePadding)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: RetainMetrics.radiusChatBubble,
                    bottomLeadingRadius: RetainMetrics.radiusChatBubble,
                    bottomTrailingRadius: RetainMetrics.radiusChatBubbleTail,
                    topTrailingRadius: RetainMetrics.radiusChatBubble,
                    style: .continuous
                )
                .fill(RetainPalette.surfaceChatBubble)
            }
            .frame(maxWidth: width * RetainMetrics.chatBubbleMaxWidthFraction, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The model answers as plain text. No bubble: the board gives the answer
    /// the page rather than a container, which is what lets it be four
    /// sentences long in a rail this narrow without looking boxed in.
    private var answer: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.chatSourceChipTopGap) {
            Text(verbatim: turn.text)
                .retainStyle(RetainTypography.chatMessageModel)
                .foregroundStyle(RetainPalette.inkBody)
                .fixedSize(horizontal: false, vertical: true)

            if !turn.references.isEmpty {
                HStack(spacing: RetainMetrics.chatSourceChipGap) {
                    ForEach(Array(turn.references.enumerated()), id: \.offset) { _, reference in
                        SourceChip(reference: reference) { follow(reference) }
                    }
                }
            }
        }
        .frame(maxWidth: width * RetainMetrics.chatAnswerMaxWidthFraction, alignment: .leading)
    }
}

// MARK: - A citation

/// `00:38:20` or `Note 1` — a second in the audio, or a card in the notes.
/// Both are jump targets, which is the whole point of drawing them.
struct SourceChip: View {

    let reference: ChatReference
    let follow: () -> Void

    var body: some View {
        Button(action: follow) {
            Text(verbatim: label)
                .retainStyle(RetainTypography.chatSourceChip)
                .foregroundStyle(RetainPalette.blue)
                .padding(RetainMetrics.chatSourceChipPadding)
        }
        .buttonStyle(
            RetainSurfaceButtonStyle(
                cornerRadius: RetainMetrics.radiusChatSourceChip,
                border: RetainPalette.lineChipBorder
            )
        )
    }

    private var label: String {
        switch reference {
        case let .transcript(time): RetainTimeFormat.clock(time)
        case let .note(number): DetailCopy.noteChip(number)
        }
    }
}

// MARK: - Three dots

/// `breathe` at 1.4 seconds, the three dots 0.2 seconds apart. Standing still
/// under Reduce Motion, which `retainLoop` decides and this does not.
struct TypingIndicator: View {

    var body: some View {
        HStack(spacing: RetainMetrics.typingDotGap) {
            ForEach(Array(RetainMotion.typingIndicatorDelays.enumerated()), id: \.offset) { _, delay in
                Circle()
                    .fill(RetainPalette.inkFaintest)
                    .frame(width: RetainMetrics.statusDotSmall, height: RetainMetrics.statusDotSmall)
                    .retainLoop(.typingIndicator, delay: delay)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: DetailCopy.thinking))
    }
}
