# Mover Tuning

## About

This is a simple [Unraid](https://unraid.net/) plugin that will let you fine-tune the operation of the [mover](https://docs.unraid.net/unraid-os/manual/additional-settings/#mover).

[![Codacy Badge](https://app.codacy.com/project/badge/Grade/6f52a17f3cc6448c99787e6f94fafa65)](https://app.codacy.com/gh/masterwishx/ca.mover.tuning/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![CodeFactor](https://www.codefactor.io/repository/github/masterwishx/ca.mover.tuning/badge)](https://www.codefactor.io/repository/github/masterwishx/ca.mover.tuning)

- On scheduled runs of mover    
    - Only actually move file(s) if the cache drive is getting full (selectable thresholds) or/and based on files age,size,etc.
    - Optionally don't move if a parity check / rebuild is already in-progress.
    - Optionally validate input filenames to prevent attacks on the filename.
    - Optionally select the file-moving tool between Rsync and Unraid's built-in move utility.
- Optional ability to completely disable the scheduled runs of mover.
- Manually executed runs of mover ("Move Now" button) or via command line ("mover start") can follow schedule rules or/and always move all files.
- Expanded functionality with numerous additional options and settings.

This new fork merge all [pull requests](https://github.com/R3yn4ld/ca.mover.tuning/pulls) after review from [R3yn4ld](https://github.com/R3yn4ld/ca.mover.tuning). (cosmetics, merge skipfiletypes from shares and add several feature, as for example automatic age threshold, sanitize input filenames to prevent attacks and compatibility with Unraid 7.x, and other stuff coming.

## How it works

First it checks if it's valid for this script run: there must be a cache disk present and an instance of the script must not already be running.

Next, check each of the top-level directories (shares) on the cache disk.
For all share with 'Use Cache' setting set to "prefer" or "yes", we use 'find' to create a filtered file list of that share directory.
For all share with 'Use Cache' setting set to "only", we use 'du' or 'zfs list' to get total size of that share directory.

The list is sorted by "Use cache", increasing age, pool, and file inode, giving priority for being on cache to "cache only" shares, then "cache prefer" by moving newest from array to cache and older to array, and finally to "cache yes" share by moving only from cache to array.
Please note that if age setting is set to something else than "Auto (smart cache)" this script is actually dumb and do not check for size and free space and rely on your own calculations.
Files at the top level of the cache or an array disk (i.e not in a share) are never moved.

The list is then passed to original unraid mover.
For each file, if the file is not "in use" by any process (as detected by 'fuser' command), then the file is moved, and upon success, deleted from the source disk.  If the file already exists on the target, it is not moved and the sourceis not deleted.  All meta-data of moved files/directories is preserved: permissions, ownership, extended attributes, and access/modified timestamps.
If an error occurs in copying a file, the partial file, if present, is deleted and the operation continues on to the next file.

## Changelog

Release notes for every version are in [CHANGELOG.md](CHANGELOG.md). Each release on the [Releases](https://github.com/masterwishx/ca.mover.tuning/releases) page lists its notes, its install URL, and how to roll back to the release before it.

## Installation

You can download and install plugins with [Community Apps](https://unraid.net/community/apps/c/plugins).

Or paste a URL into Plugins > Install Plugin:

- Stable: `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/master/plugins/ca.mover.tuning.plg`
- Beta, for trying changes before they reach the stable release: `https://raw.githubusercontent.com/masterwishx/ca.mover.tuning/beta/plugins/ca.mover.tuning.plg`

## Configuration

You'll find its settings within Settings - [Scheduler](https://docs.unraid.net/unraid-os/manual/additional-settings/#scheduler).

## Usage

After installation, Test Mode is disabled by default. Enable Test Mode before reviewing /tmp/ca.mover.tuning/Mover_actions_date.list to confirm that the mover will move/keep/sync files as expected.

There are several commands that can be launched from terminal or a script:
/usr/local/emhttp/plugins/ca.mover.tuning/age_mover start
To start age mover (the internal moving engine) with the settings you set in the GUI

/usr/local/emhttp/plugins/ca.mover.tuning/age_mover softstop
To cleanly exit loops (Filtering, Deciding, Moving) and age_mover. While moving/syncing, the ongoing file transfer is not interrupted and softstop occurs after actual file operation.

/usr/local/emhttp/plugins/ca.mover.tuning/age_mover stop
To kill all the process (can lead to unfinished or corrupted file transferts while moving).

See the [Mover Tuning_ thread on the Unraid support forum](https://forums.unraid.net/topic/70783-plugin-mover-tuning/) for more details and discussions.

## Thanks

This was originally created by [Squid](https://github.com/Squidly271).

@2023 – Updated by [hugenbd](https://github.com/hugenbd/ca.mover.tuning), with contributions by [Castcore](https://github.com/Castcore), [Swarles](https://github.com/hugenbd/ca.mover.tuning/commit/64e06e91bd83431d768346e4d8158f7be039564e), [Dphelan](https://github.com/dphelan) and [Davendsai](https://github.com/davendesai).

@2024 – Updated by [R3yn4ld](https://github.com/R3yn4ld/ca.mover.tuning).

@2025 – Updated by [masterwishx](https://github.com/masterwishx/ca.mover.tuning).

@2026 – Updated by [masterwishx](https://github.com/masterwishx/ca.mover.tuning) and [chodeus](https://github.com/chodeus), with contributions by [Joly0](https://github.com/Joly0).
