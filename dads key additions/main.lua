local mod = RegisterMod('Dad\'s Key Additions', 1)
local json = require('json')
local sfx = SFXManager()
local game = Game()

mod.state = {}
mod.state.dadsKey = {
  lockedChests = true,
  bombChests = true,
  keyBlocks = true,
  strangeDoor = true, -- ascent / soul of cain already does this
  fleshDoor = true, -- corpse / soul of cain already does this
  fixMirror = false,
  bossRush = false,
  blueWomb = false, -- hush
  devilDoor = false,
}
mod.state.soulOfCain = {
  fixMirror = true,
  bossRush = true,
  blueWomb = true,
  devilDoor = true,
}

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if type(state.dadsKey) == 'table' then
        for _, v in ipairs({ 'lockedChests', 'bombChests', 'keyBlocks', 'strangeDoor', 'fleshDoor', 'fixMirror', 'bossRush', 'blueWomb', 'devilDoor' }) do
          if type(state.dadsKey[v]) == 'boolean' then
            mod.state.dadsKey[v] = state.dadsKey[v]
          end
        end
      end
      if type(state.soulOfCain) == 'table' then
        for _, v in ipairs({ 'fixMirror', 'bossRush', 'blueWomb', 'devilDoor' }) do
          if type(state.soulOfCain[v]) == 'boolean' then
            mod.state.soulOfCain[v] = state.soulOfCain[v]
          end
        end
      end
    end
  end
end

function mod:onGameExit()
  mod:save()
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

-- filtered to COLLECTIBLE_DADS_KEY (includes get out of jail free card)
function mod:onUseItem(collectible, rng, player, useFlags, activeSlot, varData)
  if useFlags & UseFlag.USE_CARBATTERY == UseFlag.USE_CARBATTERY then
    return
  end
  
  local room = game:GetRoom()
  player = player or game:GetPlayer(0)
  
  for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, -1, -1, false, false)) do
    if (
         (
           mod.state.dadsKey.lockedChests and
           (
             v.Variant == PickupVariant.PICKUP_ETERNALCHEST or
             v.Variant == PickupVariant.PICKUP_OLDCHEST or
             v.Variant == PickupVariant.PICKUP_MEGACHEST or
             v.Variant == PickupVariant.PICKUP_LOCKEDCHEST
           )
         ) or
         (
           mod.state.dadsKey.bombChests and
           v.Variant == PickupVariant.PICKUP_BOMBCHEST
         )
       ) and
       v.SubType >= ChestSubType.CHEST_CLOSED
    then
      v:ToPickup():TryOpenChest(player)
    end
  end
  
  if mod.state.dadsKey.keyBlocks then
    for i = 0, room:GetGridSize() - 1 do
      local gridEntity = room:GetGridEntity(i)
      if gridEntity and gridEntity:GetType() == GridEntityType.GRID_LOCK and gridEntity.State == 0 then -- 1 is unlocked
        local doFallback = true
        if REPENTOGON then
          local lock = gridEntity:ToLock()
          if lock and lock.TryUnlock then -- rgon+ check
            lock:TryUnlock(player, true) -- force so we don't consume a key
            doFallback = false
          end
        end
        if doFallback then
          local sprite = gridEntity:GetSprite()
          if sprite:GetAnimation() == 'IdleCoin' then
            sprite:Play('BreakingCoin', true)
          elseif player:HasGoldenKey() then
            sprite:Play('BreakingGolden', true)
          else
            sprite:Play('Breaking', true)
          end
          sfx:Play(SoundEffect.SOUND_METAL_BLOCKBREAK)
          gridEntity.State = 1
        end
      end
    end
  end
  
  mod:handleDoors(player,
                  mod.state.dadsKey.strangeDoor,
                  mod.state.dadsKey.fleshDoor,
                  mod.state.dadsKey.fixMirror,
                  mod.state.dadsKey.bossRush,
                  mod.state.dadsKey.blueWomb,
                  mod.state.dadsKey.devilDoor)
end

