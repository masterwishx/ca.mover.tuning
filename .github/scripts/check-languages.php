<?php
// Checks languages/*.txt the way Unraid reads them: format errors fail the run, drift is reported as warnings.
// Usage: php check-languages.php <plugin directory>

$pluginDir = rtrim($argv[1] ?? '', '/');
$langDir = "$pluginDir/languages";
if ($pluginDir === '' || is_dir($langDir) === false) {
    fwrite(STDERR, "usage: php check-languages.php <plugin directory holding languages/>\n");
    exit(2);
}

// Words every Unraid language pack translates already; en_US.txt leaves them out on purpose.
$coreWords = ['Yes', 'No', 'Apply', 'Done', 'OK', 'Close', 'Version', 'Auto', 'Important', 'Normal', 'Move'];

$errors = 0;
$warnings = 0;

function report(string $level, string $file, int $line, string $message): void
{
    global $errors, $warnings;
    if ($level === 'error') {
        $errors++;
    } else {
        $warnings++;
    }
    $where = $line > 0 ? "file=$file,line=$line" : "file=$file";
    echo "::$level $where::" . str_replace(["\r", "\n"], ' ', $message) . "\n";
}

// Lookup key _() builds from a text (same expressions as _() in webgui Translations.php)
function lookup_key(string $text): string
{
    return preg_replace(
        ['/\&amp;|[\?\{\}\|\&\~\!\[\]\(\)\/\\:\*^\.\"\']|<.+?\/?>/', '/^(null|yes|no|true|false|on|off|none)$/i', '/  +/'],
        ['', '$1.', ' '],
        trim($text)
    );
}

// What Unraid's parse_lang_file() makes of a file (same expressions as webgui Translations.php)
function unraid_parse(string $raw)
{
    $escaped = str_replace(["\"\n", '"'], ["\" \n", '\"'], $raw);
    return @parse_ini_string(preg_replace(
        ['/^\s*?(null|yes|no|true|false|on|off|none)\s*?=/mi', '/^\s*?([^>].*?)\s*?=\s*?(.*)\s*?$/m', '/^:(.+_(help|plug)):$/m', '/^:end$/m'],
        ['$1.=', '$1="$2"', '_$1="', '"'],
        $escaped
    ));
}

function placeholders(string $text): array
{
    preg_match_all('/%s|%[1-9]/', $text, $m);
    $counts = array_count_values($m[0]);
    ksort($counts);
    return $counts;
}

// Reads one language file: entries and help sections with their line numbers; format errors are reported here.
function read_language_file(string $path): array
{
    $raw = file_get_contents($path);
    $entries = [];
    $sections = [];
    if (strncmp($raw, "\xEF\xBB\xBF", 3) === 0) {
        report('error', $path, 1, 'The file starts with a byte order mark; save it as UTF-8 without BOM.');
    }
    if (mb_check_encoding($raw, 'UTF-8') === false) {
        report('error', $path, 0, 'The file is not valid UTF-8.');
    }
    $open = null;
    foreach (preg_split('/\r?\n/', $raw) as $i => $line) {
        $n = $i + 1;
        if (preg_match('/^:(.+_(?:help|plug)):$/', $line, $m) === 1) {
            if ($open !== null) {
                report('error', $path, $n, "Section :{$m[1]}: starts before :{$open[0]}: (line {$open[1]}) has its :end.");
            }
            if (isset($sections[$m[1]]) === true) {
                report('error', $path, $n, "Section :{$m[1]}: appears twice.");
            }
            $open = [$m[1], $n];
            $sections[$m[1]] = $n;
            continue;
        }
        if ($line === ':end') {
            if ($open === null) {
                report('error', $path, $n, ':end without an open section.');
            }
            $open = null;
            continue;
        }
        if ($open !== null) {
            // parse_ini_string() fails on such a line, and Unraid then drops every translation in the file
            if (strpos($line, '=') !== false && ($line === '' || $line[0] !== '>')) {
                report('error', $path, $n, "A line inside :{$open[0]}: holds an equal sign but does not start with >. Unraid would drop the whole file.");
            }
            continue;
        }
        if (trim($line) === '' || $line[0] === ';') {
            continue;
        }
        if (strpos($line, '=') === false) {
            report('error', $path, $n, 'Not a key=text line, a comment or part of a section.');
            continue;
        }
        [$key, $text] = explode('=', $line, 2);
        $key = trim($key);
        if (isset($entries[$key]) === true) {
            report('error', $path, $n, "Key \"$key\" appears twice (first on line {$entries[$key][1]}).");
            continue;
        }
        $expected = lookup_key($key);
        if ($expected !== $key) {
            report('error', $path, $n, "Key \"$key\" can never be looked up: Unraid turns the text into \"$expected\" first (it drops & ? { } | ~ ! [ ] ( ) / \\ : * ^ . \" ' and HTML tags, and adds . to a bare yes/no).");
        }
        $entries[$key] = [$text, $n];
    }
    if ($open !== null) {
        report('error', $path, $open[1], "Section :{$open[0]}: has no :end.");
    }
    if (unraid_parse($raw) === false) {
        report('error', $path, 0, "Unraid's parser rejects this file, so none of its translations would load.");
    }
    return [$entries, $sections];
}

