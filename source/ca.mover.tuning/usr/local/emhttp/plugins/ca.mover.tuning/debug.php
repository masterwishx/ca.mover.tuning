<?PHP

exec("timeout -s9 30 /usr/local/emhttp/plugins/ca.mover.tuning/debug_mover", $debug_result);

if(!empty($debug_result)) {
    if(strpos(end($debug_result), "DONE:") !== false) {
        $debugFile = explode(":", end($debug_result))[1];
        if(!empty($debugFile) && file_exists($debugFile)) {
            http_response_code(200); // OK for successful file download
            header("Content-Disposition: attachment; filename=\"" . basename($debugFile) . "\"");
            header("Content-Type: application/octet-stream");
            header("Content-Length: " . filesize($debugFile));
            header("Connection: close");
            readfile($debugFile);
            unlink($debugFile);
            exit;
        } else {
            http_response_code(500); // Internal Server Error
            echo("ERROR: The Mover Tuning Debug Package Generation Script has failed - bash backend returned filename, php could not find file.");
        }
    } else {
        http_response_code(500); // Internal Server Error
        echo("ERROR: The Mover Tuning Debug Package Generation Script has failed - response from the bash backend:<br><pre>");
        echo(implode("\n",$debug_result));
        echo("</pre>");
    }
} else {
    http_response_code(500); // Internal Server Error
    echo("ERROR: The Mover Tuning Debug Package Generation Script has failed - no response from the bash backend.");
}
?>
