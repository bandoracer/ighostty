import AppKit

// MARK: - Colors

/// A plain sRGB color value (components 0...1) used throughout settings.
struct TermColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            r: Double((v >> 16) & 0xFF) / 255.0,
            g: Double((v >> 8) & 0xFF) / 255.0,
            b: Double(v & 0xFF) / 255.0
        )
    }

    var hexString: String {
        String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Color schemes

struct ColorScheme: Codable, Equatable, Hashable, Identifiable {
    var name: String
    /// Exactly 16 entries: the standard + bright ANSI colors.
    var ansi: [TermColor]
    var foreground: TermColor
    var background: TermColor
    var cursor: TermColor
    var cursorText: TermColor
    var selection: TermColor

    var id: String { name }

    var isLight: Bool {
        (0.299 * background.r + 0.587 * background.g + 0.114 * background.b) > 0.6
    }
}

enum GhosttyAppError: LocalizedError {
    case invalidColorScheme(String)
    case invalidITermConfig(String)

    var errorDescription: String? {
        switch self {
        case .invalidColorScheme(let why): return "Could not import color scheme: \(why)"
        case .invalidITermConfig(let why): return "Could not import iTerm2 config: \(why)"
        }
    }
}

extension ColorScheme {
    static func make(_ name: String, bg: String, fg: String, cursor: String, selection: String, ansi: [String]) -> ColorScheme {
        ColorScheme(
            name: name,
            ansi: ansi.map { TermColor(hex: $0) },
            foreground: TermColor(hex: fg),
            background: TermColor(hex: bg),
            cursor: TermColor(hex: cursor),
            cursorText: TermColor(hex: bg),
            selection: TermColor(hex: selection)
        )
    }

    static func builtIns(for appearance: AppearanceVariant) -> [ColorScheme] {
        switch appearance {
        case .light: return lightBuiltIns
        case .dark: return darkBuiltIns
        }
    }

    static let builtIns: [ColorScheme] = darkBuiltIns
    static let defaultLight = lightBuiltIns.first { $0.name == "Codex" } ?? lightBuiltIns[0]
    static let defaultDark = darkBuiltIns.first { $0.name == "Codex" } ?? darkBuiltIns[0]

    private struct Palette {
        var bg: String
        var fg: String
        var selection: String
        var ansi: [String]
    }

    private static func theme(_ name: String, light: Palette, dark: Palette) -> (light: ColorScheme, dark: ColorScheme) {
        (
            light: .make(name, bg: light.bg, fg: light.fg, cursor: light.fg, selection: light.selection, ansi: light.ansi),
            dark: .make(name, bg: dark.bg, fg: dark.fg, cursor: dark.fg, selection: dark.selection, ansi: dark.ansi)
        )
    }

    private static func p(_ bg: String, _ fg: String, _ selection: String, _ ansi: [String]) -> Palette {
        Palette(bg: bg, fg: fg, selection: selection, ansi: ansi)
    }

    private static let codexThemePairs: [(light: ColorScheme, dark: ColorScheme)] = [
        theme("Codex",
              light: p("FFFFFF", "0D0D0D", "DCE7F7", ["0D0D0D", "D14D41", "0F7B5C", "A06400", "1F6FEB", "8250DF", "0A7C86", "F4F4F4", "666666", "E5534B", "129C73", "B7791F", "3B82F6", "A855F7", "0891B2", "FFFFFF"]),
              dark: p("0D0D0D", "F4F4F4", "263A36", ["161616", "FF6B5F", "34D399", "FBBF24", "60A5FA", "C084FC", "22D3EE", "D4D4D4", "737373", "FF8A80", "6EE7B7", "FDE68A", "93C5FD", "D8B4FE", "67E8F9", "FFFFFF"])),
        theme("Ayu",
              light: p("FAFAFA", "5C6773", "E6EEF7", ["000000", "F07171", "86B300", "F2AE49", "36A3D9", "A37ACC", "4CBF99", "ABB0B6", "828C99", "F07171", "86B300", "F2AE49", "36A3D9", "A37ACC", "4CBF99", "5C6773"]),
              dark: p("0A0E14", "B3B1AD", "253340", ["01060E", "EA6C73", "91B362", "F9AF4F", "53BDFA", "FAE994", "90E1C6", "C7C7C7", "686868", "F07178", "C2D94C", "FFB454", "59C2FF", "FFEE99", "95E6CB", "FFFFFF"])),
        theme("Catppuccin",
              light: p("EFF1F5", "4C4F69", "CCD0DA", ["5C5F77", "D20F39", "40A02B", "DF8E1D", "1E66F5", "EA76CB", "179299", "ACB0BE", "6C6F85", "E64553", "40A02B", "DF8E1D", "1E66F5", "EA76CB", "179299", "BCC0CC"]),
              dark: p("1E1E2E", "CDD6F4", "585B70", ["45475A", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "BAC2DE", "585B70", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "A6ADC8"])),
        theme("Dracula",
              light: p("F8F8F2", "282A36", "E7E2F4", ["282A36", "D92055", "2B8A3E", "A06A00", "3B5CCC", "8A3FFC", "087F8C", "D6D6D2", "6272A4", "FF5555", "50A060", "B58B00", "6272E8", "BD5FFF", "009FB7", "FFFFFF"]),
              dark: p("282A36", "F8F8F2", "44475A", ["21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2", "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF"])),
        theme("Everforest",
              light: p("FDF6E3", "5C6A72", "E8DFCA", ["5C6A72", "F85552", "8DA101", "DFA000", "3A94C5", "DF69BA", "35A77C", "E0D5B5", "879598", "F85552", "8DA101", "DFA000", "3A94C5", "DF69BA", "35A77C", "FDF6E3"]),
              dark: p("2D353B", "D3C6AA", "475258", ["343F44", "E67E80", "A7C080", "DBBC7F", "7FBBB3", "D699B6", "83C092", "D3C6AA", "475258", "E67E80", "A7C080", "DBBC7F", "7FBBB3", "D699B6", "83C092", "FDF6E3"])),
        theme("GitHub",
              light: p("FFFFFF", "24292F", "DDF4FF", ["24292F", "CF222E", "116329", "4D2D00", "0969DA", "8250DF", "1B7C83", "F6F8FA", "57606A", "A40E26", "1A7F37", "9A6700", "218BFF", "A475F9", "3192AA", "FFFFFF"]),
              dark: p("0D1117", "C9D1D9", "1F6FEB", ["484F58", "FF7B72", "3FB950", "D29922", "58A6FF", "BC8CFF", "39C5CF", "B1BAC4", "6E7681", "FFA198", "56D364", "E3B341", "79C0FF", "D2A8FF", "56D4DD", "F0F6FC"])),
        theme("Gruvbox",
              light: p("FBF1C7", "3C3836", "EBDBB2", ["3C3836", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984", "928374", "9D0006", "79740E", "B57614", "076678", "8F3F71", "427B58", "7C6F64"]),
              dark: p("282828", "EBDBB2", "504945", ["282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984", "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2"])),
        theme("Linear",
              light: p("F7F8FA", "171717", "DCE0FF", ["171717", "D14343", "198754", "A76F00", "5E6AD2", "8B5CF6", "0E7490", "E5E7EB", "6B7280", "EF4444", "22C55E", "EAB308", "6C7CFF", "A78BFA", "06B6D4", "FFFFFF"]),
              dark: p("08090A", "F7F8FA", "252B43", ["17181A", "F87171", "4ADE80", "FACC15", "6C7CFF", "C084FC", "22D3EE", "D1D5DB", "6B7280", "FCA5A5", "86EFAC", "FDE047", "93A3FF", "D8B4FE", "67E8F9", "FFFFFF"])),
        theme("Lobster",
              light: p("FFF7F2", "3A1F1A", "F6D7CA", ["3A1F1A", "D84A35", "3F8C5A", "B97814", "2878A8", "B05A87", "238A8A", "F1D7C8", "8F6257", "F06A4D", "55A66D", "D79A2B", "3B95C4", "D36FA5", "36A8A8", "FFFFFF"]),
              dark: p("21110F", "F6D7C8", "4A2C28", ["2E1815", "FF6B4A", "65C987", "F0B84F", "5DADE2", "F08BBF", "55D6D0", "E8C8B8", "8A5A50", "FF8A6B", "8EE6A8", "FFD36E", "85C8F2", "F7A8D2", "7AE6E0", "FFF7F2"])),
        theme("Material",
              light: p("FAFAFA", "263238", "E3F2FD", ["263238", "E53935", "43A047", "F9A825", "1E88E5", "8E24AA", "00ACC1", "ECEFF1", "607D8B", "EF5350", "66BB6A", "FDD835", "42A5F5", "AB47BC", "26C6DA", "FFFFFF"]),
              dark: p("263238", "EEFFFF", "314549", ["000000", "F07178", "C3E88D", "FFCB6B", "82AAFF", "C792EA", "89DDFF", "EEFFFF", "546E7A", "FF5370", "C3E88D", "FFCB6B", "82AAFF", "C792EA", "89DDFF", "FFFFFF"])),
        theme("Matrix",
              light: p("F3FFF3", "0B3D0B", "CFEFD0", ["0B3D0B", "B42318", "008F11", "6C8500", "0E7490", "5B3B8C", "047857", "D8F5D8", "357A35", "D92D20", "00C853", "A3B300", "0891B2", "7C3AED", "10B981", "FFFFFF"]),
              dark: p("000000", "00FF41", "003B12", ["001100", "FF2A6D", "00CC33", "D7FF00", "00A7FF", "B967FF", "00E5C0", "C8FFC8", "006B1A", "FF5C8A", "00FF41", "F2FF66", "66D9FF", "D199FF", "66FFE6", "FFFFFF"])),
        theme("Monokai",
              light: p("FDF9F3", "272822", "EFE4C9", ["272822", "F92672", "4E8A24", "A66F00", "1E70BF", "9B4DCA", "1F8A70", "E6DB74", "75715E", "F92672", "66A61E", "B58900", "268BD2", "AE81FF", "2AA198", "FFFFFF"]),
              dark: p("272822", "F8F8F2", "49483E", ["272822", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "F8F8F2", "75715E", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "FFFFFF"])),
        theme("Absolutely",
              light: p("FFFFFF", "111827", "E5E7EB", ["111827", "DC2626", "16A34A", "CA8A04", "2563EB", "9333EA", "0891B2", "E5E7EB", "6B7280", "EF4444", "22C55E", "EAB308", "3B82F6", "A855F7", "06B6D4", "FFFFFF"]),
              dark: p("000000", "FFFFFF", "303030", ["000000", "EF4444", "22C55E", "EAB308", "3B82F6", "A855F7", "06B6D4", "D4D4D4", "737373", "F87171", "4ADE80", "FACC15", "60A5FA", "C084FC", "22D3EE", "FFFFFF"])),
        theme("Night Owl",
              light: p("FBFBFB", "403F53", "DDEAFE", ["011627", "D3423E", "2AA298", "DAAA01", "4876D6", "A626A4", "08916A", "E0E7FF", "637777", "F76E6E", "49B6B1", "DAC26B", "5CA7E4", "C792EA", "00C990", "FFFFFF"]),
              dark: p("011627", "D6DEEB", "1D3B53", ["011627", "EF5350", "22DA6E", "C5E478", "82AAFF", "C792EA", "21C7A8", "D6DEEB", "575656", "EF5350", "22DA6E", "FFEB95", "82AAFF", "C792EA", "7FDBCA", "FFFFFF"])),
        theme("Nord",
              light: p("ECEFF4", "2E3440", "D8DEE9", ["3B4252", "BF616A", "A3BE8C", "D08770", "5E81AC", "B48EAD", "88C0D0", "E5E9F0", "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "FFFFFF"]),
              dark: p("2E3440", "D8DEE9", "434C5E", ["3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0", "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4"])),
        theme("Notion",
              light: p("FDFCF9", "37352F", "E9E5DC", ["37352F", "EB5757", "0F7B6C", "CB912F", "2F80ED", "9B51E0", "0F7B8A", "F1EFEA", "787774", "EB5757", "27AE60", "F2C94C", "2D9CDB", "BB6BD9", "56CCF2", "FFFFFF"]),
              dark: p("191919", "F7F6F3", "333333", ["202020", "FF7369", "4DAB9A", "FFDC49", "529CCA", "9A6DD7", "4DAB9A", "D4D4D4", "6B6B6B", "FF9C92", "6FE0C3", "FFE36E", "7AB8E6", "C9A3FF", "7DE3D0", "FFFFFF"])),
        theme("Oscurange",
              light: p("FFF8F0", "322018", "F2D1B0", ["322018", "D0452F", "5E8C31", "B56D00", "2F74C0", "A44A8F", "168A8A", "F3DEC8", "8B5E3C", "F0643C", "76A64A", "D9901F", "4F8FD8", "C665A9", "30A6A6", "FFFFFF"]),
              dark: p("1B120B", "F7D7B5", "4A2B15", ["24170E", "FF5F3A", "9AD66B", "FFB84D", "6AA6FF", "E07AC3", "55D6C2", "EBC8A4", "8F5A2B", "FF7A55", "B4F27E", "FFD27A", "8ABFFF", "F0A1D8", "7DEBE0", "FFF8F0"])),
        theme("One",
              light: p("FAFAFA", "383A42", "E5E5E6", ["383A42", "E45649", "50A14F", "C18401", "4078F2", "A626A4", "0184BC", "E5E5E6", "A0A1A7", "E45649", "50A14F", "C18401", "4078F2", "A626A4", "0184BC", "FFFFFF"]),
              dark: p("282C34", "ABB2BF", "3E4451", ["282C34", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF", "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF"])),
        theme("Proof",
              light: p("FFFFFE", "111111", "D8D8D8", ["111111", "C1121F", "0B6E4F", "A16207", "1D4ED8", "7E22CE", "0E7490", "E5E5E5", "555555", "DC2626", "15803D", "CA8A04", "2563EB", "9333EA", "0891B2", "FFFFFF"]),
              dark: p("101010", "F5F5F5", "303030", ["101010", "EF4444", "22C55E", "F59E0B", "3B82F6", "A855F7", "06B6D4", "D4D4D4", "737373", "F87171", "4ADE80", "FBBF24", "60A5FA", "C084FC", "22D3EE", "FFFFFF"])),
        theme("Raycast",
              light: p("FFFFFF", "1F1F23", "FFE0E0", ["1F1F23", "FF6363", "28C76F", "FFB020", "3B82F6", "A855F7", "00B8D9", "F2F2F2", "6B7280", "FF8585", "4ADE80", "FACC15", "60A5FA", "C084FC", "22D3EE", "FFFFFF"]),
              dark: p("141416", "FFFFFF", "402020", ["1F1F23", "FF6363", "28C76F", "FFB020", "3B82F6", "A855F7", "00B8D9", "E5E7EB", "6B7280", "FF8585", "4ADE80", "FACC15", "60A5FA", "C084FC", "22D3EE", "FFFFFF"])),
        theme("Rose Pine",
              light: p("FAF4ED", "575279", "DFDAD9", ["575279", "B4637A", "286983", "EA9D34", "56949F", "907AA9", "D7827E", "F2E9E1", "9893A5", "B4637A", "286983", "EA9D34", "56949F", "907AA9", "D7827E", "FFFaf3"]),
              dark: p("191724", "E0DEF4", "403D52", ["26233A", "EB6F92", "9CCFD8", "F6C177", "31748F", "C4A7E7", "EBBCBA", "E0DEF4", "6E6A86", "EB6F92", "9CCFD8", "F6C177", "31748F", "C4A7E7", "EBBCBA", "FFFFFF"])),
        theme("Sentry",
              light: p("FFFFFF", "2B2233", "ECE5F4", ["2B2233", "E03E2F", "2E7D32", "B7791F", "6C5FC7", "8A3FFC", "088F8F", "F3F0F6", "746A80", "F05A48", "43A047", "D69E2E", "7D6FE8", "A66CFF", "21B6B6", "FFFFFF"]),
              dark: p("1F1726", "F4EFFA", "392C45", ["2B2233", "FF6A5A", "7DD37D", "F5C451", "8B7CF6", "C084FC", "4DD0CF", "DAD1E5", "746A80", "FF8A7A", "A3E7A3", "F8D56E", "A69BFF", "D8B4FE", "7DE8E6", "FFFFFF"])),
        theme("Solarized",
              light: p("FDF6E3", "657B83", "EEE8D5", ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5", "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"]),
              dark: p("002B36", "839496", "073642", ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5", "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"])),
        theme("Temple",
              light: p("FFF9ED", "322A1F", "EADCC5", ["322A1F", "A83E32", "557A42", "A66A1F", "3C6E91", "8C5A8C", "3A8176", "EFE3D0", "776A5A", "C94A3D", "6A994E", "C98324", "4F86A8", "A76AA8", "4CA194", "FFFFFF"]),
              dark: p("211A14", "EDE0CF", "423226", ["2C231A", "D65A4A", "83B06B", "D79A3D", "6AA0C8", "C08AC0", "62C1B1", "DDCBB7", "80705E", "F07866", "9CCD82", "F0B457", "8ABBDD", "D7A5D7", "83D8CC", "FFF9ED"])),
        theme("Tokyo Night",
              light: p("E1E2E7", "3760BF", "C4C8DA", ["343B58", "F52A65", "587539", "8C6C3E", "2E7DE9", "9854F1", "007197", "D5D6DB", "9699A3", "F52A65", "587539", "8C6C3E", "2E7DE9", "9854F1", "007197", "FFFFFF"]),
              dark: p("1A1B26", "C0CAF5", "283457", ["15161E", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "A9B1D6", "414868", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "C0CAF5"])),
        theme("Vercel",
              light: p("FFFFFF", "000000", "EAEAEA", ["000000", "E5484D", "30A46C", "F5A524", "0070F3", "7928CA", "00A3A3", "EAEAEA", "666666", "FF4D4F", "52C41A", "FADB14", "3291FF", "A855F7", "00D4D4", "FFFFFF"]),
              dark: p("000000", "FFFFFF", "333333", ["000000", "FF4D4F", "52C41A", "FADB14", "3291FF", "A855F7", "00D4D4", "D4D4D4", "666666", "FF7875", "73D13D", "FFEC3D", "69B1FF", "C084FC", "5CDBD3", "FFFFFF"])),
        theme("VSCode Plus",
              light: p("FFFFFF", "1F1F1F", "ADD6FF", ["000000", "CD3131", "00BC00", "949800", "0451A5", "BC05BC", "0598BC", "CCCCCC", "666666", "CD3131", "14CE14", "B5BA00", "0451A5", "BC05BC", "0598BC", "FFFFFF"]),
              dark: p("1E1E1E", "D4D4D4", "264F78", ["000000", "F44747", "6A9955", "DCDCAA", "569CD6", "C586C0", "4EC9B0", "D4D4D4", "666666", "F44747", "B5CEA8", "DCDCAA", "9CDCFE", "C586C0", "4EC9B0", "FFFFFF"])),
        theme("Xcode",
              light: p("FFFFFF", "1F1F24", "D7E8FF", ["1F1F24", "C41A16", "326D20", "9B5D00", "0A65D8", "7A3E9D", "0F7B8C", "ECECEC", "6E6E73", "E12D39", "3B8A28", "B76E00", "0A84FF", "9C4DCC", "18A0B5", "FFFFFF"]),
              dark: p("292A30", "FFFFFF", "3D4F66", ["1F2026", "FF8170", "78C2B3", "D9C97C", "6CB6FF", "D9A6FF", "7FDBDA", "DCDCDC", "7F8490", "FFA198", "9CE6D5", "F0DB8C", "8CC8FF", "E5C7FF", "A3F0E8", "FFFFFF"])),
        theme("Classic",
              light: p("FFFFFF", "000000", "D9E8FF", ["000000", "CC0000", "008000", "A66F00", "2666CC", "CC00CC", "008B8B", "E5E5E5", "4D4D4D", "FF0000", "00AA00", "B58900", "5C5CFF", "FF00FF", "00AAAA", "FFFFFF"]),
              dark: p("000000", "BFBFBF", "4D4D4D", ["000000", "CC0000", "00CC00", "CCCC00", "2666CC", "CC00CC", "00CCCC", "E5E5E5", "4D4D4D", "FF0000", "00FF00", "FFFF00", "5C5CFF", "FF00FF", "00FFFF", "FFFFFF"])),
    ]

    private static let lightBuiltIns: [ColorScheme] = codexThemePairs.map(\.light)
    private static let darkBuiltIns: [ColorScheme] = codexThemePairs.map(\.dark)

    /// Parses an iTerm2 `.itermcolors` property list.
    static func fromITermColors(url: URL) throws -> ColorScheme {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GhosttyAppError.invalidColorScheme("not a property list")
        }
        func component(_ dict: [String: Any], _ key: String) -> Double? {
            (dict[key] as? NSNumber)?.doubleValue
        }
        func color(_ key: String) -> TermColor? {
            guard let d = plist[key] as? [String: Any],
                  let r = component(d, "Red Component"),
                  let g = component(d, "Green Component"),
                  let b = component(d, "Blue Component") else { return nil }
            return TermColor(r: r, g: g, b: b)
        }
        var ansi: [TermColor] = []
        for i in 0..<16 {
            guard let c = color("Ansi \(i) Color") else {
                throw GhosttyAppError.invalidColorScheme("missing Ansi \(i) Color")
            }
            ansi.append(c)
        }
        let bg = color("Background Color") ?? TermColor(hex: "000000")
        let fg = color("Foreground Color") ?? TermColor(hex: "BFBFBF")
        return ColorScheme(
            name: url.deletingPathExtension().lastPathComponent,
            ansi: ansi,
            foreground: fg,
            background: bg,
            cursor: color("Cursor Color") ?? fg,
            cursorText: color("Cursor Text Color") ?? bg,
            selection: color("Selection Color") ?? TermColor(hex: "4D4D4D")
        )
    }
}

// MARK: - Profile

enum CursorShape: String, Codable, CaseIterable, Identifiable {
    case block, underline, bar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .block: return "Block"
        case .underline: return "Underline"
        case .bar: return "Bar"
        }
    }
}

enum WorkingDirectoryOption: String, Codable, CaseIterable, Identifiable {
    case home, inherit, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Home directory"
        case .inherit: return "Reuse previous session’s directory"
        case .custom: return "Custom directory"
        }
    }
}

enum CloseOnExit: String, Codable, CaseIterable, Identifiable {
    case always, cleanExit, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: return "Close the pane"
        case .cleanExit: return "Close only on clean exit"
        case .never: return "Keep the pane open"
        }
    }
}

struct Profile: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var name = "Default"

    // Command
    var useLoginShell = true
    var customShellPath = ""          // empty -> $SHELL
    var shellArguments: [String] = []
    var initialCommand = ""
    var workingDirectory: WorkingDirectoryOption = .inherit
    var customWorkingDirectory = "~"
    /// One KEY=VALUE per line.
    var environmentOverrides = ""

    // Text
    var fontName = ""                 // empty -> system monospace (SF Mono)
    var fontSize: Double = 13
    var cursorShape: CursorShape = .block
    var cursorBlink = true

    // Colors / window
    var scheme: ColorScheme = ColorScheme.defaultDark
    var lightScheme: ColorScheme = ColorScheme.defaultLight
    var darkScheme: ColorScheme = ColorScheme.defaultDark
    /// iTerm2 semantics: 0 = fully opaque, higher = more see-through.
    var transparency: Double = 0.0
    var blurEnabled: Bool = false
    /// Background blur radius (iTerm2's "Blur" radius), applied when transparent.
    var blurRadius: Double = 16
    /// When true (default), transparency also makes the title bar see-through;
    /// when false, the title bar stays opaque while the content is transparent.
    var transparentTitleBar: Bool = true
    var padding: Double = 8
    var columns = 120
    var rows = 30

    // Terminal behavior
    var scrollbackLines = 10_000
    var unlimitedScrollback = false
    var termVariable = "xterm-256color"
    var optionAsMeta = true
    var mouseReporting = true
    var audibleBell = true
    var visualBell = false
    var closeOnExit: CloseOnExit = .cleanExit

    static let placeholder = Profile(name: "—")

    var environmentDictionary: [String: String] {
        var out: [String: String] = [:]
        for line in environmentOverrides.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...])
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}

// Tolerant decoding so settings files from older builds keep working, and the
// pre-iTerm2 `opacity`/`blur` fields migrate to `transparency`/`blurEnabled`.
// In an extension so the memberwise `Profile(...)` initializer is preserved.
extension Profile {
    private enum LegacyKeys: String, CodingKey {
        case opacity, blur
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        func val<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init()
        id = val(.id, d.id)
        name = val(.name, d.name)
        useLoginShell = val(.useLoginShell, d.useLoginShell)
        customShellPath = val(.customShellPath, d.customShellPath)
        shellArguments = val(.shellArguments, d.shellArguments)
        initialCommand = val(.initialCommand, d.initialCommand)
        workingDirectory = val(.workingDirectory, d.workingDirectory)
        customWorkingDirectory = val(.customWorkingDirectory, d.customWorkingDirectory)
        environmentOverrides = val(.environmentOverrides, d.environmentOverrides)
        fontName = val(.fontName, d.fontName)
        fontSize = val(.fontSize, d.fontSize)
        cursorShape = val(.cursorShape, d.cursorShape)
        cursorBlink = val(.cursorBlink, d.cursorBlink)
        let legacyScheme = val(.scheme, d.scheme)
        scheme = legacyScheme
        lightScheme = val(.lightScheme, legacyScheme)
        darkScheme = val(.darkScheme, legacyScheme)
        padding = val(.padding, d.padding)
        columns = val(.columns, d.columns)
        rows = val(.rows, d.rows)
        scrollbackLines = val(.scrollbackLines, d.scrollbackLines)
        unlimitedScrollback = val(.unlimitedScrollback, d.unlimitedScrollback)
        termVariable = val(.termVariable, d.termVariable)
        optionAsMeta = val(.optionAsMeta, d.optionAsMeta)
        mouseReporting = val(.mouseReporting, d.mouseReporting)
        audibleBell = val(.audibleBell, d.audibleBell)
        visualBell = val(.visualBell, d.visualBell)
        closeOnExit = val(.closeOnExit, d.closeOnExit)
        blurRadius = val(.blurRadius, d.blurRadius)
        transparentTitleBar = val(.transparentTitleBar, d.transparentTitleBar)

        // transparency: prefer the new key, else migrate legacy opacity (1 - opacity).
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        if let t = (try? c.decodeIfPresent(Double.self, forKey: .transparency)) ?? nil {
            transparency = t
        } else if let op = (try? legacy?.decodeIfPresent(Double.self, forKey: .opacity)) ?? nil {
            transparency = min(max(1 - op, 0), 1)
        } else {
            transparency = d.transparency
        }
        if let b = (try? c.decodeIfPresent(Bool.self, forKey: .blurEnabled)) ?? nil {
            blurEnabled = b
        } else if let legacyBlur = (try? legacy?.decodeIfPresent(Bool.self, forKey: .blur)) ?? nil {
            // Old default blur=true only ever did anything when transparent; keep it.
            blurEnabled = legacyBlur && transparency > 0
        } else {
            blurEnabled = d.blurEnabled
        }
    }
}

// MARK: - App-level settings

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum AppearanceVariant: String, Codable, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

extension Profile {
    func colorScheme(for appearance: AppearanceVariant) -> ColorScheme {
        switch appearance {
        case .light: return lightScheme
        case .dark: return darkScheme
        }
    }

    var activeColorScheme: ColorScheme {
        colorScheme(for: currentAppearanceVariant())
    }

    mutating func setUniformColorScheme(_ colorScheme: ColorScheme) {
        scheme = colorScheme
        lightScheme = colorScheme
        darkScheme = colorScheme
    }

    mutating func syncLegacyColorScheme() {
        scheme = darkScheme
    }
}

enum HotkeyActivationMode: String, Codable, CaseIterable, Identifiable {
    case doubleTapModifier, shortcut
    var id: String { rawValue }
    var label: String {
        switch self {
        case .doubleTapModifier: return "Double-tap a modifier key"
        case .shortcut: return "Keyboard shortcut"
        }
    }
}

enum WindowStyle: String, Codable, CaseIterable, Identifiable {
    case regular, compact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .regular: return "Standard title bar"
        case .compact: return "Compact — no title bar"
        }
    }
}

