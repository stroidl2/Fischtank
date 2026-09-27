<?php
// ── DB-Verbindung ────────────────────────────────────────────────────────────
$dsn    = 'mysql:host=mariadb;port=3306;dbname=namen;charset=utf8mb4';
$dbUser = 'webuser';
$dbPass = getenv('DB_PASSWORD') ?: 'changeme';

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    // Tabelle anlegen falls nicht vorhanden
    $pdo->exec("CREATE TABLE IF NOT EXISTS personen (
        id        INT AUTO_INCREMENT PRIMARY KEY,
        vorname   VARCHAR(100) NOT NULL,
        nachname  VARCHAR(100) NOT NULL,
        erstellt  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )");
} catch (PDOException $e) {
    $dbError = 'Datenbankverbindung fehlgeschlagen.';
}

// ── Formular verarbeiten ─────────────────────────────────────────────────────
$vorname  = '';
$nachname = '';
$message  = '';

if (!isset($dbError) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? 'insert';

    // Eintrag löschen
    if ($action === 'delete' && isset($_POST['id'])) {
        $id = (int)$_POST['id'];
        $stmt = $pdo->prepare("DELETE FROM personen WHERE id = ?");
        $stmt->execute([$id]);
        $message = '🗑️ Eintrag #' . $id . ' wurde gelöscht.';

    // Neuen Eintrag speichern
    } else {
        $vorname  = trim($_POST['vorname']  ?? '');
        $nachname = trim($_POST['nachname'] ?? '');

        if ($vorname !== '' && $nachname !== '') {
            $stmt = $pdo->prepare("INSERT INTO personen (vorname, nachname) VALUES (?, ?)");
            $stmt->execute([
                mb_substr($vorname,  0, 100),
                mb_substr($nachname, 0, 100),
            ]);
            $message = '✅ ' . htmlspecialchars($vorname, ENT_QUOTES, 'UTF-8')
                     . ' ' . htmlspecialchars($nachname, ENT_QUOTES, 'UTF-8')
                     . ' wurde gespeichert.';
            $vorname = $nachname = '';
        }
    }
}

// ── Alle Einträge laden ──────────────────────────────────────────────────────
$personen = [];
if (!isset($dbError)) {
    $personen = $pdo->query("SELECT * FROM personen ORDER BY erstellt DESC")->fetchAll();
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Namenseingabe</title>
  <style>
    body  { font-family: sans-serif; max-width: 600px; margin: 60px auto; padding: 0 1rem; }
    h1,h2 { font-size: 1.3rem; margin-bottom: 1rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text] {
      width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; box-sizing: border-box;
    }
    button {
      padding: .5rem 1.5rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer;
    }
    button:hover { background: #2563b0; }
    button.del {
      padding: .25rem .75rem; background: #fff; color: #c0392b;
      border: 1px solid #fca5a5; font-size: .85rem;
    }
    button.del:hover { background: #fff0f0; }
    .msg   { margin-top: 1rem; padding: .75rem; background: #f0f6ff; border: 1px solid #bfdbfe; border-radius: 4px; }
    .err   { background: #fff0f0; border-color: #fca5a5; }
    table  { width: 100%; border-collapse: collapse; margin-top: 1.5rem; font-size: .95rem; }
    th,td  { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid #e5e7eb; }
    th     { background: #f7f8fa; font-weight: bold; }
    tr:hover td { background: #f7f8fa; }
  </style>
</head>
<body>
  <h1>Namenseingabe</h1>

  <?php if (isset($dbError)): ?>
    <div class="msg err"><?= htmlspecialchars($dbError, ENT_QUOTES, 'UTF-8') ?></div>
  <?php else: ?>

  <form method="POST" action="">
    <label for="vorname">Vorname</label>
    <input type="text" id="vorname" name="vorname"
           value="<?= htmlspecialchars($vorname, ENT_QUOTES, 'UTF-8') ?>"
           placeholder="z. B. Max" required maxlength="100">

    <label for="nachname">Nachname</label>
    <input type="text" id="nachname" name="nachname"
           value="<?= htmlspecialchars($nachname, ENT_QUOTES, 'UTF-8') ?>"
           placeholder="z. B. Mustermann" required maxlength="100">

    <button type="submit">Speichern</button>
  </form>

  <?php if ($message): ?>
    <div class="msg"><?= $message ?></div>
  <?php endif; ?>

  <h2>Gespeicherte Einträge</h2>
  <?php if (empty($personen)): ?>
    <p style="color:#57606a">Noch keine Einträge vorhanden.</p>
  <?php else: ?>
  <table>
    <thead><tr><th>#</th><th>Vorname</th><th>Nachname</th><th>Gespeichert</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($personen as $p): ?>
      <tr>
        <td><?= (int)$p['id'] ?></td>
        <td><?= htmlspecialchars($p['vorname'],  ENT_QUOTES, 'UTF-8') ?></td>
        <td><?= htmlspecialchars($p['nachname'], ENT_QUOTES, 'UTF-8') ?></td>
        <td><?= htmlspecialchars($p['erstellt'], ENT_QUOTES, 'UTF-8') ?></td>
        <td>
          <form method="POST" action="" style="margin:0">
            <input type="hidden" name="action" value="delete">
            <input type="hidden" name="id" value="<?= (int)$p['id'] ?>">
            <button type="submit" class="del">Löschen</button>
          </form>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>

  <?php endif; ?>
</body>
</html>
