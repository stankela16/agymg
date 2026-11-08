import SwiftUI

public struct FilterChipsView: View {
    public let categories: [String]
    public let counts: [String: Int]
    @Binding public var selectedCategory: String
    @Binding public var searchText: String
    public var placeholder: String

    public init(
        categories: [String],
        counts: [String: Int] = [:],
        selectedCategory: Binding<String>,
        searchText: Binding<String> = .constant(""),
        placeholder: String = "Filter resources..."
    ) {
        self.categories = categories
        self.counts = counts
        self._selectedCategory = selectedCategory
        self._searchText = searchText
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(categories, id: \.self) { cat in
                        ChipButton(
                            name: cat,
                            count: counts[cat],
                            isSelected: selectedCategory == cat
                        ) {
                            withAnimation(DesignTokens.snappySpring) {
                                selectedCategory = cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Spacer(minLength: 4)

            searchBox
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DesignTokens.surfaceContainerLowest)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.inkTertiary)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.ink)
                .frame(width: 140)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.inkTertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(DesignTokens.inkSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(DesignTokens.surfaceContainerHigh)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DesignTokens.surfaceContainerLow)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.divider, lineWidth: 1))
    }
}

private struct ChipButton: View {
    let name: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isHovered ? DesignTokens.ink : DesignTokens.inkSecondary))

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? DesignTokens.primaryContainer : DesignTokens.inkTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white : DesignTokens.surfaceContainerHigh)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? DesignTokens.primaryContainer : (isHovered ? DesignTokens.surfaceContainerLow : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Filter by: \(name)")
    }
}
