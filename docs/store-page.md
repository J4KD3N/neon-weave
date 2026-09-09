# Store page checklist

What Steamworks needs for the demo page, where each piece comes from, and
what this repo can already supply. Nothing on this list ships in a build.

## Assets

| Asset | Size | Source | Status |
|---|---|---|---|
| Header capsule | 920×430 | Artist | missing (no artist attached, see D-075) |
| Small capsule | 462×174 | Artist | missing |
| Main capsule | 1232×706 | Artist | missing |
| Vertical capsule | 748×896 | Artist | missing |
| Library capsule / hero / logo | 600×900 / 3840×1240 / 1280×720 | Artist | missing |
| Screenshots (min. 5) | 1920×1080 | `screenshot` CI job: `screenshot-title.png`, `screenshot.png` (plaza), `screenshot-combat.png`, `screenshot-shard.png`, `screenshot-datacore.png`, `screenshot-road.png`, `screenshot-dialogue.png`, `screenshot-creator.png` | available every run; placeholder art |
| Trailer | 1920×1080, 30–90 s | Capture a run: title → yard → gate road fight → Shard → relay → throat | not made |
| Store description | text | `docs/store-page.md` below | draft below |

Download the current screenshots with `gh run download <run-id> -n screenshot`.

## Short description (draft)

Neon Weave is an open-source, party-based, isometric CRPG in an arcane-cyberpunk ruin. Lead a party of Weavers, scavenger-mages, into procedurally generated Shards, bank what you bring back, and follow a handcrafted story to the thing that woke the Shards. Turn-based combat with four action points and free movement, six classes with resource loops, three companions who disagree with each other, and a Bastion that grows with your books.

## Long description (draft)

Centuries after a hyper-advanced civilisation tore open the Weft to drown its own machine mind, magic and technology have fused and the fusion has never stopped deepening. You run the Beacon: the only link to the Shards, the stirring ruins where the loot and the answers are.

- **Delve.** Procedural Shards with secrets, Cipher vaults, relay waypoints and merchants. Extract to bank your haul; wipe and lose it, never the story.
- **Fight.** Turn-based, four action points plus free movement, cover, high ground, mana pools that amplify, conduits that arc, spores that shroud. Every hit chance shown before you commit.
- **Build.** Six classes, each with a resource loop (Surge, Heat, Hexes, Scrap, Null), subclasses at level three, talents bought with Aether.
- **Choose.** Story-Protected or Mortal at new game. Three companions with personal quests that cut across the main plot, and a faction that notices what you do.
- **Read it, change it.** The whole demo is data: JSON you can open, and a mod folder the game scans on start.

The demo is Act 1's opening: the gate road, Relay Station Nine, the Undercity throat, and the first thing that says your name.

## Tags

RPG, CRPG, Turn-Based Tactics, Party-Based RPG, Isometric, Cyberpunk, Procedural Generation, Story Rich, Open Source, Controller

## System requirements (placeholder, verified on the CI runner only)

- OS: Windows 10 64-bit / Linux 64-bit / macOS 12
- GPU: OpenGL 3.3 or Vulkan 1.0
- RAM: 2 GB
- Storage: 200 MB

## Still needed from people

An artist for every capsule; a trailer capture; a Steamworks app id (see `steam/README.md`); the art decision (D-075).
