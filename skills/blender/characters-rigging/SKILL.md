---
name: characters-rigging
description: Builds stylized characters and creatures for Roblox - blockout proportions, R15-compatible rigs and part naming, custom rigs with AnimationController, skinning weights, animation authoring in Blender and export as FBX, plus accessory and layered-clothing caveats. Use when making an NPC, pet, creature or avatar body, rigging a mesh, or getting a Blender animation into Roblox.
license: MIT
metadata:
  category: blender
  version: 1.0.0
  triggers: [rig, rigging, armature, skinning, character model, creature, r15, pet model, weight paint]
  depends: [blender-roblox-export, roblox-animation]
---

# Characters and rigging

## When to use

Characters, pets, creatures. For static props use `procedural-mesh-generation`; for playing animations in game use `roblox-animation`.

## Workflow

1. Proportions: stylized Roblox characters read best chunky: head 1/4 to 1/3 of height, thick limbs, big hands and feet. Block out with primitives at stud scale (an R15 avatar is about 5 studs tall).
2. Choose the rig:
   - **Avatar-compatible (R15)**: 15 parts named as Roblox expects (`Head`, `UpperTorso`, `LowerTorso`, `LeftUpperArm` ... `RightFoot`) with matching bones; use Roblox's Blender rig templates or the Avatar Setup tool in Studio. Verify current naming and attachment requirements in creator docs.
   - **Custom creature**: any bone hierarchy, one skinned mesh, driven by `AnimationController` + `Animator` in game.
3. Skin: Armature deform with automatic weights, then fix shoulders, hips and neck by hand; keep at most 4 influences per vertex.
4. Animate: actions per clip (`Idle`, `Walk`, `Attack`), 30 fps, root motion off unless the game script moves the root.
5. Export FBX: armature + mesh selected, `global_scale=0.01` with Apply Transform as in `blender-roblox-export`, `add_leaf_bones=False`, `bake_anim=True`, `use_armature_deform_only=True`.
6. Import in Studio with the 3D Importer (rig detected), then upload animations via the Animation Editor; animation assets must be owned by the experience owner (user or group) to play.

## Validation

- In Blender: pose each clip and check for candy-wrapper twists and floating parts; `blender-asset-qa`-style multi-angle renders.
- In Studio: play every clip on the imported rig; confirm scale (Size) and that the rig stands on the ground.

## Pitfalls

- Bones scaled ≠ 1 export as broken animations.
- Leaf bones add junk joints; keep them off.
- Animation plays in Studio but not live: asset owned by a different account than the experience.

## Limitations

The kit has no automatic rigging script; rigs are hand work guided by this checklist. Layered clothing and dynamic heads have extra cage and FACS requirements not covered here.
