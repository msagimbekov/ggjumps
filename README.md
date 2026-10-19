# GG Jumps

Top-down mobile game (Android + iOS) made with **Godot 4.5.2** / GDScript. A small liquid bubble
sits on a piece of land surrounded by water. Press the bubble and drag back (slingshot): the drag
direction is opposite to the jump, the drag length is the power. Land on the next island or lose
a life. 99 jumps to win.

## Rules (current prototype)

- 3 lives; a miss splashes the bubble, it respawns on the last island. Out of lives: restart.
- Island kinds: grass (stops), ice (you slide on after landing), treadmill (belt carries you, off the end = splash), swaying (drifts side to side, sandy brown). Islands shrink along the way.
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
