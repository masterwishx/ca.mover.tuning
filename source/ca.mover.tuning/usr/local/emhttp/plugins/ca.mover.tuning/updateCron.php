#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini") ?: [];

// Get config value of forced cron
$cfg_cronEnabled = $cfg['force'];
// Get cron time of forced cron (normalized)
$cfg_cron = trim($cfg['cron'] ?? '');
// Get config value of mover disabled
$cfg_moverDisabled = $cfg['moverDisabled'];
// Get Mover Tuning cron time (normalized)
$cfg_moverTuneCron = trim($cfg['moverTuneCron'] ?? $vars['shareMoverSchedule'] ?? '');

/** Writes a message to syslog under the "move" tag when plugin logging is enabled; errors are always written */
function logger($string)
{
	global $cfg;

	if ($cfg['logging'] === 'yes' || strpos($string, 'Error:') === 0) {
		exec("logger -t move " . escapeshellarg($string));
	}
}

// A form field as a string; anything else, such as an array, counts as empty
function post_string($key)
{
	return isset($_POST[$key]) === true && is_string($_POST[$key]) === true ? $_POST[$key] : '';
}

// Five fields of * / n / n-m lists with an optional /step, each within its range; anything else would land in root's crontab.
// dcron's @hourly..@yearly forms need an ID= job name the writers below do not add, so they are not accepted.
function valid_cron($cron)
{
	$fields = preg_split('/[ \t]+/', $cron);
	if (count($fields) !== 5) {
		return false;
	}
	$limits = [
		[0, 59, []],
		[0, 23, []],
		[1, 31, []],
		[1, 12, ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec']],
		[0, 7, ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']],
	];
	foreach ($fields as $i => $field) {
		if (cron_field_ok($field, $limits[$i][0], $limits[$i][1], $limits[$i][2]) === false) {
			return false;
		}
	}
	return true;
}

// One cron field: a comma list of * / n / n-m, each with an optional /step; numbers within min..max, names looked up in $names
function cron_field_ok($field, $min, $max, $names)
{
	foreach (explode(',', $field) as $item) {
		if (preg_match('/^(\*|([a-z0-9]+)(?:-([a-z0-9]+))?)(?:\/([0-9]+))?\z/i', $item, $m) !== 1) {
			return false;
		}
		if (isset($m[4]) === true && (int)$m[4] < 1) {
			return false;
		}
		if ($m[1] === '*') {
			continue;
		}
		foreach ([$m[2], $m[3] ?? ''] as $value) {
			if ($value === '') {
				continue;
			}
			// names count from $min, so jan is 1 and sun is 0
			$index = array_search(strtolower($value), $names, true);
			$n = ctype_digit($value) === true ? (int)$value : ($index === false ? -1 : $index + $min);
			if ($n < $min || $n > $max) {
				return false;
			}
		}
	}
	return true;
}

/** Writes Unraid's mover.cron from the Mover Settings schedule, before Unraid 7.2.1; true when the file was written */
function make_unraid_cron()
{
	global $vars;

	if (!empty($vars['shareMoverSchedule'])) {
		$moverCron = trim($vars['shareMoverSchedule']);
		if (valid_cron($moverCron) === false) {
			logger("Error: Invalid Unraid mover schedule: " . preg_replace('/[^[:print:]]/', '?', $moverCron));
			return false;
		}
		$cronMoverFile = "# Generated mover schedule:\n" . $moverCron . " /usr/local/sbin/mover start |& logger -t move\n\n";
		if (file_put_contents("/boot/config/plugins/dynamix/mover.cron", $cronMoverFile) === false) {
			logger("Error: Failed to write mover.cron file.");
			return false;
		}
		return true;
	}
	logger("No mover schedule set in Mover Settings.");
	return false;
}

/** Writes mover.tuning.cron for the $tuneCron schedule, from Unraid 7.2.1; true when the file was written */
function make_tune_cron($tuneCron)
{
	if (empty($tuneCron)) {
		logger("No cron schedule provided for Mover Tuning move.");
		return false; // Nothing to write
	}
	if (valid_cron($tuneCron) === false) {
		logger("Error: Invalid cron schedule for Mover Tuning move: " . preg_replace('/[^[:print:]]/', '?', $tuneCron));
		return false;
	}
	$cronTuneFile = "# Generated schedule for Mover Tuning move:\n" . $tuneCron . " /usr/local/emhttp/plugins/ca.mover.tuning/mover start |& logger -t move\n\n";
	if (file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron", $cronTuneFile) === false) {
		logger("Error: Failed to write mover.tuning.cron file.");
		return false;
	}
	return true;
}

/** Writes the forced move's mover.cron for the $cron schedule, run through mover.php force; true when the file was written */
function make_cron($cron)
{
	if (empty($cron)) {
		logger("No cron schedule provided for forced move.");
		return false;
	}
	if (valid_cron($cron) === false) {
		logger("Error: Invalid cron schedule for forced move: " . preg_replace('/[^[:print:]]/', '?', $cron));
		return false;
	}
	$cronFile = "# Generated schedule for forced move:\n{$cron} /usr/local/emhttp/plugins/ca.mover.tuning/mover.php force start |& logger -t move\n\n";
	if (file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile) === false) {
		logger("Error: Failed to write forced mover.cron file.");
		return false;
	}
	return true;
}

/** Deletes a cron file; false, with an error logged, when it exists and cannot be deleted */
function remove_cron_file($file)
{
	if (file_exists($file) === false) {
		return true;
	}
	if (@unlink($file) === false) {
		logger("Error: Failed to remove $file.");
		return false;
	}
	return true;
}

// Check if value was changed to prevent the logger of printing when cron was not changed and not make cron file when avalible already
if ($cfg_cronEnabled != $_POST['cronEnabled']) {
	if ($_POST['cronEnabled'] == "yes") {
		if (make_cron(trim(post_string('cron'))) === true) {
			logger("Forced move schedule enabled successfully.");
		}
	} elseif (remove_cron_file("/boot/config/plugins/ca.mover.tuning/mover.cron") === true) {
		logger("Forced move schedule disabled successfully.");
	}
} else {
	// If cron already enabled and cron time was changed update cron file
	if ($cfg_cronEnabled == "yes" && $cfg_cron != $_POST['cron']) {
		if (make_cron(trim(post_string('cron'))) === true) {
			logger("Forced move schedule updated successfully.");
		}
	}
}

// Check if value was changed
if ($cfg_moverDisabled != $_POST["ismoverDisabled"]) {
	// If mover schedule is disabled
	if ($_POST['ismoverDisabled'] == "yes") {
		if (version_compare($vars['version'], '7.2.1', '>=')) {
			// Check if the file exists
			if (file_exists("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron") === false) {
				logger("Mover Tuning cron file does not exist");
			} elseif (remove_cron_file("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron") === true) {
				logger("Mover Tuning schedule disabled successfully.");
			}
		} else {
			// Check if the file exists
			if (file_exists("/boot/config/plugins/dynamix/mover.cron") === false) {
				logger("Mover cron file does not exist");
			} elseif (remove_cron_file("/boot/config/plugins/dynamix/mover.cron") === true) {
				logger("Mover schedule disabled successfully.");
			}
		}
	} else {
		if (version_compare($vars['version'], '7.2.1', '>=')) {
			$tuneCron = isset($_POST['tune_cron']) === true ? trim(post_string('tune_cron')) : $cfg_moverTuneCron;
			if (make_tune_cron($tuneCron) === true) {
				logger("Mover Tuning schedule enabled successfully.");
			}
		} elseif (make_unraid_cron() === true) {
			logger("Mover schedule enabled successfully.");
		}
	}
}

// Handle Mover Tuning custom cron schedule, unless this request disables Mover Tuning
if (version_compare($vars['version'], '7.2.1', '>=') === true && ($_POST['ismoverDisabled'] ?? '') !== 'yes') {
	$postTuneCron = post_string('tune_cron');
	if ($cfg_moverTuneCron !== $postTuneCron) {
		$tuneCron = trim($postTuneCron);
		if ($tuneCron === "" && remove_cron_file("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron") === true) {
			logger("Mover Tuning cron schedule removed.");
		} elseif ($tuneCron !== "" && make_tune_cron($tuneCron) === true) {
			logger("Mover Tuning cron schedule updated successfully.");
		}
	}
}

exec("update_cron");
?>