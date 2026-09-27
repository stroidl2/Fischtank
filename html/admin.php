<?php
session_start();

// ── Nur für eingeloggte Benutzer ──────────────────────────────────────────────
if (empty($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}

// ── DB-Verbindung ─────────────────────────────────────────────────────────────
$dsn    = 'mysql:host=mariadb;port=3306;dbname=namen;charset=utf8mb4';
$dbUser = 'webuser';
$dbPass = getenv('DB_PASSWORD') ?: 'changeme';

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException $e) {
    die('Datenbankverbindung fehlgeschlagen.');
}

$message = '';
$error   = '';

// ── Aktionen verarbeiten ──────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';

    // Neuen Benutzer anlegen
    if ($action === 'create') {
        $newUser = trim($_POST['username'] ?? '');
        $newPass = $_POST['password']  ?? '';
        $newPass2= $_POST['password2'] ?? '';

        if ($newUser === '' || $newPass === '') {
            $error = 'Benutzername und Passwort dürfen nicht leer sein.';
        } elseif (strlen($newUser) > 100) {
            $error = 'Benutzername zu lang (max. 100 Zeichen).';
        } elseif ($newPass !== $newPass2) {
            $error = 'Passwörter stimmen nicht überein.';
        } elseif (strlen($newPass) < 8) {
            $error = 'Passwort muss mindestens 8 Zeichen lang sein.';
        } else {
            $stmt = $pdo->prepare("SELECT id FROM users WHERE username = ?");
            $stmt->execute([$newUser]);
            if ($stmt->fetch()) {
                $error = 'Benutzername „' . htmlspecialchars($newUser, ENT_QUOTES, 'UTF-8') . '" existiert bereits.';
            } else {
                $hash = password_hash($newPass, PASSWORD_BCRYPT);
                $pdo->prepare("INSERT INTO users (username, password_hash) VALUES (?, ?)")
                    ->execute([$newUser, $hash]);
                $message = '✅ Benutzer „' . htmlspecialchars($newUser, ENT_QUOTES, 'UTF-8') . '" wurde angelegt.';
            }
        }
    }

    // Benutzer aktivieren / deaktivieren
    if ($action === 'toggle' && isset($_POST['id'])) {
        $id = (int)$_POST['id'];
        // Admin-Account darf nicht deaktiviert werden wenn es der einzige aktive ist
        $activeCount = (int)$pdo->query("SELECT COUNT(*) FROM users WHERE active = 1")->fetchColumn();
        $isActive    = (int)$pdo->query("SELECT active FROM users WHERE id = $id")->fetchColumn();
        if ($isActive && $activeCount <= 1) {
            $error = 'Es muss mindestens ein aktiver Benutzer vorhanden bleiben.';
        } else {
            $pdo->prepare("UPDATE users SET active = 1 - active WHERE id = ?")
                ->execute([$id]);
            $message = '✅ Benutzer-Status wurde geändert.';
        }
    }

    // Benutzer löschen
    if ($action === 'delete' && isset($_POST['id'])) {
        $id = (int)$_POST['id'];
        $targetUser = $pdo->query("SELECT username FROM users WHERE id = $id")->fetchColumn();
        if ($targetUser === $_SESSION['user']) {
            $error = 'Du kannst deinen eigenen Account nicht löschen.';
        } else {
            $pdo->prepare("DELETE FROM users WHERE id = ?")
                ->execute([$id]);
            $message = '🗑️ Benutzer wurde gelöscht.';
        }
    }
}

