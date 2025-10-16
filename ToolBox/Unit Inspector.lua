function widget:GetInfo()
    return {
        name      = "Unit Inspector",
        desc      = [[Displays all properties of a clicked unit.
        THIS IS A DIRTY WAY TO INSPECT UNITS PROPERTIES, THIS IS NOT OPTIMIZED AT ALL AND IS NOT MEANT TO BE USED DURING A REAL GAME. THIS JUST BUT A TOOL]],
        author    = "Noryon",
        date      = "2025-08-10",
        license   = "MIT",
        layer     = 0,
        enabled   = true
    }
end

local inspectedUnitID = nil
local inspectedData = {}

local function SerializeTable(t, prefix)
    local result = {}
    prefix = prefix or ""
    for k, v in pairs(t) do
        local key = prefix .. tostring(k)
        if type(v) == "table" then
            local sub = SerializeTable(v, key .. ".")
            for _, s in ipairs(sub) do
                table.insert(result, s)
            end
        else
            table.insert(result, key .. " = " .. tostring(v))
        end
    end
    return result
end
local function GetFullUnitInfo(unitID)
    local info = {}

    -- Helper to safely append lines
    local function add(line)
        info[#info + 1] = tostring(line)
    end

    -- Static UnitDef info
    local unitDefID = Spring.GetUnitDefID(unitID)
    if unitDefID then
        add("UnitDefID = " .. tostring(unitDefID))

        local unitDef = UnitDefs[unitDefID]
        if unitDef then
            -- basic name fields
            add("UnitDef.name = " .. tostring(unitDef.name))
            add("UnitDef.humanName = " .. tostring(unitDef.humanName or unitDef.tooltip or unitDef.description or "nil"))

            -- other useful top-level fields
            add("UnitDef.health = " .. tostring(unitDef.health or "nil"))
            add("UnitDef.maxDamage = " .. tostring(unitDef.maxDamage or "nil"))
            add("UnitDef.speed = " .. tostring(unitDef.speed or unitDef.maxVelocity or "nil"))
            add("UnitDef.buildCostMetal = " .. tostring(unitDef.buildCostMetal or "nil"))
            add("UnitDef.buildCostEnergy = " .. tostring(unitDef.buildCostEnergy or "nil"))

            -- dump the unitDef (if you still want the full serialized form)
            if SerializeTable then
                local defProps = SerializeTable(unitDef)
                for _, line in ipairs(defProps) do
                    add("UnitDef." .. line)
                end
            end

            -- ---------- WeaponDefs attached directly to the UnitDef ----------
            -- unitDef.weaponDefs is usually a table keyed by weaponDefName -> weaponDefTable
            if unitDef.weaponDefs and next(unitDef.weaponDefs) then
                add("UnitDef.weaponDefs found")
                for wname, wdef in pairs(unitDef.weaponDefs) do
                    add("  WeaponDef[" .. tostring(wname) .. "] -----------------")
                    -- some common useful fields (nil-safe)
                    add("    name = " .. tostring(wdef.name or wname))
                    add("    damage = " .. tostring((wdef.damage and wdef.damage.default) or wdef.damage or "nil"))
                    add("    range = " .. tostring(wdef.range or "nil"))
                    add("    reload = " .. tostring(wdef.reloadtime or wdef.reload or "nil"))
                    add("    accuracy = " .. tostring(wdef.accuracy or wdef.predictedHit or "nil"))
                    add("    areaOfEffect = " .. tostring(wdef.areaOfEffect or wdef.aoe or "nil"))
                    add("    projectileSpeed = " .. tostring(wdef.projectilespeed or wdef.weaponVelocity or "nil"))
                    -- full dump for each weaponDef (optional)
                    if SerializeTable then
                        local wprops = SerializeTable(wdef)
                        for _, l in ipairs(wprops) do
                            add("    WeaponDef." .. l)
                        end
                    end
                end
            end

            -- ---------- Per-slot weapons (mount points) ----------
            -- unitDef.weapons is typically an array describing each mounted weapon slot,
            -- with `.def` referencing the weaponDef name referenced in WeaponDefs table.
            if unitDef.weapons and #unitDef.weapons > 0 then
                add("UnitDef.weapons (mount points) found: " .. tostring(#unitDef.weapons))
                for slotIndex, slot in ipairs(unitDef.weapons) do
                    local defname = slot.def or slot.name or slot.weaponDef or "nil"
                    add(string.format("  slot %d -> weaponDefName = %s (muzzle = %s, onlyTargetCategory = %s)",
                                      slotIndex, tostring(defname), tostring(slot.muzzle or "nil"), tostring(slot.onlyTargetCategory or "nil")))
                    -- If we can find the referenced WeaponDef in global WeaponDefs table, show some fields
                    local wdef = nil
                    if type(defname) == "string" then
                        -- some mods populate WeaponDefs by name
                        wdef = WeaponDefs and WeaponDefs[defname] or nil
                    elseif type(defname) == "number" then
                        -- if def references a numeric id (less common), try numeric lookup
                        wdef = WeaponDefs and WeaponDefs[defname] or nil
                    end
                    if wdef then
                        add("    -> Resolved WeaponDef: " .. tostring(wdef.name or defname))
                        add("       damage = " .. tostring((wdef.damage and wdef.damage.default) or wdef.damage or "nil"))
                        add("       range = " .. tostring(wdef.range or "nil"))
                        add("       reload = " .. tostring(wdef.reloadtime or "nil"))
                        if SerializeTable then
                            local wz = SerializeTable(wdef)
                            for _, l in ipairs(wz) do
                                add("       WeaponDef." .. l)
                            end
                        end
                    else
                        add("    -> WeaponDef not found in WeaponDefs table for: " .. tostring(defname))
                    end
                end
            else
                add("UnitDef.weapons = nil or empty")
            end
        else
            add("UnitDef = nil for id " .. tostring(unitDefID))
        end
    else
        add("UnitDefID = nil (invalid unitID?)")
    end

    -- Dynamic state info (existing)
    local dynamicCalls = {
        {"Spring.GetUnitHealth", Spring.GetUnitHealth, {"health", "maxHealth", "paralyzeDamage", "captureProgress", "buildProgress"}},
        {"Spring.GetUnitPosition", Spring.GetUnitPosition, {"posX", "posY", "posZ"}},
        {"Spring.GetUnitDirection", Spring.GetUnitDirection, {"dirX", "dirY", "dirZ"}},
        {"Spring.GetUnitVelocity", Spring.GetUnitVelocity, {"velX", "velY", "velZ", "velMag"}},
        {"Spring.GetUnitExperience", Spring.GetUnitExperience, {"experience"}},
        {"Spring.GetUnitIsStunned", Spring.GetUnitIsStunned, {"stunned", "inBuild"}},
        {"Spring.GetUnitNeutral", Spring.GetUnitNeutral, {"neutral"}},
        {"Spring.GetUnitTeam", Spring.GetUnitTeam, {"team"}},
        {"Spring.GetUnitAllyTeam", Spring.GetUnitAllyTeam, {"allyTeam"}},
        {"Spring.GetUnitIsDead", Spring.GetUnitIsDead, {"isDead"}},
    }

    for _, call in ipairs(dynamicCalls) do
        local callName, func, labels = call[1], call[2], call[3]
        local results = {func(unitID)}
        for i, label in ipairs(labels) do
            add(callName .. "." .. label .. " = " .. tostring(results[i]))
        end
    end

    

    table.sort(info)
    return info
end


function widget:MousePress(x, y, button)
    if button ~= 1 then return false end
    local result, id = Spring.TraceScreenRay(x, y)
    if result == "unit" and id then
        inspectedUnitID = id
        inspectedData = GetFullUnitInfo(id)
    end
    return false
end

function widget:DrawScreen()
    if not inspectedUnitID or not inspectedData then return end

    local sx = 50
    local bottomMargin = 200
    local lineHeight = 20
    local padding = 4
    local fontSize = 18
    local maxRowsPerColumn = 20
    local colSpacing = 30 -- extra space between columns

    -- compute number of columns
    local numColumns = math.ceil(#inspectedData / maxRowsPerColumn)

    -- compute width of each column individually
    local colWidths = {}
    for col = 1, numColumns do
        local startIdx = (col - 1) * maxRowsPerColumn + 1
        local endIdx = math.min(col * maxRowsPerColumn, #inspectedData)

        local maxWidth = 0
        for i = startIdx, endIdx do
            local line = inspectedData[i]
            local w = gl.GetTextWidth(line) * fontSize
            if w > maxWidth then
                maxWidth = w
            end
        end
        colWidths[col] = maxWidth + padding * 2
    end

    -- compute total rect size
    local colHeight = maxRowsPerColumn * lineHeight + padding * 2
    local rectHeight = math.min(#inspectedData, maxRowsPerColumn) * lineHeight + padding * 2
    local rectBottom = bottomMargin
    local rectTop = rectBottom + rectHeight

    -- draw each column
    gl.Color(1, 1, 1, 1)
    gl.BeginText()

    local xOffset = sx
    for col = 1, numColumns do
        local startIdx = (col - 1) * maxRowsPerColumn + 1
        local endIdx = math.min(col * maxRowsPerColumn, #inspectedData)

        -- draw background for this column
        gl.Color(0, 0, 0, 0.6)
        gl.Rect(xOffset - padding, rectBottom, xOffset + colWidths[col], rectTop)

        -- draw text lines
        gl.Color(1, 1, 1, 1)
        for row = 0, endIdx - startIdx do
            local line = inspectedData[startIdx + row]
            gl.Text(line, xOffset, rectTop - (row + 1) * lineHeight, fontSize, "o")
        end

        -- shift xOffset for next column
        xOffset = xOffset + colWidths[col] + colSpacing
    end

    gl.EndText()
end



