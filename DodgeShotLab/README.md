# Dodge Shot Lab

A minimal Godot 4 prototype for a movement-only dodge shooter.

Controls:

- Arrow keys or WASD: move
- R: restart after game over

Core loop:

- The player only controls position.
- The ship fires automatically.
- Enemies and bullets keep pushing into the play area.
- Weapon packs switch bullet type; repeated packs of the same type upgrade that bullet.
- Local high scores are saved under Godot's `user://` data path.

Design document:

- `docs/design.md`
