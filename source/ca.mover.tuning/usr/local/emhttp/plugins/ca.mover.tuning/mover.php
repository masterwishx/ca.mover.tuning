#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$cron = $argv[1] == "crond";
$args = [];

function logger($string)
{
    global $cfg;

    if ($cfg['logging'] == 'yes') {
        exec("logger " . escapeshellarg($string));
    }
}

//function startMover($options = "start")
function startMover(array $args)
{
    global $vars, $cfg, $cron, $argv, $args;

    if ($argv[2]) {

        if ($argv[2]) {
            $args[] = trim($argv[2]);
        }
    }

    if (!$cron) {
        // Example usage of specific arguments
        if (isset($args[0])) {
            $option1 = $args[0];
            logger("Option 1: $option1\n");
        }
        // Combine all arguments into a single string with spaces
        $options = implode(' ', $args);

        // Example usage of $options
        logger("Options: $options\n");

        if (isset($args[1]) && $args[1] == "-e" && isset($args[2])) {
            logger("Mover " . implode(' ', array_slice($args, 0, 3)));
        } else {
            logger("Mover " . implode(' ', $args));
        }
    } else {
        $options = "start";
        logger("options: $options");
    }

    if ($options != "stop") {
        clearstatcache();
        $pid = @file_get_contents("/var/run/mover.pid");
        if ($pid) {
            logger("Mover already running");
            exit();
        }
    }
    if ($options == "force") {
        $options = "";
        if ($cfg['forceParity'] == "no" && $vars['mdResyncPos']) {
            logger("Parity Check / Rebuild in Progress.  Not running forced move");
            exit();
        }
    }

    if ($options == "stop") {
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";
        logger("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old stop");
        passthru("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old stop");
        exit();
    }

    if ($cron or $cfg['movenow'] == "yes") {
        //exec("echo 'running from cron or move now question is yes' >> /var/log/syslog");
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";

        if ($cfg['movingThreshold'] >= 0 or $cfg['fillupThreshold'] >= 0 or $cfg['age'] == "yes" or $cfg['sizef'] == "yes" or $cfg['sparsnessf'] == "yes" or $cfg['filelistf'] == "yes" or $cfg['filetypesf'] == "yes" or $cfg['$beforescript'] != '' or $cfg['$afterscript'] != '' or $cfg['testmode'] == "yes") {
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
        logger("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");
        passthru("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");
    }
}

// if ($cron)
//     if ($argv[2]) {
//         $args[] = trim($argv[2]);
//         startMover($args);
//         exit();
//     } 

/*if ( ! $cron && $cfg['moveFollows'] != 'follows') {
    logger("Manually starting mover");
    startMover();
    exit();
}
*/

if ($cron && $cfg['moverDisabled'] == 'yes') {
    logger("Mover schedule disabled");
    exit();
}

if ($cfg['parity'] == 'no' && $vars['mdResyncPos']) {
    logger("Parity Check / rebuild in progress.  Not running mover");
    exit();
}

logger("Starting Mover ...");
logger("cron is: $cron");
startMover($args);

?>