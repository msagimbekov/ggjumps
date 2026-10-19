# GG Jumps

Top-down mobile game (Android + iOS) made with **Godot 4.5.2** / GDScript. A small liquid bubble
sits on a piece of land surrounded by water. Press the bubble and drag back (slingshot): the drag
direction is opposite to the jump, the drag length is the power. Land on the next island or lose
a life. 99 jumps to win.

## Rules (current prototype)

- 3 lives (more from pickups; up to 4 show as bubbles, 5+ as a number); a miss splashes the bubble, it respawns on the last island. Out of lives: restart.
- Island kinds: grass (stops), ice (you slide on after landing), rock (drifts left-right or up-down). Treadmill islands (belt carries you) still exist in code but are off (`TREADMILLS` in main.gd). The last island is plain grass, centred. Islands shrink along the way.
- Islands two apart are always out of jump range, so none can be skipped; every jump is checked solvable (`scripts/verify_levels.gd`).
- Dragging shows up to five quarter-circle arcs towards the jump direction (no landing marker). Tapping the lives icons five times toggles the old landing line + target (test aid).
- The 100 islands (start + 99) come from one seeded RNG in `scripts/main.gd` (`_build_level`),
  so every device gets the same level. Never use unseeded randomness for the layout.

## Layout

- `scripts/main.gd` game states (aim / fly / slide / fall / over / won), input, level, camera
- `scripts/land.gd` island polygon, landing test, drawing
- `scripts/bubble.gd` the player's look (wobble, squash, shadow)
- `scripts/fx.gd` drag arcs, rings, splash; `scripts/critters.gd` fish; fonts/Fredoka.ttf (OFL); `scripts/hud.gd` counter, lives, end overlay
- `shaders/water.gdshader` world-space animated water

## Dev

Godot 4.5.2 exactly (portable at `C:\Users\madis\tools\Godot\`).

- Run: `Godot_v4.5.2-stable_win64.exe --path .` (mouse = touch)
- Import/parse check: `Godot_v4.5.2-stable_win64_console.exe --headless --editor --quit`
- Android on a phone over USB: enable USB debugging, then Godot's one-click deploy button.
  SDK `C:\Users\madis\Android\Sdk`, JDK 17 (Temurin); both are set in Godot's Editor Settings.

## Over-the-air patches

Same system as ggcuts. `scripts/ota.gd` (autoload `Ota`, **first** in the list) loads a downloaded
`.pck` in `_init`, before every other autoload and the main scene, so a patch replaces scripts,
scenes, shaders, fonts and art. After launch the game checks `ota/manifest.json` on GitHub Pages
(`https://msagimbekov.github.io/ggjumps/ota/`), downloads a newer patch made for this build,
verifies its SHA-256 and RSA signature and applies it on the **next** launch. Two patched launches
in a row that never reach the game drop the patch for good.

**Publish:** push to main, then run the **OTA patch** workflow (`.github/workflows/ota.yml`,
manual, Linux). It exports `.pck` packs for iOS and Android, signs them and pushes them with the
merged manifest to the `gh-pages` branch (folder `ota/`). Needs the repo secret `OTA_SIGNING_KEY`
(private key in `~/ggjumps-signing/ota_private.pem`, never in the repo; the public half is in
`scripts/ota.gd`) and GitHub Pages enabled for `gh-pages`.

**Needs a store build instead:** anything native, export settings, `project.godot` settings,
`scripts/ota.gd` itself, and the set of `class_name`s and autoloads (the build's "shape",
`scripts/dev/ota_shape.gd`). Adding the `Ota` autoload changed the shape, so only builds made
after it (TestFlight etc.) can take patches. Bump `application/config/version` with every change.

Test locally: serve a folder with a manifest and pass `-- --ota-url=http://localhost:8765/`.
