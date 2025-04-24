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


// function is_run_by_cron() {
//     $parent_process_id = escapeshellarg($_ENV['PPID']);
//     $parent_process = shell_exec("ps h -o comm= . $parent_process_id . ");
//     $parent_process = trim($parent_process);

//     if ($parent_process == "cron" || $parent_process == "crond") {
//         echo "This script is being run by crond.";
//         return true;
//     } else {
//         echo "This script is NOT being run by crond.";
//         return false;
//     }
// }

// Add this at the top of your file with other functions
function is_run_by_cron() {
    // Combines both checks for better reliability
    if (isset($_ENV['SHELL']) && strpos($_ENV['SHELL'], '/cron') !== false) {
        return true;
    }
    
    $pppid = trim (shell_exec("ps h -o ppid= $$"));
    $parent_process = trim(shell_exec("ps h -o comm= $pppid"));
    logger ("pppid = $pppid , parent_process =  $parent_process");
    return $parent_process === 'cron' || $parent_process === 'crond';
}


// function is_run_by_cron() {
//     // Check if the script was called from a cron job by looking at the environment variable
//     if (isset($_ENV['SHELL']) && strpos($_ENV['SHELL'], '/cron') !== false) {
//         echo "This script is being run by crond.";
//         return true;
//     } else {
//         echo "This script is NOT being run by crond.";
//         return false;
//     }
// }

// function is_run_by_cron() {
//     // Check if the /var/run/mover.pid file exists
//     $pidFilePath = '/var/run/mover.pid';
//     if (file_exists($pidFilePath)) {
//         echo "This script is being run manually or by another method.\n";
//         return true;
//     } else {
//         echo "This script is NOT being run by crond or manually.\n";
//         return false;
//     }
// }

// Add this at the top of your file with other functions
// 
// Add this at the top of your file with other functions
// function is_run_by_cron() {
//     // First check if running via crond by parent process ID
//     $ppid = shell_exec("ps h -o ppid= $$");
//     $parent_process = trim(shell_exec("ps h -o comm= $ppid"));
    
//     // If not found via ppid, try checking the process name directly
//     if (!in_array($parent_process, ['cron', 'crond'])) {
//         // Check if any of the ancestors is cron/crond
//         $depth = 0;
//         while ($depth < 10) { // Prevent infinite loop in case of weird process trees
//             $ppid = shell_exec("ps h -o ppid= $$");
//             $parent_process = trim(shell_exec("ps h -o comm= $ppid"));
            
//             if (in_array($parent_process, ['cron', 'crond'])) {
//                 return true;
//             }
            
//             // If we reach the init process, break
//             if ($parent_process == 'init' || $parent_process == 'systemd') {
//                 break;
//             }
            
//             ++$depth;
//         }
//     }
    
//     // Also check if running via a shell that indicates cron (like /bin/sh)
//     return strpos(shell_exec("ps h -o args= $$"), '/cron') !== false;
// }

#PPPID=$(ps h -o ppid= "$PPID" 2>/dev/null)
#P_COMMAND=$(ps h -o %c "$PPPID" 2>/dev/null)

// //Call the function
// is_run_by_cron();

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

// Add this near the top of your main script execution
if (is_run_by_cron()) {
    logger("This process was started by crond");
    // Handle cron-specific logic here
    if ($cfg['moverDisabled'] == 'yes') {
        logger("Mover schedule disabled when run by cron");
        exit();
    }
} else {
    logger("This process was NOT started by crond");
}



startMover($args);

?>