-- filtered to CARD_SOUL_CAIN
function mod:onUseCard(card, player, useFlags)
  if useFlags & UseFlag.USE_CARBATTERY == UseFlag.USE_CARBATTERY then
    return
  end
  
  player = player or game:GetPlayer(0)
  
  mod:handleDoors(player,
                  false,
                  false,
                  mod.state.soulOfCain.fixMirror,
                  mod.state.soulOfCain.bossRush,
                  mod.state.soulOfCain.blueWomb,
                  mod.state.soulOfCain.devilDoor)
end

function mod:handleDoors(player, strangeDoor, fleshDoor, fixMirror, bossRush, blueWomb, devilDoor)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    if door then
      if door:IsLocked() and door.TargetRoomIndex == GridRooms.ROOM_SECRET_EXIT_IDX then
        if strangeDoor and door:GetVariant() == DoorVariant.DOOR_LOCKED and door.TargetRoomType == RoomType.ROOM_SECRET_EXIT then
          door:TryUnlock(player, true)
        elseif fleshDoor and door:GetVariant() == DoorVariant.DOOR_LOCKED_CRACKED and door.TargetRoomType == RoomType.ROOM_BOSS then
          if door:TryUnlock(player, true) and REPENTANCE_PLUS then
            -- knife sets this, soul of cain doesn't for some reason
            game:SetStateFlag(GameStateFlag.STATE_MOTHER_HEART_DOOR_OPENED, true)
          end
        end
      elseif fixMirror and door.TargetRoomIndex == GridRooms.ROOM_MIRROR_IDX and
             (door:IsBusted() or not door:IsLocked()) -- IsBusted is transient, add fallback
      then
        door.Busted = false
        door.State = DoorState.STATE_CLOSED
        door:SetVariant(DoorVariant.DOOR_LOCKED)
        door:GetSprite():Play('Closed', true)
        level:SetStateFlag(LevelStateFlag.STATE_MIRROR_BROKEN, false)
        if sfx:IsPlaying(SoundEffect.SOUND_MIRROR_BREAK) then
          sfx:Stop(SoundEffect.SOUND_MIRROR_BREAK)
        end
      end
    end
  end
  
  if not game:IsGreedMode() and
     stage ~= LevelStage.STAGE4_3 and -- exclude hush
     stage < LevelStage.STAGE7 and -- exclude void/home
     room:GetType() == RoomType.ROOM_BOSS and
     room:IsCurrentRoomLastBoss() and -- 2nd boss on xl floors
     room:IsClear() and -- edge cases
     roomDesc.GridIndex >= 0 -- exclude mega satan in challenges
  then
    if bossRush and not mod:hasDoor(GridRooms.ROOM_BOSSRUSH_IDX) then
      -- ignore time, don't force so this only works after mom
      room:TrySpawnBossRushDoor(true, false)
    end
    if blueWomb and not mod:hasDoor(GridRooms.ROOM_BLUE_WOOM_IDX) then
      -- first time (animate), ignore time, don't force so this only works after mom's heart
      room:TrySpawnBlueWombDoor(true, true, false)
    end
    if devilDoor and not mod:hasDoor(GridRooms.ROOM_DEVIL_IDX) then
      -- animate, force so this works even if the devil percent is zero
      room:TrySpawnDevilRoomDoor(true, true)
    end
  end
end

function mod:hasDoor(roomIdx)
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    if door and door.TargetRoomIndex == roomIdx then
      return true
    end
  end
  
  return false
end

