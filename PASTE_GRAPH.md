# Pasting the graph

Two clipboard blobs. Paste each into the widget's **Graph** tab, then make three
connections between them.

- `D:\SkinLiveUE\graph_blobA.txt` — 10 nodes: the F6 trigger and the three loops
- `D:\SkinLiveUE\graph_blobB.txt` — 13 nodes: the per-slot import-and-swap chain

## Before pasting

1. Open `D:\SkinLiveUE\SkinLive.uproject`, then open
   `WBP_SkinLivePreviewBootstrap01` from the Content Browser.
2. **Designer tab**: drag a **Canvas Panel** from the Palette onto the empty
   surface. The widget draws nothing, but it needs a root to be valid.
3. **Graph tab**: delete the `Event Construct` and `Event Tick` nodes that come
   for free. We do not use them.

## Pasting

Open each .txt, select all, copy. Click empty space in the graph, Ctrl+V.

Paste **A** first, then **B** somewhere below it. Each blob is self-contained —
every link inside it resolves — so one landing badly does not hurt the other.

## The three connections to draw by hand

All three come off **Create Dynamic Material Instance**, the last node of blob A:

| from | to |
|---|---|
| `then` (white exec) | `Get Texture Parameter Value` → `execute` |
| `Return Value` (the MID) | `Get Texture Parameter Value` → `Target` |
| `Return Value` (the MID) | `Set Texture Parameter Value` → `Target` |

Then **Compile** and **Save**.

## What the graph does

F6 → the actors attached to your pawn → every skeletal mesh on them → every
material slot → make a dynamic material instance → read what texture is in its
`BaseColor` → take that texture's name → build
`<game>/Marvel/Content/SkinStudioLive/<name>.png` → import it → if it imported,
set it back into `BaseColor`.

A texture you never edited has no PNG, `Import File as Texture 2D` returns null,
and the `Is Valid` branch skips it. That null **is** the protocol — nothing to
parse, nothing to keep in sync.

## If a paste misbehaves

These blobs were generated without being able to test a paste, so treat the
first attempt as the test. Tell me which of these it is:

- **nothing appears** — the whole blob was rejected; send me the first 3 lines of
  the file you pasted
- **nodes appear but wires are missing** — tell me which connections are absent
- **a node shows an error badge** after Compile — send me the exact message from
  the Compiler Results panel

Every function name in these blobs was verified against the engine headers in
`D:\UE_5.3\Engine\Source`, and both files pass a link check (every `LinkedTo`
points at a node and pin that exists). The likeliest failure is the two loop
macros, since their `GraphGuid` is left zeroed and they resolve by object path
instead — if the ForEachLoop or ForLoop nodes come in blank or broken, that is
the cause, and the fix is to delete those three and add them by hand from the
right-click menu (`For Each Loop`, `For Each Loop`, `For Loop`).

The full node-by-node build is in `GRAPH_RECIPE.md` if you would rather not
fight a bad paste.