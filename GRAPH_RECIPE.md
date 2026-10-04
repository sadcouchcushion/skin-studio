# The live-refresh graph — node by node

Build this once, in `WBP_SkinLivePreviewBootstrap01` (already created at
`D:\SkinLiveUE\Content\Marvel\SkinLive\UI\Widgets\`). 22 nodes.

Open the project by double-clicking `D:\SkinLiveUE\SkinLive.uproject`, then
open the widget from the Content Browser. Two tabs matter: **Designer** and
**Graph** (top right).

## First, in Designer

Drag a **Canvas Panel** from the Palette onto the empty designer surface. That is
the only visual work — the widget draws nothing and is never shown. It just needs
a root so the asset is valid.

## Then, in Graph

Delete the two nodes that come for free (`Event Construct`, `Event Tick`) — we
do not use them.

Everything below is added by **right-clicking empty graph space and typing the
name**. Uncheck "Context Sensitive" if something does not appear.

### The trigger

1. **F6** — under Input → Key Events. Use its **Pressed** exec pin.

### Find the character's meshes

2. **Get Player Pawn** — leave Player Index at 0.
3. **Get Attached Actors** — Target = Get Player Pawn. In Rivals the visible
   character lives on an actor *attached* to the pawn, not on the pawn itself.
4. Drag off **Out Actors** → **Promote to Variable**. Name it `Targets`.
5. **Add** (Array Add) — Target = `Targets`, New Item = Get Player Pawn. Covers
   the case where the mesh is on the pawn after all. Cheap insurance.
6. **For Each Loop** — Array = `Targets`.

### Walk every skeletal mesh on each one

7. **Get Components by Class** — Target = Array Element, Component Class =
   `SkeletalMeshComponent`.
8. **For Each Loop** — Array = the returned components.
9. **Cast to SkeletalMeshComponent** — Object = Array Element. `Get Components
   by Class` hands back the base `ActorComponent` type, so this is required.

### Walk every material slot

10. **Get Num Materials** — Target = the cast result.
11. **Subtract** (int - int) — A = Get Num Materials, B = 1.
12. **For Loop** — First Index = 0, Last Index = that subtraction.
13. **Create Dynamic Material Instance** — Target = the cast mesh, Element Index
    = the loop Index. Returns the MID we are allowed to write to. Calling this
    twice on the same slot returns the same MID, so there is nothing to cache.

### Read the vanilla texture's name

14. **Get Texture Parameter Value** — Target = the MID, Parameter Name =
    `BaseColor`.
15. **Is Valid** (the macro with two exec pins) — on that texture. Not every
    slot has a BaseColor.
16. **Get Object Name** — Object = the texture. Gives `T_1025502_10250_Hair_D`.

### Build the file path

17. **Project Content Dir** — no inputs. Returns a relative path.
18. **Convert Relative Path to Full** — Path = that.
19. **Append** — this node has an **Add Pin** button; give it four inputs:
    - the full content dir
    - `SkinStudioLive/`
    - Get Object Name
    - `.png`

### Swap it

20. **Import File as Texture 2D** — Filename = the appended string. Returns null
    when the file does not exist, which is exactly our "this texture was not
    edited" test — no manifest needed.
21. **Is Valid** — on the imported texture.
22. **Set Texture Parameter Value** — Target = the MID, Parameter Name =
    `BaseColor`, Value = the imported texture.

Then **Compile** and **Save**.

## Wiring the exec line

    F6 (Pressed)
      → Get Attached Actors → Set Targets → Add
      → For Each Loop [Targets]
           Loop Body → Get Components by Class → For Each Loop [components]
                Loop Body → Cast → For Loop [0 .. NumMaterials-1]
                     Loop Body → Create Dynamic Material Instance
                                → Is Valid? (texture)
                                   Is Valid → Is Valid? (imported)
                                                Is Valid → Set Texture Parameter Value

Leave every **Completed** pin unconnected.

## Then test it before we pack anything

Press **Play** in the editor. Nothing will happen — there is no Rivals character
in this empty project — but the graph must compile with **zero errors**. That is
all we need from the editor.

## Later, once it works

`Normal` and `ORM` are the other two texture parameters on every character
material. Adding them is the same three nodes (14, 20, 22) twice more, or a
**For Each Loop** over a **Make Array** of the three names wrapped around 14-22.
Leave that until `BaseColor` is proven in game — colour maps are what you
actually edit.

---

# v2 edits — lobby preview, and making it cheap enough to afford

`BaseColor` **is** proven in game now (2026-09-21), so this is the next session.
Two edits, both in the same graph, **done together on purpose**: edit A is the
feature, edit B is what stops edit A being expensive. Do not ship A alone.

Steps 4 and 5 of the recipe above (`Targets` variable, `Array Add`) were never
built, and edit A removes the need for them entirely.

## ✗ RESULT 2026-09-22: edit A works, but the LOBBY IS NOT REACHABLE

Built, cooked, installed and tested. Verified from files: container mounted
(`pak_invalid` absent), no crash (count held at 22), `SkinLiveInit.sav` and
**`SkinLiveFired.sav` both written on the test run** — so the widget loads, runs,
and **F6 reaches it in the lobby**. The cooked class reports
`search = all-actors (lobby and match)`.

**And the lobby still does not repaint**, with Vampy Jammies (`1064300`, the
staged skin) on screen. The same build repaints fine in the practice range.

★ **So the trigger was never the problem and neither was the search's breadth —
the lobby hero is not an actor in the widget's world.** A lobby/gallery hero
display is a scene capture of a *separate* preview world, or skeletal mesh
components registered without an owning Actor. `GetAllActorsOfClass` is scoped to
the caller's world, and Blueprint has **no** node that crosses worlds or
enumerates ownerless components. There is no wider search to try. **Do not
re-attempt this from a UserWidget.**

★ Keep the practice range as the test bed, exactly as before.

**Is edit A worth keeping?** It costs more per press in a match than the old
pawn-scoped search (MIDs for every skeletal mesh walked) and bought nothing,
since the range already worked. Kept for now because reverting is more editor
work than the stutter is worth; revert to `Get Player Pawn` + `Get Attached
Actors` if a real match hitches.

## Edit A — search the whole level, not just the pawn

Today the chain starts `Get Player Pawn` → `Get Attached Actors`, so **F6 does
nothing wherever there is no pawn**: the lobby, hero select, the gallery. That is
where a colour actually gets judged.

1. Add **Get All Actors Of Class** (right-click, uncheck Context Sensitive if it
   hides). Set **Actor Class = `Actor`**.
2. Wire **F6 (Pressed) → Get All Actors Of Class**, then its exec out → the
   first **For Each Loop**. Unlike `Get Attached Actors` this node is *impure*
   and has exec pins, so it sits in the exec line rather than hanging off it.
3. Wire **Out Actors → the loop's `Array` pin**, replacing `Get Attached Actors`.
4. Delete **Get Player Pawn** and **Get Attached Actors**.

Both arrays are `Actor[]`, so the loop's wildcard is already resolved and does
not need re-deriving. ★ If it does complain *"the type of Target Array … is
undetermined"*, that is the pasted-macro wildcard trap: delete the For Each Loop,
add a fresh one from the right-click menu, and **connect `Array` first**.

## ✗✗ Edit B as written below is WRONG — do not build it (2026-09-22)

`GetTextureParameterValue` is **not** on `MaterialInterface`. Resolved from the
game's own reflection (`retoc print-script-objects global.utoc`, owner resolved
by `outer_index`): **`K2_GetTextureParameterValue` is owned by
`MaterialInstanceConstant` and `MaterialInstanceDynamic`, and nothing else.**
So `Get Material` → `Get Texture Parameter Value` will not even connect, and
`INGAME_MENU.md`'s function table listing it under `MaterialInterface` is wrong.

A cast to `MaterialInstanceConstant` looks like the patch, and is a trap: after
the first F6 the slot's material **is** the MID, and a MID is not a
`MaterialInstanceConstant` (both descend from `MaterialInstance`, which exposes
no getter), so the cast fails on every press after the first.

★ **And the bigger question that turned up while checking it:** after the first
press, `Get Texture Parameter Value` reads back the **imported** texture, not the
vanilla one. `ImportFileAsTexture2D` builds its texture with `CreateTransient`
and no name, so it is named like `Texture2D_0` — meaning press two looks for
`Texture2D_0.png`, finds nothing, and skips. **The preview may only work once per
game session.** Only one successful press was ever recorded, so this is untested
either way.

**Test that first, with edit A alone installed:** F6 in the practice range,
then change a colour, save, and F6 again. If press two updates, this is void and
edit B is only about cost. If it does not, the real fix is to stop reading the
name off the live material — read it from the instance's parent, or re-key the
drop folder on material **slot names** (`GetMaterialSlotNames` is available)
instead of texture names — and the cost question rides along with it.

## ★ Edit B — create the MID only after a successful import (SUPERSEDED, see above)

The reason A needs B: node 13 calls **Create Dynamic Material Instance** on
*every slot of every skeletal mesh it finds*, before it has any idea whether that
texture was edited. Pawn-scoped that is a handful of MIDs. Level-scoped, in a
real match, it is every skeletal mesh in the level — which is a hitch, and it
also converts materials we have no business touching.

`GetTextureParameterValue` is on **`MaterialInterface`**, not on the dynamic
instance, so the vanilla texture can be read from the *static* material and the
MID deferred until there is something to write:

1. Add **Get Material** — Target = the cast `SkeletalMeshComponent`, Element
   Index = the **For Loop** `Index`. (Same two inputs node 13 had.)
2. Repoint **Get Texture Parameter Value** (node 14) — Target = **Get Material**
   instead of the MID. Parameter Name stays `BaseColor`.
3. **Move Create Dynamic Material Instance** down: unhook it from the For Loop
   body and put it *inside the second `Is Valid`* — the one testing the imported
   texture — so the exec line becomes
   `Is Valid (imported) → Create Dynamic Material Instance → Set Texture Parameter Value`.
   Target and Element Index are unchanged (the cast mesh, the loop Index).
4. **Set Texture Parameter Value** (node 22) — Target = that MID. Unchanged
   otherwise.

New exec line for the inner loop body:

    For Loop [0 .. NumMaterials-1]
      Loop Body → Is Valid? (Get Texture Parameter Value on Get Material)
                    Is Valid → Is Valid? (Import File as Texture 2D)
                                 Is Valid → Create Dynamic Material Instance
                                          → Set Texture Parameter Value

Cost is now proportional to **edited textures**, not to meshes in the level: a
slot with no matching PNG costs one parameter read and one failed file open, and
mints nothing.

## Before you build it

★ **Compile, then Save, then cook** — a Widget Blueprint saved without compiling
cooks to an empty class, silently, with a clean log.

★ Then let the build script check the cooked name table rather than trusting the
compile: unreachable nodes are pruned with no error, so a wire you forgot looks
exactly like success. **Never pass `-NoGraphCheck`.**

    C:\rs\SkinStudio\ingame\build_live_mod.ps1 -Install

★ After edit A the graph check should be taught the new node — `GetAllActorsOfClass`
in the cooked name table is the proof edit A survived, and `GetMaterial` the proof
edit B did.

## Not doing: a timer that auto-refreshes

`Event Tick` is unavailable for good (the widget is never arranged — see
`INGAME_MENU.md`), and a `Set Timer` from `Event On Initialized` *would* fire.
It is still the wrong thing to build:

**`ImportFileAsTexture2D` creates a brand-new transient `Texture2D` on every
call.** On a keypress that is fine. On a timer it is a new texture object every
few seconds for the whole session, for every matching slot — an unbounded leak —
and Blueprint has no way to ask whether the PNG changed first (there is no
file-timestamp node, and texture pixels cannot be read back to compare).

So the keypress is not a missing feature, it **is** the change signal. If
hands-free is ever wanted, the honest version is a second key that toggles a
timer on and off, so the churn only happens while it is wanted — not an
always-on refresh.