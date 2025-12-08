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

function logger($string)
{
	global $cfg;

	if ($cfg['logging'] == 'yes') {
		exec("logger -t move " . escapeshellarg($string));
	}
}

// Unraid Mover cron for unraid v7.2.1+
function make_unraid_cron()
{
	global $vars;

	if (!empty($vars['shareMoverSchedule'])) {
		$moverCron = trim($vars['shareMoverSchedule']);
		$cronMoverFile = "# Generated mover schedule:\n" . $moverCron . " /usr/local/sbin/mover start |& logger -t move\n\n";
		if (file_put_contents("/boot/config/plugins/dynamix/mover.cron", $cronMoverFile) === false) {
			logger("Error: Failed to write mover.cron file.");
		}
	}
}

// Mover Tuning cron for unraid v7.2.1+
function make_tune_cron()
{
	global $cfg_moverTuneCron;
	$tuneCron = isset($_POST['tune_cron']) ? trim($_POST['tune_cron']) : $cfg_moverTuneCron;
	if (empty($tuneCron)) {
		logger("Error: No cron schedule provided for Mover Tuning move.");
		return; // Nothing to write
	}
	$cronTuneFile = "# Generated schedule for Mover Tuning move:\n" . $tuneCron . " /usr/local/emhttp/plugins/ca.mover.tuning/age_mover start |& logger -t move\n\n";
	if (file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron", $cronTuneFile) === false) {
		logger("Error: Failed to write mover.tuning.cron file.");
	}
}

// Cron for forced move (unraid mover)
function make_cron()
{
	global $vars;
	$version = $vars['version'] ?? '0.0.0';
	$mover = version_compare($version, '7.2.1', '<') ? '/usr/local/sbin/mover.old' : '/usr/local/sbin/mover';
	$cron = isset($_POST['cron']) ? trim($_POST['cron']) : '';
	if (empty($cron)) {
		logger("Error: No cron schedule provided for forced move.");
		return;
	}
	$cronFile = "# Generated schedule for forced move:\n{$cron} {$mover} start |& logger -t move\n\n";
	if (file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile) === false) {
		logger("Error: Failed to write forced mover.cron file.");
	}
}

// Check if value was changed to prevent the logger of printing when cron was not changed and not make cron file when avalible already
if ($cfg_cronEnabled != $_POST['cronEnabled']) {
	if ($_POST['cronEnabled'] == "yes") {
		make_cron();
		logger("Forced move schedule enabled successfully.");
	} else {
		@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
		logger("Forced move schedule disabled successfully.");
	}
} else {
	// If cron already enabled and cron time was changed update cron file
	if ($cfg_cronEnabled == "yes" && $cfg_cron != $_POST['cron']) {
		make_cron();
		logger("Forced move schedule updated successfully.");
	}
}

// Check if value was changed
if ($cfg_moverDisabled != $_POST["ismoverDisabled"]) {
	// If mover schedule is disabled
	if ($_POST['ismoverDisabled'] == "yes") {
		// Check if the file exists
		if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
			@unlink("/boot/config/plugins/dynamix/mover.cron");
			logger("Mover schedule disabled successfully.");
		} else {
			logger("Error: Mover cron file does not exist");
		}
		if (version_compare($vars['version'], '7.2.1', '>=')) {
			// Check if the file exists
			if (file_exists("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron")) {
				@unlink("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron");
				logger("Mover Tuning schedule disabled successfully.");
			} else {
				logger("Error: Mover Tuning cron file does not exist");
			}
		}
	} else {
		// If mover schedule is enabled
		make_unraid_cron();
		if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
			logger("Mover schedule enabled successfully.");
		} else {
			logger("Error: Failed to create mover cron file.");
		}
		if (version_compare($vars['version'], '7.2.1', '>=')) {
			// Check if the file exists
			make_tune_cron();
			if (file_exists("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron")) {
				logger("Mover Tuning schedule enabled successfully.");
			} else {
				logger("Error: Failed to create Mover Tuning cron file.");
			}
		}
	}
}

// Handle Mover Tuning custom cron schedule
if (version_compare($vars['version'], '7.2.1', '>=')) {
	$postTuneCron = isset($_POST['tune_cron']) ? $_POST['tune_cron'] : '';
	if ($cfg_moverTuneCron !== $postTuneCron) {
		if (trim($postTuneCron) !== "") {
			make_tune_cron();
			logger("Mover Tuning cron schedule updated successfully.");
		} else {
			@unlink("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron");
			logger("Mover Tuning cron schedule removed.");
		}
	}
}

exec("update_cron");
?>