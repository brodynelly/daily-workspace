import Foundation

/// Renders Moment.js format strings (the syntax Obsidian uses for daily-note names and `{{date:…}}`).
///
/// Tokens are matched in Moment's own order, longest first, so `MMM` is never read as `MM` + `M`.
/// Supported: `YYYY YY Q M MM MMM MMMM D DD Do d dd ddd dddd H HH h hh m mm s ss A a`, `[literal]`
/// and `\x` escapes. Letters Moment does not treat as tokens pass through unchanged, as in Moment.
/// Moment tokens this renderer does not implement (week numbers, day of year, locale formats such as `L`,
/// time zones, …) are refused rather than guessed, because a guessed file name puts a note in the wrong place.
public struct MomentFormat {
    /// The tokens `string(_:for:)` renders, for showing in Settings.
    public static let supportedTokens = [
        "YYYY", "YY", "Q", "M", "MM", "MMM", "MMMM", "D", "DD", "Do", "d", "dd", "ddd", "dddd",
        "H", "HH", "h", "hh", "m", "mm", "s", "ss", "A", "a",
    ]

    /// Obsidian's default locale is English, and note names must match the ones it creates.
    public static let englishLocale = Locale(identifier: "en_US_POSIX")

    /// Moment always counts in the Gregorian calendar, in the current time zone.
    public static func gregorianCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public let calendar: Calendar
    public let locale: Locale
    private let months: [String]
    private let shortMonths: [String]
    private let weekdays: [String]
    private let shortWeekdays: [String]
    private let amSymbol: String
    private let pmSymbol: String

    public init(calendar: Calendar = MomentFormat.gregorianCalendar(), locale: Locale = MomentFormat.englishLocale) {
        self.calendar = calendar
        self.locale = locale
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        months = formatter.monthSymbols
        shortMonths = formatter.shortMonthSymbols
        weekdays = formatter.weekdaySymbols
        shortWeekdays = formatter.shortWeekdaySymbols
        amSymbol = formatter.amSymbol
        pmSymbol = formatter.pmSymbol
    }

