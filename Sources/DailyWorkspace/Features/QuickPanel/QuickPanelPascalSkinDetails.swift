import SwiftUI

extension QuickPanelPascalSkin {
    var documentTable: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let columns: [CGFloat] = music ? [0.055, 0.40, 0.245, 0.215, 0.085] : [0.045, 0.30, 0.435, 0.22]
                let headings =
                    music ? ["#", "Title", "Artist", "Album", "Time"] : ["#", "Name", "Context", "Keys / State"]
                HStack(spacing: 0) {
                    ForEach(headings.indices, id: \.self) { index in
                        Text(headings[index])
                            .frame(width: geometry.size.width * columns[index], alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 5)
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
                        controller.selectPlaylist(playlist.id)
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
                            controller.select(index)
                        } label: {
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    if music {
                                        Text("\(index + 1)").foregroundStyle(Ink.meta)
                                            .frame(width: geometry.size.width * 0.055, alignment: .leading)
                                        Text(row.title).frame(width: geometry.size.width * 0.40, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.musicArtist).foregroundStyle(Ink.meta)
                                            .frame(width: geometry.size.width * 0.245, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.musicAlbum).foregroundStyle(Ink.meta)
                                            .frame(width: geometry.size.width * 0.215, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.badge).foregroundStyle(Ink.cyan)
                                            .frame(width: geometry.size.width * 0.085, alignment: .leading)
                                            .lineLimit(1)
                                    } else {
                                        Text("\(index + 1)").foregroundStyle(Ink.meta)
                                            .frame(width: geometry.size.width * 0.045, alignment: .leading)
                                        Text(row.title).frame(width: geometry.size.width * 0.30, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.detail).foregroundStyle(Ink.meta)
                                            .frame(width: geometry.size.width * 0.435, alignment: .leading)
                                            .lineLimit(1)
                                        Text(row.keys.isEmpty ? (row.badge.isEmpty ? row.status : row.badge) : row.keys)
                                            .foregroundStyle(Ink.cyan).lineLimit(1)
                                    }
                                }
                                .padding(.leading, 5)
                            }
                            .frame(height: 28)
                            .frame(maxWidth: .infinity)
                            .background(controller.selectedIndex == index ? Ink.selection : .clear)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                controller.select(index)
                                controller.activateSelected()
                            }
                        )
                        .id(row.id)
                        .accessibilityLabel("\(row.title), \(row.detail), \(row.group), \(row.status)")
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
            Text(
                controller.error
                    ?? (music
                        ? controller.music.summary
                        : "\(controller.rows.count) \(controller.rows.count == 1 ? "item" : "items") · \(route.title)")
            )
            .font(Typography.font(11, preferred: controller.panelFont))
            .foregroundStyle(controller.error == nil ? Ink.meta : Ink.notice)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel("Search and command pane")
    }

    var footer: some View {
        HStack(spacing: 0) {
            let hints =
                music
                ? [
                    ("F1", " Help  "), ("F2", " Random  "), ("F3", " Find  "), ("F4", " Shuffle  "), ("F5", " Vol-  "),
                    ("F6", " Vol+  "), ("F7", " Prev  "), ("F8", " Play  "), ("F9", " Next  "), ("F10", " Menu"),
                ]
                : [
                    ("F1", " Help  "), ("F2", " Agents  "), ("F3", " Find  "), ("F4", " Projects  "),
                    ("F5", " Sessions  "), ("F6", " Files  "), ("F7", " Workspaces  "), ("F8", " Keys  "),
                    ("F9", " Refresh  "), ("F10", " Menu"),
                ]
            ForEach(hints.indices, id: \.self) { index in
                Text(hints[index].0).foregroundStyle(Ink.gold)
                Text(hints[index].1).foregroundStyle(Ink.footer)
            }
            Spacer(minLength: 0)
        }
        .font(Typography.font(11, preferred: controller.panelFont))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityLabel("Function key hints")
    }
}
