# WoW Patch 12.1.5c

- Fix: items were sold to the vendor (or attached to mail, put in trade, deposited in the bank) when an upgrade was equipped with one of those windows open. Upgrades are now equipped with EquipItemByName and the addon pauses while a vendor, mail, trade, auction house, bank or similar window is visible
- Skip items that require a higher level than the character, so they are not retried on every scan
- New /autoequip command: shows whether the addon is active or paused (and why) and scans the bags
- Login message
