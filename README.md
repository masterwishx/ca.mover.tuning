# Mover Tuning

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/6f52a17f3cc6448c99787e6f94fafa65)](https://app.codacy.com/gh/masterwishx/ca.mover.tuning/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/masterwishx/ca.mover.tuning/badge)](https://www.codefactor.io/repository/github/masterwishx/ca.mover.tuning)

[![Release](https://img.shields.io/github/v/release/masterwishx/ca.mover.tuning?style=flat-square&label=Release)](https://github.com/masterwishx/ca.mover.tuning/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/masterwishx/ca.mover.tuning/total?style=flat-square&label=Downloads)](https://github.com/masterwishx/ca.mover.tuning/releases)
[![License: GPL-2.0](https://img.shields.io/github/license/masterwishx/ca.mover.tuning?style=flat-square&label=License)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/masterwishx/ca.mover.tuning?style=flat-square&label=Last%20commit)](https://github.com/masterwishx/ca.mover.tuning/commits/master)
[![Stars](https://img.shields.io/github/stars/masterwishx/ca.mover.tuning?style=flat-square&label=Stars)](https://github.com/masterwishx/ca.mover.tuning/stargazers)
[![Unraid](https://img.shields.io/badge/Unraid-6.9.0--rc2%2B-orange?style=flat-square)](#requirements)

[![Donate](https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=UDXM742YK5ZV6)

## About

This is an [Unraid](https://unraid.net/) plugin that lets you fine-tune the operation of the [mover](https://docs.unraid.net/unraid-os/using-unraid-to/manage-storage/cache-pools/#using-mover).

This fork merges all [pull requests](https://github.com/R3yn4ld/ca.mover.tuning/pulls) from [R3yn4ld](https://github.com/R3yn4ld/ca.mover.tuning) after review (cosmetics, per-share skipfiletypes merge, automatic age threshold, Unraid 7.x compatibility) and adds many new features. See [CHANGELOG.md](CHANGELOG.md) for the full history.

## Requirements

**Unraid 6.9.0-rc2 or newer.** With Perl, which is part of Unraid's base distribution from 6.11.0, the mover checks whether a file is in use faster, with a Linux file lease. Unraid 7.2.1+ and the 7.4.0 are supported (see [Unraid 7.2.1 and newer](#unraid-721-and-newer)).

## Features

### When and what to move

- Only move files if the cache is getting full: *move above* a threshold of used Primary (cache) space, *free down* to a lower level, and *fill up* (Array → Cache) to a chosen level.
- Threshold lists adjust to the chosen moving threshold (freeing thresholds stay at or below it, Move All thresholds above it). A warning appears when the freeing threshold is above the moving threshold, and out-of-range saved values are corrected and flagged.
- Filter by file age ("Auto" enables smart caching), CTIME or ATIME, minimum size, sparseness, hidden files, file types, or a list of ignored files and folders in a text file.
- **Move order:** oldest, largest or smallest first.
- Optionally move all files from Primary → Secondary (cache:yes) shares when the pool is above a chosen percentage.
- **Cache watchdog** (opt-in): monitors the cache and starts a run when the pool reaches a trigger level.
- Optionally don't run the scheduled mover during a parity check / rebuild. A paused check or rebuild does not count, so it no longer blocks scheduled or forced moves.
- Optionally force a move of all files on a schedule, or disable the scheduled run completely.
- Files that are in use are left where they are, unless you enable "Move files that are in use".
- Choose the file-moving tool: **Move** (Unraid's built-in utility) or **Rsync**. Optionally force turbo write and set the priority of the mover process and of disk I/O.

### Shares

- Per-share overrides of the global settings (Shares → click a share → Mover Tuning). Every override has a "Use global" choice.
- Cache:prefer shares: array → cache moves up to a configurable fill-up level.
- Rebalance, Resynchronize and Synchronize Primary files to Secondary (with an optional maximum file size). "Run once" options reset themselves after the run.
- Moving between pools (Unraid 7+).
- Ignore list and ignored file types (with wildcard support) also work for cache:prefer shares and `/mnt/user` paths.
- Hardlinked files are moved and synced together.
- "Share size calculation" option to avoid slow scans on large or busy shares.

### Cleanup

- Optional moving and cleanup of empty folders, including top-level share folders.
- Cleanup of empty ZFS datasets, with protection for ZFS datasets and `.placeholder` files.

### Safety, logging and troubleshooting

- Test Mode (dry run) with clear warnings.
- **Live progress** of a run under the Move button: named steps (filtering, deciding, moving), the file being processed, size left, speed and ETA. Updated every 5 seconds while a file moves (with the Move tool, in 2 GiB steps). On Unraid 7.4 and newer, the rows show only when **Mover Progress** is enabled in Settings → Scheduler → Mover Settings (it is disabled by default).
- Verified results: a move counts as successful only after the file has arrived at the destination and is gone from the source; a sync, only after the copy matches the source in size and modification time. Successful and failed items are counted and reported separately in logs and notifications.
- **Pause** and **Resume** buttons on Main and next to "Move now" while a run moves files. An Rsync copy pauses at once; with Move, the run pauses once the current file is done. The per-share Move and the runs of the built-in mover that the plugin starts (forced move, "Move now" without the filters) pause once their current file is done; runs Unraid starts itself are left alone. The next scheduled run or a cache watchdog trigger resumes a paused run.
- Detailed logs (file only, or file and syslog), configurable log folder and log age, a Log files row that views or downloads any run's log, and a "Run by" entry showing whether the run came from cron, the CLI or the web UI.
- The log explains why a file did not move (for example "No space left on device") and warns when a share's minimum free space is smaller than the largest file to move.
- Unraid notifications for failures and completion, with a "Moved Only" option. Notifications follow the GUI language.
- Optional scripts to run **before** and **after** the mover.
- Debug package (.zip) for the support thread, with file names hidden.
- "Defaults" button that asks first and then **resets** all settings, including schedules.

### Unraid 7.2.1+

- Own Mover Tuning schedule, separate from the native mover, with automatic migration of the old schedule.
- "Move now" button that shows the mover as running until it finishes.

**Languages:** English, Russian, German, French and Simplified Chinese (interface, help and notifications).

## How it works

First it checks if it's valid for this script run: there must be a cache disk present and an instance of the script must not already be running.

Next, it checks each of the top-level directories (shares) on the cache disk.
For all shares with the 'Use Cache' setting set to "prefer" or "yes", we use 'find' to create a filtered file list of that share directory.
For all shares with the 'Use Cache' setting set to "only", we use 'du' or 'zfs list' to get the total size of that share directory.

The list is sorted by pool, "Use cache", newest file first, and file inode. This gives priority for space on the Primary pool to "cache only" shares, then to "cache prefer" shares, whose newest files move from Secondary to Primary up to the fill-up level, and last to "cache yes" shares, whose files move from Primary to Secondary in the Move order (oldest first by default).
Please note that if the age setting is set to something other than "Auto (smart cache)", this script is actually dumb: it does not check for size and free space and relies on your own calculations.
Files at the top level of the cache or an array disk (i.e. not in a share) are never moved.

The list is then processed with the chosen tool (Rsync by default, or Unraid's move utility).
For each file, if the file is not "in use" by any process (as detected by an exclusive Linux file lease, with `fuser` as a compatibility fallback when leases or Perl are unavailable), then the file is moved and, upon success, deleted from the source disk. If the file already exists on the target, Unraid's move leaves both copies in place and the run counts the file as not moved; Rsync replaces the copy on the target with the source file. Moved files keep their permissions, ownership, extended attributes and modification time. Unraid's move also keeps the access time; with Rsync, it becomes the time of the copy.
If an error occurs while copying a file, the partial file, if present, is deleted and the operation continues on to the next file.

## Changelog

Release notes for every version are in [CHANGELOG.md](CHANGELOG.md). Each release on the [Releases](https://github.com/masterwishx/ca.mover.tuning/releases) page lists its notes, its install URL, and how to roll back to the release before it.

## Installation

You can download and install plugins with [Community Apps](https://unraid.net/community/apps/c/plugins).

Or paste a URL into Plugins > Install Plugin:

- Stable: `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/master/plugins/ca.mover.tuning.plg`
- Beta, for trying changes before they reach the stable release: `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/beta/plugins/ca.mover.tuning.plg`

### Unraid 7.2.1 and newer

Starting with Unraid 7.2.1, Mover Tuning is separated from the built-in Unraid mover:

- "Move Now" in Mover Settings and "Move" on the Main page run the **built-in Unraid mover**.
- "Move Now" in Mover Tuning → Options runs the **Mover Tuning mover** (`age_mover`).
- To stop the built-in mover from running on its own schedule, set its schedule to Disabled in Mover Settings.
- Use the **Mover Tuning schedule** in the plugin settings to schedule Mover Tuning instead. On install, an existing mover schedule is migrated automatically.
- The built-in Unraid mover can still be started on a schedule with the "Force move of all files on a schedule" option.
- In the command line, `age_mover --help` shows the plugin commands. `mover --help` calls the built-in Unraid mover.

## Configuration

You'll find the settings on the Mover Tuning page within Settings - [Scheduler](https://docs.unraid.net/unraid-os/manual/additional-settings/#scheduler). The page is split into sections:

| Section | What you can set |
| --- | --- |
| **Plugin Settings** | Disable the plugin's schedule, cache watchdog and its trigger level, Mover Tuning schedule, Test Mode (dry run), logging, debug logging and notifications, log folder, log files (view or download) and log retention, parity check behavior, mover and disk I/O priority, force move of all files on a schedule, before/after scripts. |
| **Filters** | Whether "Move now" follows the plugin filters, thresholds (move above, free down, fill up), age, move order, CTIME/ATIME, minimum size, sync maximum size, sparseness, ignore list file, ignored file types, hidden files, and "Move All" for cache:yes shares above a pool percentage. |
| **Options** | Force turbo write, move files tool, move files that are in use, move/clean empty folders, clean empty ZFS datasets, share size calculation, Synchronize, Rebalance and Resynchronize. Buttons: Apply, Done, Defaults and Move Now, and Pause or Resume while a run moves files. |
| **Help** | Debug package (.zip), a link to the support thread, GitHub link and a collapsible "CLI help commands" panel. |

Per-share overrides are on each share's own page (Shares → click a share → Mover Tuning).

> **Tip:** click on any option or press **F1** on the settings page to read a detailed description of all settings.

## Plugin Settings

![Plugin Settings](screenshots/settings.png)

<details>
<summary>More screenshots</summary>

### Filters

![Filters](screenshots/filters.png)

### Options

![Options](screenshots/options.png)

### Help

![Help](screenshots/help.png)

</details>

## Usage

After installation, Test Mode is disabled by default. Enable Test Mode before reviewing `/tmp/ca.mover.tuning/Mover_actions_date.list` to confirm that the mover will move/keep/sync files as expected.

Commands that can be launched from a terminal or a script (`age_mover` is installed on your path; the full path is `/usr/local/emhttp/plugins/ca.mover.tuning/age_mover`):

| Command | What it does |
| --- | --- |
| `age_mover start` | Starts the age_mover with the settings you set in the GUI. |
| `age_mover stop` | Forced stop of the age_mover process tree. Not recommended: it can leave partial files and incomplete hardlink transfers. Use `softstop` instead. |
| `age_mover softstop` | Soft stop (recommended) of a Mover Tuning run. Cleanly exits the loops (Filtering, Deciding, Moving); an ongoing file transfer is not interrupted, and the stop occurs after the current file operation. Turbo write is restored afterwards. Also works on Unraid before 7.2.1. |
| `age_mover pause` | Pauses a run that is moving files, like the Pause button: an Rsync copy waits at once, a Move copy once its file is done. |
| `age_mover resume` | Resumes a paused run. The next scheduled run or a cache watchdog trigger also resumes it. |
| `age_mover status` | Checks if age_mover is running (also on Unraid before 7.2.1). |
| `age_mover reset` | Resets the plugin config and schedules to default values and deletes the override config folder. |
| `age_mover debug` | Creates a diagnostics ZIP at `/boot/logs/ca.mover.tuning-debug-<date-time>.zip`. |
| `age_mover watchdog` | Starts a run when a cache:yes share's primary pool reaches the Cache watchdog trigger level. Run by cron, so you normally don't need to call it yourself. |
| `age_mover --help` | Shows the usage for your version. |

On Unraid older than 7.2.1 you can use `mover` instead of `age_mover` (for example `mover start`). On 7.2.1+ `mover` runs the built-in Unraid mover, so use `age_mover`.

See the [Mover Tuning thread on the Unraid support forum](https://forums.unraid.net/topic/70783-plugin-mover-tuning/) for more details and discussions. When asking for help, attach the debug package from the Help section.

## License

Released under the [GPL-2.0 license](LICENSE).

## Thanks

This was originally created by [Squid](https://github.com/Squidly271).

@2023 – Updated by [hugenbd](https://github.com/hugenbd/ca.mover.tuning), with contributions by [Castcore](https://github.com/Castcore), [Swarles](https://github.com/hugenbd/ca.mover.tuning/commit/64e06e91bd83431d768346e4d8158f7be039564e), [Dphelan](https://github.com/dphelan) and [Davendsai](https://github.com/davendesai).

@2024 – Updated by [R3yn4ld](https://github.com/R3yn4ld/ca.mover.tuning).

@2025 – Updated by [masterwishx](https://github.com/masterwishx/ca.mover.tuning).

@2026 – Updated by [masterwishx](https://github.com/masterwishx/ca.mover.tuning) and [chodeus](https://github.com/chodeus), with contributions by [Joly0](https://github.com/Joly0), [coppit](https://github.com/coppit).
