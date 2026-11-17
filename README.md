# whip_persist

Street cars a player has driven stay where they were left, and come back if they are removed from the world, for the
rest of the server session. whip_core's take on xrp_misc's persistent vehicles.

## What whip_core already does

| | whip_core |
|---|---|
| Owned cars left out | Never removed by the game (KeepEntity), position saved, **rebuilt after a restart** |
| Street cars someone got into | Kept while a player is within 300 m; after 10 minutes with nobody near, handed back to GTA, which may clean them up |

So owned cars need nothing. This resource covers the street cars.

## What this adds

- **Tracked** from whip's own events: a street car someone gets into (`whip_core:vehicle:registered` / `entered`).
  Owned and temporary cars (rentals, job vans) are left to whip.
- **Kept**: when whip hands one back to GTA for being idle (`whip_core:vehicle:released`, reason `idle`), it is set to
  KeepEntity again.
- **Brought back** when it is removed anyway (`entityRemoved`): built again where it stood, with its model, plate, lock
  and its look (mods, colours, wheels). The look is reported by the driver's game when they get in, every minute
  while they drive, and when they get out.
- **Forgotten** when it goes on purpose:
  - whip put it away or deleted it (`/dv`, `DespawnVehicle`, `DeleteVehicle`);
  - it was removed with a player standing within `Config.DeliberateRange` (8 m): someone removed it;
  - it became someone's own car (claimed);
  - nobody drove it for `Config.ForgetAfterMinutes` (180), or more than `Config.Max` (150) are kept (the one driven
    longest ago goes);
  - another resource called `Forget` (below).

Memory only: a restart starts fresh, as with xrp_misc.

## Setup

`ensure whip_persist` after whip_core. Remove xrp_misc's `persistentVehicles.lua` (both halves) if xrp_misc stays, or
the two will fight over the same cars.

## For other resources

A script that deletes a street car itself (`DeleteEntity`) from far away should say so first, or the car comes back:

```lua
exports.whip_persist:Forget(entityOrNetId)          -- stop keeping it
exports.whip_persist:Forget(entityOrNetId, true)    -- stop keeping it and delete it
exports.whip_persist:Keep(entityOrNetId)            -- keep a car you spawned (not owned, not a whip temp car)
exports.whip_persist:IsKept(entityOrNetId)
exports.whip_persist:Count()
```

## Worth adding to whip_core upstream

None of this is needed for whip_persist to work; each would make it simpler or cleaner.

1. **The idle release as a setting.** `SESSION_IDLE_MS` (10 min) and `SESSION_NEAR` (300 m) in
   `server/vehicles.lua` are constants. As `Config.Vehicles.SessionIdleMinutes` (0 = never) and
   `Config.Vehicles.SessionNear`, a server could keep street cars without a resource re-pinning them.
2. **A hook before the idle release.** e.g. `exports.whip_core:OnSessionIdle(fn)` where `fn(vehicleId)` returning
   false keeps the car tracked by whip (its trunk and glovebox stay too, which whip_persist cannot keep: they are whip's
   memory-only storage and go with the release).
3. **An `entityRemoved` safety net for owned cars.** whip_core has none on purpose (cost; KeepEntity cars shouldn't be
   removed). A light one, keyed on `Vehicles._byEntity` only, would rebuild an owned car another script or a crash
   removed, instead of it reading "not spawned" until the next restart or garage retrieve:

   ```lua
   AddEventHandler('entityRemoved', function(entity)
       local vehicleId = Vehicles._byEntity[entity]
       if not vehicleId then return end
       local def = Vehicles._records[vehicleId]
       if not def or def.session or def.state ~= 'out' then return end
       local c, h = GetEntityCoords(entity), GetEntityHeading(entity)
       SetTimeout(1000, function()
           if not Vehicles.getEntity(vehicleId) then Vehicles.spawn(vehicleId, c.x, c.y, c.z, h) end
       end)
   end)
   ```

4. **`/dv` and street cars whip has let go of.** `/dv` deletes an unknown car with `DeleteEntity`. whip_persist
   treats a removal next to a player as on purpose, so this already works; calling `exports.whip_persist:Forget`
   there (when the resource is running) would make it exact.
