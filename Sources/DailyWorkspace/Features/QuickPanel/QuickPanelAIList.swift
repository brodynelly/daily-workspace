import SwiftUI

/// The corner list for actions, models and `/` commands: Raycast's action panel in the panel's frame style.
struct QuickPanelAIList: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var keys = ""
        var destructive = false
    }

    var title = ""
    let rows: [Row]
    let selected: Int
    let query: String?
    let placeholder: String
    let status: String?
    let run: (Int) -> Void
    private typealias Ink = QuickPanelPascalSkin.Ink

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let status {
                            Text(status).foregroundStyle(Ink.meta).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 10) {
                                Image(systemName: row.symbol).frame(width: 18)
                                    .foregroundStyle(row.destructive ? Ink.coral : Ink.cyan)
                                Text(row.title).lineLimit(1)
                                    .foregroundStyle(row.destructive ? Ink.coral : Ink.primary)
                                Spacer(minLength: 8)
                                if !row.keys.isEmpty {
                                    if row.keys.count > 6 {
                                        Text(row.keys).foregroundStyle(Ink.meta).panelFont(10).lineLimit(1)
                                    } else {
                                        QuickPanelKeyCaps(keys: row.keys.map(String.init).joined(separator: " "))
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(
                                Rectangle().fill(index == selected ? Ink.selection : .clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { run(index) }
                            .id(row.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selected) { _, index in
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
            if let query {
                Rectangle().fill(Ink.idleRule.opacity(0.35)).frame(height: 1)
                Text(query.isEmpty ? placeholder : query)
                    .foregroundStyle(query.isEmpty ? Ink.meta : Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
            }
        }
        .frame(width: 380)
        .frame(maxHeight: 330)
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.titleBox)
        .overlay {
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(0.5)
            Rectangle().strokeBorder(Ink.activeRule, lineWidth: 1).padding(3.5)
        }
        .overlay(alignment: .top) {
            if !title.isEmpty {
                Text(" \(title) ").foregroundStyle(Ink.title).background(Ink.titleBox).offset(y: -8)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .padding(12)
    }
}
