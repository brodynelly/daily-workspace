import SwiftUI

extension QuickPanelPascalSkin {
    func displayTitle(for row: QuickPanelDataRow) -> String {
        route == .attention && controller.attentionIdentities[row.id] != nil ? "! \(row.title)" : row.title
    }

    var documentTable: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let columns = QuickPanelColumns.widths(for: geometry.size.width, music: music)
                let headings =
                    music ? ["#", "Title", "Artist", "Album", "Time"] : ["#", "Name", "Context", "Keys / State"]
                HStack(spacing: QuickPanelColumns.gutter) {
                    ForEach(headings.indices, id: \.self) { index in
                        Text(headings[index])
                            .frame(width: columns[index], alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, QuickPanelColumns.leading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
            .frame(height: 27)
            .foregroundStyle(Ink.cyan)
            .background(Ink.header)
            .accessibilityAddTraits(.isHeader)
            resultList
        }
        .accessibilityLabel(music ? "Music library results" : "\(route.title) results")
    }

    var playlistList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(controller.music.library?.playlists ?? []) { playlist in
                    Button {
                        controller.selectPlaylistFromPointer(playlist.id)
                    } label: {
                        HStack {
                            Text(playlist.id == controller.music.selectedPlaylistID ? "▼" : "▸")
                            Text(playlist.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(playlist.tracks.count)").foregroundStyle(Ink.meta)
                        }
                        .frame(height: 28)
                        .padding(.horizontal, 6)
                        .background(playlist.id == controller.music.selectedPlaylistID ? Ink.selection : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel("Music playlists")
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(controller.rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            controller.selectResultFromPointer(index)
                        } label: {
                            GeometryReader { geometry in
                                let columns = QuickPanelColumns.widths(for: geometry.size.width, music: music)
                                HStack(spacing: QuickPanelColumns.gutter) {
                                    if music {
                                        Text("\(index + 1)").foregroundStyle(Ink.meta)
                                            .frame(width: columns[0], alignment: .leading)
                                        Text(row.title).frame(width: columns[1], alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.musicArtist).foregroundStyle(Ink.meta)
                                            .frame(width: columns[2], alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.musicAlbum).foregroundStyle(Ink.meta)
                                            .frame(width: columns[3], alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.badge).foregroundStyle(Ink.cyan)
                                            .frame(width: columns[4], alignment: .leading)
                                            .lineLimit(1)
                                    } else {
                                        Text("\(index + 1)").foregroundStyle(Ink.meta)
                                            .frame(width: columns[0], alignment: .leading)
                                        HStack(spacing: 0) {
                                            if route == .attention && controller.attentionIdentities[row.id] != nil {
                                                Text("! ").foregroundStyle(Ink.coral)
                                            }
                                            Text(row.title)
                                        }
                                        .frame(width: columns[1], alignment: .leading)
                                        .lineLimit(1)
                                        Text(row.detail).foregroundStyle(Ink.meta)
                                            .lineLimit(1)
                                            .truncationMode(QuickPanelColumns.isPath(row.detail) ? .middle : .tail)
                                            .frame(width: columns[2], alignment: .leading)
                                        Group {
                                            if row.keys.isEmpty {
                                                Text(row.badge.isEmpty ? row.status : row.badge)
                                                    .foregroundStyle(Ink.cyan).lineLimit(1)
                                            } else {
                                                QuickPanelKeyCaps(keys: row.keys)
                                            }
                                        }
                                        .frame(width: columns[3], alignment: .leading)
                                    }
                                }
                                .padding(.leading, QuickPanelColumns.leading)
                                // GeometryReader pins content top-leading; centre it in the 28pt band.
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                            }
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                            .background(controller.selectedIndex == index ? Ink.selection : .clear)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                controller.selectResultFromPointer(index)
                                controller.activateSelected()
                            }
                        )
                        .id(row.id)
                        .accessibilityLabel("\(displayTitle(for: row)), \(row.detail), \(row.group), \(row.status)")
                    }
                }
            }
            .onChange(of: controller.selectedIndex) { _, index in
                guard controller.rows.indices.contains(index) else { return }
                proxy.scrollTo(controller.rows[index].id)
            }
        }
        .overlay {
            if controller.rows.isEmpty {
                Text(controller.query.isEmpty ? emptyMessage : "No matches. Try a different search.")
                    .foregroundStyle(Ink.meta)
            }
        }
        .accessibilityLabel("\(route.title) results")
    }

    private var emptyMessage: String {
        if route == .calendar {
            switch controller.calendarSnapshot {
            case nil: return "Loading calendar…"
            case .access: return "Calendar access unavailable. See Preview for its status."
            case .agenda: return "No events today. See the next event in Preview."
            }
        }
        if route == .music {
            if controller.musicLoading { return "Loading Music library…" }
            return controller.music.errorMessage
                ?? (controller.music.library == nil
                    ? "Music library unavailable" : "No songs in this playlist")
        }
        if case .ready = controller.dataProvider.refreshState { return "Nothing here yet. ⌘R to refresh." }
        return "Loading source results…"
    }
    var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = controller.attentionPreview {
                ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button("Focus agent ↵") { controller.activateSelected() }
                    Button("Dismiss ⌘⌫") { controller.activateSelected(remove: true) }
                }
            } else if route == .calendar, let snapshot = controller.calendarSnapshot {
                QuickPanelCalendar(snapshot: snapshot) {
                    controller.open(.calendar)
                    controller.model?.navigation.showSettings(tab: .permissions)
                }
                Button("Open Calendar in Daily Workspace") { controller.open(.calendar) }
                    .foregroundStyle(Ink.title).buttonStyle(.plain)
            } else if music, let error = controller.music.errorMessage {
                Text("MUSIC ACCESS ERROR").foregroundStyle(Ink.notice)
                Text(error).fixedSize(horizontal: false, vertical: true)
            } else if let row = controller.rows.indices.contains(controller.selectedIndex)
                ? controller.rows[controller.selectedIndex] : nil
            {
                Text(row.title.uppercased()).foregroundStyle(Ink.cyan)
                Text(row.detail).fixedSize(horizontal: false, vertical: true)
                if !row.group.isEmpty { Text("Source: \(row.group)").foregroundStyle(Ink.meta) }
                if !row.status.isEmpty { Text("Status: \(row.status)").foregroundStyle(Ink.meta) }
                if let runID = row.nativeRunID, let model = controller.model,
                    model.luunaWork.selectedRunID == runID
                {
                    let work = model.luunaWork
                    if let detail = work.selectedRun.value {
                        Text("Run state: \(detail.state.rawValue)").foregroundStyle(Ink.meta)
                    }
                    if work.follower.isFollowing { Text("Following run events…").foregroundStyle(Ink.meta) }
                    Text(
                        "Events: \(LuunaStatusWords.describe(work.follower.events.state, origin: model.luuna.origin).text)"
                    ).foregroundStyle(Ink.meta)
                    if let events = work.follower.events.value {
                        ForEach(events.suffix(12), id: \.sequence) { event in
                            Text(verbatim: "#\(event.sequence) \(event.fields["type"]?.stringValue ?? "event")")
                                .foregroundStyle(Ink.meta)
                            if let chunk = event.fields["payload"]?["chunk"]?.stringValue {
                                Text(verbatim: String(chunk.prefix(2_000))).textSelection(.enabled)
                            }
                        }
                    }
                }
                if !row.keys.isEmpty { Text("Keys: \(row.keys)").foregroundStyle(Ink.meta) }
                if row.nativeRunID != nil || row.action != nil || route == .system || route == .music
                    || route == .attention
                {
                    Button("Open selection ↵") { controller.activateSelected() }
                        .foregroundStyle(Ink.title).buttonStyle(.plain)
                }
                if row.alternate != nil {
                    Button("Workspace actions ⌘↵") { controller.activateSelected(alternate: true) }
                        .buttonStyle(.plain)
                }
                if row.remove != nil || route == .attention {
                    Button("Dismiss / Close ⌘⌫") { controller.activateSelected(remove: true) }
                        .buttonStyle(.plain)
                }
            } else {
                Text(route.title.uppercased()).foregroundStyle(Ink.cyan)
                Text(route.detail)
            }
            if route == .attention {
                Button("All agents") { controller.navigate(to: .agents) }
            }
            if music { Text(controller.music.summary).foregroundStyle(Ink.meta) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("\(route.title) preview")
    }

    var command: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(">").foregroundStyle(Ink.title)
                TextField("Type to search \(route.title)", text: $controller.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onTapGesture { controller.focusSearch() }
                    .accessibilityLabel("Search \(route.title)")
            }
            Text(statusLine)
                .font(Typography.font(11, preferred: controller.panelFont))
                .foregroundStyle(statusIsNormal ? Ink.meta : Ink.notice)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Search and command pane")
        // The pane is inserted on demand, so claim focus once the field exists.
        .onAppear { DispatchQueue.main.async { searchFocused = controller.focusedPane == "command" } }
    }

    var statusLine: String {
        controller.error
            ?? (music
                ? controller.music.summary
                : "\(controller.rows.count) \(controller.rows.count == 1 ? "item" : "items") · \(route.title)")
    }

    var statusIsNormal: Bool {
        controller.error == nil && (!music || controller.music.errorMessage == nil)
    }

    var footer: some View {
        HStack(spacing: 14) {
            let hints = controller.vimHints
            ForEach(hints.indices, id: \.self) { index in
                QuickPanelKeyCaps(keys: hints[index].0, label: hints[index].1)
            }
            Spacer(minLength: 0)
        }
        .font(Typography.font(11, preferred: controller.panelFont))
        .lineLimit(1)
        .accessibilityLabel("Keyboard hints")
    }
}

/// Column widths shared by the results header and rows, with a fixed gutter between columns.
enum QuickPanelColumns {
    static let leading: CGFloat = 8
    static let trailing: CGFloat = 12
    static let gutter: CGFloat = 20
    static let number: CGFloat = 30

    static func widths(for total: CGFloat, music: Bool) -> [CGFloat] {
        let shares: [CGFloat] = music ? [0.38, 0.25, 0.25, 0.12] : [0.25, 0.56, 0.19]
        let available = max(0, total - leading - trailing - number - gutter * CGFloat(shares.count))
        return [number] + shares.map { (available * $0).rounded(.down) }
    }

    static func isPath(_ text: String) -> Bool { text.hasPrefix("~/") || text.hasPrefix("/") }
}
