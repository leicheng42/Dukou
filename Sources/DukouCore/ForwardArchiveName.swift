import Foundation

/// Shared naming for exported chat and Moments ZIPs. Date ranges describe the
/// content only when both endpoints are known; otherwise the export is dated.
///
/// The user can rearrange the parts with a template. Whatever it says, a batch
/// number and `.zip` follow it, and the result is one portable file name.
public enum ForwardArchiveName {
    private static let maximumBytes = 200

    /// The name before templates existed, and what an empty template means.
    public static let defaultTemplate = "{名称}_{时间}_{条数}"

    /// Kept in Chinese in every language: a template written once has to mean
    /// the same after the app's language changes. Unknown braces stay text.
    public enum Token: String, CaseIterable, Sendable {
        case name = "{名称}", time = "{时间}", date = "{日期}", count = "{条数}"
    }

    public static func make(
        source: String,
        count: Int?,
        start: Date?,
        end: Date?,
        part: Int? = nil,
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current,
        template: String = defaultTemplate
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"

        let period: String
        if let start, let end,
           start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite {
            let first = formatter.string(from: min(start, end))
            let last = formatter.string(from: max(start, end))
            period = first == last ? first : "\(first)至\(last)"
        } else {
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            period = exportedAt.timeIntervalSince1970.isFinite
                ? "导出\(formatter.string(from: exportedAt))" : "导出时间未知"
        }
        formatter.dateFormat = "yyyyMMdd"
        let day = exportedAt.timeIntervalSince1970.isFinite ? formatter.string(from: exportedAt) : "日期未知"
        let quantity = count.flatMap { $0 >= 0 ? "\($0)条" : nil } ?? "条数未知"
        // Parts exported together must not paste as one repeated name.
        let suffix = (part.map { "_第\($0)批" } ?? "") + ".zip"
        let budget = maximumBytes - suffix.utf8.count

        var pattern = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.lowercased().hasSuffix(".zip") { pattern = String(pattern.dropLast(4)) }
        // Split on the name first, so a chat called 「{条数}」 stays its name.
        // The name alone gives way when the whole is too long, leaving the
        // dates, count and extension intact.
        let pieces = pattern.components(separatedBy: Token.name.rawValue).map {
            cleaned($0.replacingOccurrences(of: Token.time.rawValue, with: period)
                .replacingOccurrences(of: Token.date.rawValue, with: day)
                .replacingOccurrences(of: Token.count.rawValue, with: quantity))
        }
        var name = sanitized(source)
        if pieces.count > 1 {
            name = shortened(name, byteLimit: (budget - pieces.joined().utf8.count) / (pieces.count - 1))
        }
        let stem = escapingDevice(pieces.joined(separator: name).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        guard !stem.trimmingCharacters(in: CharacterSet(charactersIn: "._")).isEmpty else {
            return make(source: source, count: count, start: start, end: end, part: part, exportedAt: exportedAt, timeZone: timeZone)
        }
        return shortened(stem, byteLimit: budget) + suffix
    }

    private static func sanitized(_ source: String) -> String {
        let result = cleaned(source).trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        return result.isEmpty ? "记录" : escapingDevice(result)
    }

    private static func cleaned(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:<>\"'`|?*%")
        var result = ""
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            let category = scalar.properties.generalCategory
            if forbidden.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
                || [.control, .format, .lineSeparator, .paragraphSeparator].contains(category) {
                if !result.hasSuffix("_") { result.append("_") }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// A Windows device name remains reserved when followed by an extension.
    private static func escapingDevice(_ name: String) -> String {
        let base = name.split(separator: ".", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
        let devices = ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"]
            + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
            + ["¹", "²", "³"].flatMap { ["COM\($0)", "LPT\($0)"] }
        return devices.contains(base) ? "_" + name : name
    }

    private static func shortened(_ source: String, byteLimit: Int) -> String {
        guard source.utf8.count > byteLimit else { return source }
        let ellipsis = "…"
        var result = ""
        var bytes = 0
        // Cut only at character boundaries, leaving the complete date, count
        // and extension intact even for long names containing multibyte text.
        for character in source {
            let size = String(character).utf8.count
            guard bytes + size <= byteLimit - ellipsis.utf8.count else { break }
            result.append(character)
            bytes += size
        }
        return result.isEmpty ? "记录" : result + ellipsis
    }
}
