# Browser version: frame rate on phones

The browser version (`/play/` on the download worker) draws with Godot's
Compatibility renderer (WebGL 2). On a Galaxy Z Fold 8 the first browser
builds (0.12, 0.13) ran at a few frames a second; the survivor could barely
move. The app (Mobile renderer, Vulkan) was fine. This is why, and what the
browser version does about it. Everything here is browser-only: it is gated on
`OS.has_feature("web")` and the app keeps its own settings.

## Why the browser was slow

Measured with `tests/perf_probe.gd` (Compatibility renderer under llvmpipe;
the counts don't depend on the machine):

Draw calls per frame at the probe's spots in chapter 1 (the survivor's own
view, torch on):

| spot | as shipped in 0.13 | browser profile, start (2 lamp shadows) | most (4 lamp shadows) | fewest (no lamp shadows) |
|---|---|---|---|---|
| Ashgrove Street, start | 3,481 | 1,430 | 1,803 | 899 |
| Ashgrove Street, west | 17,012 | 2,566 | 2,894 | 2,233 |
| courtyard | 13,558 | 2,973 | 2,989 | 2,081 |
| Great Hall | 7,730 | 2,331 | 3,753 | 1,895 |
| reading room | 21,523 | 2,722 | 2,969 | 2,048 |
| safe room | 1,739 | 686 | 1,207 | 333 |
| Records Vault | 6,744 | 3,119 | 3,446 | 1,407 |

and the 3D picture has about a third of the pixels to start with (1.36
million instead of 4 on the Fold's inner screen). The game's own scripts,
physics and animation (infected awake and chasing) take 2 to 3 ms a frame
(native, headless), so the drawing was the problem, not the game logic.

- **Every shadowed lamp or window draws the scene again.** The Compatibility
  renderer lights shadowed omni/spot lights in extra passes: each object a
  shadowed light touches is drawn once more, with the full surface shader.
  Every moonlit window is a shadowed spot light, and omni shadows are cube
  maps (6 renders each time something in range moves, which the infected
  always do). 20 lights in chapter 1 had shadows.
- **The moon's shadow is redrawn every frame, once per split** (4 splits,
  ~800 objects a frame).
- **Desktop shadow settings.** The `.mobile` overrides (2048 px atlases,
  hard-edged filtering) only apply to the app; the browser got 4096 px atlases
  and soft filtering.
- **Too many separate meshes.** Rooms are built from thousands of small
  pieces (trim, frames, mullions, papers, props; 1,300 books in the reading
  room), each one a WebGL draw call. In a phone browser the draw calls alone
  take most of the frame.
- **Full resolution.** The 3D picture rendered at the canvas's full size,
  about 2176 x 1812 (4 million pixels) on the Fold's inner screen.
- The screen grade (`shaders/post_fx.gdshader`) asked for mipmaps of the
  screen, which built a mip chain of the whole screen every frame. It never
  sampled them (fixed for the app too; the picture is identical).

## What the browser version does (scripts/world/web_quality.gd)

`LevelBase._ready()` calls `WebQuality.apply_level(self)` once the level is
built. On the web it:

