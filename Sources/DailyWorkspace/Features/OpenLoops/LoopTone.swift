import DailyCore

/// The tone of an owner's native status. Unknown statuses, including Luuna's, stay neutral rather than inferred.
/// Finished items are not success: success requires verified evidence. Badge text stays verbatim.
enum LoopTone {
    static func tone(authority: LoopAuthority, nativeStatus: String) -> Tone {
        switch authority {
        case .local: return local(nativeStatus)
        case .reminders: return reminders(nativeStatus)
        case .luuna, .mail: return .neutral
        }
    }

    static func tone(for loop: OpenLoop) -> Tone {
        tone(authority: loop.authority, nativeStatus: loop.nativeStatus)
    }

    /// `OpenLoopsStore.localOpenStatus` and `localDoneStatus`.
    private static func local(_ status: String) -> Tone {
        status == "open" ? .attention : .neutral
    }

    /// `OpenLoopsStore.reminderOpenStatus`; a completed reminder is no longer listed.
    private static func reminders(_ status: String) -> Tone {
        status == "incomplete" ? .attention : .neutral
    }
}
