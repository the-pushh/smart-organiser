import SwiftUI

struct SummonView: View {
    @ObservedObject var model: OrganiserModel
    let focus: PromptInputFocus
    let dismiss: () -> Void
    @State private var showError = false
    private let accent = Color(red: 0.68, green: 0.9, blue: 0.74)

    var body: some View {
        HStack(spacing: 14) {
            PromptInput(text: $model.taskText, enabled: !model.busy, focus: focus,
                submit: { model.generate() }, dismiss: dismiss)
                .frame(maxWidth: .infinity).frame(height: 25)
            if let error = model.error {
                Button { showError.toggle() } label: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.plain).help(error)
                .accessibilityLabel("Show arrangement error")
                .popover(isPresented: $showError) {
                    Text(error).font(.callout).textSelection(.enabled).padding(16).frame(width: 340)
                }
            }
            Toggle("Vibe", isOn: $model.vibeEnabled)
                .toggleStyle(.switch).controlSize(.small).fixedSize().tint(accent)
                .disabled(model.busy).help("Include a music app")
            if model.busy {
                Button { model.cancel() } label: {
                    ZStack {
                        ProgressView().controlSize(.small)
                        Image(systemName: "stop.fill").font(.system(size: 6))
                    }.frame(width: 34, height: 34)
                }.buttonStyle(.plain).help("Stop arranging").accessibilityLabel("Stop arranging")
            } else {
                Button { model.generate() } label: {
                    Image(systemName: "return").font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 34)
                        .foregroundStyle(Color.black.opacity(0.85))
                        .background(accent.opacity(canSubmit ? 1 : 0.25), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).disabled(!canSubmit)
                    .help("Close current windows and open the chosen apps · Return. Closing windows cannot be undone.").accessibilityLabel("Arrange workspace")
            }
        }
        .padding(.horizontal, 20).frame(width: 720, height: 72)
        .background(Color(red: 0.08, green: 0.095, blue: 0.086), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.16), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
        .onChange(of: model.vibeEnabled) { _, _ in focus.focus() }
        .onChange(of: model.error) { _, error in showError = error != nil }
    }
    private var canSubmit: Bool { !model.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(enabled ? 0.85 : 0.5))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color(red: 0.68, green: 0.9, blue: 0.74).opacity(enabled ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
