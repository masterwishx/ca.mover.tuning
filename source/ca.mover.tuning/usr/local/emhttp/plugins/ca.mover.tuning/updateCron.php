#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");
require_once("/usr/local/emhttp/plugins/ca.mover.tuning/cronSchedule.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$vars = is_array($vars) === true ? $vars : [];
// var.ini does not exist yet while plugins install at boot, before emhttp starts; empty when neither file gives it
if (isset($vars['version']) === false) {
	$release = @parse_ini_file("/etc/unraid-version");
	$vars['version'] = $release['version'] ?? '';
}

// Get config value of forced cron
$cfg_cronEnabled = $cfg['force'];
// Get cron time of forced cron (normalized)
$cfg_cron = trim($cfg['cron'] ?? '');
// Get config value of mover disabled
$cfg_moverDisabled = $cfg['moverDisabled'];
// Get Mover Tuning cron time (normalized)
$cfg_moverTuneCron = trim($cfg['moverTuneCron'] ?? '');
// Get config value of the cache watchdog
$cfg_watchdog = $cfg['watchdog'] ?? '';

// "Error:" lines logged so far; sync and apply exit 1 when there are any
$loggedErrors = 0;

/** Writes a message to syslog under the "move" tag when plugin logging is enabled; errors are always written, and counted */
function logger($string)
{
	global $cfg, $loggedErrors;

	$isError = strpos($string, 'Error:') === 0;
	if ($isError === true) {
		$loggedErrors++;
	}
	if ($cfg['logging'] === 'yes' || $isError === true) {
		// the message goes through the environment so the command stays literal for the code scanner
		putenv("MT_LOG_MESSAGE=$string");
		exec('logger -t move "$MT_LOG_MESSAGE"');
	}
}

/** Writes $content to the cron file $file and logs $done, unless the file already holds it; logs an error when the write fails */
function put_cron_file($file, $content, $done)
{
	if (is_file($file) === true && file_get_contents($file) === $content) {
		return;
	}
	if (file_put_contents($file, $content) === false) {
		logger("Error: Failed to write $file.");
		return;
	}
	logger($done);
}

/** Makes Unraid's mover.cron run the Mover Settings schedule, before Unraid 7.2.1 */
function make_unraid_cron()
{
	global $vars;

	if (empty($vars['shareMoverSchedule']) === false) {
		$moverCron = trim($vars['shareMoverSchedule']);
		if (valid_cron($moverCron) === false) {
			logger("Error: Invalid Unraid mover schedule: " . preg_replace('/[^[:print:]]/', '?', $moverCron));
			return;
		}
		$cronMoverFile = "# Generated mover schedule:\n" . $moverCron . " /usr/local/sbin/mover start |& logger -t move\n\n";
		put_cron_file("/boot/config/plugins/dynamix/mover.cron", $cronMoverFile, "Mover schedule set to $moverCron.");
		return;
	}
	logger("No mover schedule set in Mover Settings.");
}

/** Makes mover.tuning.cron run Mover Tuning on the $tuneCron schedule, from Unraid 7.2.1 */
function make_tune_cron($tuneCron)
{
	if (valid_cron($tuneCron) === false) {
		logger("Error: Invalid cron schedule for Mover Tuning move: " . preg_replace('/[^[:print:]]/', '?', $tuneCron));
		return;
	}
	$cronTuneFile = "# Generated schedule for Mover Tuning move:\n" . $tuneCron . " /usr/local/emhttp/plugins/ca.mover.tuning/mover start |& logger -t move\n\n";
	put_cron_file("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron", $cronTuneFile, "Mover Tuning schedule set to $tuneCron.");
}

/** Makes the forced move's mover.cron run mover.php force on the $cron schedule */
function make_cron($cron)
{
	if (valid_cron($cron) === false) {
		logger("Error: Invalid cron schedule for forced move: " . preg_replace('/[^[:print:]]/', '?', $cron));
		return;
	}
	$cronFile = "# Generated schedule for forced move:\n{$cron} /usr/local/emhttp/plugins/ca.mover.tuning/mover.php force start |& logger -t move\n\n";
	put_cron_file("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile, "Forced move schedule set to $cron.");
}

/** Makes mover.watchdog.cron run the cache watchdog every 5 minutes (a run it starts logs to syslog itself, so the line discards output) */
function make_watchdog_cron()
{
	$cronFile = "# Generated schedule for the Mover Tuning cache watchdog:\n*/5 * * * * /usr/local/emhttp/plugins/ca.mover.tuning/age_mover watchdog >/dev/null 2>&1\n\n";
	put_cron_file("/boot/config/plugins/ca.mover.tuning/mover.watchdog.cron", $cronFile, "Cache watchdog schedule set to every 5 minutes.");
}

/** Deletes a cron file, logging $why when given; false, with an error logged, when it exists and cannot be deleted */
function remove_cron_file($file, $why = '')
{
	if (file_exists($file) === false) {
		return true;
	}
	if (@unlink($file) === false) {
		logger("Error: Failed to remove $file.");
		return false;
	}
	if ($why !== '') {
		logger("Removed $file: $why.");
	}
	return true;
}

/** Writes each plugin cron file the saved settings call for when missing or different (an invalid schedule is logged, its file kept), removes the rest; false when the settings file does not parse */
function sync_cron_files()
{
	// parse_plugin_cfg reads it with my_parse_ini_file from Unraid 6.12.14, parse_ini_file before; a file that does not
	// parse leaves only default.cfg in $cfg from 7.2.0 (null on 6.9), which would remove every cron file
	$cfgFile = "/boot/config/plugins/ca.mover.tuning/ca.mover.tuning.cfg";
	if (file_exists($cfgFile) === true) {
		$saved = function_exists('my_parse_ini_file') === true ? @my_parse_ini_file($cfgFile) : @parse_ini_file($cfgFile);
		if (is_array($saved) === false) {
			logger("Error: $cfgFile does not parse, so the cron files are left as they are.");
			return false;
		}
	}
	sync_forced_cron();
	sync_tune_cron();
	sync_watchdog_cron();
	retire_unraid_cron();
	return true;
}

/** sync_cron_files() for the forced move's mover.cron */
function sync_forced_cron()
{
	global $cfg_cronEnabled, $cfg_cron;

	$forcedFile = "/boot/config/plugins/ca.mover.tuning/mover.cron";
	if ($cfg_cronEnabled !== 'yes') {
		remove_cron_file($forcedFile, "force move is off");
	} elseif ($cfg_cron === '') {
		remove_cron_file($forcedFile, "no forced move schedule is set");
	} else {
		make_cron($cfg_cron);
	}
}

/** sync_cron_files() for mover.tuning.cron, the Mover Tuning schedule from Unraid 7.2.1 */
function sync_tune_cron()
{
	global $vars, $cfg_moverDisabled, $cfg_moverTuneCron;

	$tuneFile = "/boot/config/plugins/ca.mover.tuning/mover.tuning.cron";
	if ($vars['version'] === '') {
		logger("Error: The Unraid version is unknown, so $tuneFile is left as it is.");
	} elseif (version_compare($vars['version'], '7.2.1', '<') === true) {
		remove_cron_file($tuneFile, "Unraid before 7.2.1 has no separate Mover Tuning schedule");
	} elseif ($cfg_moverDisabled === 'yes') {
		remove_cron_file($tuneFile, "the Mover Tuning schedule is disabled");
	} elseif ($cfg_moverTuneCron === '') {
		remove_cron_file($tuneFile, "no Mover Tuning schedule is set");
	} else {
		make_tune_cron($cfg_moverTuneCron);
	}
}

/** sync_cron_files() for mover.watchdog.cron, the cache watchdog */
function sync_watchdog_cron()
{
	global $cfg_watchdog;

	$watchdogFile = "/boot/config/plugins/ca.mover.tuning/mover.watchdog.cron";
	if ($cfg_watchdog !== 'yes') {
		remove_cron_file($watchdogFile, "the cache watchdog is off");
	} else {
		make_watchdog_cron();
	}
}

/** From Unraid 7.2.1, after the install migrated Unraid's schedule: renames Unraid's mover.cron to mover.cron.old once mover.tuning.cron exists or the schedule is disabled */
function retire_unraid_cron()
{
	global $vars, $cfg_moverDisabled;

	$mark = "/boot/config/plugins/ca.mover.tuning/retire.unraid.schedule";
	$unraidFile = "/boot/config/plugins/dynamix/mover.cron";
	if (is_file($mark) === false || $vars['version'] === '' || version_compare($vars['version'], '7.2.1', '<') === true) {
		return;
	}
	if ($cfg_moverDisabled !== 'yes' && is_file("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron") === false) {
		logger("Unraid's mover schedule in $unraidFile is kept: mover.tuning.cron is not written yet.");
		return;
	}
	if (is_file($unraidFile) === true) {
		if (@rename($unraidFile, "$unraidFile.old") === false) {
			logger("Error: Failed to rename $unraidFile to mover.cron.old.");
			return;
		}
		logger("Retired Unraid's mover schedule: $unraidFile is now mover.cron.old.");
	}
	if (@unlink($mark) === false) {
		logger("Error: Failed to remove $mark.");
	}
}

/** Before Unraid 7.2.1, where Unraid's own mover.cron starts Mover Tuning: removed while the schedule is disabled, else written back when missing and the array is started */
function apply_unraid_cron()
{
	global $vars, $cfg_moverDisabled;

	$unraidFile = "/boot/config/plugins/dynamix/mover.cron";
	if ($vars['version'] === '' || version_compare($vars['version'], '7.2.1', '>=') === true) {
		return;
	}
	if ($cfg_moverDisabled === 'yes') {
		remove_cron_file($unraidFile, "the Mover Tuning schedule is disabled");
	} elseif (is_file($unraidFile) === false && ($vars['mdState'] ?? '') === 'STARTED') {
		// as emhttpd does: it writes this file from Mover Settings and removes it at array stop
		make_unraid_cron();
	}
}

// "sync" runs at plugin install, whose caller runs update_cron; "apply" runs at age_mover reset and as the settings form's
// #command, which update.php runs once it has saved the settings. A web request, such as a page loaded before an update, does nothing.
$mode = PHP_SAPI === 'cli' ? ($argv[1] ?? '') : '';
if ($mode === 'sync') {
	sync_cron_files();
} elseif ($mode === 'apply') {
	if (sync_cron_files() === true) {
		apply_unraid_cron();
	}
	exec("/usr/local/sbin/update_cron", $output, $status);
	if ($status !== 0) {
		logger("Error: /usr/local/sbin/update_cron exited with $status, so crond may still run the previous schedules.");
	}
}
exit($loggedErrors === 0 ? 0 : 1);
?>