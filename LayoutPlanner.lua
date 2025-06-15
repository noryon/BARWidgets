function widget:GetInfo()
  return {
    name    = "Layout Planner",
    desc    = "Plan, save and load base layouts using in game interface. The widget uses the concept of Building Unit (BU), which is the smallest building unit allowed, which represents 16 units in world space.",
    author  = "Noryon",
    date    = "2025-06-12",
    license = "MIT",
    layer   = 0,
    enabled = true
  }
end

-- Constants
local BU_SIZE = 16  -- 1 BU = 16 game units (BU stand for Building Unit, the smallest unit size i could find, which is Cameras)
local SQUARE_SIZE = 3 * BU_SIZE  -- 1 square = 3x3 BUs = 48 units
local CHUNK_SIZE = 4 * SQUARE_SIZE  -- 1 chunk = 4x4 squares = 12x12 BUs

--TODO, maybe set more slots, or set a "textbox" where player can use type a name?
local LAYOUT_FILES = {
  "LuaUI/Widgets/layout_1.txt",
  "LuaUI/Widgets/layout_2.txt",
  "LuaUI/Widgets/layout_3.txt",
  "LuaUI/Widgets/layout_4.txt"
}


local drawingToGame = false;

-- Building types (in BUs)
--Enable/Disable sizes by uncomment/comment building type line below
local buildingTypes = {
 -- { name = "1x1", size = 1, tooltip = "e.g.: Camera (lol)" }, --nobody really need this, probably. If you want it just uncomment this line
  { name = "Small", size = 2, tooltip = "e.g.: Wall, Dragon's Maw/Claw/Fury"},
  { name = "Square", size = 3, tooltip = "e.g.: T1 Con. Turret, T1 Wind, T1 Converter"},
  { name = "Big", size = 4, tooltip =  "e.g.: T2 Con. Turret, T2 Converter", "Basilica"},
  { name = "Large", size = 6, tooltip = "e.g.: AFUS, T3 Con. Turret, T2 Wind, Olympus, Basilisk" },
  { name = "Chunk", size = 12, tooltip = "e.g.: EFUS" },
}
-- Control Variables
local selectedBuildings = {} --Stores the current working layout
local drawingMode = false
local currentSizeIndex = 1
local layoutRotation = 0
local layoutToPlace = nil --Layout being displayed (it is the original layout rotated and inverted)
local originalLayoutToPlace = nil --Layout loaded. Might be possible to remove this and rotate the layout directly?
local dragging = false
local dragStart = nil
local layoutInverted = false
local snapLoadedLayoutToSmallest = false --Snap loaded layout might not be a great idea as i first thought. Testing without snap for now. One problem is that if the layout is "zeroed" with a irregular building it might end up  missaligned
local snapBuilding = true --Snap building block
--Render stuff
local drawLineQueue = {}
local timer = 0
local renderingToGame = false;

-- Convert between world space and BU grid coordinates
local function WorldToBU(x, z)
  return math.floor(x / BU_SIZE), math.floor(z / BU_SIZE)
end

local function BUToWorld(bx, bz)
  return bx * BU_SIZE, bz * BU_SIZE
end

local function ToggleBuilding(bx, bz, size)
  local key = bx .. "," .. bz
  if selectedBuildings[key] then
    selectedBuildings[key] = nil
  else
    selectedBuildings[key] = { size = size }
  end
