#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini") ?: [];
$file = "/var/local/emhttp/var.ini";

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

function make_tune_cron()
{
	global $vars,$file;
	if (!empty($vars['shareMoverSchedule'])) {
		// Disable Unraid mover
		$vars['shareMoverSchedule'] = "";
		// Read the file into an array of lines
		$lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

		// Loop through each line and replace the target
		foreach ($lines as &$line) {
			if (strpos($line, 'shareMoverSchedule=') === 0) {
				$line = 'shareMoverSchedule=""'; // change value
			}
		}

		// Write the updated lines back to the file
		file_put_contents($file, implode("\n", $lines) . "\n");
	}

	$tuneCron = isset($_POST['tune_cron']) ? trim($_POST['tune_cron']) : '';
	$cronTuneFile = "# Generated schedule for Mover Tuning move\n" . $tuneCron . " /usr/local/emhttp/plugins/ca.mover.tuning/age_mover start |& logger -t move\n\n";
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.tuning.cron", $cronTuneFile);
}

function make_cron()
{
	global $vars;
	$version = $vars['version'] ?? '0.0.0';
	$mover = version_compare($version, '7.2.1', '<') ? '/usr/local/sbin/mover.old' : '/usr/local/sbin/mover';
	$cron = isset($_POST['cron']) ? trim($_POST['cron']) : '';
	$cronFile = "# Generated schedule for forced move\n{$cron} {$mover} start |& logger -t move\n\n";
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile);
}

// Check if value was changed to prevent the logger of printing when cron was not changed and not make cron file when avalible already
if ($cfg_cronEnabled != $_POST['cronEnabled']) {
	if ($_POST['cronEnabled'] == "yes") {
		make_cron();
		logger("Unraid mover schedule enabled successfully.");
	} else {
		@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
		logger("Unraid mover schedule disabled successfully.");
	}
} else {
	// If cron already enabled and cron time was changed update cron file
	if ($cfg_cronEnabled == "yes" && $cfg_cron != $_POST['cron']) {
		make_cron();
		logger("Unraid mover schedule time updated successfully.");
	}
}

// Check if value was changed
if ($cfg_moverDisabled != $_POST["ismoverDisabled"]) {
	// If mover schedule is disabled
	if ($_POST['ismoverDisabled'] == "yes") {
		// Check if the file exists
		if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
			logger("Mover schedule disabled successfully.");
		} else {
			logger("Error: Mover cron file does not exist");
		}
	} else {
		// If mover schedule is enabled
		if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
			logger("Mover schedule enabled successfully.");
		} else {
			logger("Error: Mover cron file does not exist");
		}
	}
}

// Handle Mover Tuning custom cron schedule
if ($cfg_moverTuneCron != $_POST['tune_cron']) {

	if (trim($_POST['tune_cron']) != "") {
		make_tune_cron();
		logger("Mover Tuning cron schedule updated successfully.");
	} else {
		@unlink("/boot/config/plugins/ca.mover.tuning/mover.tune.cron");
		logger("Mover Tuning cron schedule removed.");
	}
}

exec("update_cron");
?>