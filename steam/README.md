# Steam

Everything Steam-specific lives here or behind `Platform` (`src/core/platform/`). The game runs Steam-free by default: CI, the editor and the open-source build use the null backend, which keeps achievements in memory and a "cloud" folder under `user://cloud_null/` so the same sync code runs everywhere.

## Wiring GodotSteam

1. Download the GodotSteam GDExtension for Godot 4.7 and unpack it to `addons/godotsteam/` (kept out of git; see `.gitignore`).
2. Create `steam_appid.txt` beside the editor or exported executable with the app id during development.
3. Put the app id (and the demo app id) in `steam/steam.json`. With `app_id` 0 the Steam backend never initialises, so a checkout without Steamworks keeps working.
4. Define the achievements in Steamworks with the exact `steam_id` names from `content/achievements/*.json`.
5. Enable Steam Cloud for the app with a quota that covers `saves/` (four small JSON files) and set the auto-cloud path to the Godot user directory, or leave it off: the game writes through the Steam Remote Storage API itself.

`PlatformService` picks the Steam backend when the `Steam` singleton exists and `steamInitEx` reports success; every call is dynamic, so the scripts load without the extension.

## Steam Input

`steam_input_template.vdf` is the default controller template mirroring `docs/controller.md`: A confirm, B cancel, X/Y/L1/R1 abilities, L2/R2 zoom, Start system menu or end turn, Select swap member; the Deck's back grips duplicate L1/R1 and Select and the right trackpad drives the mouse. Upload it through Steamworks as the app's default configuration.

## Demo depot

The demo is the same build with `"demo": true` in `steam/steam.json` (a separate demo app id). S26 adds the depot layout and the build script.
