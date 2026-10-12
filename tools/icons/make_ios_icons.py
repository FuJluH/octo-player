"""Writes the iPhone app's icon outlines from the same vectors the other apps draw.

    python tools/icons/make_ios_icons.py

reads icons.json and the vectors make_icons.py wrote into design/src/main/res/drawable,
and writes ios/Sources/Octo/Design/OctoIcon+Paths.swift: one outline per icon, on
Phosphor's 256 grid, in the order and with the names OctoIcon uses.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRAWABLES = ROOT / "design/src/main/res/drawable"
OUT = ROOT / "ios/Sources/Octo/Design/OctoIcon+Paths.swift"

# The Swift name for each vector, in the order OctoIcon lists them.
NAMES = [
    ("previous", "sym_fast_rewind"),
    ("next", "sym_fast_forward"),
    ("play", "sym_play_arrow"),
    ("pause", "sym_pause"),
    ("shuffle", "sym_shuffle"),
    ("repeatAll", "sym_repeat"),
    ("repeatOne", "sym_repeat_one"),
    ("sleepTimer", "sym_bedtime"),
    ("queue", "sym_queue_music"),
    ("volumeDown", "sym_volume_down"),
    ("volumeUp", "sym_volume_up"),
    ("lossless", "sym_graphic_eq"),
    ("like", "sym_favorite"),
    ("liked", "sym_favorite_filled"),
    ("more", "sym_more_horiz"),
    ("playNext", "sym_queue_play_next"),
    ("addToQueue", "sym_add_to_queue"),
    ("addToPlaylist", "sym_playlist_add"),
    ("rename", "sym_edit"),
    ("delete", "sym_delete"),
    ("album", "sym_album"),
    ("artist", "sym_person"),
    ("songs", "sym_music_note"),
    ("genres", "sym_genres"),
    ("playlists", "sym_playlist"),
    ("chevron", "sym_chevron_right"),
    ("chevronBack", "sym_chevron_left"),
    ("collapse", "sym_chevron_down"),
    ("back", "sym_arrow_back"),
    ("cloud", "sym_cloud"),
    ("check", "sym_check"),
    ("download", "sym_download"),
    ("downloading", "sym_downloading"),
    ("downloaded", "sym_download_done"),
    ("addToLibrary", "sym_add"),
    ("notInLibrary", "sym_add_light"),
    ("radio", "sym_radio"),
    ("share", "sym_share"),
    ("sound", "sym_tune"),
    ("star", "sym_star"),
    ("starFilled", "sym_star_filled"),
    ("lyrics", "sym_lyrics"),
    ("folder", "sym_folder"),
    ("sort", "sym_sort"),
    ("filter", "sym_filter_list"),
    ("ascending", "sym_arrow_upward"),
    ("descending", "sym_arrow_downward"),
    ("info", "sym_info"),
    ("select", "sym_check_circle"),
    ("close", "sym_close"),
    ("history", "sym_history"),
    ("pin", "sym_keep"),
    ("pinned", "sym_keep_filled"),
    ("removeFromPlaylist", "sym_playlist_remove"),
    ("shareFile", "sym_audio_file"),
    ("ringtone", "sym_ring_volume"),
    ("playback", "sym_play_circle"),
    ("appearance", "sym_palette"),
    ("library", "sym_library_music"),
    ("scrobbling", "sym_insights"),
    ("backup", "sym_settings_backup_restore"),
    ("search", "sym_search"),
    ("phone", "sym_smartphone"),
    ("home", "sym_home"),
    ("homeSelected", "sym_home_filled"),
    ("searchSelected", "sym_search_filled"),
    ("librarySelected", "sym_library_filled"),
    ("settings", "sym_settings"),
    ("settingsSelected", "sym_settings_filled"),
    ("cast", "sym_cast"),
    ("castConnected", "sym_cast_connected"),
    ("tv", "sym_tv"),
    ("speaker", "sym_speaker"),
    ("speakerGroup", "sym_speaker_group"),
    ("headphones", "sym_headphones"),
    ("globe", "sym_globe"),
    ("lock", "sym_lock"),
    ("lockOpen", "sym_lock_open"),
    ("key", "sym_key"),
    ("sparkle", "sym_sparkle"),
    ("sync", "sym_sync"),
    ("storage", "sym_database"),
    ("servers", "sym_servers"),
    ("timer", "sym_timer"),
    ("listeners", "sym_listeners"),
    ("layout", "sym_layout"),
    ("wifi", "sym_wifi"),
    ("camera", "sym_camera"),
    ("qrCode", "sym_qr_code"),
    ("copy", "sym_copy"),
    ("link", "sym_link"),
    ("audioQuality", "sym_equalizer"),
    ("visible", "sym_visibility"),
    ("hidden", "sym_visibility_off"),
    ("minimize", "sym_minimize"),
    ("maximize", "sym_maximize"),
    ("restore", "sym_restore"),
    ("system", "sym_system"),
    ("keyboard", "sym_keyboard"),
    ("loudness", "sym_loudness"),
    ("balance", "sym_balance"),
    ("crossfade", "sym_crossfade"),
]


def main():
    icons = json.loads((ROOT / "tools/icons/icons.json").read_text(encoding="utf-8"))["icons"]
    named = {drawable for _, drawable in NAMES}
    missing = sorted(set(icons) - named)
    if missing:
        raise SystemExit("icons without a Swift name: " + ", ".join(missing))
    lines = [
        "// Made by tools/icons/make_ios_icons.py from tools/icons/icons.json; change that, not this.",
        "",
        "extension OctoIcon {",
        "    /// The outline, on Phosphor's 256 grid, filled with the nonzero rule.",
        "    var pathData: String {",
        "        switch self {",
    ]
    for name, drawable in NAMES:
        text = (DRAWABLES / f"{drawable}.xml").read_text(encoding="utf-8")
        paths = re.findall(r'android:pathData="([^"]+)"', text)
        if len(paths) != 1:
            raise SystemExit(f"{drawable} has {len(paths)} paths")
        spec = icons[drawable]
        lines.append(f"        // {spec['icon']} ({spec['weight']}{', at ' + str(spec['scale']) if 'scale' in spec else ''})")
        lines.append(f'        case .{name}: "{paths[0]}"')
    lines += ["        }", "    }", "}", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"Wrote {len(NAMES)} icons to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
