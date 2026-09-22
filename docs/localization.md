# Localization

Since S55 (D-110) every string the player reads goes through one table, `Loc`
(`src/core/loc.gd`), and a language is a content entry a mod can ship. Nothing
is translated yet; this is the scaffolding, and the test that keeps it whole.

## How a string reaches the screen

| Kind of string | Call | Key in the table |
|---|---|---|
| UI text in code (menus, hints, toasts, the HUD) | `Loc.t("Save game…")` | the English source text itself |
| A content entry's field (a name, a summary, a line) | `Loc.text(entry, "name")` or `Loc.content("dialogue", "sera_recruit", "nodes.greet.text", source)` | `kind.id.path`, dots for keys and indices: `quests.main_waking.stages.gate.objectives.0.text` |
| A content string whose path the code does not know (a toast an effect carries, a banter line, an epilogue) | `Loc.any(source)` | looked up by its source text across the content table |

Missing means the source: a half-finished table still runs. Format tokens
(`%s`, `%d`, `%.1f`) stay in the translation where the source has them.

## Languages

A language is a `locales` entry, `content/locales/<code>.json` in the base game
or `locales/<code>.json` in a mod:

```json
{ "name": "Français", "ui": { "Back": "Retour" }, "content": { "companions.sera.short_name": "Séra" } }
```

`content/locales/en.json` is the source language and empty; `pseudo.json` is
not a language but a transform (below). The settings screen's Language row
lists every locale loaded, English first, pseudo last; the choice is saved in
`user://settings.json`.

## The template

```bash
godot --headless --path . -s tools/extract_strings.gd -- --out=user://locale_template.json
```

writes every UI source string found in `Loc.t("…")` calls under `src/` and
every content text field of the base game, keyed and sorted, as one JSON file
to copy and fill. `Loc.TEXT_FIELDS` is the list of text fields per content kind
(`*` any key, `[]` any index); a new text field on a kind is added there so the
template and the pseudo test see it.

| Kind | Text fields |
|---|---|
| abilities, items, resources, subclasses, talents, achievements, difficulties | name, summary |
| affixes, biomes, branches, enemies, factions, maps, merchants, parties, pickups, shards, tiles | name |
| buildings | name, levels[].blurb |
| classes | name, summary, resource.name, resource.summary |
| companions | name, short_name, summary, scenes[].label |
| dialogue | name, nodes.*.text, nodes.*.choices[].text, lines[].text |
| endings | name, summary, epilogue.*.*, modifiers[].text |
| lore | name, text, source |
| npcs | name, short_name, summary |
| origins | name, summary, unlock_blurb |
| quests | name, start_toast, stages.*.summary, stages.*.objectives[].text, stages.*.next_toast, stages.*.branches[].toast |
| races | name, identity |
| rules | lines[] (the credits) |

## The pseudo-locale and its test

The `pseudo` locale wraps every string that comes through the table in ⟦ ⟧
and accents every letter (`Save game` → `⟦Šåṽé ğåɱé⟧`), keeping format tokens
whole. Anything still in plain ASCII letters on a screen is a string that did
not come through. `tests/unit/test_localization.gd` switches to it and renders
every screen (the title and its pages, the creator, the pause menu, the saves
screen, the settings and every row, the journal, a talk with its history, the
Bastion, the Roster, the Weave, the pack, the Archive, a Shard's status line, a
fight's HUD, an ending, the demo boundary) and fails on the first plain word,
naming the screen and the word. The player's typed name is theirs and is
typed in accented letters in the test.

To eyeball it in a build: Settings → Language → Pseudo-locale (test).

## What is not done

- No language has a table; the template is the deliverable.
- The dialogue history stores the lines as they were shown, so switching
  language mid-game leaves the earlier history in the earlier language.
- Ids that reach the screen as words (a faction lean, a slot name, a status)
  go through `Loc.t` on the id, so a table can name them, but they are not
  content fields.
- Right-to-left scripts, plural rules and font coverage are untouched.
