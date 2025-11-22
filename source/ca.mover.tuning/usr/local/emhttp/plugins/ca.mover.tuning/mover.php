#!/usr/bin/php
<?
require_once("/usr/local/emhttp/plugins/dynamix/include/Wrappers.php");

$cfg = parse_plugin_cfg("ca.mover.tuning");
$vars = @parse_ini_file("/var/local/emhttp/var.ini");
$cron = ($argv[1] == "crond");

function logger($string)
{
    global $cfg;

    if ($cfg['logging'] == 'yes') {
        exec("logger " . escapeshellarg($string));
    }
}

function startMover($options = "")
{
    global $vars, $cfg, $cron;


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
    if ($cfg['enableTurbo'] == "yes") {
        logger("Forcing turbo write on");
        exec("/usr/local/sbin/mdcmd set md_write_method 1");
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
        $beforescript = $cfg['beforeScript'];
        $afterscript = $cfg['afterScript'];

        if ($cfg['threshold'] >= 0 or $cfg['age'] == "yes" or $cfg['sizef'] == "yes" or $cfg['sparsnessf'] == "yes" or $cfg['filelistf'] == "yes" or $cfg['filetypesf'] == "yes" or $beforescript != '' or $afterscript != '' or $cfg['testmode'] == "yes") {

			$age_mover_str = "/usr/local/emhttp/plugins/ca.mover.tuning/age_mover start";
            $niceLevel = $cfg['moverNice'] ?: "0";
            $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";
            $threshold = $cfg['threshold'];
            $ageLevel = $cfg['daysold'];
            $sizeLevel = $cfg['sizeinM'];
            $sparsnessLevel = $cfg['sparsnessv'];
            $filelistLevel = $cfg['filelistv'];
            $filetypesLevel = $cfg['filetypesv'];
            $ctime = $cfg['ctime'];
            $testmode = $cfg['testmode']; #Not used
            $omoverth = $cfg['omoverthresh'];
            $ihidden = $cfg['ignoreHidden']; #Not used

            #build age_mover command for all options.
            if ($cfg['age'] == "yes") {
                $age_mover_str = "$age_mover_str $ageLevel";
            } else {
                $age_mover_str = "$age_mover_str 0";
            }
            if ($cfg['sizef'] == "yes") {
                $age_mover_str = "$age_mover_str $sizeLevel";
            } else {
                $age_mover_str = "$age_mover_str 0";
            }
            if ($cfg['sparsnessf'] == "yes") {
                $age_mover_str = "$age_mover_str $sparsnessLevel";
            } else {
                $age_mover_str = "$age_mover_str 0";
            }
            if ($cfg['filelistf'] == "yes") {
                $age_mover_str = "$age_mover_str \"$filelistLevel\"";
            } else {
                $age_mover_str = "$age_mover_str ''";
            }
            if ($cfg['filetypesf'] == "yes") {
                $age_mover_str = "$age_mover_str \"$filetypesLevel\"";
            } else {
                $age_mover_str = "$age_mover_str ''";
            }
            if (empty($beforescript)) {
                $age_mover_str = "$age_mover_str ''";
            } else {
                $age_mover_str = "$age_mover_str \"$beforescript\"";
            }
            if (empty($afterscript)) {
                $age_mover_str = "$age_mover_str ''";
            } else {
                $age_mover_str = "$age_mover_str \"$afterscript\"";
            }
            if (empty($ctime)) {
                $age_mover_str = "$age_mover_str ''";
            } else {
                $age_mover_str = "$age_mover_str $ctime";
            }
            if ($cfg['omovercfg'] == "yes") {
                $age_mover_str = "$age_mover_str $omoverth";
            } else {
                $age_mover_str = "$age_mover_str ''";
            }
            if ($cfg['testmode'] == "yes") {
                $age_mover_str = "$age_mover_str 'yes'";
            } else {
                $age_mover_str = "$age_mover_str ''";
            }
            if ($cfg['ignoreHidden'] == "yes") {
                $age_mover_str = "$age_mover_str 'yes'";
            } else {
                $age_mover_str = "$age_mover_str ''";
            }
            if (empty($threshold)) {
                $age_mover_str = "$age_mover_str 0";
            } else {
                $age_mover_str = "$age_mover_str $threshold";
            }

            //exec("echo 'about to hit mover string here: $age_mover_str' >> /var/log/syslog");

            logger("ionice $ioLevel nice -n $niceLevel $age_mover_str");
            passthru("ionice $ioLevel nice -n $niceLevel $age_mover_str");
        }

    } else {
        //exec("echo 'Running from button' >> /var/log/syslog");
        //Default "move now" button has been hit.
        $niceLevel = $cfg['moverNice'] ?: "0";
        $ioLevel = $cfg['moverIO'] ?: "-c 2 -n 0";
        logger("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");
        passthru("ionice $ioLevel nice -n $niceLevel /usr/local/sbin/mover.old $options");

    }


    if ($cfg['enableTurbo'] == "yes") {
        logger("Restoring original turbo write mode");
        exec("/usr/local/sbin/mdcmd set md_write_method {$vars['md_write_method']}");
    }

}

if ($argv[2]) {
    startMover(trim($argv[2]));
    exit();
}


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



logger("Starting Mover");
startMover();

?>