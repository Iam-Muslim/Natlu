import SwiftUI

struct MicBar: View {
    let isRecording: Bool, isVoiceSearching: Bool
    let colors: ThemeColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(isVoiceSearching ? colors.gold : isRecording ? colors.red : colors.green,
                            in: .rect(cornerRadius: 22))
                .shadow(color: (isRecording ? colors.red : colors.green).opacity(0.25), radius: 14, y: 7)
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
    }
}
