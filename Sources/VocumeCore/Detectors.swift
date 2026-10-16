import Foundation
import NaturalLanguage

/// A class of text Vocume finds by itself, so "redact all numbers" never depends on the AI listing
/// every number: the AI only names the class (`"detect": "numbers"`) and the app runs a fixed,
/// tested detector over all the OCR text. This is how redaction tools work (Presidio, Google's
/// Sensitive Data Protection, Snagit's Smart Redact): models choose, deterministic detectors find.
public enum TextKind: String, CaseIterable, Sendable {
    case numbers, emails, urls, phones, ips, dates, addresses, cards, ibans, ids, secrets, names
    case allText = "all text"
    case redText = "red text", orangeText = "orange text", yellowText = "yellow text"
    case greenText = "green text", blueText = "blue text", purpleText = "purple text", greyText = "grey text"

    /// The ink hue a colour kind looks for; `nil` for kinds found from the text.
    var color: InkColor? {
        switch self {
        case .redText: .red
        case .orangeText: .orange
        case .yellowText: .yellow
        case .greenText: .green
        case .blueText: .blue
        case .purpleText: .purple
        case .greyText: .grey
        default: nil
        }
    }

    /// Where this kind occurs in one line of OCR text. Colour kinds need the pixels and are found
    /// in ``RecognizedScreenshot/resolve(_:)`` instead.
    func ranges(in text: String) -> [Range<String.Index>] {
        // Names and whole lines are read from the text as it is ("Bjørn" stays a name).
        if self == .names { return Self.names(in: text) }
        if self == .allText { return text.isEmpty ? [] : [text.startIndex..<text.endIndex] }
        // The rest run on the folded text, whose ranges are only valid there until mapped back.
        let folded = Fold.digits(text)
        let found: [Range<String.Index>] =
            switch self {
            case .numbers: Self.numbers(in: folded)
            case .emails: Self.matches(Rules.email, in: folded) + Self.links(in: folded, mail: true)
            case .urls: Self.matches(Rules.url, in: folded) + Self.links(in: folded, mail: false)
            case .phones: Self.detected(.phoneNumber, in: folded) + Self.matches(Rules.phone, in: folded)
            case .ips: Self.matches(Rules.ipv4, in: folded) + Self.matches(Rules.ipv6, in: folded)
            case .dates: Self.detected(.date, in: folded) + Rules.dates.flatMap { Self.matches($0, in: folded) }
            case .addresses: Self.detected(.address, in: folded)
            case .cards: Self.matches(Rules.card, in: folded)
            case .ibans: Self.matches(Rules.iban, in: folded)
            case .ids: Self.matches(Rules.uuid, in: folded) + Self.matches(Rules.hex, in: folded)
            case .secrets: Self.secrets(in: folded)
            default: []
            }
        // Folding maps one character to one, so a range in the folded text is the same stretch of
        // the original; move it over by character offsets.
        let ranges = found.map { Fold.range($0, from: folded, to: text) }
        // A look-alike is a digit only beside a real one or after a sign ("-б" is "−6"): a lone
        // Cyrillic "о" is a letter.
        guard self == .numbers else { return ranges }
        return ranges.filter { text[$0].contains(where: \.isNumber) || "+-−–—".contains(text[$0].first ?? " ") }
    }

    // MARK: Finders

    private static func matches(_ regex: NSRegularExpression?, in text: String, group: Int = 0) -> [Range<String.Index>]
    {
        guard let regex else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: group), in: text)
        }.filter { !$0.isEmpty }
    }

    private static func detected(_ types: NSTextCheckingResult.CheckingType, in text: String) -> [Range<String.Index>] {
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text)
        }
    }

    /// Numbers, minus a lone 0, 1, 5 or 8 with letters on both sides: that is OCR reading a word's
    /// "l", "O", "S" or "B" as a digit ("marktp1atz"), and covering it would hide the whole word.
    private static func numbers(in text: String) -> [Range<String.Index>] {
        matches(Rules.number, in: text).filter { range in
            guard text[range].count == 1, "0158".contains(text[range]), range.lowerBound > text.startIndex,
                range.upperBound < text.endIndex
            else { return true }
            return !(text[text.index(before: range.lowerBound)].isLetter && text[range.upperBound].isLetter)
        }
    }

    /// Apple's link detector, split into email addresses and everything else.
    private static func links(in text: String, mail: Bool) -> [Range<String.Index>] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { result in
            (result.url?.scheme == "mailto") == mail ? Range(result.range, in: text) : nil
        }
    }

    /// Known key formats, the value after a secret's label ("token: …"), and long random-looking
    /// tokens (two or more character classes, Shannon entropy ≥ 3.5 bits, as gitleaks' generic rule).
    private static func secrets(in text: String) -> [Range<String.Index>] {
        let generic = matches(Rules.token, in: text).filter { range in
            let token = text[range]
            let classes = [
                token.contains(where: \.isLowercase), token.contains(where: \.isUppercase),
                token.contains(where: \.isNumber), token.contains { "+/=_.-".contains($0) },
            ]
            return classes.filter { $0 }.count >= 2 && entropy(token) >= 3.5
        }
        return matches(Rules.keyPrefix, in: text) + matches(Rules.labelledSecret, in: text, group: 1) + generic
    }

    private static func entropy(_ text: Substring) -> Double {
        let counts = Dictionary(text.map { ($0, 1.0) }, uniquingKeysWith: +).values
        let total = Double(text.count)
        return -counts.reduce(0) { $0 + $1 / total * log2($1 / total) }
    }

    /// People's names, from Apple's on-device name tagger.
    private static func names(in text: String) -> [Range<String.Index>] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .personalName { found.append(range) }
            return true
        }
        return found
    }
}

