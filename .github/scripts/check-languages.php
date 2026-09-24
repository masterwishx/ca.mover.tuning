<?php
// Checks languages/*.txt the way Unraid reads them: format errors fail the run, drift is reported as warnings.
// Usage: php check-languages.php <plugin directory>

// Words every Unraid language pack translates already; en_US.txt leaves them out on purpose.
const CORE_WORDS = ['Yes', 'No', 'Apply', 'Done', 'OK', 'Close', 'Version', 'Auto', 'Important', 'Normal', 'Move'];

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

function check_bytes(string $path, string $raw): void
{
    if (strncmp($raw, "\xEF\xBB\xBF", 3) === 0) {
        report('error', $path, 1, 'The file starts with a byte order mark; save it as UTF-8 without BOM.');
    }
    if (mb_check_encoding($raw, 'UTF-8') === false) {
        report('error', $path, 0, 'The file is not valid UTF-8.');
    }
    if (unraid_parse($raw) === false) {
        report('error', $path, 0, "Unraid's parser rejects this file, so none of its translations would load.");
    }
}

// Opens or closes a :tag_plug: section; returns false for a line that is neither.
function section_line(string $path, string $line, int $n, ?array &$open, array &$sections): bool
{
    if (preg_match('/^:(.+_(?:help|plug)):$/', $line, $m) === 1) {
        if ($open !== null) {
            report('error', $path, $n, "Section :{$m[1]}: starts before :{$open[0]}: (line {$open[1]}) has its :end.");
        }
        if (isset($sections[$m[1]]) === true) {
            report('error', $path, $n, "Section :{$m[1]}: appears twice.");
        }
        $open = [$m[1], $n];
        $sections[$m[1]] = $n;
        return true;
    }
    if ($line !== ':end') {
        return false;
    }
    if ($open === null) {
        report('error', $path, $n, ':end without an open section.');
    }
    $open = null;
    return true;
}

// A line inside a section: parse_ini_string() fails on an equal sign there, and Unraid then drops the whole file.
function section_text(string $path, string $line, int $n, string $tag): void
{
    if (strpos($line, '=') !== false && ($line === '' || $line[0] !== '>')) {
        report('error', $path, $n, "A line inside :$tag: holds an equal sign but does not start with >. Unraid would drop the whole file.");
    }
}

// A key=text line outside the sections.
function entry_line(string $path, string $line, int $n, array &$entries): void
{
    if (trim($line) === '' || ltrim($line)[0] === ';') {
        return;
    }
    if (strpos($line, '=') === false) {
        report('error', $path, $n, 'Not a key=text line, a comment or part of a section.');
        return;
    }
    [$key, $text] = explode('=', $line, 2);
    // parse_lang_file stores a bare INI keyword (yes, no, ...) with a trailing dot, the form _() looks up
    $key = preg_replace('/^(null|yes|no|true|false|on|off|none)$/i', '$1.', trim($key));
    if (isset($entries[$key]) === true) {
        report('error', $path, $n, "Key \"$key\" appears twice (first on line {$entries[$key][1]}).");
        return;
    }
    $expected = lookup_key($key);
    if ($expected !== $key) {
        report('error', $path, $n, "Key \"$key\" can never be looked up: Unraid turns the text into \"$expected\" first (it drops & ? { } | ~ ! [ ] ( ) / \\ : * ^ . \" ' and HTML tags, and adds . to a bare yes/no).");
    }
    // Unraid drops an empty text (English shows) but keeps one of only blanks, which shows as an empty label;
    // the caller fills the placeholders of its own text, which the key keeps, so every text in every file must match them
    if ($text !== '' && preg_match('/^[\s\x{00A0}]*$/u', $text) === 1) {
        report('error', $path, $n, 'The text is only blanks: Unraid shows an empty label instead of the English text.');
    } elseif ($text !== '' && placeholders($text) !== placeholders($key)) {
        report('error', $path, $n, 'Placeholders differ from the key: ' . json_encode(placeholders($key)) . ' there, ' . json_encode(placeholders($text)) . ' here.');
    }
    $entries[$key] = [$text, $n];
}

// Reads one language file into entries and sections, each with its line number; format errors are reported here.
function read_language_file(string $path): array
{
    $raw = file_get_contents($path);
    check_bytes($path, $raw);
    $entries = [];
    $sections = [];
    $open = null;
    foreach (preg_split('/\r?\n/', $raw) as $i => $line) {
        if (section_line($path, $line, $i + 1, $open, $sections) === true) {
            continue;
        }
        if ($open !== null) {
            section_text($path, $line, $i + 1, $open[0]);
            continue;
        }
        entry_line($path, $line, $i + 1, $entries);
    }
    if ($open !== null) {
        report('error', $path, $open[1], "Section :{$open[0]}: has no :end.");
    }
    return [$entries, $sections];
}