// ── Alle Benutzer laden ────────────────────────────────────────────────────────
$users = $pdo->query("SELECT id, username, active, erstellt FROM users ORDER BY erstellt ASC")->fetchAll();
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Benutzerverwaltung</title>
  <style>
    body  { font-family: sans-serif; max-width: 680px; margin: 60px auto; padding: 0 1rem; }
    h1,h2 { font-size: 1.3rem; margin-bottom: 1rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text], input[type=password] {
      width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; box-sizing: border-box;
    }
    .row  { display: flex; gap: .75rem; }
    .row > div { flex: 1; }
    button { padding: .5rem 1.25rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer; }
    button:hover { background: #2563b0; }
    button.del  { padding: .25rem .6rem; background: #fff; color: #c0392b;
      border: 1px solid #fca5a5; font-size: .82rem; border-radius: 4px; cursor: pointer; }
    button.del:hover  { background: #fff0f0; }
    button.tog  { padding: .25rem .6rem; background: #fff; color: #57606a;
      border: 1px solid #d1d5db; font-size: .82rem; border-radius: 4px; cursor: pointer; }
    button.tog:hover  { background: #f7f8fa; }
    .msg  { margin-bottom: 1rem; padding: .75rem; background: #f0f6ff;
      border: 1px solid #bfdbfe; border-radius: 4px; }
    .err  { background: #fff0f0; border-color: #fca5a5; color: #c0392b; }
    table { width: 100%; border-collapse: collapse; margin-top: 1rem; font-size: .95rem; }
    th,td { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid #e5e7eb; }
    th    { background: #f7f8fa; font-weight: bold; }
    tr:hover td { background: #f7f8fa; }
    .badge-on  { display:inline-block;padding:.15rem .5rem;background:#d1fae5;color:#065f46;
      border-radius:9999px;font-size:.8rem;font-weight:bold; }
    .badge-off { display:inline-block;padding:.15rem .5rem;background:#f3f4f6;color:#6b7280;
      border-radius:9999px;font-size:.8rem; }
    nav { display:flex; justify-content:space-between; align-items:center;
      margin-bottom:1.5rem; padding-bottom:.75rem; border-bottom:1px solid #e5e7eb; }
  </style>
</head>
<body>

  <nav>
    <span><a href="index.php" style="text-decoration:none;color:#3b82d4;">← Zurück zur Anwendung</a></span>
    <span style="font-size:.9rem;color:#57606a">
      👤 <?= htmlspecialchars($_SESSION['user'], ENT_QUOTES, 'UTF-8') ?> &nbsp;
      <a href="index.php?logout=1" style="color:#c0392b;text-decoration:none;">Abmelden</a>
    </span>
  </nav>

  <h1>Benutzerverwaltung</h1>

  <?php if ($message): ?>
    <div class="msg"><?= $message ?></div>
  <?php endif; ?>
  <?php if ($error): ?>
    <div class="msg err"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
  <?php endif; ?>

  <!-- Neuen Benutzer anlegen -->
  <h2>Neuen Benutzer anlegen</h2>
  <form method="POST" action="">
    <input type="hidden" name="action" value="create">
    <label for="username">Benutzername</label>
    <input type="text" id="username" name="username" required maxlength="100"
           placeholder="z. B. max.mustermann"
           value="<?= htmlspecialchars($_POST['username'] ?? '', ENT_QUOTES, 'UTF-8') ?>">
    <div class="row">
      <div>
        <label for="password">Passwort</label>
        <input type="password" id="password" name="password" required minlength="8"
               placeholder="mind. 8 Zeichen">
      </div>
      <div>
        <label for="password2">Passwort wiederholen</label>
        <input type="password" id="password2" name="password2" required minlength="8"
               placeholder="mind. 8 Zeichen">
      </div>
    </div>
    <button type="submit">Benutzer anlegen</button>
  </form>

  <!-- Bestehende Benutzer -->
  <h2 style="margin-top:2rem">Vorhandene Benutzer</h2>
  <?php if (empty($users)): ?>
    <p style="color:#57606a">Keine Benutzer vorhanden.</p>
  <?php else: ?>
  <table>
    <thead>
      <tr><th>Benutzername</th><th>Status</th><th>Angelegt</th><th colspan="2"></th></tr>
    </thead>
    <tbody>
    <?php foreach ($users as $u): ?>
      <tr>
        <td>
          <?= htmlspecialchars($u['username'], ENT_QUOTES, 'UTF-8') ?>
          <?php if ($u['username'] === $_SESSION['user']): ?>
            <span style="font-size:.8rem;color:#57606a">(du)</span>
          <?php endif; ?>
        </td>
        <td>
          <?php if ($u['active']): ?>
            <span class="badge-on">aktiv</span>
          <?php else: ?>
            <span class="badge-off">inaktiv</span>
          <?php endif; ?>
        </td>
        <td><?= htmlspecialchars($u['erstellt'], ENT_QUOTES, 'UTF-8') ?></td>
        <td>
          <form method="POST" action="" style="margin:0">
            <input type="hidden" name="action" value="toggle">
            <input type="hidden" name="id" value="<?= (int)$u['id'] ?>">
            <button type="submit" class="tog">
              <?= $u['active'] ? 'Deaktivieren' : 'Aktivieren' ?>
            </button>
          </form>
        </td>
        <td>
          <?php if ($u['username'] !== $_SESSION['user']): ?>
          <form method="POST" action="" style="margin:0">
            <input type="hidden" name="action" value="delete">
            <input type="hidden" name="id" value="<?= (int)$u['id'] ?>">
            <button type="submit" class="del">Löschen</button>
          </form>
          <?php endif; ?>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>

</body>
</html>