1. **Batches the static pieces** (`scripts/world/static_batch.gd`): a prop
   placed many times (books, crates, chairs) becomes one `MultiMesh` per few
   metres, keeping the mesh's distance detail levels; one-off pieces with no
   detail levels (the boxes, frames, trim, papers the rooms are built from)
   are merged into one mesh per material; materials made in code with the same
   settings are drawn as one. The originals stay in the tree (collisions,
   children and code that looks them up still work); only their render layers
   go to 0. Chapter 1: 2,650 pieces become ~680 batches in ~0.4 s at load.
   Never batched: anything under a scripted node or a node in a group, the
   glass and lamp fixtures a `Breakable` changes, skinned/animated meshes,
   see-through materials, shaders other than `surface.gdshader`, mirrored
   transforms, pieces over 4 m. A chunk is split smaller when more lights
   would touch it than any of its pieces had, and never past 8 of a kind: the
   renderer lights each object with at most 8 omni + 8 spot lights, and past
   8 it keeps the ones it paired first, not the nearest. Lights that are off
   for now (the tunnel lights before the generator runs) count too. A piece
   already touched by more than 8 is left as it was.
   `tests/web_batch_shots.gd` renders 10 views of chapter 1 and 6 of chapter
   2 before and after, plus a second unbatched pass to show how far two renders
   drift on their own: chapter 1 indoors is identical (mean difference under 1
   of 255), outdoors only the rain streaks running down the walls differ (they
   move with time). In chapter 2 one view differs: before batching, the safe
   room's desk lamp leaked a glow into the service corridor through a hairline
   crack in its shadow round the closed lodge door, and the batched walls
   close the crack (with the door open, both light the corridor the same).
2. **Shadow settings as on the phone app**: 2048 px atlases, hard filtering.
3. **The moon's shadow in two splits** instead of four.
4. **A shadow budget**: only the few lamps and windows that matter most for
   what you see keep their shadows; the others fade theirs out over 0.4 s
   (the light itself stays on) and fade back in when they matter again.
   "Matter most" is how much of a light would leak, without its shadow,
   onto what you see from behind something: every 0.25 s, 24 rays through
   the screen and 8 round the camera find the walls, floors and shelves in
   view, two more points sit on each survivor on screen, and a ray from each
   point to each light asks whether something is in between. A lamp in the
   next room leaking through the wall, the vault lamp shining through the
   shelves onto the boxes under them, or a lamp lighting her hair while she
   stands behind a pillar from it all count fully; light that reaches a
   point in the open counts a little (for the small things the rays pass
   between). A light that lights nothing you see gets no shadow even with
   places free. The pick weighs 4 lights a frame (under 1 ms), and a light
   only takes a place from one that matters 15 % less, so shadows don't
   flick. With 2 shadows the views above look like the 4-shadow ones (the
   probe's `shots=` saves both); choosing by distance instead lost the vault
   lamp's shelf shadows to the Great Hall's windows. The survivors' torches
   and the moon always keep theirs. Lights that appear later (fires, the
   elevator car, story lights) join the budget as they enter the level.
   Each shadowed light is expensive in the browser: every object it touches
   is drawn again, and an omni light's shadow is six renders (a cube), redone
   whenever anything in reach moves. One more lamp shadow costs 100 to 1,400
   draw calls depending on the room.
5. **Adapting to the phone**: the 3D picture starts at about 1280 x 1066
   pixels and is scaled up to the screen (the HUD and menus stay sharp), with
   2 lamp shadows. Every 1.5 s: when frames take over 36 ms one thing steps
   down (sharpness while it's above 75 %, then lamp shadows, then sharpness
   down to 50 %); a step that didn't make frames faster is undone and that
   knob is left alone for a while (the phone was busy with something else).
   When frames stay under 20 ms the last thing given up comes back, up to 4
   lamp shadows and full sharpness. A knob that makes frames slow again each
   time it's raised waits longer before the next try, so the picture doesn't
   keep flicking. `tests/web_quality_adapt_test.gd` runs this on made-up
   phones (GPU-bound, draw-call-bound, fast, tipping, hopeless).

## Measuring

    xvfb-run -a -s "-screen 0 1100x920x24" godot --path . \
      --rendering-method gl_compatibility --rendering-driver opengl3 \
      --resolution 544x453 --script tests/perf_probe.gd -- web,spots=street_start

`web` applies the browser profile; without it you get the app's settings on
the browser's renderer. `shots=<dir>` saves each view as a PNG, `lightlist`
prints the budget's lights near each spot with their importance. `variants=base+noshadow+nosun+...` measures what each
part costs. Under `--headless` it measures only the CPU side (scripts,
animation, physics).
