<?php
// Not opened in SQLite's URI mode=ro here -- immediately after the migration's
// write session, PDO's mode=ro open failed with SQLITE_CANTOPEN, almost
// certainly because opening needs to clear a stale journal left from that
// session, which read-only mode can't do. This script only ever issues
// SELECTs regardless of how the connection itself is opened.
$dbPath = '/var/www/html/data/data/nextcloud.db';
$pdo = new PDO('sqlite:' . $dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

$rows = $pdo->query('SELECT numeric_id, id FROM oc_storages')->fetchAll(PDO::FETCH_ASSOC);
foreach ($rows as $row) {
    $sum = $pdo->query('SELECT COUNT(*), COALESCE(SUM(size), 0), MIN(size), MAX(size) FROM oc_filecache WHERE storage = ' . (int)$row['numeric_id'])->fetch(PDO::FETCH_NUM);
    printf("storage numeric_id=%-4s id=%-40s rows=%-6s total_size=%-15s min_size=%-15s max_size=%s\n", $row['numeric_id'], $row['id'], $sum[0], $sum[1], $sum[2], $sum[3]);
}

echo "\n--- mounts ---\n";
$mounts = $pdo->query('SELECT id, storage_id, root_id, user_id, mount_point FROM oc_mounts')->fetchAll(PDO::FETCH_ASSOC);
foreach ($mounts as $m) {
    echo json_encode($m) . "\n";
}

echo "\n--- sample rows from storage 4, ordered by size desc ---\n";
$sample = $pdo->query('SELECT fileid, path, size, mimetype FROM oc_filecache WHERE storage = 4 ORDER BY size DESC LIMIT 15')->fetchAll(PDO::FETCH_ASSOC);
foreach ($sample as $s) {
    echo json_encode($s) . "\n";
}

echo "\n--- negative-size row count in storage 4 ---\n";
echo $pdo->query('SELECT COUNT(*) FROM oc_filecache WHERE storage = 4 AND size < 0')->fetchColumn() . "\n";
