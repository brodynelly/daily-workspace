import DailyCore

/// The tone of an owner's own status, following Luuna's rule that green is earned.
///
/// - attention: waiting on Brody (the Org to-do keyword, `NEXT` and `WAIT`; Seeds and Plot `open`/`ready`; a local
///   task `open`; a reminder `incomplete`).
/// - active: the owner is working it (Seeds `in_progress`/`claimed`/`active`, Plot `drafting`/`active`).
/// - danger: blocked (Seeds `blocked`).
/// - neutral: recorded or finished (`DONE`, `CANCELLED`, `closed`, `completed`, `archived`), and every status this
///   table does not know.
///
/// A finished item is never success: success means a live connection or verified evidence, and no open-loop
/// status is either. The badge text is always `nativeStatus` verbatim; matching is exact, so a spelling the owner
/// did not use stays neutral instead of being guessed at.
enum LoopTone {
    static func tone(authority: LoopAuthority, nativeStatus: String) -> Tone {
        switch authority {
        case .org: return org(nativeStatus)
        case .seeds: return seeds(nativeStatus)
        case .plot: return plot(nativeStatus)
        case .local: return local(nativeStatus)
        case .reminders: return reminders(nativeStatus)
        case .luuna: return .neutral
        }
    }

    static func tone(for loop: OpenLoop) -> Tone {
        tone(authority: loop.authority, nativeStatus: loop.nativeStatus)
    }

    private static func org(_ status: String) -> Tone {
        switch status {
        case "TODO", "NEXT", "WAIT", "WAITING": return .attention
        default: return .neutral
        }
    }

    private static func seeds(_ status: String) -> Tone {
        switch status {
        case "open", "ready": return .attention
        case "in_progress", "claimed", "active": return .active
        case "blocked": return .danger
        default: return .neutral
        }
    }

    private static func plot(_ status: String) -> Tone {
        switch status {
        case "ready": return .attention
        case "drafting", "active": return .active
        default: return .neutral
        }
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