    /// `format` rendered for `date`. Throws `VaultError.invalidTemplate` for a Moment token it does not support.
    public func string(_ format: String, for date: Date) throws -> String {
        let fields = Fields(
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date))
        var output = ""
        for piece in Self.tokenize(format) {
            switch piece {
            case .literal(let text): output += text
            case .token(let token): output += render(token, fields)
            case .unsupported(let token): throw VaultError.invalidTemplate("unsupported format token “\(token)”")
            }
        }
        return output
    }

    /// Vault-relative path of a note: `folder` (taken literally, as Obsidian does) joined with `format` rendered
    /// for `date`, which may contain `/` for date-based subfolders, plus `.md`.
    ///
    /// Refuses empty, `.` or `..` segments, hidden segments and characters Obsidian forbids in file names,
    /// so the result can never point outside the folder or at a different file than intended.
    public func notePath(folder: String, format: String, for date: Date) throws -> String {
        var folderPart = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        while folderPart.hasPrefix("/") { folderPart.removeFirst() }
        while folderPart.hasSuffix("/") { folderPart.removeLast() }
        let folderSegments = folderPart.isEmpty ? [] : folderPart.components(separatedBy: "/")
        let segments = try folderSegments + string(format, for: date).components(separatedBy: "/")
        for segment in segments { try Self.validate(segment) }
        var path = segments.joined(separator: "/")
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        return path
    }

    private static let forbiddenCharacters = CharacterSet(charactersIn: "\\:*?\"<>|\0")

    private static func validate(_ segment: String) throws {
        if segment.trimmingCharacters(in: .whitespaces).isEmpty {
            throw VaultError.invalidTemplate("empty path segment")
        }
        if segment == "." || segment == ".." {
            throw VaultError.invalidTemplate("“\(segment)” is not allowed in a path")
        }
        if segment.hasPrefix(".") { throw VaultError.invalidTemplate("hidden folders and files are not allowed") }
        if segment.rangeOfCharacter(from: forbiddenCharacters) != nil {
            throw VaultError.invalidTemplate("“\(segment)” contains a character not allowed in a file name")
        }
    }

    // MARK: Rendering

    /// The calendar fields a numeric token prints.
    struct Fields {
        let year, shortYear, quarter, month, day, weekday, hour, hour12, minute, second: Int

        init(_ c: DateComponents) {
            year = c.year ?? 1970
            shortYear = year % 100
            month = c.month ?? 1
            quarter = (month - 1) / 3 + 1
            day = c.day ?? 1
            weekday = (c.weekday ?? 1) - 1  // Moment: 0 = Sunday
            hour = c.hour ?? 0
            hour12 = hour % 12 == 0 ? 12 : hour % 12
            minute = c.minute ?? 0
            second = c.second ?? 0
        }
    }

    enum WeekdayStyle {
        case min, short, long
    }

    enum Token: Equatable {
        /// A number, zero-padded to `width`.
        case number(KeyPath<Fields, Int>, width: Int)
        case monthName(short: Bool)
        case weekdayName(WeekdayStyle)
        case ordinalDay
        case meridiem(uppercase: Bool)
    }

    private func render(_ token: Token, _ f: Fields) -> String {
        switch token {
        case .number(let field, let width): return Self.pad(f[keyPath: field], width)
        case .monthName(let short): return (short ? shortMonths : months)[f.month - 1]
        case .weekdayName(.min): return String(shortWeekdays[f.weekday].prefix(2))
        case .weekdayName(.short): return shortWeekdays[f.weekday]
        case .weekdayName(.long): return weekdays[f.weekday]
        case .ordinalDay: return Self.englishOrdinal(f.day)
        case .meridiem(let uppercase):
            let symbol = f.hour < 12 ? amSymbol : pmSymbol
            return uppercase ? symbol : symbol.lowercased()
        }
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        return (value < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func englishOrdinal(_ n: Int) -> String {
        if (n % 100) / 10 == 1 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    // MARK: Tokenizing

    enum Piece: Equatable {
        case literal(String)
        case token(Token)
        case unsupported(String)
    }

    private typealias Entry = (pattern: String, tokens: [Token]?)

    /// Moment's formatting regex, alternative by alternative in its order, each optional part expanded longest
    /// first. The first entry that matches at a position wins, as regex alternation does. Nil tokens mark a
    /// Moment token this renderer refuses. Immutable after initialization; `nonisolated(unsafe)` only because the
    /// key paths inside `Token` are not `Sendable`.
    nonisolated(unsafe) private static let table: [Entry] = {
        func number(_ field: KeyPath<Fields, Int>, _ width: Int = 1) -> [Token] { [.number(field, width: width)] }
        func refused(_ patterns: [String]) -> [Entry] { patterns.map { ($0, nil) } }
        // `Hmm`, `Hmmss`, `hmm` and `hmmss` are single Moment tokens that print like `H` + `mm` (+ `ss`).
        var table: [Entry] = [
            ("Hmmss", number(\.hour) + number(\.minute, 2) + number(\.second, 2)),
            ("Hmm", number(\.hour) + number(\.minute, 2)),
            ("hmmss", number(\.hour12) + number(\.minute, 2) + number(\.second, 2)),
            ("hmm", number(\.hour12) + number(\.minute, 2)),
            ("Mo", nil),
            ("MMMM", [.monthName(short: false)]), ("MMM", [.monthName(short: true)]),
            ("MM", number(\.month, 2)), ("M", number(\.month)),
            ("Do", [.ordinalDay]),
            ("DDDo", nil), ("DDDD", nil), ("DDD", nil),
            ("DD", number(\.day, 2)), ("D", number(\.day)),
            ("dddd", [.weekdayName(.long)]), ("ddd", [.weekdayName(.short)]), ("dd", [.weekdayName(.min)]),
            ("do", nil), ("d", number(\.weekday)),
        ]
        table += refused(["wo", "w|", "ww", "w", "Wo", "W|", "WW", "W"])
        table += [("Qo", nil), ("Q", number(\.quarter))]
        table += refused(["NNNNN", "NNNN", "NNN", "NN", "N", "YYYYYY", "YYYYY"])
        table += [("YYYY", number(\.year, 4)), ("YY", number(\.shortYear, 2))]
        table += refused(["yyyy", "yyy", "yy", "yo", "y", "ggggg", "gggg", "gg", "GGGGG", "GGGG", "GG", "e", "E"])
        table += [
            ("a", [.meridiem(uppercase: false)]), ("A", [.meridiem(uppercase: true)]),
            ("hh", number(\.hour12, 2)), ("h", number(\.hour12)),
            ("HH", number(\.hour, 2)), ("H", number(\.hour)),
            ("kk", nil), ("k", nil),
            ("mm", number(\.minute, 2)), ("m", number(\.minute)),
            ("ss", number(\.second, 2)), ("s", number(\.second)),
        ]
        table += refused((1...9).reversed().map { String(repeating: "S", count: $0) })
        // Single characters with a meaning: `Y` (year) and the locale formats `L…`/`l…` Moment expands first.
        table += refused(["x", "X", "zz", "z", "ZZ", "Z", "Y", "L", "l"])
        return table
    }()

    /// Splits `format` the way Moment does: `[…]` literals first, then an optional backslash escape, then the
    /// table above, then any single character as a literal.
    static func tokenize(_ format: String) -> [Piece] {
        let chars = Array(format)
        var pieces: [Piece] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "[", let close = bracketEnd(chars, from: i) {
                pieces.append(.literal(String(chars[(i + 1)..<close])))
                i = close + 1
            } else if chars[i] == "\\" {
                // `\X` prints X, or a whole token, literally; a trailing backslash prints nothing.
                guard i + 1 < chars.count else { break }
                let length = match(chars, at: i + 1)?.pattern.count ?? 1
                pieces.append(.literal(String(chars[(i + 1)..<(i + 1 + length)])))
                i += 1 + length
            } else if let entry = match(chars, at: i) {
                pieces += entry.tokens.map { $0.map(Piece.token) } ?? [.unsupported(entry.pattern)]
                i += entry.pattern.count
            } else {
                pieces.append(.literal(String(chars[i])))
                i += 1
            }
        }
        return pieces
    }

    private static func match(_ chars: [Character], at i: Int) -> Entry? {
        table.first { entry in
            let pattern = Array(entry.pattern)
            return i + pattern.count <= chars.count && Array(chars[i..<(i + pattern.count)]) == pattern
        }
    }

    /// Index of the `]` closing the `[` at `start`: the last `]` before the next `[`, as Moment's greedy regex.
    private static func bracketEnd(_ chars: [Character], from start: Int) -> Int? {
        var end = start + 1
        while end < chars.count && chars[end] != "[" { end += 1 }
        return chars[(start + 1)..<end].lastIndex(of: "]")
    }
}
