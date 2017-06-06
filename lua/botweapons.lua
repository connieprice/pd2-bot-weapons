if not _G.BotWeapons then

  _G.BotWeapons = {}
  BotWeapons._path = ModPath
  BotWeapons._data_path = SavePath
  BotWeapons._data = {}

  function BotWeapons:log(message, condition)
    if condition or condition == nil then
      log("[BotWeapons] " .. message)
    end
  end
  
  function BotWeapons:init()
    self._revision = 0
    local file = io.open(BotWeapons._path .. "mod.txt", "r")
    if file then
      local data = json.decode(file:read("*all"))
      file:close()
      self._revision = data and data.updates and data.updates[1] and data.updates[1].revision or 0
    end
    self:log("Revision " .. self._revision)
  
    self.armor = {
      { menu_name = "bm_armor_level_1" },
      { menu_name = "bm_armor_level_2" },
      { menu_name = "bm_armor_level_3" },
      { menu_name = "bm_armor_level_4" },
      { menu_name = "bm_armor_level_5" },
      { menu_name = "bm_armor_level_6" },
      { menu_name = "bm_armor_level_7" }
    }
  
    self.equipment = {
      { menu_name = "item_none" },
      { menu_name = "bm_equipment_ammo_bag", name = "ammo_bag" },
      { menu_name = "bm_equipment_armor_kit", name = "armor_kit" },
      { menu_name = "bm_equipment_bodybags_bag", name = "bodybags_bag" },
      { menu_name = "bm_equipment_doctor_bag", name = "doctor_bag" },
      { menu_name = "bm_equipment_ecm_jammer", name = "ecm_jammer" },
      { menu_name = "bm_equipment_first_aid_kit", name = "first_aid_kit" },
      { menu_name = "bm_equipment_sentry_gun", name = "sentry_gun" }
    }
  
    -- load weapon definitions
    file = io.open(BotWeapons._path .. "weapons.json", "r")
    if file then
      self.weapons_legacy = json.decode(file:read("*all"))
      file:close()
    end
    self.weapons_legacy = self.weapons_legacy or {}
    
    -- load user overrides
    file = io.open(BotWeapons._data_path .. "bot_weapons_overrides.json", "r")
    if file then
      self:log("Found custom weapon override file, loading it")
      local overrides = json.decode(file:read("*all"))
      file:close()
      if overrides then
        for _, weapon in ipairs(self.weapons_legacy) do
          if weapon.tweak_data and weapon.tweak_data.name and overrides[weapon.tweak_data.name] then
            weapon.blueprint = overrides[weapon.tweak_data.name].blueprint or weapon.blueprint
          end
        end
      end
    end
    
    -- load mask sets
    file = io.open(BotWeapons._path .. "masks.json", "r")
    if file then
      self.masks = json.decode(file:read("*all"))
      file:close()
    end
    self.masks = self.masks or {}
    
    self.masks_legacy = {
      { menu_name = "bm_msk_character_locked" },
      { menu_name = "item_same_as_me" },
    }
    for k, v in pairs(self.masks) do
      local msk = deep_clone(v)
      msk.menu_name = "item_" .. k
      table.insert(self.masks_legacy, msk)
    end
    
    -- load settings
    self:load()
  end
  
  function BotWeapons:get_menu_list(tbl, add)
    if not tbl then
      return {}
    end
    local menu_list = {}
    local names = {}
    local item_name
    local localized_name
    for _, v in ipairs(tbl) do
      item_name = v.menu_name:gsub("^bm_w_", "item_")
      localized_name = managers.localization:text(v.menu_name):upper()     
      if v.menu_name:match("^bm_w_.+") then
        localized_name = localized_name:gsub(" PISTOLS?$", ""):gsub(" REVOLVERS?$", ""):gsub(" RIFLES?$", ""):gsub(" SHOTGUNS?$", ""):gsub(" GUNS?$", ""):gsub(" LIGHT MACHINE$", ""):gsub(" SUBMACHINE$", ""):gsub(" ASSAULT$", ""):gsub(" SNIPER$", "")
      end
      table.insert(menu_list, item_name)
      names[item_name] = localized_name
    end
    if add then
      for _, v in ipairs(add) do
        table.insert(menu_list, v)
      end
    end
    managers.localization:add_localized_strings(names)
    return menu_list
  end
  
  function BotWeapons:set_single_fire_mode(weapon, rec)
    if not weapon or not rec then
      return
    end
    for _, v in ipairs(weapon.FALLOFF) do
      v.recoil = rec
    end
  end
  
  function BotWeapons:set_auto_fire_mode(weapon, mode)
    if not weapon or not mode then
      return
    end
    for _, v in ipairs(weapon.FALLOFF) do
      v.mode = mode
    end
  end
  
  function BotWeapons:create_interpolated_falloff_data(presets, steps)
    if not presets or not steps then
      return
    end
    self:log("Interpolating FALLOFF in " .. steps .. " steps for gang presets")
    for _, weapon in pairs(presets) do
      if not weapon._interpolation_done then
        local first = weapon.FALLOFF[1]
        local last = weapon.FALLOFF[#weapon.FALLOFF]
        local data = {}
        local falloff, blend
        for i = 1, steps + 1 do
          falloff = deep_clone(last)
          table.insert(data, 1, falloff)
          blend = (i - 1) / steps
          falloff.r = math.lerp(last.r, first.r, blend)
          falloff.acc = { 
            math.lerp(last.acc[1], first.acc[1], blend),
            math.lerp(last.acc[2], first.acc[2], blend)
          }
          falloff.recoil = {
            math.lerp(last.recoil[1], first.recoil[1], blend),
            math.lerp(last.recoil[2], first.recoil[2], blend)
          }
        end
        weapon.FALLOFF = data
        weapon._interpolation_done = true
      end
    end
  end
  
  function BotWeapons:set_equipment(unit, equipment)
    if not alive(unit) then
      return
    end
    for k, v in pairs(tweak_data.equipments) do
      if v.visual_object then
        local mesh_obj = unit:get_object(Idstring(v.visual_object))
        if mesh_obj then
          mesh_obj:set_visibility(k == equipment)
        end
      end
    end
    if Utils:IsInGameState() and not Global.game_settings.single_player and LuaNetworking:IsHost() then
      local name = unit:base()._tweak_table
      DelayedCalls:Add("bot_weapons_sync_equipment_" .. name, 1, function ()
        LuaNetworking:SendToPeers("bot_weapons_equipment", name .. "," .. tostring(equipment))
      end)
    end
  end
   
  function BotWeapons:get_masks_data()
    if not self._masks_data then
      self._masks_data = {}
      self._masks_data.masks = {}
      for k, v in pairs(tweak_data.blackmarket.masks) do
        if not v.inaccessible then
          table.insert(self._masks_data.masks, k)
        end
      end
      self._masks_data.colors = {}
      for k, _ in pairs(tweak_data.blackmarket.colors) do
        table.insert(self._masks_data.colors, k)
      end
      self._masks_data.patterns = {}
      for k, _ in pairs(tweak_data.blackmarket.textures) do
        table.insert(self._masks_data.patterns, k)
      end
      self._masks_data.materials = {}
      for k, _ in pairs(tweak_data.blackmarket.materials) do
        table.insert(self._masks_data.materials, k)
      end
    end
    return self._masks_data
  end

  function BotWeapons:get_npc_version(weapon_id)
    local factory_id = weapon_id and managers.weapon_factory:get_factory_id_by_weapon_id(weapon_id)
    local tweak = factory_id and tweak_data.weapon.factory[factory_id .. "_npc"]
    return tweak and (not tweak.custom or DB:has(Idstring("unit"), tweak.unit:id())) and factory_id .. "_npc"
  end
  
  function BotWeapons:get_random_weapon(category)
    local cat = type(category) ~= "string" and "all" or category
    if not self.weapons or not self.weapons[cat] then
      self.weapons = self.weapons or {}
      self.weapons[cat] = {}
      for weapon_id, data in pairs(tweak_data.weapon) do
        if data.autohit then
          local factory_id = self:get_npc_version(weapon_id)
          if factory_id and (type(category) ~= "string" or data.categories[1] == category) and managers.blackmarket:is_weapon_category_allowed_for_crew(data.categories[1]) then
            local data = {
              category = data.use_data.selection_index == 2 and "primaries" or "secondaries",
              factory_id = factory_id
            }
            table.insert(self.weapons[cat], data)
          end
        end
      end
    end
    local weapon = self.weapons[cat][math.random(#self.weapons[cat])]
    if not weapon then
      return {}
    end
    weapon.blueprint = {}
    local has_part_of_type = {}
    local parts = deep_clone(tweak_data.weapon.factory[weapon.factory_id].uses_parts)
    local adds = tweak_data.weapon.factory[weapon.factory_id].adds or {}
    local must_use = {}
    for _, part_name in ipairs(tweak_data.weapon.factory[weapon.factory_id].default_blueprint) do
      local part_type = tweak_data.weapon.factory.parts[part_name].type
      must_use[part_type] = true
    end   
    while #parts > 0 do
      local index = math.random(#parts)
      local part_name = parts[index]
      local part = tweak_data.weapon.factory.parts[part_name]
      local is_forbidden = part.unatainable or table.contains(adds, part_name) or managers.weapon_factory:_get_forbidden_parts(weapon.factory_id, weapon.blueprint)[part_name]
      if not has_part_of_type[part.type] and not is_forbidden then
        if (must_use[part.type] or math.random() < 0.5) then
          table.insert(weapon.blueprint, part_name)
          for i, v in ipairs(adds[part_name] or {}) do
            table.insert(weapon.blueprint, v)
            local add_type = tweak_data.weapon.factory.parts[v].type
            has_part_of_type[add_type] = v
          end
        end
        has_part_of_type[part.type] = part_name
      end
      table.remove(parts, index)
    end
    return weapon
  end
  
  function BotWeapons:get_loadout(char_name, original_loadout, refresh)
    if not char_name then
      return original_loadout
    end
    if not refresh and self._loadouts and self._loadouts[char_name] then
      return self._loadouts[char_name]
    end
    if not original_loadout then
      return
    end
    local loadout = deep_clone(original_loadout)
    if LuaNetworking:IsHost() then
    
      -- choose mask
      if loadout.mask == "character_locked" or loadout.mask_random then
        loadout.mask_slot = nil

        local index = self._data[char_name .. "_mask"] or 1
        if self._data.toggle_override_masks then
          index = self._data.override_masks or (#self.masks_legacy + 1)
        end
        
        if index > #self.masks_legacy or loadout.mask_random and type(loadout.mask_random) ~= "string" then
          local masks_data = self:get_masks_data()
          loadout.mask = masks_data.masks[math.random(#masks_data.masks)]
          if math.random() < (self._data.slider_mask_customized_chance or 0.5) then
            loadout.mask_blueprint = {
              color = {id = masks_data.colors[math.random(#masks_data.colors)]},
              pattern = {id = masks_data.patterns[math.random(#masks_data.patterns)]},
              material = {id = masks_data.materials[math.random(#masks_data.materials)]}
            }
          end
        elseif type(loadout.mask_random) == "string" and (self.masks[loadout.mask_random].character and self.masks[loadout.mask_random].character[char_name] or self.masks[loadout.mask_random].pool) then
          local selection = self.masks[loadout.mask_random].character and self.masks[loadout.mask_random].character[char_name] or self.masks[loadout.mask_random].pool[math.random(#self.masks[loadout.mask_random].pool)]
          loadout.mask = selection.id
          loadout.mask_blueprint = selection.blueprint
        elseif self.masks_legacy[index].character and self.masks_legacy[index].character[char_name] or self.masks_legacy[index].pool then
          local selection = self.masks_legacy[index].character and self.masks_legacy[index].character[char_name] or self.masks_legacy[index].pool[math.random(#self.masks_legacy[index].pool)]
          loadout.mask = selection.id
          loadout.mask_blueprint = selection.blueprint
        elseif self.masks_legacy[index].menu_name == "item_same_as_me" then
          local player_mask = managers.blackmarket:equipped_mask()
          if player_mask then
            loadout.mask = player_mask.mask_id
            loadout.mask_blueprint = player_mask.blueprint
          end
        end
      end
      
      -- choose weapon
      if not loadout.primary or loadout.primary_random then
        local weapon_index = self._data[char_name .. "_weapon"] or 1
        if self._data.toggle_override_weapons then
          weapon_index = self._data.override_weapons or (#self.weapons_legacy + 1)
        end
        if weapon_index > #self.weapons_legacy or loadout.primary_random then
          local weapon = self:get_random_weapon(type(loadout.primary_random) == "string" and loadout.primary_random or nil)
          loadout.primary_slot = nil
          loadout.primary = weapon.factory_id
          loadout.primary_category = weapon.category
          loadout.primary_blueprint = weapon.blueprint
        else
          local weapon = self.weapons_legacy[weapon_index]
          loadout.primary_slot = nil
          loadout.primary = weapon.factory_name
          loadout.primary_blueprint = weapon.blueprint
        end
      end
      
      -- choose armor models
      if not loadout.armor or loadout.armor_random then
        local armor_index = BotWeapons._data[char_name .. "_armor"] or 1
        if BotWeapons._data.toggle_override_armor then
          armor_index = BotWeapons._data.override_armor or (#BotWeapons.armor + 1)
        end
        if armor_index > #BotWeapons.armor or loadout.armor_random then
          armor_index = math.random(#BotWeapons.armor)
        end
        loadout.armor = "level_" .. tostring(armor_index)
      end
      
      -- choose equipment models
      if not loadout.deployable or loadout.deployable_random then
        local equipment_index = BotWeapons._data[char_name .. "_equipment"] or 1
        if BotWeapons._data.toggle_override_equipment then
          equipment_index = BotWeapons._data.override_equipment or (#BotWeapons.equipment + 1)
        end
        if equipment_index > #BotWeapons.equipment or loadout.deployable_random then
          equipment_index = 1 + math.random(#BotWeapons.equipment - 1)
        end
        loadout.deployable = BotWeapons.equipment[equipment_index].name
      end
      
    end
    self._loadouts = self._loadouts or {}
    self._loadouts[char_name] = loadout
    return loadout
  end
  
  Hooks:Add("NetworkReceivedData", "NetworkReceivedDataBotWeapons", function(sender, id, data)
    local peer = LuaNetworking:GetPeers()[sender]
    local params = string.split(data or "", ",", true)
    if id == "bot_weapons_equipment" and managers.criminals then
      if #params == 2 then
        local name = params[1]
        local equipment = params[2]
        BotWeapons:set_equipment(managers.criminals:character_unit_by_name(name), equipment)
      end
    end
  end)

  function BotWeapons:save()
    local file = io.open(self._data_path .. "bot_weapons_data.txt", "w+")
    if file then
      file:write(json.encode(self._data))
      file:close()
    end
  end

  function BotWeapons:load()
    local file = io.open(self._data_path .. "bot_weapons_data.txt", "r")
    if file then
      self._data = json.decode(file:read("*all"))
      file:close()
    end
  end
  
  -- initialize
  BotWeapons:init()
  
end