struct HotkeySettings: Codable, Equatable {
    var enabled = true
    var activationMode: HotkeyActivationMode = .doubleTapModifier
    var doubleTapModifier: UInt = NSEvent.ModifierFlags.control.rawValue
    var keyCode: UInt16 = 49 // Space
    var modifierFlags: UInt = NSEvent.ModifierFlags.option.rawValue
    var rows = 30
    var widthFraction: Double = 1.0
    var animationDuration: Double = 0.16
    var autoHide = true
    var followMouseScreen = true
    var profileID: UUID? = nil // nil -> default profile
    /// ⌘Q closes terminal windows but keeps the app (and the drop-down
    /// terminal) alive in the background; ⌥⌘Q quits completely.
    var keepAvailableInBackground = true

    init() {}

    // Lenient decoding so settings files written by older builds keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HotkeySettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil ?? d.enabled
        activationMode = (try? c.decodeIfPresent(HotkeyActivationMode.self, forKey: .activationMode)) ?? nil ?? d.activationMode
        doubleTapModifier = (try? c.decodeIfPresent(UInt.self, forKey: .doubleTapModifier)) ?? nil ?? d.doubleTapModifier
        keyCode = (try? c.decodeIfPresent(UInt16.self, forKey: .keyCode)) ?? nil ?? d.keyCode
        modifierFlags = (try? c.decodeIfPresent(UInt.self, forKey: .modifierFlags)) ?? nil ?? d.modifierFlags
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? nil ?? d.rows
        widthFraction = (try? c.decodeIfPresent(Double.self, forKey: .widthFraction)) ?? nil ?? d.widthFraction
        animationDuration = (try? c.decodeIfPresent(Double.self, forKey: .animationDuration)) ?? nil ?? d.animationDuration
        autoHide = (try? c.decodeIfPresent(Bool.self, forKey: .autoHide)) ?? nil ?? d.autoHide
        followMouseScreen = (try? c.decodeIfPresent(Bool.self, forKey: .followMouseScreen)) ?? nil ?? d.followMouseScreen
        profileID = (try? c.decodeIfPresent(UUID.self, forKey: .profileID)) ?? nil
        keepAvailableInBackground = (try? c.decodeIfPresent(Bool.self, forKey: .keepAvailableInBackground)) ?? nil ?? d.keepAvailableInBackground
    }
}