// Texts the pages look up, each with where it first appears.
function page_texts(string $pluginDir): array
{
    $used = [];
    // _(text)_ markers are taken as written; _('text') calls are PHP strings, so their escapes are undone
    $patterns = ['/_\((.+?)\)_/' => false, "/_\\('((?:[^'\\\\]|\\\\.)*)'\\)/" => true];
    foreach (glob("$pluginDir/*.page") as $page) {
        $code = file_get_contents($page);
        foreach ($patterns as $pattern => $unescape) {
            preg_match_all($pattern, $code, $m, PREG_OFFSET_CAPTURE);
            foreach ($m[1] as [$text, $offset]) {
                $used[$unescape === true ? stripslashes($text) : $text] ??= [$page, substr_count($code, "\n", 0, $offset) + 1];
            }
        }
    }
    return $used;
}

// Templates age_mover translates for its notifications and log, each with where it first appears.
function mover_texts(string $pluginDir): array
{
    $mover = "$pluginDir/age_mover";
    if (is_file($mover) === false) {
        return [];
    }
    $used = [];
    $code = file_get_contents($mover);
    preg_match_all('/(?:translate_text|mvlogger_t) "((?:[^"\\\\]|\\\\.)*)"/', $code, $m, PREG_OFFSET_CAPTURE);
    foreach ($m[1] as [$text, $offset]) {
        // an unescaped $ is a shell variable: the text is only known at run time
        if (preg_match('/(?<!\\\\)\$/', $text) === 1) {
            continue;
        }
        $used[stripcslashes($text)] ??= [$mover, substr_count($code, "\n", 0, $offset) + 1];
    }
    return $used;
}

// Every looked-up text should have an en_US entry, or translators never see it.
function check_used_texts(array $used, array $master): void
{
    foreach ($used as $text => [$file, $line]) {
        // _() returns '' for blank text
        if (trim($text) === '' || in_array($text, CORE_WORDS, true) === true) {
            continue;
        }
        if (isset($master[lookup_key($text)]) === false) {
            report('warning', $file, $line, "\"$text\" has no entry in en_US.txt, so it cannot be translated.");
        }
    }
}

// One translation against en_US.txt: drift is a warning (read_language_file reports the errors).
function check_translation(string $path, array $master, array $masterSections): void
{
    [$entries, $sections] = read_language_file($path);
    $coreKeys = array_map('lookup_key', CORE_WORDS);
    foreach ($entries as $key => [, $line]) {
        if (isset($master[$key]) === false && in_array($key, $coreKeys, true) === false) {
            report('warning', $path, $line, "Key \"$key\" is not in en_US.txt: nothing uses it any more, or en_US.txt misses it.");
        }
    }
    foreach (array_diff_key($sections, $masterSections) as $tag => $line) {
        report('warning', $path, $line, "Section :$tag: is not in en_US.txt any more.");
    }
    $missing = array_filter(array_keys($master), fn($k) => ($entries[$k][0] ?? '') === '');
    $missingSections = array_diff_key($masterSections, $sections);
    if (count($missing) > 0 || count($missingSections) > 0) {
        report('warning', $path, 0, count($missing) . ' entries and ' . count($missingSections) . ' sections of en_US.txt are not translated yet (they show in English).');
    }
}

$pluginDir = rtrim($argv[1] ?? '', '/');
$langDir = "$pluginDir/languages";
if ($pluginDir === '' || is_dir($langDir) === false) {
    fwrite(STDERR, "usage: php check-languages.php <plugin directory holding languages/>\n");
    exit(2);
}
$masterPath = "$langDir/en_US.txt";
if (is_file($masterPath) === false) {
    report('error', $masterPath, 0, 'en_US.txt, the master file, is missing.');
    exit(1);
}
[$master, $masterSections] = read_language_file($masterPath);
check_used_texts(page_texts($pluginDir) + mover_texts($pluginDir), $master);
foreach (glob("$langDir/*.txt") as $path) {
    if ($path !== $masterPath) {
        check_translation($path, $master, $masterSections);
    }
}
echo "language files: $errors errors, $warnings warnings\n";
exit($errors > 0 ? 1 : 0);
