# WoW Patch 12.1.5b

- Fix Lua error "attempt to call a nil value" in 12.1.5: use C_Item.GetItemInfoInstant (the global GetItemInfoInstant was removed)
- Bag scan no longer freezes the game on login: it waits a few seconds after logging in, groups bag updates, and spreads the scan over several frames
