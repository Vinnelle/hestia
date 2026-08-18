<?php
$dbPath = '/var/www/html/data/data/nextcloud.db';
// Not opened in SQLite's URI mode=ro here -- immediately after the migration's
// write session, PDO's mode=ro open failed with SQLITE_CANTOPEN, almost
// certainly because opening needs to clear a stale journal left from that
// session, which read-only mode can't do. This script only ever issues
// SELECTs regardless of how the connection itself is opened.
$pdo = new PDO('sqlite:' . $dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

$rows = $pdo->query('SELECT numeric_id, id FROM oc_storages')->fetchAll(PDO::FETCH_ASSOC);
foreach ($rows as $row) {
    $sum = $pdo->query('SELECT COUNT(*), COALESCE(SUM(size), 0) FROM oc_filecache WHERE storage = ' . (int)$row['numeric_id'])->fetch(PDO::FETCH_NUM);
    printf("storage numeric_id=%-4s id=%-30s rows=%-6s total_size=%s bytes\n", $row['numeric_id'], $row['id'], $sum[0], $sum[1]);
}
