# Roblox reference sizes for 3D objects

Measurements used and checked in the supermarket project (source: its modeling guide, "Blender → Roblox pipeline" section, 2026-10). They are a starting point for any store, room or prop set. 1 Blender unit = 1 stud, and a Roblox avatar is about 5 studs tall. Real-world scale: 1 m ≈ 2.9 studs; then scale small items up about 1.2× so they stay readable.

## Building

| Thing | Size (studs) |
|---|---|
| Wall height | 12 |
| Wall thickness | 1 |
| Wall module | 4 wide (rooms grow in 4-stud steps) |
| Door module | 12 wide × 12 tall × 1 thick, with a 6 wide × 8 tall opening |

## Fixtures

| Thing | Size (studs) |
|---|---|
| Shelf | 8 long × 2.5 deep × 7 tall |
| Checkout counter | 10 × 3 × 3.15 tall at the belt rim (conveyor belt 1.8 wide) |
| Computer desk | 6.2 × 2.5 × 3 tall; stool seat 2.0 high |
| Storage rack | 4 × 2.6 × 8.45 tall; 5 levels × 2 compartments, each 1.82 × 2.4 × 1.47 clear |
| Refrigerator | 8.4 × 3.2 × 10.2 tall; 5 levels × 2 compartments, each 3.6 × 1.85 usable |
| Chest freezer | 8.5 × 4.75 × 3.3 tall; 2 × 2 compartments, each 3.6 × 1.85 usable |
| Display case | 8 × 2.5 × 7 tall; 2 levels × 2 halves, each 3.6 × 1.85 usable, about 2.6 tall |
| Delivery boxes | XS 0.56 × 0.74 × 0.66 · S 0.86 × 0.74 × 1.0 · M 1.75 × 1.14 × 1.3 · L 1.75 × 2.3 × 1.35 · XL 2.6 × 2.6 × 1.8 |

## Products (hand-held items)

- Must fit the 1.8-wide conveyor belt: footprint at most 1.5 × 1.5, height at most 1.5.
- Display spot: 3.6 × 1.85 studs, one layer, no stacking. Cell = 3.6 / cols × 1.85 / rows; keep a gap of about 0.05 to 0.15 stud.
- Examples: milk carton about 0.5 × 0.5 × 0.9, cereal box 0.9 × 0.35 × 1.2, bread loaf 1.0 × 0.5 × 0.45, apple 0.35, egg carton 1.0 × 0.4 × 0.25.
- Single MeshPart, one 1024 texture, under about 400 triangles (most approved products were under 150).

## Model rules that carried over

- Pivot at bottom-centre, resting on Z = 0, front facing -Y in Blender (becomes Roblox -Z, the LookVector); transforms applied.
- Moving or scripted parts (drawer, screen, slots) stay separate, clearly named objects so they import as separate MeshParts.
- Every product is a closed solid with back, sides, top and bottom. Check from behind with backface culling.
- FBX export scale 0.01: at 1.0, the first shelf came in 100× too big (verified 2026-10-22).
- After the user imports in Studio: anchor, set collisions, set PrimaryPart and attachments, move into `ReplicatedStorage/Assets`.