/// The ink hues the colour kinds look for.
enum InkColor: Sendable {
    case red, orange, yellow, green, blue, purple, grey

    /// The hue family of a colour given as hue (0–360°), saturation and brightness (0–1). Weakly
    /// saturated ink is grey (black and white text included), unless it is nearly black or white.
    init?(hue: Double, saturation: Double, brightness: Double) {
        if saturation < 0.25 {
            guard brightness > 0.2, brightness < 0.85 else { return nil }
            self = .grey
            return
        }
        switch hue {
        case ..<18, 340...: self = .red
        case ..<45: self = .orange
        case ..<70: self = .yellow
        case ..<170: self = .green
        case ..<255: self = .blue
        default: self = .purple
        }
    }
}

/// OCR's look-alikes. Vision reads a small "−6" as "-б", "0" as "О" (Cyrillic) or "ø", and the
/// minus sign as a dash, so detectors run on text where those read as what they show.
enum Fold {
    private static let digitLookalikes: [Character: Character] = [
        "б": "6", "Б": "6", "З": "3", "з": "3", "О": "0", "о": "0", "ø": "0", "Ø": "0",
        "−": "-", "–": "-", "—": "-",
    ]

    /// The text with look-alikes replaced one character for one, so ranges carry over by offset.
    static func digits(_ text: String) -> String {
        String(text.map { digitLookalikes[$0] ?? $0 })
    }

    /// The same characters' range in `original`, given a range in `folded` (equal lengths).
    static func range(_ range: Range<String.Index>, from folded: String, to original: String) -> Range<String.Index> {
        let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let length = folded.distance(from: range.lowerBound, to: range.upperBound)
        let lower = original.index(original.startIndex, offsetBy: start)
        return lower..<original.index(lower, offsetBy: length)
    }
}

/// The detectors' rules (ICU regular expressions), from Presidio, Google DLP, gitleaks and tests
/// against OCR output. Spaces are tolerated where OCR inserts them.
private enum Rules {
    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    static let number = regex(#"[+\-]?\p{N}+(?:[.,:'’_/\x{00A0}\x{202F}]\p{N}+)*%?"#)
    static let email = regex(#"[\p{L}\p{N}._%+'\-]+ ?@ ?[\p{L}\p{N}\-]+(?:\. ?[\p{L}\p{N}\-]+)+"#)
    static let url = regex(
        #"(?i)(?:[a-z][a-z0-9+.\-]*://|www\.)[^\s<>"']+|(?<![\w@.\-])(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}(?::\d{1,5})?(?:/[^\s<>"']*)?"#
    )
    static let phone = regex(#"(?<![\w+])\+?\(?\d[\d ()\-./]{5,}\d(?!\w)"#)
    static let ipv4 = regex(
        #"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:/\d{1,2})?(?![\d.]*\d)"#
    )
    static let ipv6 = regex(
        #"(?i)(?<![\w:])(?:[0-9a-f]{1,4}:|:){2,7}(?:[0-9a-f]{1,4}|:)(?:%[\w.]+)?(?:/\d{1,3})?(?![\w:])"#)
    static let dates = [
        regex(
            #"(?<!\d)(?:\d{4}[\-./]\d{1,2}[\-./]\d{1,2}|\d{1,2}[\-./]\d{1,2}[\-./]\d{2,4})(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+\-]\d{2}:?\d{2})?)?(?!\d)"#
        ),
        regex(#"(?<!\d)\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:\s?[AaPp]\.?[Mm]\.?)?(?!\d)"#),
    ]
    static let card = regex(#"(?<!\d)(?:\d[ \-\x{00A0}]?){12,18}\d(?!\d)"#)
    static let iban = regex(
        #"(?<![A-Z0-9])[A-Z]{2}\d{2}(?:[ \-\x{00A0}]?[A-Z0-9]{4}){2,7}(?:[ \-\x{00A0}]?[A-Z0-9]{1,3})?(?![\p{L}\p{N}])"#
    )
    static let uuid = regex(
        #"(?i)(?<![0-9a-f])[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}(?![0-9a-f])"#)
    static let hex = regex(#"(?i)(?<![0-9a-z])(?:0x)?[0-9a-f]{16,}(?![0-9a-z])"#)
    static let keyPrefix = regex(
        #"sk-ant-[\w\-]{20,}|sk-(?:proj-|svcacct-|admin-)?[\w\-]{20,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_\w{22,}|glpat-[\w\-]{20}|xox[baprs]-[\w\-]{10,}|(?:AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}|AIza[\w\-]{35}|(?:sk|rk|pk)_(?:live|test)_\w{10,}|eyJ[\w\-]{10,}\.eyJ[\w\-]{10,}\.[\w\-]*|-----BEGIN[ A-Z]*PRIVATE KEY-----"#
    )
    static let labelledSecret = regex(
        #"(?i)\b(?:api[_\- ]?key|secret|token|passw(?:or)?d|pwd|bearer|authorization|credential|private[_\- ]?key)[\w\-]*["']?\s*(?:[:=]>?|\s)\s*(?:bearer\s+)?["'`]?([^\s"'`]{6,})"#
    )
    static let token = regex(#"[A-Za-z0-9+/=_.\-]{20,}"#)
}