function mod:setupEid()
  EID:addDescriptionModifier(mod.Name .. ' - Key', function(descObj)
    return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE and descObj.ObjSubType == CollectibleType.COLLECTIBLE_DADS_KEY
  end, function(descObj)
    for _, v in ipairs({
                        { field = 'lockedChests', s = '#{{GoldenChest}} Opens locked chests' }, -- HolyChest, DirtyChest, MegaChest
                        { field = 'bombChests'  , s = '#{{StoneChest}} Opens bomb chests' },
                        { field = 'keyBlocks'   , s = '#{{Key}} Opens key blocks' },
                        { field = 'strangeDoor' , s = '#{{Collectible327}} Opens strange door' }, -- 328
                        { field = 'fleshDoor'   , s = '#{{Collectible626}} Opens flesh door' }, -- 627
                        { field = 'fixMirror'   , s = '#{{MirrorRoom}} Fixes mirror' },
                        { field = 'bossRush'    , s = '#{{MomBossSmall}} Opens boss rush' },
                        { field = 'blueWomb'    , s = '#{{MomsHeartSmall}} Opens the blue womb' }, -- HushSmall
                        { field = 'devilDoor'   , s = '#{{BossRoom}} Opens devil or angel room' }, -- DevilRoom, AngelRoom
                      })
    do
      if mod.state.dadsKey[v.field] then
        EID:appendToDescription(descObj, v.s)
      end
    end
    return descObj
  end)
  EID:addDescriptionModifier(mod.Name .. ' - Soul', function(descObj)
    return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_TAROTCARD and descObj.ObjSubType == Card.CARD_SOUL_CAIN
  end, function(descObj)
    for _, v in ipairs({
                        { field = 'fixMirror', s = '#{{MirrorRoom}} Fixes mirror' },
                        { field = 'bossRush' , s = '#{{MomBossSmall}} Opens boss rush' },
                        { field = 'blueWomb' , s = '#{{MomsHeartSmall}} Opens the blue womb' },
                        { field = 'devilDoor', s = '#{{BossRoom}} Opens devil or angel room' },
                      })
    do
      if mod.state.soulOfCain[v.field] then
        EID:appendToDescription(descObj, v.s)
      end
    end
    return descObj
  end)
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Key', 'Soul' }) do -- Dad, Cain
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
  ModConfigMenu.AddTitle(mod.Name, 'Key', 'Dad\'s Key')
  ModConfigMenu.AddTitle(mod.Name, 'Soul', 'Soul of Cain')
  for _, v in ipairs({
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'lockedChests', name = 'Locked chests', info = { 'Default: on', 'Golden, eternal, old, and mega chests' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'bombChests'  , name = 'Bomb chests'  , info = { 'Default: on' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'keyBlocks'   , name = 'Key blocks'   , info = { 'Default: on' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'strangeDoor' , name = 'Strange door' , info = { 'Default: on', 'Polaroid door to ascent' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'fleshDoor'   , name = 'Flesh door'   , info = { 'Default: on', 'Knife door to corpse' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'fixMirror'   , name = 'Fix mirror'   , info = { 'Default: off', 'Door to mirror dimension' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'bossRush'    , name = 'Boss rush'    , info = { 'Default: off', 'Door to boss rush after mom' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'blueWomb'    , name = 'Blue womb'    , info = { 'Default: off', 'Door to ??? after mom\'s heart' } },
                      { subcat = 'Key' , field1 = 'dadsKey'   , field2 = 'devilDoor'   , name = 'Devil door'   , info = { 'Default: off', 'Door to devil room after boss' } },
                      { subcat = 'Soul', field1 = 'soulOfCain', field2 = 'fixMirror'   , name = 'Fix mirror'   , info = { 'Default: on', 'Door to mirror dimension' } },
                      { subcat = 'Soul', field1 = 'soulOfCain', field2 = 'bossRush'    , name = 'Boss rush'    , info = { 'Default: on', 'Door to boss rush after mom' } },
                      { subcat = 'Soul', field1 = 'soulOfCain', field2 = 'blueWomb'    , name = 'Blue womb'    , info = { 'Default: on', 'Door to ??? after mom\'s heart' } },
                      { subcat = 'Soul', field1 = 'soulOfCain', field2 = 'devilDoor'   , name = 'Devil door'   , info = { 'Default: on', 'Door to devil room after boss' } },
                    })
  do
    ModConfigMenu.AddSetting(
      mod.Name,
      v.subcat,
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.field1][v.field2]
        end,
        Display = function()
          return v.name .. ' : ' .. (mod.state[v.field1][v.field2] and 'on' or 'off')
        end,
        OnChange = function(b)
          mod.state[v.field1][v.field2] = b
          mod:save()
        end,
        Info = v.info
      }
    )
  end
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_DADS_KEY)
mod:AddCallback(ModCallbacks.MC_USE_CARD, mod.onUseCard, Card.CARD_SOUL_CAIN)

if EID then
  mod:setupEid()
end
if ModConfigMenu then
  mod:setupModConfigMenu()
end