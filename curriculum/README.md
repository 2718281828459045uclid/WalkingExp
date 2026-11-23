# Curriculum

One folder per lesson: `NN-short-name/README.md`. The sequence and status of all lessons is in `ROADMAP.md`.

## Lesson format

Each lesson has the same sections, in this order.

| Section | Purpose |
|---|---|
| 1. Orientation | What the lesson builds, which goal in `plan.md` it serves, which files it touches. |
| 2. Predict | Questions answered on paper before reading code. A wrong prediction marks the place where learning happens. |
| 3. Read | A guided walk through the starter code. |
| 4. Run and observe | Experiments in the running game. Each states what to look for, not what will be seen. |
| 5. Tweak | Small edits to parameters or single lines, with a question attached to each. |
| 6. Exercises | New code. Difficulty: ★ (an hour or less), ★★ (an evening), ★★★ (open-ended). |
| 7. Reflect | Questions that connect the lesson to later phases. |
| 8. Answers | Answers to sections 2, 4, and 5, folded in `<details>` blocks. Open one only after committing to an answer. |

Exercises have no worked solutions in the lesson text. Some lessons include reference measurements, folded, for checking an exercise's results after the measurement is done.

## Lesson scenes and code written ahead

The lessons were written before you reach them, so the repository already contains the code of every lesson. Three rules keep each lesson readable in order:

- Each lesson has its own scene showing the game at the end of that lesson: `game/scenes/sandbox.tscn` for Lessons 00–01, `game/scenes/lessons/NN_slug.tscn` from Lesson 02 onward. Open the lesson's scene and press **F6** (Run Current Scene). **F5** runs the project's main scene, which is the newest lesson's scene.
- Later lessons add files rather than rewrite the files an earlier lesson explains. Folders and files you have not reached yet can be ignored; `docs/architecture.md` lists which lesson introduced each module.
- Exercises are not solved by later code, with one exception: when a later lesson needs the result of an earlier exercise, it says so at its top ("Complete Lesson NN exercise EX before reading this lesson").

## Working with an AI assistant on a lesson

- Ask for "hint 1", "hint 2", "hint 3" on an exercise. The tiers run from concept, to approach, to partial code. `CLAUDE.md` instructs the assistant to stop after each tier.
- Ask the assistant to check a derivation or to review exercise code rather than to write it.
- Ask for a new lesson in this format when a topic outside the roadmap comes up.

## Notes

Keep a `notes.md` in each lesson folder: predictions that were wrong and why, measurements, open questions. These notes are the record of what was learned; the code is the record of what was built.
