<?php
$vorname  = '';
$nachname = '';
$anzeige  = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $vorname  = htmlspecialchars(trim($_POST['vorname']  ?? ''), ENT_QUOTES, 'UTF-8');
    $nachname = htmlspecialchars(trim($_POST['nachname'] ?? ''), ENT_QUOTES, 'UTF-8');
    $anzeige  = ($vorname !== '' && $nachname !== '');
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <title>Namenseingabe</title>
  <style>
    body { font-family: sans-serif; max-width: 480px; margin: 60px auto; padding: 0 1rem; }
    h1   { font-size: 1.4rem; margin-bottom: 1.5rem; }
    label { display: block; margin-bottom: .25rem; font-weight: bold; }
    input[type=text] {
      width: 100%; padding: .5rem; margin-bottom: 1rem;
      border: 1px solid #ccc; border-radius: 4px; font-size: 1rem;
    }
    button {
      padding: .5rem 1.5rem; background: #3b82d4; color: #fff;
      border: none; border-radius: 4px; font-size: 1rem; cursor: pointer;
    }
    button:hover { background: #2563b0; }
    .result {
      margin-top: 1.5rem; padding: 1rem;
      background: #f0f6ff; border: 1px solid #bfdbfe; border-radius: 4px;
    }
  </style>
</head>
<body>
  <h1>Namenseingabe</h1>

  <form method="POST" action="">
    <label for="vorname">Vorname</label>
    <input type="text" id="vorname" name="vorname"
           value="<?= $vorname ?>" placeholder="z. B. Max" required>

    <label for="nachname">Nachname</label>
    <input type="text" id="nachname" name="nachname"
           value="<?= $nachname ?>" placeholder="z. B. Mustermann" required>

    <button type="submit">Absenden</button>
  </form>

  <?php if ($anzeige): ?>
  <div class="result">
    <strong>Eingegebener Name:</strong><br>
    <?= $vorname ?> <?= $nachname ?>
  </div>
  <?php endif; ?>
</body>
</html>
