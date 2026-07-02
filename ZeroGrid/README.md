# 归零格 / ZeroGrid

A small Godot 4 prototype for a keyboard-driven bubble merge-and-pop board game.

Controls:

- Arrow keys or WASD: slide the board
- R: restart

Prototype rule:

- Matching bubbles merge like 2048.
- Bubbles grow through 2, 4, 8, and 16 visual stages.
- Any bubble that reaches 32 bursts and clears itself plus adjacent lower/equal bubbles.
- Every valid move adds pressure, and bursting bubbles no longer drops pressure.
- Max pressure triggers overload, spawns extra bubbles, then rolls pressure back.
- High pressure marks warning cells that spawn bubbles after the next valid move.
- Higher pressure changes the spawn table, adding more 4/8 bubbles and rare 16 bubbles.
- Score comes from merges, pops, and pop combos.

Code comment standard:

- New scripts should start with a short module responsibility comment.
- Gameplay constants should explain what system they tune.
- Complex functions should include comments that describe intent, not obvious line-by-line behavior.
