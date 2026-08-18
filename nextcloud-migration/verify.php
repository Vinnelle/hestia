<?php
// Not opened in SQLite's URI mode=ro here -- immediately after the migration's
// write session, PDO's mode=ro open failed with SQLITE_CANTOPEN, almost
// certainly because opening needs to clear a stale journal left from that
// session, which read-only mode can't do. This script only ever issues
// SELECTs regardless of how the connection itself is opened.
$dbPath = '/var/www/html/data/data/nextcloud.db';
$pdo = new PDO('sqlite:' . $dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

function out($s)
{
    fwrite(STDOUT, $s . "\n");
    fflush(STDOUT);
}

out('--- storages ---');
foreach ($pdo->query('SELECT numeric_id, id FROM oc_storages')->fetchAll(PDO::FETCH_ASSOC) as $row) {
    out(json_encode($row));
}

out('--- mounts ---');
foreach ($pdo->query('SELECT id, storage_id, root_id, user_id, mount_point, mount_provider_class FROM oc_mounts')->fetchAll(PDO::FETCH_ASSOC) as $row) {
    out(json_encode($row));
}

out('--- storage 4 root entry (fileid = its root_id from oc_mounts) ---');
$rootId = $pdo->query("SELECT root_id FROM oc_mounts WHERE storage_id = 4")->fetchColumn();
if ($rootId !== false) {
    $root = $pdo->query('SELECT fileid, storage, path, mimetype FROM oc_filecache WHERE fileid = ' . (int)$rootId)->fetch(PDO::FETCH_ASSOC);
    out(json_encode($root));
}

out('--- non-directory byte total for storage 4 ---');
$dirMimeId = (int)$pdo->query("SELECT id FROM oc_mimetypes WHERE mimetype = 'httpd/unix-directory'")->fetchColumn();
$sum = $pdo->query('SELECT COUNT(*), COALESCE(SUM(size), 0) FROM oc_filecache WHERE storage = 4 AND mimetype != ' . $dirMimeId)->fetch(PDO::FETCH_NUM);
out("regular_file_rows={$sum[0]} total_bytes={$sum[1]}");
