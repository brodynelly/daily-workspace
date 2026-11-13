// `osascript -l JavaScript music.js <action> [args]` returns one JSON object.
// The fixture branch never creates an Application("Music") object or requests Automation access.
const previewLibrary = {
    playlists: [
        { id: "preview-library", name: "Library", tracks: [
            ["preview-1", "First Song", "Sample Artist", "Sample Album", 133],
            ["preview-2", "Second Song", "Another Artist", "Another Album", 125],
            ["preview-3", "Short Recording", "", "", 19]
        ] },
        { id: "preview-favorites", name: "Favorites", tracks: [
            ["preview-2", "Second Song", "Another Artist", "Another Album", 125]
        ] }
    ]
};
const previewStatus = { state: "stopped", volume: 50, track: null, position: 0 };

function trackList(tracks) {
    if (tracks.length === 0) return [];
    const ids = tracks.persistentID();
    const names = tracks.name();
    const artists = tracks.artist();
    const albums = tracks.album();
    const durations = tracks.duration();
    // Zero-length items include PDF booklets, which Music cannot play.
    return ids
        .map((id, i) => [id, names[i] || "", artists[i] || "", albums[i] || "", Math.round(durations[i] || 0)])
        .filter((track) => track[4] > 0);
}

function library(music) {
    const playlists = [];
    const lib = music.libraryPlaylists[0];
    playlists.push({ id: lib.persistentID(), name: "Library", tracks: trackList(lib.tracks) });
    for (const playlist of music.playlists()) {
        if (playlist.class() === "folderPlaylist" || playlist.specialKind() !== "none") continue;
        playlists.push({ id: playlist.persistentID(), name: playlist.name().trim(), tracks: trackList(playlist.tracks) });
    }
    return { playlists };
}

function status(music) {
    const state = music.playerState();
    const result = { state, volume: music.soundVolume(), track: null, position: 0 };
    if (state === "stopped") return result;
    try {
        const track = music.currentTrack;
        result.track = {
            id: track.persistentID(), name: track.name(), artist: track.artist(),
            album: track.album(), duration: Math.round(track.duration() || 0)
        };
        result.position = Math.round((music.playerPosition() || 0) * 10) / 10;
    } catch (_) {
        // Streams and radio items may have no readable current track.
    }
    return result;
}

function run(argv) {
    const action = argv[0] || "status";
    if (action === "fixture") {
        if (argv[1] === "library") return JSON.stringify(previewLibrary);
        if (argv[1] === "status") return JSON.stringify(previewStatus);
        throw new Error("Unknown fixture request");
    }
    try {
        const music = Application("Music");
        switch (action) {
            case "library":
                return JSON.stringify(library(music));
            case "play": {
                const playlist = music.playlists.whose({ persistentID: argv[1] })[0];
                music.play(playlist.tracks.whose({ persistentID: argv[2] })[0]);
                break;
            }
            case "playpause":
                music.playpause();
                break;
            case "pause":
                music.pause();
                break;
            case "stop":
                music.stop();
                break;
            case "next":
                music.nextTrack();
                break;
            case "prev":
                music.previousTrack();
                break;
            case "volume":
                music.soundVolume = Math.max(0, Math.min(100, music.soundVolume() + Number(argv[1] || 0)));
                break;
            case "status":
                break;
            default:
                throw new Error("Unknown Music action");
        }
        return JSON.stringify(status(music));
    } catch (error) {
        // osascript normally writes JXA errors to stderr, which the bounded runner
        // intentionally discards. Return only a code so -1743 remains recognizable.
        const code = Number(error.number) || (/(^|\D)-?1743(\D|$)/.test(String(error)) ? -1743 : 0);
        return JSON.stringify({ error: { code } });
    }
}
