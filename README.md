# DrPlayer

A macOS music player built with SwiftUI that connects to [MPD](https://www.musicpd.org/) (Music Player Daemon). Designed for audiophiles who care about sound quality, metadata, and their music collection.

## Features

### Playback & Library
- **MPD client** via Network.framework (TCP, no dependencies)
- **Album grid** with cover art discovery (scans folders, NFS symlink support)
- **Browse by** Albums, Artists, Composers, or Tracks
- **Queue management** with drag reordering
- **Search** across artists, albums, and tracks
- **Lyrics** display
- **Waveform visualization** for the current track
- **Full-screen now playing** view with artwork gallery

### Audio Quality
- **DR14 Dynamic Range analysis** — computed natively using Accelerate/vDSP, cached per track
- **Signal path indicator** — shows if playback is bitperfect (no mixer, no resampling)
- **Audio output management** — enable/disable MPD outputs, shows plugin type, mixer config, DoP status
- **Format detection** — FLAC, DSF, WAV, ALAC, MP3, and more

### Metadata Enrichment
- **MusicBrainz** — release details, credits, band members, genres
- **Wikipedia** — album and artist biographies with fuzzy search and disambiguation handling
- **Last.fm** — artist tags, global stats, similar artists (requires API key)
- Sources are credited inline ("Fuente: Wikipedia", "Fuente: MusicBrainz")

### Smart Features
- **Other editions** — detects different pressings/remasters of the same album (fuzzy title matching)
- **Other versions** — finds the same track across different albums (compilations, live, remasters)
- **Artist normalization** — groups "Baron Rojo" / "Baron Rojo" / broken encodings as one artist
- **Compound artist handling** — "B.B. King & Eric Clapton" searches metadata for "B.B. King"

### Configuration
- **Auto-detects mpd.conf** — reads music_directory, host, port automatically
- **First-run setup wizard** — dependency check, mpd.conf generation, music source management
- **Music sources** — add/remove library paths as symlinks in MPD's music directory
- **Settings** (Cmd+,) — General, Sources, Audio tabs

## Requirements

- **macOS 14+** (Sonoma)
- **MPD** — Music Player Daemon
- **ffmpeg** — for waveform generation, DR14 analysis, and track metadata

Install with Homebrew:

```bash
brew install mpd ffmpeg
```

## Build & Run

```bash
cd DrPlayer
swift build
swift run
```

Or for a release build:

```bash
swift build -c release
.build/release/DrPlayer
```

## Configuration

On first launch, DrPlayer will:

1. Check that MPD and ffmpeg are installed
2. Auto-detect your `mpd.conf` (searches `~/.mpd/mpd.conf`, `~/.mpdconf`, `/etc/mpd.conf`)
3. Let you configure the music directory and MPD connection
4. Optionally generate a basic bitperfect `mpd.conf`

### Last.fm API (optional)

For artist enrichment (tags, stats, similar artists), add your Last.fm API key in Settings > General > APIs externas.

Get one at [last.fm/api/account/create](https://www.last.fm/api/account/create).

## Architecture

- **SwiftUI** — native macOS UI with no third-party dependencies
- **Network.framework** — TCP connection to MPD
- **Accelerate/vDSP** — vectorized DR14 computation
- **posix_spawn** — subprocess management for ffmpeg/ffprobe
- **UserDefaults** — settings persistence

### Key Files

| File | Description |
|------|-------------|
| `MPDClient.swift` | MPD protocol implementation |
| `PlayerViewModel.swift` | Central state management, data model |
| `DR14Analyzer.swift` | Native DR14 dynamic range computation |
| `SignalPathView.swift` | Bitperfect signal chain indicator |
| `AppSettings.swift` | Settings with mpd.conf auto-detection |
| `WikipediaService.swift` | Wikipedia API with fuzzy search |
| `MusicBrainzService.swift` | MusicBrainz metadata enrichment |
| `LastFMService.swift` | Last.fm artist data |
| `WaveformGenerator.swift` | Audio waveform extraction |

## License

This project is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE) for details.
