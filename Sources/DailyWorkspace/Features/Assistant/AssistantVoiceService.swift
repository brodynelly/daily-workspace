import AVFoundation
import AppKit
import Speech

/// Ephemeral voice controls for one visible Assistant composer. Dictation never submits a question.
@MainActor
final class AssistantVoiceService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var recognizedText = ""
    @Published private(set) var error: String?
    @Published private(set) var speaksReplies = false

    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var permissionTask: Task<Void, Never>?
    private var permissionMonitor: Timer?
    private var generation = 0

    /// Tracks the exact text inserted by this dictation session, not a matching suffix elsewhere.
    struct Draft {
        private var previousDraft: String?
        private var recognizedRange: Range<Int>?
        private var previousRecognition = ""
        private var userEditedRecognition = false

        mutating func update(_ existing: String, with recognized: String) -> String {
            guard !recognized.isEmpty, !userEditedRecognition else { return existing }

            if let previousDraft, let recognizedRange {
                guard
                    let start = adjustedStart(
                        in: existing, since: previousDraft, recognizedRange: recognizedRange
                    )
                else {
                    userEditedRecognition = true
                    return existing
                }

                guard start >= 0, start + recognizedRange.count <= existing.count else {
                    userEditedRecognition = true
                    return existing
                }
                let lower = existing.index(existing.startIndex, offsetBy: start)
                let upper = existing.index(lower, offsetBy: recognizedRange.count)
                guard existing[lower..<upper] == previousRecognition else {
                    userEditedRecognition = true
                    return existing
                }
                var result = existing
                result.replaceSubrange(lower..<upper, with: recognized)
                self.previousDraft = result
                self.recognizedRange = start..<(start + recognized.count)
                previousRecognition = recognized
                return result
            }

            var result = existing
            if !result.isEmpty, !result.hasSuffix(" ") { result += " " }
            let start = result.count
            result += recognized
            previousDraft = result
            recognizedRange = start..<(start + recognized.count)
            previousRecognition = recognized
            return result
        }

        private func adjustedStart(
            in existing: String, since previousDraft: String, recognizedRange: Range<Int>
        ) -> Int? {
            if existing == previousDraft { return recognizedRange.lowerBound }
            var prefix = 0
            var oldCursor = previousDraft.startIndex
            var newCursor = existing.startIndex
            while oldCursor < previousDraft.endIndex, newCursor < existing.endIndex,
                previousDraft[oldCursor] == existing[newCursor]
            {
                prefix += 1
                previousDraft.formIndex(after: &oldCursor)
                existing.formIndex(after: &newCursor)
            }

            var suffix = 0
            var oldTail = previousDraft.endIndex
            var newTail = existing.endIndex
            while oldTail > oldCursor, newTail > newCursor {
                let oldBefore = previousDraft.index(before: oldTail)
                let newBefore = existing.index(before: newTail)
                guard previousDraft[oldBefore] == existing[newBefore] else { break }
                suffix += 1
                oldTail = oldBefore
                newTail = newBefore
            }

            let oldChangedEnd = previousDraft.count - suffix
            if oldChangedEnd <= recognizedRange.lowerBound {
                return recognizedRange.lowerBound + existing.count - previousDraft.count
            }
            if prefix >= recognizedRange.upperBound { return recognizedRange.lowerBound }
            return nil
        }
    }

    func startDictation() {
        guard !isListening, !isRequestingPermission else { return }
        error = nil
        recognizedText = ""
        isRequestingPermission = true
        generation += 1
        let attempt = generation
        permissionTask = Task { [weak self] in
            guard let self else { return }
            await self.authorizeAndBegin(attempt: attempt)
        }
    }

    private func authorizeAndBegin(attempt: Int) async {
        defer {
            if generation == attempt {
                permissionTask = nil
                isRequestingPermission = false
            }
        }
        guard await Self.microphoneGranted() else {
            error = "Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone."
            return
        }
        guard !Task.isCancelled, generation == attempt else { return }
        guard await Self.speechGranted() else {
            error =
                "Speech Recognition access is off. "
                + "Enable it in System Settings → Privacy & Security → Speech Recognition."
            return
        }
        guard !Task.isCancelled, generation == attempt else { return }
        guard NSApp.isActive else {
            error = "Return to Daily Workspace to start dictation."
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            SFSpeechRecognizer.authorizationStatus() == .authorized
        else {
            error =
                "Microphone or Speech Recognition access changed. "
                + "Check System Settings before trying again."
            return
        }
        beginRecognition()
    }

    private static func microphoneGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    private static func speechGranted() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization {
                    continuation.resume(returning: $0 == .authorized)
                }
            }
        default: false
        }
    }

    func stopDictation() {
        generation += 1
        permissionTask?.cancel()
        permissionTask = nil
        permissionMonitor?.invalidate()
        permissionMonitor = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if recognitionRequest != nil { audioEngine.inputNode.removeTap(onBus: 0) }
        isRequestingPermission = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognizer = nil
        isListening = false
    }

    func setSpeaksReplies(_ enabled: Bool) {
        speaksReplies = enabled
        if !enabled { speechSynthesizer.stopSpeaking(at: .immediate) }
    }

    /// Only a finished AssistantTurn.finalAnswer is passed here, never tool output or streamed thinking.
    func speakAnswer(_ answer: String) {
        guard speaksReplies else { return }
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else {
            error = "Spoken replies are unavailable on this Mac."
            return
        }
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(AVSpeechUtterance(string: answer))
    }

    func stop() {
        stopDictation()
        setSpeaksReplies(false)
    }

    private func beginRecognition() {
        let recognizer = SFSpeechRecognizer(locale: .current)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device speech recognition is unavailable for this language or Mac. Audio was not recorded."
            return
        }
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "No microphone input is available."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognizer = recognizer
        recognitionRequest = request
        let attempt = generation
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, recognitionError in
            Task { @MainActor [weak self] in
                guard let self, self.generation == attempt else { return }
                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    if result.isFinal { self.stopDictation() }
                }
                if recognitionError != nil {
                    self.stopDictation()
                    self.error = "Dictation stopped. Check microphone and Speech Recognition access, then try again."
                }
            }
        }
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            permissionMonitor = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isListening else { return }
                    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                        SFSpeechRecognizer.authorizationStatus() == .authorized,
                        self.recognizer?.isAvailable == true
                    else {
                        self.stopDictation()
                        self.error =
                            "Dictation stopped because microphone or "
                            + "on-device speech recognition is unavailable."
                        return
                    }
                }
            }
        } catch {
            stopDictation()
            self.error = "The microphone could not start. Check your input device and try again."
        }
    }
}
