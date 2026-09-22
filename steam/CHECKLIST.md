# Steam live checklist

What only a Steamworks account, an app id and a running client can verify.
`tools/steam_check.gd` (`steam/READINESS.md`) says what is still unfilled;
`--strict` exits 1 until it is. Tick these in order.

1. **Extension.** Download the GodotSteam GDExtension for Godot 4.7 to `addons/godotsteam/` (git-ignored). Put `steam_appid.txt` with the app id beside the editor. Run `steam_check`: the extension row turns present.
2. **Ids.** Put `app_id` and `demo_app_id` in `steam/steam.json`; put the app id and the three depot ids in `steam/app_build.vdf`. Run `steam_check --strict`: it exits 0 when the ids are in and the template is whole.
3. **Achievements.** In Steamworks → Stats & Achievements, define every API name from `steam/READINESS.md` (twelve; the table is copy-paste ready). Publish the changes.
4. **Cloud.** Steamworks → Cloud: enable, quota 16 MB, 12 files (the readiness report lists them). Leave auto-cloud off: the game writes through the Remote Storage API.
5. **Live achievements.** Start the game under the client, extract from a Shard once: `first_extraction` unlocks and the overlay shows it. `-- --playtest` logs it too. Check the Steamworks stats page shows the unlock.
6. **Live cloud.** Save to slot 1 with a thumbnail (a real frame), quit, delete `user://saves/slot_1.json` and its PNG, start: `pull_missing` restores both. The pause menu's Load game shows the picture.
7. **Steam Input.** Upload `steam/steam_input_template.vdf` as the default configuration. On a Deck: the stick walks and glides the combat cursor, A/B/X/Y and the shoulders do what `docs/controller.md` says, the back grips duplicate L1/R1 and Select, the right trackpad is the mouse. Rumble fires on a hit.
8. **Demo depot.** Unzip the release artifacts into `build/<platform>/`, run `steamcmd +run_app_build ../steam/app_build.vdf`. Set the demo app's launch option to `--demo`. Install the demo from the client: it boots to the title, plays to first contact, shows the demo boundary.
9. **Full depot.** The same build with `"demo": false`; the launch option passes nothing. Install: Act 2 opens after first contact.
10. **Workshop.** `godot --headless --path . -s tools/workshop_upload.gd -- --mod=examples/mods/stranger`: with the client running the item is created (the tool prints its id); subscribe to it in the client, start the game: the Ashwalker is on the creator and F1 lists the mod. Without the client the same command publishes to `user://workshop_null/1/`, and the next start loads it from there, which is how CI proves the path.

Each step that passes is a line in `docs/decisions.md` under S58's decision; the gaps entry for Steam closes when all ten are ticked.