end
--It gets a layout and returns a new one, rotated and inverted
local function ApplyRotationAndInversion(layout, rotation, inverted)
  local cx, cz = 0, 0  -- center of the layout (in BU units)

  -- Step 1: Compute bounds
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, b in ipairs(layout) do
    minX = math.min(minX, b.dx)
    maxX = math.max(maxX, b.dx + b.size - 1)
    minZ = math.min(minZ, b.dz)
    maxZ = math.max(maxZ, b.dz + b.size - 1)
  end

  local width = maxX - minX + 1
  local height = maxZ - minZ + 1

  cx = minX + width / 2
  cz = minZ + height / 2

  -- Step 2: Rotate each building
  local rotated = {}

  for _, b in ipairs(layout) do
    local dx, dz = b.dx, b.dz

    -- offset from center
    local ox, oz = dx + b.size / 2 - cx, dz + b.size / 2 - cz
    local rx, rz

    if rotation == 0 then
      rx, rz = ox, oz
    elseif rotation == 90 then
      rx, rz = -oz, ox
    elseif rotation == 180 then
      rx, rz = -ox, -oz
    elseif rotation == 270 then
      rx, rz = oz, -ox
    end

    -- new position = center + rotated offset - half size
    local newDx = math.floor(cx + rx - b.size / 2 + 0.5)
    local newDz = math.floor(cz + rz - b.size / 2 + 0.5)

    if inverted then
      newDx = 2 * cx - newDx - b.size
    end

    table.insert(rotated, {dx = newDx, dz = newDz, size = b.size})
  end

  return rotated
end





