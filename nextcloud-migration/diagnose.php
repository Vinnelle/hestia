<?php
$dir = '/var/www/html/data';

echo "--- top-level contents of $dir ---\n";
foreach (scandir($dir) as $entry) {
    if ($entry === '.' || $entry === '..') {
        continue;
    }
    $path = $dir . '/' . $entry;
    if (is_dir($path)) {
        echo "DIR   $entry\n";
    } else {
        printf("FILE  %12d bytes  %s\n", filesize($path), $entry);
    }
}

echo "\n--- any file starting with the SQLite magic header, one level deep ---\n";
foreach (glob($dir . '/*') as $path) {
    if (is_file($path)) {
        $candidates = [$path];
    } elseif (is_dir($path)) {
        $candidates = glob($path . '/*');
    } else {
        continue;
    }
    foreach ($candidates as $f) {
        if (!is_file($f)) {
            continue;
        }
        $fh = fopen($f, 'rb');
        $header = fread($fh, 16);
        fclose($fh);
        if ($header === "SQLite format 3\000") {
            printf("%12d bytes  %s\n", filesize($f), $f);
        }
    }
}
