# Approved furniture

Curated, game-ready props. Rojo syncs this folder to **`ServerStorage.FurnitureModels`**.

**One prop per file**, named for what it is:

```
assets/approved-imports/furniture/Wardrobe.rbxm  ->  ServerStorage.FurnitureModels.Wardrobe
```

Every file here must have a row in [`../../ASSET_MANIFEST.md`](../../ASSET_MANIFEST.md) recording its
source, licence, room, scale, collision policy and gameplay role. No row, no import.

Before saving a prop here, check it against the manifest:

- `Anchored = true` on every part (free models frequently ship unanchored)
- scale matches the §4 table against a 5-stud avatar
- collision policy from §5 applied
- hiding props satisfy the §6 shell contract — solid mesh, invisible trigger, 3×5×3 cavity
- no `Script` / `LocalScript` / `ModuleScript` anywhere in it
