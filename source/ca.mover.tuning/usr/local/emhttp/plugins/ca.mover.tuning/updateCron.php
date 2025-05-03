#!/usr/bin/php
<?PHP

if ($_POST['cronEnabled'] == "yes") {
	$cronFile = "# Generated schedule for forced move\n" . trim($_POST['cron']) . " /usr/local/sbin/mover.old start |& logger -t move\n\n";
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile);
} else {
	@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
}

// If mover schedule is disabled then rename 'mover.cron' to 'mover.cron.disabled'
if ($_POST['ismoverDisabled'] == "yes") {
	// Check if the file exists before attempting to rename it
	if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
		if (!rename("/boot/config/plugins/dynamix/mover.cron", "/boot/config/plugins/dynamix/mover.cron.disabled")) {
			echo ("ERROR: Failed to disable mover cron file");
		}
	}
} else {
	// If mover schedule is enabled then rename back
	if (file_exists("/boot/config/plugins/dynamix/mover.cron.disabled")) {
		if (!rename("/boot/config/plugins/dynamix/mover.cron.disabled", "/boot/config/plugins/dynamix/mover.cron")) {
			echo ("ERROR: Failed to enable mover cron file");
		}
	}
}

exec("update_cron");
?>