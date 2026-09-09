# Controller and Steam Deck layout

Every input path in Neon Weave works on a gamepad. Keyboard and pad share
one action set (`src/core/input_actions.gd`); `tests/unit/test_input_actions.gd`
fails the build if an action ever loses its pad path (D-059).

## Layout (Steam Deck names; any XInput pad matches)

| Control | Exploration | Combat | Menus (system, Bastion, dialogue, creator) |
|---|---|---|---|
| Left stick / D-pad | Steer the leader | Move the cell cursor (one cell per tap, repeats when held) | Move the cursor / adjust a creator row |
| A | Interact: extract on the pad, bank at a relay, open an adjacent vault or locked gate, trade with a merchant, talk to a companion within two cells | Act on the cursor cell: move, attack, or aim the selected ability | Confirm |
| B | — | Clear the selected ability | Close / leave the conversation |
| X / Y / L1 / R1 | — | Abilities 1–4 | — |
| L2 / R2 | Zoom out / in | Zoom out / in | — |
| Start | Open the system menu | End turn | Close the system menu |
| Select | — | Swap to the next party member in the turn group | — |
| Right stick | unused (camera follows the leader) | unused | — |

The **system menu** (Start, or Esc on a keyboard while exploring) lists
every keyboard-only key as an item: Extract, Launch a Shard (N), Return
home (H), the Bastion (B), the Creator (C), the Weave (T), the Journal (J), Save / Load slots 1–3 (F5/F9 for slot 1),
Load autosave (F10), and the registry dump (F1). Items that would not
work right now say why. There is no pausing a fight: the menu refuses to
open in combat.

After a wipe, A returns to the yard (R) and B reloads the checkpoint (Esc).

## Combat cursor

The cursor appears at the acting member on the first stick or D-pad tap
and then steps one cell in the **screen** direction pressed (up on the
stick is up on screen, which is the (-1,-1) grid diagonal). WASD and the
arrow keys drive it too. It hovers exactly like the mouse: path preview
for a move, hit chance and damage for an attack, swap hint on an ally. A
confirms; any mouse movement hands control back to the mouse.

## Keyboard equivalents

Enter is Confirm, Esc is Cancel and the system menu, = and - zoom, Tab
swaps members, Space ends the turn, 1–4 pick abilities. Number keys still
pick dialogue and Bastion lines directly.

## Steam Deck

The layout above is the Deck layout; `steam/steam_input_template.vdf` is the Steam Input default configuration that mirrors it (upload it through Steamworks).
When GodotSteam lands (M2), the Steam Input default template will mirror
this table, add the back grips as duplicates of L1/R1 (abilities 3–4) and
Select (swap), and map the right trackpad to the mouse so the pointer path
stays available. Until then the Deck's built-in "Gamepad" template works
as-is.

## Remapping and glyphs

Bindings are code, not project settings, so mods cannot change them yet.
Settings (Start / Esc → Settings, or the title screen) rebinds any action to a new key or pad button; overrides live in `user://input.json` on top of the defaults, and Reset restores them. Pad glyphs follow the connected pad (Xbox or PlayStation names) unless you pick a style.
