# Mover Tuning

## About

This is a simple [Unraid](https://unraid.net/) plugin that will let you fine-tune the operation of the [mover](https://docs.unraid.net/unraid-os/manual/additional-settings/#mover).

- On scheduled runs of mover
    - Only actually move file(s) if the the cache drive is getting full (selectable threshold)
    - Optionally don't move if a parity check / rebuild is already in-progress
- Optional ability to completely disable the scheduled runs of mover
- Manually executed runs of mover ("Move Now" button) can either follow the rules for schedules, or always move all files

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
- 2025.04.24a
    - fix: version number in default.cfg file. **_(masterwishx)_**

- 2025.04.24
    - fix: Fix cli arguments when running "mover command" in cli mode for pass them to age_mover script or original mover. **_(masterwishx)_**
    - new: Add "mover start -e diskX" option for age_mover from original mover for empty an array disk.
    - new: Added "mover reset" command to reset all settings in the plugin. This will delete also override existing settings.
    - new: Added a "Defaults" button in the GUI that resets all settings to their default values. This action triggers "age_mover reset" via "reset.php".
    - fix: Updated plugin version handling to ensure it is stored in the config with quotes and displayed correctly in both the console and logs.
    - fix: Schedule option to force move all files by unraid mover now logs output via syslog instead of being unlogged. Thanks to williechan91 for reported this issue.
    - fix: Fix the calculation of PRIMARYSIZETHRESH in cache prefer cases where the threshold can become negative due to freeing thresholds without moving any files. Thanks to AdamLeyshon for reported this issue.

- 2025.04.05
    - fix: Fix for Logs parent folder can be empty instead of /tmp when no value is provided. Thanks to niwmik2 from forums for reported this issue. **_(masterwishx)_**
    - fix: Fixed an issue where (cache:prefer) was generating unnecessary lists for files that should remain on the primary pool.
    - fix: Only generate updated filtered filelist for (cache:prefer) if we have files on secondary storage.
    - new: Added Help block to the plugin page, including useful links and a donation link for support. Thanks to KluthR from forums for the code example.

- 2025.03.30
    - new: Added new settings: Logs parent folder, age for mover Log,txt and List files. Thanks to Renegade605 and jimlei from forums for the idea. **_(masterwishx)_**
    - fix: Log Mover Tuning plugin actions setting when set to No, will not post to syslog and Mover_tuning_xxx.log file.
    - fix: Added a counter when deleting folders and datasets to speed up the counting of files after moving a large number of files. Thanks to Dor from the forums for the idea.
    - fix: Ensure Folders are always deleted when setting "yes" to clean folders after moving.
    - new: Added debug when deleting folders and datasets in order to get more information about the process.

- 2025.03.20a
    - fix: Exclude primary storage from find in Move now button in cache:prefer share page , when moving all data from array to cache pool by unraid mover. **_(masterwishx)_**

- 2025.03.20
    - fix: Added zfs cache:only share calculation when share is folder instead of dataset. Thanks to Sak from forums for the bug report. **_(masterwishx)_**
    - fix: Added remove potential trailing ( \/, \*, \/\* ) characters from the skipped folder path in ignore file list path.
    - fix: Fixed issue when thresholds for cache:prefer was applyed to cache:yes shares. Tnanks to Ichthus and other users from forum for the bug report.
    - new: Added fillup (%) global setting threshold option and override for cache:prefer shares.
    - new: Move now button in cache:prefer share page , moving all data from array to cache pool by unraid mover.

- 2025.03.11
    - Fixed zfs cache pool percent calculation. Thanks to Renegade605 from forums for the bug report. **_(masterwishx)_**
    - Array -> Cache (cache:prefer) now moves data to the cache pool from the array only until reaching a fillup limit of 95%.
        - Thanks to alturismo and Renegade605 from forums, who helped clarify how this feature should work.
        - Disabled override setting for mover tuning if shareUseCache="prefer" (Array->Cache) is set.
    - Format global and share settings help text descriptions add more clear description for mover thresholds.
    - Fixed ignore file list path setting when folder in list file contains ([). Thanks to JamieBriers from forums for the PR and fix.

- 2025.03.04
    - Added option for users can enable/disable Validation (Sanitize) check for input filenames to prevent attacks future added befor. **_(masterwishx)_**
    - Fixed Debug = yes/no instead of 0/1 in mover logs.
    - Fixed primary cache prefer not to move data. Set fixed moving threshold to 99% freeing threshold to 0% for skip moving.
      when chache is full set freeing to 98% to move some data. Maybe better fix will be later.

- 2025.03.01
    - [Fix for [*] in path when cache prefers or RebalanceShare. Thanks to [tehg] from the forums for identifying the bug](https://github.com/masterwishx/ca.mover.tuning/pull/7) ([masterwishx](https://github.com/masterwishx)).
    - Fix for Clean empty ZFS datset when enabled but Clean empty Folders is disabled.
    - Added Sanitize check for input filenames to prevent attacks. Thanks to [AEnterprise] from forums for identifying the bug.
    - Plugin icon changed.

- 2025.02.24
    - [Added log message when no share avalible on cache for ZFS dataset.](https://github.com/masterwishx/ca.mover.tuning/pull/7) ([masterwishx](https://github.com/masterwishx)).
    - Added option with Notifications to Unraid GUI for error and success messages.
    - Fixed issue with (') symbol in ignore File list. Thanks to JayBriers from forums.
    - ATIME option is now added for based on age option.
    - Debug Logging option added (To print find command and ignored folders/files)

- 2025.02.18.1752
    - [Check parent empty ZFS dataset for children empty datasets before destroy it.](https://github.com/masterwishx/ca.mover.tuning/pull/1) ([masterwishx](https://github.com/masterwishx))
    - Shell Check Fixes + speedup `if` checks.
    - Better help text cosmetic with Bold and italic + added note for Test Mode and some changes in config page.
    - Skip cache pool size calculation when only one share found in cache pool.
    - Changed minimum threshold of used Primary (cache) space from 5% to 0%.

- 2025.02.12.1707
    - [Fix issue for shares with spaces](https://github.com/R3yn4ld/ca.mover.tuning/pull/69) Thanks [DToX_](https://forums.unraid.net/topic/176951-mover-is-refusing-to-move-any-files-off-the-cache-from-a-share-with-a-space-in-the-name/#findComment-1521811) from forums. ([masterwishx](https://github.com/masterwishx))
    - [Add option to clean ZFS datasets](https://github.com/R3yn4ld/ca.mover.tuning/pull/69) ([masterwishx](https://github.com/masterwishx))
    
- 2024.09.05.0222
    - [Fix find not finding hidden files](https://github.com/R3yn4ld/ca.mover.tuning/pull/67) Thanks to [solidno8](https://forums.unraid.net/topic/70783-plugin-mover-tuning/?do=findComment&comment=1461454) from forums. ([R3yn4ld](https://github.com/R3yn4ld))
- 2024.09.05.0115
    - Add compatibility with unraid 7.x for share_mover ([R3yn4ld](https://github.com/R3yn4ld))
    - [Fix "integer expression expected"](https://github.com/R3yn4ld/ca.mover.tuning/pull/63/commits) Thanks to: ([RonaldJerez](https://github.com/RonaldJerez))
    - Fix "0: command not found" bugs ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.18
    - [Fix blank grep to rsync loop causing "Warning no action for; integer expected; unary operator expected" errors](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-no-action-for-blank-integer-unary) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.17
    - [Fix settings override not reverting](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-settings-override-not-reverting) ([R3yn4ld](https://github.com/R3yn4ld))
    - [Better empty folder cleaner](https://github.com/R3yn4ld/ca.mover.tuning/tree/Better-emptyfolder-cleaner) ([R3yn4ld](https://github.com/R3yn4ld))


- 2024.08.15
    - [Fix ignore list reserved space](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-ignore-list-reserved-space-) double quoting (Thanks silver226 see [forum post](https://forums.unraid.net/topic/70783-plugin-mover-tuning/?do=findComment&comment=1454141)) ([R3yn4ld](https://github.com/R3yn4ld))
    - [Better empty folder cleaner](https://github.com/R3yn4ld/ca.mover.tuning/tree/Better-emptyfolder-cleaner) ([R3yn4ld](https://github.com/R3yn4ld))
        - Rewritten to rmdir parent directory of a moved file if empty (drawbacks: will let multidirectory dirs  alive)
        - Added option to enable/disable empty folder cleaner added in Settings UI
        - UI improvements, settings sorted
    - Even [Better cache priming](https://github.com/R3yn4ld/ca.mover.tuning/tree/better-cache-priming) (hopefully) ([R3yn4ld](https://github.com/R3yn4ld))
        - Rewriten Ignore filelist from file and filetypes filtering functions (major)
        - Improve calculating size of filtered files and filetypes
        - Update calculation from basic/bc to numfmt. Removed bc option
        - Added verification for not breaking hardlinks when an hardlinked file is filtered
    - Added testmode to cleaning empty folder function, and a min depth of 2.
    - [Fix ctime bug](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-ctime-bug) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.12
    - [Repair/optimize cache priming](https://github.com/R3yn4ld/ca.mover.tuning/tree/Better-cache-priming) ([R3yn4ld](https://github.com/R3yn4ld)).
    - Adding check to bc (un)installation routine
    - [Add bc (un)install option](https://github.com/R3yn4ld/ca.mover.tuning/tree/bc-nerdtools-dependancy) ([R3yn4ld](https://github.com/R3yn4ld))
    - Force test mode only on major upgrade, keep on minor ([R3yn4ld](https://github.com/R3yn4ld))
    - [Better cache priming](https://github.com/R3yn4ld/ca.mover.tuning/tree/better-cache-priming) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.11
    - [Allow operation without array if multiple pools](https://github.com/R3yn4ld/ca.mover.tuning/tree/Allow-operation-without-array-if-multiple-pools) ([R3yn4ld](https://github.com/R3yn4ld)): Fixed fatal error bug
    - Fixed error message about mover.pid and softstop file when installing the plugin or booting Unraid

- 2024.08.10
    - [Better filtering with ctime=no](https://github.com/R3yn4ld/ca.mover.tuning/tree/Better-method-for-filtering-with-ctime-%3Dno) ([R3yn4ld](https://github.com/R3yn4ld))
    - [Improved Synchronization](https://github.com/R3yn4ld/ca.mover.tuning/tree/Improve-synchronizing-from-secondary-to-primary) ([R3yn4ld](https://github.com/R3yn4ld)):
        - Improve synchronization by looking for files on cache first
        - Do not count synchronized files twice (freeing/priming target were half achieved)
        - Optimize Filtering File and Decision loops regarding Rebalance and Synchronize
    - Moved test mode on top of Mover Tuning Page
    - Add check for primary storage not existing (dust config files)

- 2024.08.07
    - Fix bug introduced by "Allow operation without array if multiple pools" preventing mover to run if less than 2 pools installed.
    - 2024-08-07
    - [Allow operation without array if multiple pools](https://github.com/R3yn4ld/ca.mover.tuning/tree/Allow-operation-without-array-if-multiple-pools) ([R3yn4ld](https://github.com/R3yn4ld)) Unraid 7.0.0.beta2 may be required for this to work (6.x gui might not allow to have pool as Primary and Secondary)
    - [Add cleanup empty folder function](https://github.com/R3yn4ld/ca.mover.tuning/tree/Add-cleanup-empty-folders) ([R3yn4ld](https://github.com/R3yn4ld)): Will delete empty folder if file have been moved.

- 2024.08.06
    - [Bug fixes](https://github.com/R3yn4ld/ca.mover.tuning/tree/2024-08-06-release5) ([R3yn4ld](https://github.com/R3yn4ld)) 
        - Resynchronize not working for share below moving threshold.
        - Internal mover moving files from Secondary to Primary instead of syncing (you may Resynchronize to correct the effect)
    - [Added Resynchronize all Primary files to Secondary option](https://github.com/R3yn4ld/ca.mover.tuning/tree/Resync-shares) ([R3yn4ld](https://github.com/R3yn4ld)): Resynchronize all Primary files to Secondary. This will resynchronize the Primary (cached) files on both Primary and Secondary (array) so they are backed up and parity protected. All files will be synchronized again independently of modification time. This can be a long operation. Run-once setting will reset back to No after next run
    - Minor bug fixes and improvements ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.05
    - [Rebalance shares](https://forums.unraid.net/topic/92126-smart-caching-script/) ([R3yn4ld](https://github.com/R3yn4ld)): Enhance previous "Repair Primary" option. Renamed it "Rebalance shares". This will move files from shares to their primary and secondary storage if spread elsewhere. May imply moving older files from Primary->Secondary or Secondary->Primary if allowed (cache:prefer or cache:yes) to free some space. 
    - Bug fixes ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.04
    - [Unraid 7.0.0 beta2 Secondary storage Compatibility](https://github.com/R3yn4ld/ca.mover.tuning/tree/Unraid-7.0.0-Secondary-storage-Compatibility) ([R3yn4ld](https://github.com/R3yn4ld)) minor enhancements (6.12 mover action naming) and... can now move between pools (tested on 7.0.0-beta2) ! 
    - [Fix find not ignoring hidden files](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-find-not-ignoring-hidden-files) ([R3yn4ld](https://github.com/R3yn4ld)) ([Thanks to helpful-tune3401](https://forums.unraid.net/topic/70783-plugin-mover-tuning/page/65/#comment-1449644))
    - [Fix default Settings handling causing a "Unary operator" bug](https://github.com/R3yn4ld/ca.mover.tuning/tree/Fix-unary-operator-bug) ([R3yn4ld](https://github.com/R3yn4ld)) ([thanks to Alturismo](https://forums.unraid.net/topic/70783-plugin-mover-tuning/page/64/#comment-1449175))
    - [Add freeing threshold option](https://github.com/R3yn4ld/ca.mover.tuning/tree/Add-freeing-threshold-option) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.08.01
    - [Deleted share error control and SoftStop improvement](https://github.com/R3yn4ld/ca.mover.tuning/tree/deleted-share-error-control) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.07.30
    - [Various bug fixes](https://github.com/R3yn4ld/ca.mover.tuning/tree/2024.07.29-various-bug-fixes) ([R3yn4ld](https://github.com/R3yn4ld)) ([Freender](https://github.com/freender))
    - [Enhance internal mover function](https://github.com/R3yn4ld/ca.mover.tuning/tree/Enhance-processTheMove-function) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.07.29
    - [Automatic Array to Cache](https://github.com/R3yn4ld/ca.mover.tuning/tree/automatic-array-to-cache)
    - Complete rewrite of file listing functions (find, decide to move..) ([R3yn4ld](https://github.com/R3yn4ld))
    - [Fix an issue with inaccurate capacity when raid z1 is used](https://github.com/R3yn4ld/ca.mover.tuning/pull/9/) Updated zfs functions getting usage of a pool ([Freender](https://github.com/freender))
    - Added cache mode "prefer" smart moving in "Automatic age" mode ([R3yn4ld](https://github.com/R3yn4ld))
    - Added option to "repair" Cache:Only (moving everything on share to cache) and Cache:No (moving everything on share to array) shares ([R3yn4ld](https://github.com/R3yn4ld))
    - Added option to synchronize Cache:Yes and Cache:Prefer shares to array so data are parity protected ([R3yn4ld](https://github.com/R3yn4ld))
    - Turbo write mode forcing improvement to not wake spinners if not needed ([R3yn4ld](https://github.com/R3yn4ld))
    - UI improvements ([R3yn4ld](https://github.com/R3yn4ld))

- 2024.07.10
    - [Unraid 7.0.0 compatibility](https://github.com/R3yn4ld/ca.mover.tuning/tree/unraid-7.0.0-compatibility) ([R3yn4ld](https://github.com/R3yn4ld)): original mover now works with "Move Now button follows plug-in filters" set to off - ([R3yn4ld](https://github.com/R3yn4ld))


- 2024.07.07:
    - [Unraid 7.0.0 compatibility](https://github.com/R3yn4ld/ca.mover.tuning/tree/unraid-7.0.0-compatibility) ([R3yn4ld](https://github.com/R3yn4ld))

- 2024-06-30: 
    - [Automatic age threshold](https://github.com/R3yn4ld/ca.mover.tuning/tree/automatic-age-threshold) ([R3yn4ld](https://github.com/R3yn4ld))
    - [Minor spelling corrections & README](https://github.com/dphelan/ca.mover.tuning/tree/spelling-corrections) ([Dphelan](https://github.com/dphelan))
    - [Merge share skipfiletypes](https://github.com/davendesai/unraid-mover-tuning/tree/merge-share-skipfiletypes) ([Davendsai](https://github.com/davendesai))(add/merge per share skipfilestype to global skips)
    - [Update Mover.tuning.page](https://github.com/Squidly271/ca.mover.tuning/tree/patch-2) ([Squid](https://github.com/Squidly271))

- 2023.12.19 (was not in [master branch from hugenbd](https://github.com/hugenbd/ca.mover.tuning))
    - [4 changes from Swarles](https://github.com/hugenbd/ca.mover.tuning/commit/64e06e91bd83431d768346e4d8158f7be039564e) ([Swarles](https://forums.unraid.net/profile/213067-swarles/))
        - Change "while read" lines in age_mover to "while IFS= read -r" to fix trailing white spaces (Swarles)
        - Fix where sometimes mover would not run to mover.old scrip (Swarles)
        - Log if "share.cfg" doesn't exists to help trouble shooting (Swarles)
        - Check for ca.mover.tuning.cfg file and additional logging. (Swarles)

## Installation

You can download and install plugins with [Community Apps](https://unraid.net/community/apps/c/plugins).

## Configuration

You'll find its settings within Settings - [Scheduler](https://docs.unraid.net/unraid-os/manual/additional-settings/#scheduler).

## Usage

After installation, the default settings are set so that the plugin will be in test mode. You may check /tmp/ca.mover.tuning/Mover_actions_date.list to see if your settings are correct and if the mover will move/keep/sync the files as expected.

There are several commands that can be launched from terminal or a script:
/usr/local/emhttp/plugins/ca.mover.tuning/age_mover start
To start age mover (the internal moving engine) with the settings you set in the GUI

/usr/local/emhttp/plugins/ca.mover.tuning/age_mover softstop
To cleanly exit loops (Filtering, Deciding, Moving) and age_mover. While moving/syncing, the ongoing file transfer is not interrupted and softstop occurs after actual file operation.

/usr/local/emhttp/plugins/ca.mover.tuning/age_mover stop
To kill all the process (can lead to unfinished or corrupted file transferts while moving).


See the [Mover Tuning_ thread on the Unraid support forum](https://forums.unraid.net/topic/70783-plugin-mover-tuning/) for more details and discussions.

## Thanks

This was originally created by [Squid](https://github.com/Squidly271).<br>

@2023 - Updated by [hugenbd](https://github.com/hugenbd/ca.mover.tuning), with contributions by [Castcore](https://github.com/Castcore), [Swarles](https://github.com/hugenbd/ca.mover.tuning/commit/64e06e91bd83431d768346e4d8158f7be039564e), [Dphelan](https://github.com/dphelan) and [Davendsai](https://github.com/davendesai).

@2024 - Updated by [R3yn4ld](https://github.com/R3yn4ld/ca.mover.tuning).

@2025 - Updated by [masterwishx](https://github.com/masterwishx/ca.mover.tuning).
