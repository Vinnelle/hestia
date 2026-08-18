<?php
$dataRoot = '/var/www/html/data/ida';
$user     = 'ida';
$homeId   = 'home::' . $user;
$objId    = 'object::user:' . $user;
$bucket   = 'nextcloud-primary';
$filer    = 'http://seaweedfs.seaweedfs.svc.cluster.local:8888';

$candidates = glob('/var/www/html/data/*.db');
if (count($candidates) !== 1) {
    fwrite(STDERR, "expected exactly one *.db file under /var/www/html/data, found: " . implode(', ', $candidates) . "\n");
    exit(1);
}
$dbPath = $candidates[0];
echo "using database: $dbPath\n";

$pdo = new PDO('sqlite:' . $dbPath);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$tableCheck = $pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name='oc_storages'")->fetchColumn();
if ($tableCheck === false) {
    fwrite(STDERR, "oc_storages table not found in $dbPath -- refusing to proceed\n");
    exit(1);
}

$stmt = $pdo->prepare('SELECT numeric_id FROM oc_storages WHERE id = ?');
$stmt->execute([$homeId]);
$oldId = $stmt->fetchColumn();
if ($oldId === false) {
    fwrite(STDERR, "home storage '$homeId' not found -- nothing to do\n");
    exit(1);
}

$dirStmt = $pdo->query("SELECT id FROM oc_mimetypes WHERE mimetype = 'httpd/unix-directory'");
$dirMimeId = (int)$dirStmt->fetchColumn();

// --- upload phase ---
$stmt = $pdo->prepare('SELECT fileid, path, mimetype FROM oc_filecache WHERE storage = ?');
$stmt->execute([$oldId]);

$totalRows = 0;
$regularFiles = 0;
$uploaded = 0;
$skipped = [];

$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_PUT => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 300,
]);

while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
    $totalRows++;
    if ((int)$row['mimetype'] === $dirMimeId) {
        continue; // directories have no bytes, only the DB row needs to move
    }
    $regularFiles++;

    $src = $dataRoot . '/' . $row['path'];
    if (!is_file($src)) {
        $skipped[] = $src;
        fwrite(STDERR, "WARNING: missing on disk, skipping: $src (fileid={$row['fileid']})\n");
        continue;
    }

    $fh = fopen($src, 'rb');
    $url = $filer . '/buckets/' . $bucket . '/urn:oid:' . $row['fileid'];
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_INFILE, $fh);
    curl_setopt($ch, CURLOPT_INFILESIZE, filesize($src));
    curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    fclose($fh);

    if ($code < 200 || $code >= 300) {
        fwrite(STDERR, "upload failed ($code) for $src -> $url\n");
        exit(1);
    }
    $uploaded++;
}
curl_close($ch);

echo "total_rows=$totalRows regular_files=$regularFiles uploaded=$uploaded skipped=" . count($skipped) . "\n";

if ($uploaded !== $regularFiles) {
    fwrite(STDERR, "abort: uploaded ($uploaded) != regular_files ($regularFiles), not touching the database\n");
    exit(1);
}

// --- repoint phase ---
$stmt = $pdo->prepare('SELECT numeric_id FROM oc_storages WHERE id = ?');
$stmt->execute([$objId]);
$newId = $stmt->fetchColumn();
if ($newId === false) {
    $ins = $pdo->prepare('INSERT INTO oc_storages (id, available) VALUES (?, 1)');
    $ins->execute([$objId]);
    $newId = $pdo->lastInsertId();
}
echo "objectstore storage numeric_id=$newId\n";

$pdo->beginTransaction();
try {
    $upd = $pdo->prepare('UPDATE oc_filecache SET storage = ? WHERE storage = ?');
    $upd->execute([$newId, $oldId]);
    $filecacheRows = $upd->rowCount();

    $updMounts = $pdo->prepare('UPDATE oc_mounts SET storage_id = ? WHERE storage_id = ?');
    $updMounts->execute([$newId, $oldId]);
    $mountRows = $updMounts->rowCount();

    $pdo->commit();
    echo "repointed filecache_rows=$filecacheRows mount_rows=$mountRows\n";
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, "repoint failed, rolled back: " . $e->getMessage() . "\n");
    exit(1);
}
