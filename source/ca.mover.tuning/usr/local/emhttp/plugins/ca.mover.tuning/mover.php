#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$cron = $argv[1] == "crond"; //Not working anymore needs to be removed in future + change code below related to $cron
$args = [];

function logger($string)
{
    global $cfg;

    if ($cfg['logging'] == 'yes') {
        exec("logger -t move " . escapeshellarg($string));
    }
}

//function startMover($options = "start")
function startMover(array $args)
{
    global $vars, $cfg, $cron, $argv, $args;

    if ($argv[2]) {
        $args[] = trim($argv[2]);
    }

    if (!$cron) {
        // Example usage of specific arguments
        if (isset($args[0])) {
            $option1 = $args[0];
            if ($cfg['debuglogging'] == 'yes') {
                logger("Option 1: $option1\n");
            }
        } else if (version_compare($vars['version'], '7.0.0', '<')) {
            $args[0] = 'start';
            $option1 = $args[0];
            if ($cfg['debuglogging'] == 'yes') {
                logger("Option 1 set to 'start' due to version < 7.0.0\n");
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
    if ($options == "force") {
        $options = "";
        if ($cfg['forceParity'] == "no" && $vars['mdResyncPos']) {
            logger("Parity Check / Rebuild in Progress.  Not running forced move");
            exit();
        }
    }

    // Check if Move Now button follows plug-in filters
    if ($cfg['movenow'] == "yes") {
        $mover_str = "/usr/local/emhttp/plugins/ca.mover.tuning/age_mover";
    } else {
        $mover_str = "/usr/local/sbin/mover.old";
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
        logger("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");
        passthru("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");
    }
}

// //Add this at the top of your file with other functions
// function is_run_by_cron() {
//     // Combines both checks for better reliability
//     if (isset($_ENV['SHELL']) && strpos($_ENV['SHELL'], '/cron') !== false) {
//         return true;
//     }
    
//     $pppid = trim (shell_exec("ps h -o ppid= $$"));
//     $parent_process = trim(shell_exec("ps h -o comm= $pppid"));
//     logger ("pppid = $pppid , parent_process =  $parent_process");
//     return $parent_process === 'cron' || $parent_process === 'crond';
// }

if ($cron && $cfg['moverDisabled'] == 'yes') {
    logger("Mover schedule disabled");
    exit();
}

if ($cfg['parity'] == 'no' && $vars['mdResyncPos']) {
    logger("Parity Check / rebuild in progress.  Not running mover");
    exit();
}

logger("Starting Mover ...");
// logger("cron is: $cron");

// // Add this near the top of your main script execution
// if (is_run_by_cron()) {
//     logger("This process was started by crond");
//     // Handle cron-specific logic here
//     if ($cfg['moverDisabled'] == 'yes') {
//         logger("Mover schedule disabled when run by cron");
//         exit();
//     }
// } else {
//     logger("This process was NOT started by crond");
// }

startMover($args);

?>