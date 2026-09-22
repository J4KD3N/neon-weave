# The playtest kit (S47)

Nobody outside the author has played Neon Weave. This is everything needed to change that with two people and an afternoon, and to turn what they did into numbers the balance sessions can act on. The playtest itself needs the people; the kit is what a session can do.

## What to give a tester

1. The build: the `v0.3.0` archive for their platform from the [Releases page](https://github.com/J4KD3N/neon-weave/releases/tag/v0.3.0). macOS: right-click → Open the first time.
2. This page's **script** and **questions** (below).
3. The launch flag. The game writes a log of everything the balance harness measures when started with `--playtest`:

   | Platform | Run |
   |---|---|
   | Windows | `neon-weave.exe -- --playtest` |
   | Linux | `./neon-weave.x86_64 -- --playtest` |
   | macOS | `open neon-weave.app --args -- --playtest` |

   The log is `session_<date>.jsonl` under the Godot user data folder: `%APPDATA%\Godot\app_userdata\Neon Weave\playtest\` on Windows, `~/.local/share/godot/app_userdata/Neon Weave/playtest/` on Linux, `~/Library/Application Support/Godot/app_userdata/Neon Weave/playtest/` on macOS. Ask for the file back with the answers. It holds no personal data: maps, fights, runs, dialogue choices and times.

## The script (two to three hours)

Play Act 1 to first contact with the Choir without reading anything else about the game. In order, and without help unless stuck for five minutes:

1. New game. Pick Story-Protected unless you like losing people. Make a character; note what you did not understand.
2. Leave the plaza through the yard gate. Talk to whoever you meet. Recruit or refuse as you like.
3. Follow the road east. Fight what fights you. Note the first fight you found hard and the first you found boring.
4. The relay station: find out what happened to the crew, do what the survivor asks.
5. Back home: spend what you carried. Raise the Beacon. Run a Shard and get out with something.
6. Do what the journal (J) says next until the throat opens, then go down until something talks to you.
7. Stop there, or keep going into Act 2 if you want to. Either way, send the log.

## The questions

Ask these afterwards, in this order, and write down the first answer:

1. What is the game about, in one sentence?
2. Which fight did you nearly lose, and what did you do about it?
3. Which fight was a walkover?
4. When did you first not know what to do next?
5. Did you use the pad, the mouse, or the keys? What did you reach for that did nothing?
6. Who did you recruit, who did you refuse, and why?
7. What did you spend Salvage on first, and did it feel worth it?
8. Name one thing you would change and one you would keep.
9. How long did it take? (The log knows; ask anyway.)
10. Would you play Act 2?

## Reading the logs

Put every `session_*.jsonl` in one folder and run:

```
godot --headless --path . -s tools/playtest_report.gd -- --logs=path/to/folder
```

The report prints:

- **FIGHTS**: win rate, rounds, HP left and downed after a win, party level, per map and enemy set, with the harness band for that map beside it. A person under a band the harness passes is the finding; a person over the ceiling is the other finding.
- **RUNS**: extraction rate and haul per Shard template and depth. Compare to the harness's "extraction by depth" row.
- **TIME**: minutes from launch to first entering each story map, per session. The plan says Act 1 is two to three hours; this is where that is measured.
- **CHOICES**: how many times each dialogue line was picked. A line nobody picked is a line to cut or a gate nobody met.
- **ENDINGS**: which, if any.

## The triage

Fill this in from the report and the answers. One row per finding, ranked by how much it hurt the tester. The owner is the session or track that closes it.

| # | Finding | Evidence (report row or answer) | Owner | Done when |
|---|---|---|---|---|
| 1 | *pending: needs two testers* | | S48 fights / S49 economy / writing track / S51–S54 surfaces | |

When the table has rows, move the harness bands in `tests/unit/test_balance.gd` to what people did (D-081: bands are hypotheses until measured), note the closing commit in `docs/gaps.md`, and S48 starts from row 1.
