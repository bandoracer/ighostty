import SwiftUI
import AppKit

// MARK: - Theme browser

/// A searchable, grouped gallery for picking a color scheme. Replaces the flat
/// dropdown that listed all ~500 schemes by name with no preview. Schemes are
/// grouped into Custom / Featured / Ghostty Catalog, rendered as live swatch
/// cards, filtered by an instant search field, and applied live on selection
/// (with Cancel to revert to the scheme that was active when the sheet opened).
struct ThemeBrowser: View {
    let appearance: AppearanceVariant
    let customSchemes: [ColorScheme]
    let onApply: (ColorScheme) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedName: String
    private let original: ColorScheme

    init(
        appearance: AppearanceVariant,
        current: ColorScheme,
        customSchemes: [ColorScheme],
        onApply: @escaping (ColorScheme) -> Void
    ) {
        self.appearance = appearance
        self.customSchemes = customSchemes
        self.onApply = onApply
        self.original = current
        _selectedName = State(initialValue: current.name)
    }

    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 240), spacing: 12)]

    private struct SchemeGroup: Identifiable {
        let id: String
        let title: String
        let schemes: [ColorScheme]
    }

    private var groups: [SchemeGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        func match(_ list: [ColorScheme]) -> [ColorScheme] {
            needle.isEmpty ? list : list.filter { $0.name.lowercased().contains(needle) }
        }

        var result: [SchemeGroup] = []

        let custom = match(customSchemes)
        if !custom.isEmpty { result.append(SchemeGroup(id: "custom", title: "Custom", schemes: custom)) }

        let featured = match(ColorScheme.featuredBuiltIns(for: appearance))
        if !featured.isEmpty { result.append(SchemeGroup(id: "featured", title: "Featured", schemes: featured)) }

        // Catalog entries that duplicate a Custom/Featured name are dropped so a
        // theme appears once (matching the precedence the flat list used).
        let shown = Set(custom.map(\.name)).union(featured.map(\.name))
        let catalog = match(ColorScheme.catalogSchemes(for: appearance)).filter { !shown.contains($0.name) }
        if !catalog.isEmpty { result.append(SchemeGroup(id: "catalog", title: "Ghostty Catalog", schemes: catalog)) }

        return result
    }

    private var totalCount: Int { groups.reduce(0) { $0 + $1.schemes.count } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 660, height: 580)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(appearance.label) Theme")
                    .font(.headline)
                Text(query.isEmpty ? "\(totalCount) themes" : "\(totalCount) of \(allCount) match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            searchField
        }
        .padding(16)
    }

    private var allCount: Int {
        customSchemes.count
            + ColorScheme.featuredBuiltIns(for: appearance).count
            + ColorScheme.catalogSchemes(for: appearance).count
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search themes", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 180)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if totalCount == 0 {
            VStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No themes match “\(query)”")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(group.schemes) { scheme in
                                    Button {
                                        select(scheme)
                                    } label: {
                                        ThemeCard(scheme: scheme, isSelected: scheme.name == selectedName)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        } header: {
                            sectionHeader(group.title, count: group.schemes.count)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Selected:").foregroundStyle(.secondary)
                Text(selectedName).fontWeight(.medium)
            }
            .font(.callout)
            .lineLimit(1)
            Spacer()
            Button("Cancel") {
                onApply(original)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func select(_ scheme: ColorScheme) {
        selectedName = scheme.name
        onApply(scheme)
    }
}

// MARK: - Theme card

/// A compact live preview of one color scheme: a mini terminal sample on the
/// scheme's own background, an ANSI swatch strip, and the name.
struct ThemeCard: View {
    let scheme: ColorScheme
    let isSelected: Bool

    @State private var isHovering = false

    private func color(_ c: TermColor) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            HStack(spacing: 4) {
                Text(scheme.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            color(scheme.background)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("❯ ").foregroundColor(color(scheme.ansi[2]))
                    Text("git ").foregroundColor(color(scheme.foreground))
                    Text("commit").foregroundColor(color(scheme.ansi[4]))
                }
                HStack(spacing: 0) {
                    Text("+ ").foregroundColor(color(scheme.ansi[2]))
                    Text("done ").foregroundColor(color(scheme.foreground))
                    Text("▍").foregroundColor(color(scheme.cursor))
                }
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color(scheme.ansi[i]))
                            .frame(maxWidth: .infinity)
                            .frame(height: 7)
                    }
                }
                .padding(.top, 3)
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 0.35 : 0.15),
                    lineWidth: isSelected ? 2.5 : 1
                )
        )
        .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 4, y: 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
