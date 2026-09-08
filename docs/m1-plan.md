# M1 — Vertical Slice plan

GDD §14: *final art pipeline, creator v1 (5 races), full combat, 4 classes, Bastion (3 buildings), Sera fully written, save/load, controller. One hour that feels final.*

One system per session (GDD §15). Order chosen by dependency and by what makes the M0 loop feel like a game soonest. Each session ends with a PR, decisions, gaps, and a CI screenshot.

| Session | System | Why here | Done when |
|---|---|---|---|
| **S5** | **Bastion v1**: Beacon, Med-bay, Workshop; ledger v2 with building levels; party HP persists between runs | The loop produces resources nobody can spend; growth must be visible (pillar 3) | Buildings upgrade from the ledger, Beacon depth scales Shards, Med-bay heals on return, Workshop buffs the party |
| S6 | **Save/load**: slots, autosave, versioned JSON of party + ledger + bastion + current map state; Steam Cloud stays behind `Platform` | Everything after this needs to survive a restart | Round-trip test of a mid-Shard state; migration test from ledger-only saves |
| S7 | **Full combat**: cover, elevation (one storey), surfaces (mana pool, conduit, corrosive biogrowth), class resources (Surge, Vent Heat) | Pillar 1; the M0 skeleton has none of the GDD §9 texture | Each mechanic data-defined on tiles/abilities, unit-tested, and used by at least one enemy family |
| S8 | **Classes 3–4**: Circuit-Witch (Hexes) and Drone Shepherd (Scrap Charge) as registry entries only | Proves "new classes are data" (§15) and exercises the resource system from S7 | Both playable in the prototype party with 2 abilities each and their resource loop |
| S9 | **Creator v1**: race (5), origin, attributes, starting class; paper-doll rig with race overlays in placeholder form | Unlocks the player-expression pillar | A created character replaces the party leader and persists via S6 |
| S10 | **Art pipeline**: sprite sheet import conventions, per-biome palette swap, 4-direction facing, animation cycles; placeholder art replaced for one race and one enemy | "Feels final" is mostly this | Documented pipeline in `docs/art-pipeline.md`; one fully animated actor |
| S11 | **Sera Voss**: dialogue data format, approval, banter triggers, her personal quest hook in both death-stakes modes | First companion proves the narrative data model | Sera recruitable in the yard, her quest reachable from a Shard, approval visible |
| S12 | **Controller**: full navigation of exploration, combat and menus with a gamepad; Steam Deck layout | M1 exit criterion | Every input path has a pad binding; CI screenshot job unchanged |

Out of M1 scope (deferred to M2): Steam integration, exports on Windows/macOS beyond CI, Act 1 content, factions, 6 classes, second biome.

## Progress
- S5 Bastion — done (PR #11).
- S6 Save/load — done (this PR).

## Running assumptions
- Placeholder art stays until S10; systems before it must not depend on sprite details.
- The yard (`proto_yard`) is the Bastion's grounds until a dedicated Bastion map exists (S10/S11 decide).
- Balance is not tuned in M1; every session may adjust numbers in `content/rules/` but no session is "the balance pass" (that is M4).
