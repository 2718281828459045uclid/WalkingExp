# Instructions for AI assistants in this repository

Read `plan.md` before starting work. It states the goals and the teaching mode. `ROADMAP.md` lists the lesson sequence; `docs/decisions/` records why the architecture is what it is.

## Teaching mode

- The developer is learning. New technical material becomes a lesson in `curriculum/NN-name/README.md`, in the format given in `curriculum/README.md`.
- Do not write solutions to lesson exercises unless asked. When asked for help on an exercise, give hints in tiers (concept, then approach, then partial code) and stop after each tier.
- Starter code marks unfinished work with `# EXERCISE (lesson NN): ...` comments instead of implementations.
- Derive math with the developer (on paper, in the lesson text) before writing the code that uses it.
- After a lesson, update its status in `ROADMAP.md`.

## Lessons written ahead of the student

All lessons exist before the student reaches them, so the repository holds the code of every lesson at once. These rules keep each lesson true while the student works through it in order.

- **Additive evolution.** A lesson adds files, subclasses, or exported properties whose defaults keep earlier behavior. It does not rewrite code that an earlier lesson's text walks through. If an earlier file must change, update the earlier lesson's text in the same change so its descriptions, names, and line references stay correct.
- **Lesson scenes.** Each lesson from 02 onward has `game/scenes/lessons/NN_slug.tscn`, showing the game at the end of that lesson. `game/scenes/sandbox.tscn` serves Lessons 00–01. `run/main_scene` in `project.godot` points to the newest lesson scene. Earlier lesson scenes must keep running.
- **Starter code reaches the lesson's Result** (the ROADMAP column). Exercises are extensions that no later lesson depends on. When a later lesson needs something an earlier exercise asks for, it implements it in its own files and places this notice at the top of the lesson: "Complete Lesson NN exercise EX before reading this lesson; it contains one solution."
- **Tests.** `game/tests/test_*.gd` are SceneTree scripts that call `quit(0)` on success and `quit(1)` on failure. They cover starter code, never exercise solutions.
- **Architecture map.** `docs/architecture.md` describes the modules and how they control each other. Update it with every lesson.

## Conventions

- Godot 4.6.2, GDScript with static types, Jolt physics, Forward+ renderer.
- Code does not contain asset paths. Scripts declare exported Resource properties; scenes assign `.tres` files from `game/data/` (decision 0004).
- Generated geometry lives in internal child nodes (`add_child(node, false, Node.INTERNAL_MODE_FRONT)`) so it is never written into `.tscn` files. See `game/src/terrain/terrain.gd`.
- `Vector2` / `Vector3` are 32-bit floats; `float` is 64-bit. This matters for numerical derivatives.
- Godot front faces are clockwise as seen by the camera.
- New architectural choices get a numbered record in `docs/decisions/` (context, decision, consequences).
- Follow the comment and prose style in the user's global instructions: question-and-answer comments for non-obvious code, extensive comments in shaders, dry technical prose in Markdown.

## Verification

Run the headless regression check before reporting a change as complete. It runs every lesson scene and every test:

```bash
tools/check.sh
```

After visual changes, and for anything that needs the GPU (compute shaders through `RenderingDevice`, which is null in headless runs), run the windowed check. A Godot window appears for one to two seconds per scene; screenshots go to the given folder:

```bash
tools/render_check.sh <output_dir> [res://scenes/lessons/NN_slug.tscn ...]
```

Write one-off experiment harnesses (SceneTree scripts run with `-s`) in a scratch directory, not in the repository. Experiments that modify project files run on a copy of `game/` in a scratch directory.

SuperCollider:

- Never boot the real-time server (`s.boot`, `Server.default.boot`): it plays through the developer's speakers.
- Check code with sclang in batch mode: `/Applications/SuperCollider.app/Contents/MacOS/sclang file.scd`, with `0.exit;` at the end of the file. sclang listens on `NetAddr.langPort` (57120 unless another sclang holds it).
- When audio output must be checked, render offline (non-real-time, `Score.recordNRT`) to a scratch file and inspect the file.

## Version control

The developer handles Git. Do not commit, push, or change Git configuration.
