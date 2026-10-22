import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppState.Section?>(
                get: { state.section },
                set: { if let value = $0 { state.section = value } }
            )) {
                ForEach(AppState.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
            .safeAreaInset(edge: .bottom) {
                Button {
                    state.showQuickCapture = true
                } label: {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(10)
                .help("Quick capture (⌘N)")
            }
        } detail: {
            Group {
                switch state.section {
                case .today: TodayView()
                case .notes: NotesView()
                case .tasks: TasksView()
                case .calendar: CalendarView()
                }
            }
            .id(state.section)
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.section)
        .sheet(isPresented: $state.showQuickCapture) {
            QuickCaptureSheet()
        }
    }
}

struct QuickCaptureSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var asTask = true
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Capture").font(.headline)
            TextField("What's on your mind?", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            Picker("Save as", selection: $asTask) {
                Text("Task for today").tag(true)
                Text("Line in today's note").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Save as")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Capture", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { focused = true }
    }

    private func commit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.capture(text, asTask: asTask)
        dismiss()
    }
}