struct UISettings: Codable, Equatable {
    var theme: AppTheme = .system
    var windowStyle: WindowStyle = .regular
    var desaturateInactivePanes = true
    var desaturationAmount: Double = 0.15
    var copyOnSelect = false
    var confirmQuit = true
    var useMetalRenderer = true
    /// iTerm2's View > Use Transparency (⌘U): when off, profile opacity is
    /// ignored and every terminal renders fully opaque.
    var useTransparency = true

    init() {}

    private enum LegacyKeys: String, CodingKey {
        case dimInactivePanes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        let d = UISettings()
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? nil ?? d.theme
        windowStyle = (try? c.decodeIfPresent(WindowStyle.self, forKey: .windowStyle)) ?? nil ?? d.windowStyle
        desaturateInactivePanes = (try? c.decodeIfPresent(Bool.self, forKey: .desaturateInactivePanes))
            ?? nil
            ?? ((try? legacy?.decodeIfPresent(Bool.self, forKey: .dimInactivePanes)) ?? nil)
            ?? d.desaturateInactivePanes
        desaturationAmount = (try? c.decodeIfPresent(Double.self, forKey: .desaturationAmount)) ?? nil ?? d.desaturationAmount
        copyOnSelect = (try? c.decodeIfPresent(Bool.self, forKey: .copyOnSelect)) ?? nil ?? d.copyOnSelect
        confirmQuit = (try? c.decodeIfPresent(Bool.self, forKey: .confirmQuit)) ?? nil ?? d.confirmQuit
        useMetalRenderer = (try? c.decodeIfPresent(Bool.self, forKey: .useMetalRenderer)) ?? nil ?? d.useMetalRenderer
        useTransparency = (try? c.decodeIfPresent(Bool.self, forKey: .useTransparency)) ?? nil ?? d.useTransparency
    }
}

