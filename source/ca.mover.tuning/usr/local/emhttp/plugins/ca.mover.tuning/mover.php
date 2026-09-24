#!/usr/bin/php
<?PHP
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$cron = $argv[1] == "crond";
$bash = $argv[1] == "bash";
$args = [];
// the forced-move schedule (updateCron.php make_cron) calls: mover.php force start
$force = ($argv[1] ?? "") === "force";

// Read-only status check (no state change, no CSRF risk)
if (!empty($_GET['check'])) {
    echo file_exists('/var/run/mover.pid') ? "1" : "0";
    exit;
}

/**
 * Write a message to syslog under the "move" tag, when plugin logging is enabled.
 *
 * @param string $string Message to log.
 * @return void
 */
function logger($string)
{
    global $cfg;

    if ($cfg['logging'] == 'yes') {
        exec("logger -t move " . escapeshellarg($string));
    }
}

/**
 * Launch a mover command, detaching it when the caller is a web request.
 *
 * A mover run can last hours. Under the web UI the request stream is the
 * process's stdout, so a disconnect SIGPIPEs the mover and any before/after
 * script. CLI and cron keep the blocking behaviour because their stdout is
 * already durable.
 *
 * @param string $cmd Full shell command line used to launch the mover.
 * @return void
 */
function runMover($cmd)
{
    if (PHP_SAPI === 'cli') {
        passthru($cmd);
        return;
    }

    logger("Detached from web request; mover output continues in syslog and the mover log");
    // stdout is discarded rather than piped to logger: on this path age_mover's
    // mvlogger already writes each message to syslog, so piping would double it.
    // The run outlives the request and reparents to PID 1, so name the launcher.
    putenv("MOVER_RUN_METHOD=web button");
    exec($cmd . " >/dev/null 2>&1 &");

    // Wait for the run to claim the pid file so the page's status poll does
    // not race a mover that has not started yet.
    for ($i = 0; $i < 50 && file_exists("/var/run/mover.pid") === false; $i++) {
        usleep(100000);
    }
}

/**
 * Nice level and ionice class from the two priority dropdowns, or the defaults for any other value.
 *
 * @return array{0: string, 1: string} [niceLevel, ioLevel]
 */
function moverPriority()
{
    global $cfg;

    $allowedIO = ["-c 2 -n 0", "-c 2 -n 7", "-c 3"];
    $niceLevel = (string) (int) ($cfg['moverNice'] ?? 0);
    $ioLevel = in_array($cfg['moverIO'] ?? "", $allowedIO, true) === true ? $cfg['moverIO'] : "-c 2 -n 0";
    return [$niceLevel, $ioLevel];
}

// Keep each command literal: a command built from a variable is flagged by the code scanner.
function setWriteMethod($method)
{
    if ($method === "1") {
        exec("/usr/local/sbin/mdcmd set md_write_method 1");
    } elseif ($method === "0") {
        exec("/usr/local/sbin/mdcmd set md_write_method 0");
    } elseif ($method === "auto") {
        exec("/usr/local/sbin/mdcmd set md_write_method auto");
    }
}

// The forced move runs Unraid's own mover on its own schedule, without the plugin's filters or the Mover Tuning
// schedule and parity settings. Its own parity option, the two priorities and turbo write apply to it.
function forceMove()
{
    global $vars, $cfg;

    if ($cfg['forceParity'] !== "yes" && empty($vars['mdResyncPos']) === false) {
        logger("Parity Check / Rebuild in Progress.  Not running forced move");
        return;
    }
    clearstatcache();
    if (file_exists("/var/run/mover.pid") === true) {
        logger("Mover already running");
        return;
    }
    $mover = "/usr/local/sbin/mover";
    if (version_compare($vars['version'] ?? '0.0.0', '7.2.1', '<') === true) {
        $mover = "/usr/local/sbin/mover.old";
    }
    [$niceLevel, $ioLevel] = moverPriority();
    $writeMethod = $vars['md_write_method'] ?? "";
    $turbo = $cfg['enableTurbo'] === "yes" && in_array($writeMethod, ["0", "1", "auto"], true) === true;

    if ($turbo === true) {
        logger("Forcing turbo write on");
        setWriteMethod("1");
    }
    logger("Starting forced move (Unraid mover)");
    // cron runs this under the CLI, where runMover blocks until the move ends; the restore below relies on that
    runMover("ionice $ioLevel nice -n $niceLevel $mover start");
    if ($turbo === true) {
        logger("Restoring original turbo write mode");
        setWriteMethod($writeMethod);
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
            // Fix for Unraid v6.x that emhttp run mover without "start" parameter
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

    // $options, moverNice and moverIO are the only values interpolated into the
    // mover command line, and all three come from fixed sets: age_mover's own
    // command list, and the two priority dropdowns on the settings page.
    // Anything else is rejected rather than handed to a shell.
    $allowedCommands = ["start", "stop", "softstop", "status", "reset", "debug"];
    if (in_array($options, $allowedCommands, true) === false) {
        logger("Refusing to run mover: unrecognised command '$options'");
        exit();
    }

    [$niceLevel, $ioLevel] = moverPriority();

    if ($options != "stop") {
        clearstatcache();
        $pid = @file_get_contents("/var/run/mover.pid");
        if ($pid) {
            logger("Mover already running");
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
        logger("ionice $ioLevel nice -n $niceLevel $mover_str stop");
        passthru("ionice $ioLevel nice -n $niceLevel $mover_str stop");
        exit();
    }

    if ($cron or $cfg['movenow'] == "yes") {
        //exec("echo 'running from cron or move now question is yes' >> /var/log/syslog");

        if ($cfg['movingThreshold'] >= 0 or $cfg['fillupThreshold'] >= 0 or $cfg['age'] == "yes" or $cfg['sizef'] == "yes" or $cfg['sparsnessf'] == "yes" or $cfg['filelistf'] == "yes" or $cfg['filetypesf'] == "yes" or $cfg['beforeScript'] != '' or $cfg['afterScript'] != '' or $cfg['testmode'] == "yes") {
            $age_mover_str = "/usr/local/emhttp/plugins/ca.mover.tuning/age_mover";
            //exec("echo 'about to hit mover string here: $age_mover_str' >> /var/log/syslog");
            logger("ionice $ioLevel nice -n $niceLevel $age_mover_str $options");
            runMover("ionice $ioLevel nice -n $niceLevel $age_mover_str $options");
        }
    } else {
        //exec("echo 'Running from button' >> /var/log/syslog");
        //Default "move now" button has been hit.
        logger("ionice $ioLevel nice -n $niceLevel $mover_str $options");
        runMover("ionice $ioLevel nice -n $niceLevel $mover_str $options");
    }
}

if ($force === true) {
    forceMove();
    exit();
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