$masterPath = "$langDir/en_US.txt";
if (is_file($masterPath) === false) {
    report('error', $masterPath, 0, 'en_US.txt, the master file, is missing.');
    exit(1);
}
[$master, $masterSections] = read_language_file($masterPath);

// Every text the pages and the notifications look up should have an en_US entry for translators to see.
$used = [];
foreach (glob("$pluginDir/*.page") as $page) {
    $code = file_get_contents($page);
    preg_match_all('/_\((.+?)\)_/', $code, $m, PREG_OFFSET_CAPTURE);
    foreach ($m[1] as [$text, $offset]) {
        $used[$text] ??= [$page, substr_count($code, "\n", 0, $offset) + 1];
    }
    preg_match_all("/_\\('((?:[^'\\\\]|\\\\.)*)'\\)/", $code, $m, PREG_OFFSET_CAPTURE);
    foreach ($m[1] as [$text, $offset]) {
        $used[stripslashes($text)] ??= [$page, substr_count($code, "\n", 0, $offset) + 1];
    }
}
if (is_file("$pluginDir/age_mover") === true) {
    $code = file_get_contents("$pluginDir/age_mover");
    preg_match_all('/(?:translate_text|mvlogger_t) "((?:[^"\\\\]|\\\\.)*)"/', $code, $m, PREG_OFFSET_CAPTURE);
    foreach ($m[1] as [$text, $offset]) {
        $used[stripcslashes($text)] ??= ["$pluginDir/age_mover", substr_count($code, "\n", 0, $offset) + 1];
    }
}
foreach ($used as $text => [$file, $line]) {
    // _() returns '' for blank text; shell variables are not templates
    if (trim($text) === '' || strpos($text, '$') !== false || in_array($text, $coreWords, true) === true) {
        continue;
    }
    if (isset($master[lookup_key($text)]) === false) {
        report('warning', $file, $line, "\"$text\" has no entry in en_US.txt, so it cannot be translated.");
    }
}

foreach (glob("$langDir/*.txt") as $path) {
    if ($path === $masterPath) {
        continue;
    }
    [$entries, $sections] = read_language_file($path);
    foreach ($entries as $key => [$text, $line]) {
        if (isset($master[$key]) === false) {
            report('warning', $path, $line, "Key \"$key\" is not in en_US.txt any more; this text shows in English.");
            continue;
        }
        $english = $master[$key][0] !== '' ? $master[$key][0] : $key;
        if ($text !== '' && placeholders($text) !== placeholders($english)) {
            report('error', $path, $line, "Placeholders differ from en_US.txt: " . json_encode(placeholders($english)) . " there, " . json_encode(placeholders($text)) . " here.");
        }
    }
    foreach ($sections as $tag => $line) {
        if (isset($masterSections[$tag]) === false) {
            report('warning', $path, $line, "Section :$tag: is not in en_US.txt any more.");
        }
    }
    $missing = array_filter(array_keys($master), fn($k) => ($entries[$k][0] ?? '') === '');
    $missingSections = array_diff(array_keys($masterSections), array_keys($sections));
    if (count($missing) > 0 || count($missingSections) > 0) {
        report('warning', $path, 0, count($missing) . ' entries and ' . count($missingSections) . ' sections of en_US.txt are not translated yet (they show in English).');
    }
}

echo "language files: $errors errors, $warnings warnings\n";
exit($errors > 0 ? 1 : 0);
