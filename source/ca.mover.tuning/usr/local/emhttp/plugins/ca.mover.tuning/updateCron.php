#!/usr/bin/php
<?PHP

if ($_POST['cronEnabled'] == "yes") {
	$cronFile = "# Generated schedule for forced move\n" . trim($_POST['cron']) . " /usr/local/sbin/mover.old start |& logger -t move\n\n";
	file_put_contents("/boot/config/plugins/ca.mover.tuning/mover.cron", $cronFile);
} else {
	@unlink("/boot/config/plugins/ca.mover.tuning/mover.cron");
}

# if mover schedule is disabled then rename 'mover.cron' to 'mover.cron.disabled'
if ($_POST['ismoverDisabled'] == "yes") {
	// Check if the file exists before attempting to rename it
	if (file_exists("/boot/config/plugins/dynamix/mover.cron")) {
		rename("/boot/config/plugins/dynamix/mover.cron", "/boot/config/plugins/dynamix/mover.cron.disabled");
	}
} else {
	# if mover schedule is enabled then rename back
	if (file_exists("/boot/config/plugins/dynamix/mover.cron.disabled")) {
		rename("/boot/config/plugins/dynamix/mover.cron.disabled", "/boot/config/plugins/dynamix/mover.cron");
	}
}

exec("update_cron");
?>