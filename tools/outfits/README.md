# Outfits pipeline

Every outfit is its own rigged, textured 3D model (real clothing geometry),
listed in `scripts/player/outfits.gd` and stored under
`assets/characters/<character>/outfits/<id>/`.

1. **Reference renders.** `tests/render_reference.gd` renders the in-game model
   in its A-pose, front and back, on a plain backdrop.
2. **Concept art.** `make_concepts.py` edits those renders into each outfit in
   `outfits.json` (Nano Banana on fal; Seedream for swimwear and corsets,
   which Nano Banana refuses). Needs `FAL_KEY`.
3. **3D model.** Meshy image-to-3D with `rig` on (front + back views), at the
   character's height (Zegan 1.83 m, Obcera 1.72 m, 1.78 m in heels). If
   Meshy's filter refuses a picture, try the front view alone; if it still
   refuses, make the mesh with Hunyuan3D v3 and rig it with
   `skin_from_base.py`, which fits it onto the base model and copies the base
   skin weights, so it uses the base skeleton exactly.
4. **Shrink.** `repack_glb.py in.glb assets/.../<id>/<id>.glb` keeps the base
   colour at 2048 px and takes the normal and metallic-roughness maps to 1024.
5. **Skin tone.** `match_skin.py assets/characters/<c>/<c>_Image_0.jpg <id>.glb`
   moves the outfit's (much paler) skin onto the base model's skin colour.
6. **Import.** `godot --headless --import`, `python3 tools/fix_imports.py`,
   import again, then `godot --headless --script tools/outfits/import_outfits.gd`
   retargets the base clips onto the outfit's bone rest and writes
   `<id>_anims.res`. Import once more.
7. **Same face (Obcera).** Every Obcera outfit wears one shared head, the
   Red Dress model's, so her face is the same in every outfit. For a new
   Obcera outfit, add it to `TARGETS` in `shared_head.py` and run it on the
   fresh model: it removes the outfit's own head (the triangles skinned
   mostly to the head bones, keeping a dark collar round the back of the
   neck) and tucks its neck under the shared head. `CharacterModel` binds
   `assets/characters/obcera/head/obcera_head.glb` to the outfit's skeleton
   by bone name. To rebuild the shared head itself, restore the Obcera
   models from git (before the commit that added it) and run the script
   once on all of them.
8. **Check.** `tests/render_outfits.gd` renders every outfit front, back and
   aiming; `tests/render_customize.gd` shows the outfit screen;
   `tests/render_head.gd` shows the head and neck close up from five sides;
   `tests/feet_check.gd` checks the soles sit on the floor;
   `tests/chest_check.gd` measures the bust at the top of the Chest slider.
   A new Obcera outfit needs a `"chest_max"` in `scripts/player/outfits.gd`:
   the inflate the check prints under "needs", so max Chest is the same size
   on every outfit.
