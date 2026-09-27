# mediaanalysisd-watchdog

Stop macOS `mediaanalysisd` / `photoanalysisd` from burning CPU and GPU every time
your Mac sits idle. No SIP changes, no system files touched, fully reversible.

## The problem

`mediaanalysisd` is Apple's photo and video analysis service (scenes, faces, text in
images, Apple Intelligence indexing). It runs whenever the Mac is idle and plugged in.
Normally it finishes and goes quiet. Sometimes it doesn't: an analysis task fails on
every photo and is retried forever, night after night.

Symptoms:

- High `mediaanalysisd` CPU time in Activity Monitor (hundreds of CPU-minutes per day)
- Fans/heat or battery drain while the Mac is idle with the screen off
- GPU at high clock and E-cores busy with nothing open
- `VTDecoderXPCService` / `VTEncoderXPCService` busy too (it's re-analysing your videos)

### Is yours stuck?

```sh
ps -Ao time,comm | grep -E 'mediaanalysisd$|photoanalysisd'
```

Check for a task that keeps failing (adjust the path if your system Photos library is elsewhere):

```sh
sqlite3 -header -column "file:$HOME/Pictures/Photos Library.photoslibrary/private/com.apple.mediaanalysisd/MediaAnalysis/MediaAnalysis.sqlite?mode=ro" \
  "select ZTASKID task, ZERRORCODE err, count(*) failed_assets, max(ZATTEMPTCOUNT) attempts
   from ZPROCESSINGSTATUS where ZERRORCODE != 0 group by 1,2 order by 3 desc;"
```

Thousands of failed assets for one task means it is looping and will not finish on its own.

## Why the usual fixes don't work

On current macOS with SIP enabled:

| Approach | Result |
|---|---|
| `launchctl disable gui/$UID/com.apple.mediaanalysisd` | Silently erased by launchd at the next reboot |
| `launchctl bootout` / `launchctl unload -w` | `Operation not permitted while System Integrity Protection is engaged` |
| Deleting the LaunchAgent plist | `/System` is a sealed, read-only volume |
| `kill` / `killall` | launchd restarts it on demand within minutes |
| Resetting its database | Rebuilds, then fails on the same task again |
| **`kill -STOP` (this tool)** | **Works.** A stopped process still counts as running, so launchd never starts a replacement, and it uses 0% CPU |

## How it works

A small LaunchAgent runs `analysis-watchdog.sh`, which checks every 3 seconds for
`mediaanalysisd` and `photoanalysisd` processes owned by you and sends `SIGSTOP` to
any that aren't already paused. If launchd starts a new copy (after a crash or reboot),
it's paused within 3 seconds. The loop costs about two `pgrep` calls every 3 seconds.

When the watchdog stops (uninstall, `launchctl bootout`, logout), it sends `SIGCONT`
on the way out, so nothing is left frozen.

## Install

```sh
git clone https://github.com/thejazzid/mediaanalysisd-watchdog.git
cd mediaanalysisd-watchdog
./install.sh install
```

No `sudo` needed. It installs, for the current user only:

| Path | What |
|---|---|
| `~/Library/Application Support/analysis-watchdog/analysis-watchdog.sh` | Script the agent runs |
| `~/Library/LaunchAgents/local.analysis-watchdog.plist` | LaunchAgent (`RunAtLoad`, `KeepAlive`) |
| `~/Library/Logs/analysis-watchdog.log` | One line per pause/resume, rotated at 1 MB |

Re-run `./install.sh install` after editing the script.

## Usage

```sh
./analysis-watchdog.sh status   # show targets: paused / ACTIVE
tail -f ~/Library/Logs/analysis-watchdog.log
launchctl print gui/$(id -u)/local.analysis-watchdog | grep -E 'state|pid'
```

`./analysis-watchdog.sh resume` un-pauses the daemons, but the running watchdog pauses
them again within 3 seconds. To let them run, uninstall.

Settings (environment variables): `WATCHDOG_INTERVAL` (seconds, default `3`),
`WATCHDOG_LOG` (log path).

## Uninstall

```sh
./install.sh uninstall
```

Stops the agent, resumes the daemons, and removes the installed script and plist.
The log is kept.

## What you give up

While the daemons are paused:

- Photos: search by content ("dog", "beach"), Live Text in photos, People & Pets, and
  Memories stop updating. Existing results stay; browsing, editing, and import work.
- Anything that asks `mediaanalysisd` for help (e.g. Visual Look Up in Quick Look) may
  wait or show nothing.
- Each paused daemon keeps its memory (a few hundred MB). Under memory pressure macOS may
  kill it; the watchdog pauses the replacement.

The video decode/encode services are left alone because every app uses them for video
playback. They go idle on their own once `mediaanalysisd` stops feeding them work.

## Compatibility

Tested on macOS 26.7 (Apple M2 Max). It relies only on `pgrep`, `ps`, `kill`, and
`launchctl`, so it should work on any recent macOS.

## License

MIT, see [LICENSE](LICENSE).
