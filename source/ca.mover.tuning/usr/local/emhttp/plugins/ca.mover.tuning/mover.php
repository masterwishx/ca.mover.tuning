#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$cron = $argv[1] == "crond";
$bash = $argv[1] == "bash";
$args = [];

function logger($string)
{
    global $cfg;

    if ($cfg['logging'] == 'yes') {
        exec("logger -t move " . escapeshellarg($string));
    }
}

//function startMover($options = "start")
function startMover()
{
    global $vars, $cfg, $cron, $bash, $argv, $args;

    logger("Starting Mover Tuning ...");

    if ($argv[2]) {
        $args[] = trim($argv[2]);
    }

    if ($cfg['debuglogging'] == 'yes') {
        // If run manually by bash cli
        if ($bash) {
            logger("Manually executed (bash)\n");
        }
        // If run via crond then log it as cron
        else if ($cron) {
            logger("Auto executed (crond)\n");
        }
        // If run manually by button, $argv[1] is not set (""), then log it as move button
        else if (empty($argv[1])) {
            logger("Manually executed (Move button)\n");
        }
    }

    if (!$cron) {
        // Example usage of specific arguments
        if (isset($args[0])) {
            $option1 = $args[0];
            if ($cfg['debuglogging'] == 'yes') {
                logger("Option 1: $option1\n");
            }
            // Fix for Unraid v6.x that emhttp run mover without "start" parametr
        } else if (version_compare($vars['version'], '7.0.0', '<')) {
            $args[0] = 'start';
            $option1 = $args[0];
            if ($cfg['debuglogging'] == 'yes') {
                logger("Option 1 set to 'start' due to version < 7.0.0\n");
            }
            // For Unraid v7.2.1+, use $_POST for pressed move now button in plugin page
        } else if (version_compare($vars['version'], '7.2.1', '>=')) {
            if (isset($_POST['cmdStartTuneMover'])) {
                $args[0] = 'start';
                $option1 = $args[0];
                if ($cfg['debuglogging'] == 'yes') {
                    logger("Option 1 set to 'start' due to version >= 7.2.1\n");
                }
            }
        }

        // Combine all arguments into a single string with spaces
        $options = implode(' ', $args);

        // Example usage of $options
        if ($cfg['debuglogging'] == 'yes') {
            logger("Options: $options\n");
        }
    } else {
        $options = "start";
        logger("Cron + options: $options");
    }

    if ($options != "stop") {
        clearstatcache();
        $pid = @file_get_contents("/var/run/mover.pid");
        if ($pid) {
            logger("Mover already running");
            exit();
        }
    }

    // If Force move enabled
    if ($cfg['force'] == "yes") {
        if ($cfg['forceParity'] == "no" && $vars['mdResyncPos']) {
            logger("Parity Check / Rebuild in Progress.  Not running forced move");
            exit();
        }
    }

    // Check if Move Now button follows plug-in filters
    if ($cfg['movenow'] == "yes") {
        $mover_str = "/usr/local/emhttp/plugins/ca.mover.tuning/age_mover";
    } else {
        if (version_compare($vars['version'], '7.2.1', '<')) {
            $mover_str = "/usr/local/sbin/mover.old";
        } else {
            $mover_str = "/usr/local/sbin/mover";
        }
    }

    if ($options == "stop") {
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";
        logger("ionice $ioLevel nice -n $niceLevel $mover_str stop");
        passthru("ionice $ioLevel nice -n $niceLevel $mover_str stop");
        exit();
    }

    if ($cron or $cfg['movenow'] == "yes") {
        //exec("echo 'running from cron or move now question is yes' >> /var/log/syslog");
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";

        if ($cfg['movingThreshold'] >= 0 or $cfg['fillupThreshold'] >= 0 or $cfg['age'] == "yes" or $cfg['sizef'] == "yes" or $cfg['sparsnessf'] == "yes" or $cfg['filelistf'] == "yes" or $cfg['filetypesf'] == "yes" or $cfg['beforescript'] != '' or $cfg['afterscript'] != '' or $cfg['testmode'] == "yes") {
            $age_mover_str = "/usr/local/emhttp/plugins/ca.mover.tuning/age_mover";
            //exec("echo 'about to hit mover string here: $age_mover_str' >> /var/log/syslog");
            logger("ionice $ioLevel nice -n $niceLevel $age_mover_str $options");
            passthru("ionice $ioLevel nice -n $niceLevel $age_mover_str $options");
        }
    } else {
        //exec("echo 'Running from button' >> /var/log/syslog");
        //Default "move now" button has been hit.
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";
        logger("ionice $ioLevel nice -n $niceLevel $mover_str $options");
        passthru("ionice $ioLevel nice -n $niceLevel $mover_str $options");
    }
}

if ($cron && $cfg['moverDisabled'] == 'yes') {
    logger("Mover Tuning schedule disabled");
    exit();
}

if ($cfg['parity'] == 'no' && $vars['mdResyncPos']) {
    logger("Parity Check / rebuild in progress.  Not running mover");
    exit();
}

startMover();

?>