struct AppSettings: Codable, Equatable {
    var profiles: [Profile]
    var defaultProfileID: UUID
    var hotkey = HotkeySettings()
    var ui = UISettings()
    var customSchemes: [ColorScheme] = []

    static func freshDefault() -> AppSettings {
        var main = Profile(name: "Default")
        main.lightScheme = ColorScheme.defaultLight
        main.darkScheme = ColorScheme.defaultDark
        main.syncLegacyColorScheme()

        var tokyo = Profile(name: "Tokyo Night")
        tokyo.lightScheme = ColorScheme.builtIns(for: .light).first { $0.name == "Tokyo Night" } ?? ColorScheme.defaultLight
        tokyo.darkScheme = ColorScheme.builtIns(for: .dark).first { $0.name == "Tokyo Night" } ?? ColorScheme.defaultDark
        tokyo.syncLegacyColorScheme()

        var solarized = Profile(name: "Solarized")
        solarized.lightScheme = ColorScheme.builtIns(for: .light).first { $0.name == "Solarized" } ?? ColorScheme.defaultLight
        solarized.darkScheme = ColorScheme.builtIns(for: .dark).first { $0.name == "Solarized" } ?? ColorScheme.defaultDark
        solarized.syncLegacyColorScheme()

        return AppSettings(profiles: [main, tokyo, solarized], defaultProfileID: main.id)
    }
}
