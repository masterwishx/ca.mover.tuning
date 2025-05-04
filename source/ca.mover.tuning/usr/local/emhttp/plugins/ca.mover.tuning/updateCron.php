#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");

// Get config value of forced cron
$cfg_cronEnabled = $cfg['force'];
// Get config value of mover disabled
$cfg_moverDisabled = $cfg['moverDisabled'];

function logger($string)
{
	global $cfg;

	if ($cfg['logging'] == 'yes') {
		exec("logger -t move " . escapeshellarg($string));
	}
}

// Check if value was changed to prevent the logger of printing when cron was not changed and not make cron file when avalible already
if ($cfg_cronEnabled != $_POST['cronEnabled']) {
	if ($_POST['cronEnabled'] == "yes") {
		$cronFile = "# Generated schedule for forced move\n" . trim($_POST['cron']) . " /usr/local/sbin/mover.old start |& logger -t move\n\n";
		file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile);
		logger("Unraid mover schedule enabled successfully.");
	} else {
		@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
		logger("Unraid mover schedule disabled successfully.");
	}
}

// Check if value was changed
if ($cfg_moverDisabled != $_POST["ismoverDisabled"]) {
	// If mover schedule is disabled then rename 'mover.cron' to 'mover.cron.disabled'
	if ($_POST['ismoverDisabled'] == "yes") {
		// Check if the file exists before attempting to rename it
		if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
			if (!rename("/boot/config/plugins/dynamix/mover.cron", "/boot/config/plugins/dynamix/mover.cron.disabled")) {
				logger("Error: Failed to rename mover cron file");
			} else {
				logger("Mover schedule disabled successfully.");
			}
		} else {
			logger("Error: Mover cron file does not exist");
		}
	} else {
		// If mover schedule is enabled then rename back
		if (file_exists("/boot/config/plugins/dynamix/mover.cron.disabled")) {
			if (!rename("/boot/config/plugins/dynamix/mover.cron.disabled", "/boot/config/plugins/dynamix/mover.cron")) {
				logger("Error: Failed to rename mover cron file");
			} else {
				logger("Mover schedule enabled successfully.");
			}
		} else {
			logger("Error: Mover cron file does not exist");
		}
	}
}

exec("update_cron");
?>