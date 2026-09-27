<?php
session_start();

// Bereits eingeloggt → weiterleiten
if (!empty($_SESSION['user'])) {
    header('Location: index.php');
    exit;
}

// DB-Verbindung
$dsn    = 'mysql:host=mariadb;port=3306;dbname=namen;charset=utf8mb4';
$dbUser = 'webuser';
$dbPass = getenv('DB_PASSWORD') ?: 'changeme';

$error = '';

try {
    $pdo = new PDO($dsn, $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException $e) {
    $error = 'Datenbankverbindung fehlgeschlagen.';
}

// Login verarbeiten
if (empty($error) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';

    if ($username !== '' && $password !== '') {
        $stmt = $pdo->prepare("SELECT password_hash FROM users WHERE username = ? AND active = 1");
        $stmt->execute([$username]);
        $row = $stmt->fetch();

        if ($row && password_verify($password, $row['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION['user'] = $username;
            header('Location: index.php');
            exit;
        }
    }
    $error = 'Ungültiger Benutzername oder Passwort.';
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Anmeldung</title>
  <style>
    body  { font-family: sans-serif; max-width: 360px; margin: 100px auto; padding: 0 1rem; }
    h1    { font-size: 1.3rem; margin-bottom: 1.5rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text], input[type=password] {
      width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem; box-sizing: border-box;
    }
    button {
      width: 100%; padding: .6rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer;
    }
    button:hover { background: #2563b0; }
    .err { margin-bottom: 1rem; padding: .75rem; background: #fff0f0;
      border: 1px solid #fca5a5; border-radius: 4px; color: #c0392b; }
  </style>
</head>
<body>
  <h1>🔒 Anmeldung</h1>

  <?php if ($error): ?>
    <div class="err"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
  <?php endif; ?>

  <form method="POST" action="">
    <label for="username">Benutzername</label>
    <input type="text" id="username" name="username"
           value="<?= htmlspecialchars($_POST['username'] ?? '', ENT_QUOTES, 'UTF-8') ?>"
           required autofocus autocomplete="username">

    <label for="password">Passwort</label>
    <input type="password" id="password" name="password"
           required autocomplete="current-password">

    <button type="submit">Anmelden</button>
  </form>
</body>
</html>
