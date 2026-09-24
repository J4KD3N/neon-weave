# M5 plan — The promises

Written after `v1.0.0` (2026-09-24), from `docs/gap-analysis-v1.0.0.md`. M4 shipped the open-source 1.0; the analysis then read the GDD against the code and found the rows below that were never started. M5 closes every row a session can close and leaves the rest with a named owner in `docs/gaps.md`.

## What M5 is for

1. **Every mechanic the GDD names exists in the game**: the gore slider and the mature dressing (§5, §9), account unlocks past origins (§12), hackable turrets and doors (§9), awareness as a cone with a detection roll (§9).
2. **The pitch says what exists.** The campaign is four to six hours on a first run; the store page and the README say so until a writing pass changes it.
3. **Engineering keeps the bar**: the D-116 gates (smokes, screenshots, media caps, one engine version) stay green through every session.

## Sessions

| Session | Work | Done when |
|---|---|---|
| — | **Engineering and process** (done first, D-116): every binary executed, crash reports, mod media caps, a required screenshot check, tests off the player's files, one engine version | Done 2026-09-24 |
| S61 | **Gore slider and the mature layer**: a `gore` setting (off/low/full); blood splats where actors are hit and downed in combat, on the palette's `blood`; corpses left on the map after a fight; grime and failing lights as tile dressing (always on; they are not gore) | A fight leaves marks the setting can turn off; the screenshot job shows them |
| S62 | **Account unlocks, loadouts and cosmetics**: `loadouts` and `cosmetics` content kinds with an `unlock` key each, granted by the same achievement path as origins, chosen in the creator | A second run can start with a kit and a look the first one earned |
| S63 | **Hackable turrets and doors**: a `hack` interaction on locked doors (Tech check) in exploration and on turret-kind enemies in combat (adjacent, an action, a Tech roll; success disables or turns the turret) | The yard's locked door and the shepherd turret both answer to Tech |
| S64 | **Awareness as a cone and a detection roll**: enemies face a way, see a cone that walls block, roll perception against the party's stealth each tick into a noticed meter; stealth openers keep working; the HUD shows the meter | A party can walk behind a patrol; the opener test still ambushes |

## Constraints

- One system per session, data-driven, tested, never breaking exports; each session ends with a merged PR with green CI and its D-number.
- **The campaign** (30+ hours, GDD §1, §11) is a writer's, not a session's: the data format takes lines without code. It stays in `docs/gaps.md` under "Needs a person".

## Progress
- S61 Gore slider and the mature layer — done: `gore` as a Display setting (full by default; low keeps the fallen and little blood; off cleans every fight away) pushed to a `DecalLayer` under the walls that draws marks the world keeps as data (blood splats on hits, a pool on a down or kill, a body on a death, capped at 200 a map; handcrafted maps hold theirs in the story, Shards in the run, both saved); `traits.fluid` on enemies picks blood, oil (drones, turrets, constructs) or none (wisps); a `grime` floor pattern and tile plus failing lights (`art.flicker` on a glowing tile: its light gutters on two beats) scattered over every Shard's plain floor last with their own RNG so layouts stand, and placed in the yard. D-117.
- S62 Account unlocks, loadouts and cosmetics — done: `loadouts` content (Travelling light by default and empty-handed so nothing balanced moves, Scav kit, Corp issue free; Keeper's cache by first contact, Loom-walker's kit by any ending) with items worn where they fit the protagonist's slots and the rest in the pack, resources banked; tones and accents carry the same `unlock_flag` / `unlock_blurb` pair (Choir silver, Loom-lit); `Account.earnable` grants origins, loadouts, tones and accents by one path, `key_name` names the toast; the creator has a Loadout row with the kit spelled out, lists locked kits and looks with their blurbs, and shows the account's playthroughs (counted on every new game now) and unlocks earned. D-118.
- S63 Hackable turrets and doors — done: `hack` as an ability with effect `hack` (2 AP, range 1, accuracy 60) handed out per fight to the protagonist at `rules/combat.hack_tech_min` (2) and to every member whose class has the Tech branch, the protagonist adding `hack_tech_bonus` (15) per point past the minimum; a hit turns a target with `traits.hackable` (shepherd turret, feral drone, warden construct) to the caster's side, the turned machine is player-controlled, counts for victory, powers down when the fight ends and drops nothing; a map door with `hack_tech` opens to that much protagonist Tech without its key, setting its opens_flag, with the HUD saying what it would take (gate road and throat doors at 3). D-119.
- S64 Awareness as a cone and a detection roll — done: a map placement's `facing` (eight names, optional `sweep`/`sweep_period`) makes an enemy see a cone (`rules/combat.vision_cone_degrees` 180) and only hear within `hearing_radius` (2) behind it, no facing looking all round as before; `check_encounters(delta)` notices at once within `notice_instant_radius`, farther fills the enemy's `noticed` meter over `notice_seconds` scaled by closeness, empties it over `notice_decay_seconds`, and at the top rolls `detect_base` + per awareness point − per point of the party's best `stealth` trait (a Scav Runner has 1), a failed roll dropping the meter to half; a settled look (no delta: tests and teleports) is the old instant rule; the HUD shows the fullest meter; clicking an enemy whose meter is under full is an opener (`start_combat(true, true)`: every party member hidden for a turn, the first blows ambushes). The yard's chrome-addict looks north and sweeps. D-120.
