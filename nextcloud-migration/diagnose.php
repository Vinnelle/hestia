<?php
$dir = '/var/www/html/data';
echo "--- all *.db* files under $dir ---\n";
foreach (glob($dir . '/*.db*') as $f) {
    printf("%12d bytes  %s\n", filesize($f), $f);
}

echo "\n--- checking each *.db file for real Nextcloud schema (read-only) ---\n";
foreach (glob($dir . '/*.db') as $f) {
    try {
        $pdo = new PDO('sqlite:file:' . $f . '?mode=ro', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        $tables = $pdo->query("SELECT name FROM sqlite_master WHERE type='table'")->fetchAll(PDO::FETCH_COLUMN);
        $hasStorages = in_array('oc_storages', $tables, true);
        $count = null;
        if ($hasStorages) {
            $count = $pdo->query('SELECT COUNT(*) FROM oc_filecache')->fetchColumn();
        }
        echo "$f: " . count($tables) . " tables, oc_storages=" . ($hasStorages ? 'yes' : 'no') . ($count !== null ? ", oc_filecache rows=$count" : '') . "\n";
    } catch (Throwable $e) {
        echo "$f: failed to open/query: " . $e->getMessage() . "\n";
    }
}