local function DrawEdges(edges)
  Spring.Echo("[LayoutPlanner] Queuing " .. tostring(#edges) .. " edges for rendering.")
  drawLineQueue = {} -- Clear old queue

  for _, edge in ipairs(edges) do
    local x1, z1 = BUToWorld(edge.x1, edge.z1)
    local x2, z2 = BUToWorld(edge.x2, edge.z2)
    local y = 100

    local dx = x2 - x1
    local dz = z2 - z1
    local dist = math.sqrt(dx * dx + dz * dz)

    local segments = math.ceil(dist / CHUNK_SIZE)
    if segments <= 1 then
      table.insert(drawLineQueue, {
        startX = x1, startZ = z1, endX = x2, endZ = z2, y = y
      })
    else
      for i = 0, segments - 1 do
        local t1 = i / segments
        local t2 = (i + 1) / segments
        local sx = x1 + dx * t1
        local sz = z1 + dz * t1
        local ex = x1 + dx * t2
        local ez = z1 + dz * t2
        table.insert(drawLineQueue, {
          startX = sx, startZ = sz, endX = ex, endZ = ez, y = y
        })
      end
    end
  end
  renderinToGame = true
end



local function CollectEdges()
  Spring.Echo("[LayoutPlanner] Collecting and merging outer edges...")

  local function edgeKey(x1, z1, x2, z2)
    -- Normalize to avoid reversed duplicates keys
    if x1 > x2 or (x1 == x2 and z1 > z2) then
      x1, z1, x2, z2 = x2, z2, x1, z1
    end
    return x1 .. "," .. z1 .. "," .. x2 .. "," .. z2
  end

  local rawEdges = {}

  -- 1. Generate 4 outer edges per building
  for key, data in pairs(selectedBuildings) do
    local bx, bz = key:match("(-?%d+),(-?%d+)")
    bx, bz = tonumber(bx), tonumber(bz)
    local size = data.size

    local edges = {
      {bx, bz, bx + size, bz},               -- top
      {bx + size, bz, bx + size, bz + size}, -- right
      {bx + size, bz + size, bx, bz + size}, -- bottom
      {bx, bz + size, bx, bz},               -- left
    }

    for _, e in ipairs(edges) do
      local k = edgeKey(unpack(e))
      if rawEdges[k] then
        rawEdges[k] = nil -- shared, internal edge
      else
        rawEdges[k] = { x1 = e[1], z1 = e[2], x2 = e[3], z2 = e[4] }
      end
    end
  end

  -- 2. Group by horizontal and vertical
  local horizontal, vertical = {}, {}
  for _, edge in pairs(rawEdges) do
    if edge.z1 == edge.z2 then
      table.insert(horizontal, edge)
    elseif edge.x1 == edge.x2 then
      table.insert(vertical, edge)
    end
  end

  local function mergeLines(edges, isHorizontal)
    local merged = {}
    local axis1, axis2 = isHorizontal and "x" or "z", isHorizontal and "z" or "x"

    -- Group by fixed axis2 (e.g., all z for horizontal lines)
    local groups = {}
    for _, e in ipairs(edges) do
      local key = tostring(e[axis2 .. "1"])
      groups[key] = groups[key] or {}
      local a1 = math.min(e[axis1 .. "1"], e[axis1 .. "2"])
      local a2 = math.max(e[axis1 .. "1"], e[axis1 .. "2"])
      table.insert(groups[key], { a1 = a1, a2 = a2 })
    end

    for coord, segs in pairs(groups) do
      table.sort(segs, function(a, b) return a.a1 < b.a1 end)

      local currentA1, currentA2 = segs[1].a1, segs[1].a2
      for i = 2, #segs do
        local seg = segs[i]
        if seg.a1 <= currentA2 then
          currentA2 = math.max(currentA2, seg.a2) -- merge
        else
          -- emit previous
          local line = isHorizontal
            and { x1 = currentA1, z1 = tonumber(coord), x2 = currentA2, z2 = tonumber(coord) }
            or  { x1 = tonumber(coord), z1 = currentA1, x2 = tonumber(coord), z2 = currentA2 }
          table.insert(merged, line)
          currentA1, currentA2 = seg.a1, seg.a2
        end
      end
      -- final segment
      local line = isHorizontal
        and { x1 = currentA1, z1 = tonumber(coord), x2 = currentA2, z2 = tonumber(coord) }
        or  { x1 = tonumber(coord), z1 = currentA1, x2 = tonumber(coord), z2 = currentA2 }
      table.insert(merged, line)
    end

    return merged
  end

  -- 3. Merge all segments
  local result = {}
  for _, e in ipairs(mergeLines(horizontal, true)) do table.insert(result, e) end
  for _, e in ipairs(mergeLines(vertical, false)) do table.insert(result, e) end

  Spring.Echo("[LayoutPlanner] Final edge count:", #result)
  return result
end



local function CollectAndDraw()
	DrawEdges(CollectEdges())
end

local function copyLayout(tbl)
  local copy = {}
  for i, v in ipairs(tbl) do
    copy[i] = {dx = v.dx, dz = v.dz, size = v.size}
  end
  return copy
end

local function SaveBuildings(slot)
  if not next(selectedBuildings) then
    Spring.Echo("[LayoutPlanner] No buildings to save.")
    return
  end

  local filename = LAYOUT_FILES[slot]
  -- Align anchor to nearest square boundary
  local minX, minZ = math.huge, math.huge
  for key in pairs(selectedBuildings) do
    if type(key) == "string" then
      local x, z = key:match("(-?%d+),(-?%d+)")
      x, z = tonumber(x), tonumber(z)
      if x < minX then minX = x end
      if z < minZ then minZ = z end
    end
  end


  local file = io.open(filename, "w")
  if not file then
    Spring.Echo("[LayoutPlanner] Failed to open file.")
    return
  end

  for key, data in pairs(selectedBuildings) do
    if type(key) == "string" then
      local x, z = key:match("(-?%d+),(-?%d+)")
      x, z = tonumber(x), tonumber(z)
      file:write((x - minX) .. "," .. (z - minZ) .. "," .. data.size .. "\n")
    end
  end
  file:close()
  Spring.Echo("[LayoutPlanner] Layout saved relative to:", minX, minZ)
end

local function LoadBuildings(slot)
  local filename = LAYOUT_FILES[slot]
  local file = io.open(filename, "r")
  if not file then
    Spring.Echo("[LayoutPlanner] No saved layout found.")
    return
  end

  layoutToPlace = {}
  local smallest = math.huge

  for line in file:lines() do
	local dx, dz, size = line:match("(-?%d+),(-?%d+),(%d+)")
	dx, dz, size = tonumber(dx), tonumber(dz), tonumber(size)
	if dx and dz and size then
	  table.insert(layoutToPlace, {dx = dx, dz = dz, size = size})
	  if size < smallest then
		smallest = size
	  end
	end
  end
  
  if not snapLoadedLayoutToSmallest then
	smallest = buildingTypes[1].size
  end
  
  file:close()
  if #layoutToPlace > 0 then
    Spring.Echo("[LayoutPlanner] Layout loaded. Click to place.")
    for i, t in ipairs(buildingTypes) do
      if t.size == smallest then
        currentSizeIndex = i
        break
      end
    end
  else
    layoutToPlace = nil
    Spring.Echo("[LayoutPlanner] File empty or invalid.")
  end
  originalLayoutToPlace = copyLayout(layoutToPlace)
  layoutRotation = 0
  layoutInverted = false
  selectedBuildings = {}
end

local panelX = 100
local panelY = 370
local panelWidth = 520
local panelHeight = 230

local buttonW = 100
local buttonH = 30
local spacing = 10
local border = 4

local buttons = {
  {
    label = function() return "Close Panel" end,
    x = panelX + panelWidth - spacing - 120,
    y = panelY + panelHeight + 3,
    w = 120,
    h = buttonH,
    action = function() Spring.Echo("[LayoutPlanner] Disabling widget.") widgetHandler:RemoveWidget(self) end,
    color = {1, 0.2, 0.2, 0.9}, -- red
  },
  {
    label = function() return "Drawing: " .. (drawingMode and "ON" or "OFF") end,
    x = panelX + spacing,
    y = panelY + panelHeight - buttonH - spacing,
    w = 150,
    h = buttonH,
    action = function() drawingMode = not drawingMode end,
    color = {0.4, 0.6, 1, 0.8},
  },
  {
    label = function() return "Size: " .. buildingTypes[currentSizeIndex].name end,
    x = panelX + 150 + spacing * 2,
    y = panelY + panelHeight - buttonH - spacing,
    w = 150,
    h = buttonH,
    action = function() currentSizeIndex = currentSizeIndex % #buildingTypes + 1 end,
    color = {0.4, 1, 0.4, 0.8},
  },
  {
    label = function() return "Snap: " .. (snapBuilding and "ON" or "OFF") end,
    x = panelX + 300 + spacing * 3,
    y = panelY + panelHeight - buttonH - spacing,
    w = 150,
    h = buttonH,
    action = function() snapBuilding = not snapBuilding end,
    color = {0.4, 1, 0.4, 0.8},
  },
  {
    label = function() return "Clear Layout" end,
    x = panelX + spacing,
    y = panelY + panelHeight - buttonH * 2 - spacing * 2,
    w = buttonW+10,
    h = buttonH,
    action = function() selectedBuildings = {} end,
    color = {1, 0.6, 0.2, 0.8},
  },
  {
    label = function() return "Render To Game" end,
    x = panelX + buttonW + spacing * 2 + 10,
    y = panelY + panelHeight - buttonH * 2 - spacing * 2,
    w = 150,
    h = buttonH,
    action = CollectAndDraw,
    color = {0.2, 0.1, 0.9, 0.8},
  },
}

local sizeButton = buttons[3]


-- Save/Load buttons (slot 1 to 4)
local colors = {
	{0.8, 0.1, 0.1, 0.8},
	{0.1, 0.8, 0.1, 0.8},
	{0.8, 0.1, 0.8, 0.8},
	{0.8, 0.8, 0.1, 0.8},
}

for i = 1, 4 do
  local bx = panelX + (i - 1) * (buttonW + spacing) + spacing 
  local offset = 0;
  table.insert(buttons, {
	label = function() return "Save " .. i end,
	x = bx,
	y = panelY + buttonH + spacing * 2 + offset,
	w = buttonW,
	h = 25,
	color = colors[i],
	action = function() SaveBuildings(i) end,
  })
  table.insert(buttons, {
	label = function() return "Load " .. i end,
	x = bx,
	y = panelY + spacing + offset,
	w = buttonW,
	h = 25,
	color = colors[i],
	action = function() LoadBuildings(i) end,
  })
end

function widget:DrawScreen()
  -- Panel background
  gl.Color(0, 0, 0, 1)
  gl.Rect(panelX - border, panelY - border, panelX + panelWidth + border, panelY + panelHeight + border + buttonH + border)
  
  gl.Color(0.1, 0.1, 0.1, 1)
  gl.Rect(panelX, panelY, panelX + panelWidth, panelY + panelHeight)

  -- Title
  gl.Color(0.9, 0.55, 0.05, 1)
  gl.Text("Layout Planner", panelX + 10, panelY + panelHeight + 8, 20, "o")
  
  local mx, my = Spring.GetMouseState()

  

  -- Buttons
  for _, btn in ipairs(buttons) do
    local color = btn.color or {0.3, 0.3, 0.3, 0.8}
    gl.Color(unpack(color))
    gl.Rect(btn.x, btn.y, btn.x + btn.w, btn.y + btn.h)
    gl.Color(1, 1, 1, 1)
    gl.Text(btn.label(), btn.x + 10, btn.y + 8, 16, "o")
  end

  -- Placement hint text
  if layoutToPlace then
    local vsx, vsy = gl.GetViewSizes()
	local textWidth = 19 * 18
    gl.Color(1, 1, 0.5, 1)
    gl.Text("Press [R] to rotate", (vsx - textWidth) / 2, vsy * 0.4, 18, "o")
	gl.Text("Press [I] to invert", (vsx - textWidth) / 2, vsy * 0.4-20, 18, "o")
  end
  
  -- Tooltip
  if mx >= sizeButton.x and mx <= sizeButton.x + sizeButton.w and my >= sizeButton.y and my <= sizeButton.y + sizeButton.h then
    gl.Color(0.0, 0.55, 0.0, 1)
	gl.Rect(mx, my, mx + 450, my + 20)	
	gl.Color(1, 1, 1, 1)
	gl.Text(""..buildingTypes[currentSizeIndex].tooltip, mx+border, my+border, 20, "o")
  end
end




-- Extend dragging support
function widget:MousePress(mx, my, button)
  if button ~= 1 then return false end

  for _, btn in ipairs(buttons) do
    if mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h then
      btn.action()
      return true
    end
  end

  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if not pos then return false end

  local bx, bz = WorldToBU(pos[1], pos[3])
  local size = buildingTypes[currentSizeIndex].size
  if snapBuilding then
    bx = math.floor(bx / size) * size
    bz = math.floor(bz / size) * size
  end
  if layoutToPlace then
    for _, b in ipairs(layoutToPlace) do
      local dx, dz = b.dx, b.dz
      local s = b.size
      local rx, rz = dx, dz
	  local pbx, pbz = bx + rx, bz + rz
      selectedBuildings[pbx .. "," .. pbz] = { size = s }
    end
    layoutToPlace = nil
    originalLayoutToPlace = nil
    Spring.Echo("[LayoutPlanner] Layout placed.")
    return true
  elseif drawingMode then
    dragging = true
    dragStart = { bx = bx, bz = bz, size = size }
    return true
  end

  return false
end

function widget:MouseRelease(mx, my, button)
  if button ~= 1 or not dragging or not dragStart then return end

  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if not pos then return end

  local size = dragStart.size
  local bx1, bz1 = dragStart.bx, dragStart.bz
  local bx2, bz2 = WorldToBU(pos[1], pos[3])
  if snapBuilding then
	bx2 = math.floor(bx2 / size) * size
	bz2 = math.floor(bz2 / size) * size
  end
  local minX, maxX = math.min(bx1, bx2), math.max(bx1, bx2)
  local minZ, maxZ = math.min(bz1, bz2), math.max(bz1, bz2)

  for bx = minX, maxX, size do
    for bz = minZ, maxZ, size do
      ToggleBuilding(bx, bz, size)
    end
  end

  dragging = false
  dragStart = nil
end

function widget:DrawWorld()
  if drawingToGame then return end
  
  gl.DepthTest(true)

  -- Draw layout
  for key, data in pairs(selectedBuildings) do
    local x, z = key:match("(-?%d+),(-?%d+)")
    local bx, bz = tonumber(x), tonumber(z)
    local size = data.size
    local wx, wz = BUToWorld(bx, bz)
    local wy = Spring.GetGroundHeight(wx, wz)

    gl.Color(0, 1, 0, 0.3)
    gl.BeginEnd(GL.QUADS, function()
      gl.Vertex(wx, wy + 5, wz)
      gl.Vertex(wx + BU_SIZE * size, wy + 5, wz)
      gl.Vertex(wx + BU_SIZE * size, wy + 5, wz + BU_SIZE * size)
      gl.Vertex(wx, wy + 5, wz + BU_SIZE * size)
    end)
  end

  -- Draw preview
  local mx, my = Spring.GetMouseState()
  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if pos then
    local bx, bz = WorldToBU(pos[1], pos[3])
    local size = buildingTypes[currentSizeIndex].size
	if snapBuilding then
      bx = math.floor(bx / size) * size
      bz = math.floor(bz / size) * size
    end
    gl.Color(1, 1, 0, 0.4)

    if layoutToPlace then
      for _, b in ipairs(layoutToPlace) do
        local dx, dz = b.dx, b.dz
		local s = b.size
        local rx, rz = dx, dz
		
        local pbx, pbz = bx + rx, bz + rz
        local wx, wz = BUToWorld(pbx, pbz)
        local wy = Spring.GetGroundHeight(wx, wz)

        gl.BeginEnd(GL.QUADS, function()
          gl.Vertex(wx, wy + 5, wz)
          gl.Vertex(wx + BU_SIZE * s, wy + 5, wz)
          gl.Vertex(wx + BU_SIZE * s, wy + 5, wz + BU_SIZE * s)
          gl.Vertex(wx, wy + 5, wz + BU_SIZE * s)
        end)
      end
    elseif drawingMode then
      local wx, wz = BUToWorld(bx, bz)
      local wy = Spring.GetGroundHeight(wx, wz)

      gl.BeginEnd(GL.QUADS, function()
        gl.Vertex(wx, wy + 5, wz)
        gl.Vertex(wx + BU_SIZE * size, wy + 5, wz)
        gl.Vertex(wx + BU_SIZE * size, wy + 5, wz + BU_SIZE * size)
        gl.Vertex(wx, wy + 5, wz + BU_SIZE * size)
      end)
    end
  end

  gl.Color(1, 1, 1, 1)
  gl.DepthTest(false)
end

function widget:KeyPress(key, mods, isRepeat)
  if key == string.byte("r") then
    layoutRotation = (layoutRotation + 90) % 360
    layoutToPlace = ApplyRotationAndInversion(originalLayoutToPlace, layoutRotation, layoutInverted)
    Spring.Echo("[LayoutPlanner] Rotation:", layoutRotation)
    return true
  end
  if key == string.byte("i") then
    layoutInverted = not layoutInverted
    layoutToPlace = ApplyRotationAndInversion(originalLayoutToPlace, layoutRotation, layoutInverted)
    Spring.Echo("[LayoutPlanner] Layout Inverted:", layoutInverted)
    return true
  end
end

function widget:Update(dt)
  if not renderinToGame then return end
  timer = timer + dt
  if timer > 0.1 then
    for i = 1, 10 do
      if #drawLineQueue == 0 then
        Spring.Echo("[LayoutPlanner] All lines rendered. Disabling widget.")
        widgetHandler:RemoveWidget(self)
        return
      end

      local data = table.remove(drawLineQueue, 1)
      Spring.MarkerAddLine(
        data.startX, data.y, data.startZ,
        data.endX,   data.y, data.endZ
      )
    end
    timer = 0
  end
end
