function widget:GetInfo()
  return {
    name    = "Layout Planner",
    desc    = "Plan, save and load base layouts using in game interface.",
    author  = "Noryon",
    date    = "2025-06-12",
    license = "MIT",
    layer   = 0,
    enabled = true
  }
end

------------------------------------------------------------------------------------------
------------------------------USER PREFERENCES / DEFAULT VALUES---------------------------
------------------------------------------------------------------------------------------
local slots = 8                      --AMOUNT OF [SAVE/LOAD] SLOTS YOU WANT THE WIDGET TO DISPLAY   [0, ~)
local slotsPerRow = 4                --HOW MANY SLOTS WILL BE DISPLAYED PER ROW                     [1, ~)
local allowTranslationByKeys = false --WHETHER LAYOUT CAN BE SHIFTED USING KEYBOARD KEYS            [true, false]
local snapBuilding = true            --SNAP BUILDING TO GRID                                        [true, false]
local drawChunkGrid = false          --DRAW A CHUNK ALIGNED GRID                                    [true, false]
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

local function DisableWidget()
	Spring.Echo("[LayoutPlanner] Closed")
	widgetHandler:RemoveWidget(self)
end

-- Constants
local BU_SIZE = 16  -- 1 BU = 16 game units (BU stand for Building Unit, the smallest unit size i could find, which is Cameras)
local SQUARE_SIZE = 3 * BU_SIZE  -- 1 square = 3x3 BUs = 48 units
local CHUNK_SIZE = 4 * SQUARE_SIZE  -- 1 chunk = 4x4 squares = 12x12 BUs


-- Building types (in BUs)
local buildingTypes = {
 -- { name = "1x1", size = 1, tooltip = "e.g.: Camera (lol)" }, --nobody really need this, probably. Just uncomment this line if you think you really need this
  { name = "Small", size = 2, tooltip = "e.g.: Wall, Dragon's Maw/Claw/Fury"},
  { name = "Square", size = 3, tooltip = "e.g.: T1 Con. Turret, T1 Wind, T1 Converter"},
  { name = "Big", size = 4, tooltip =  "e.g.: T2 Con. Turret, T2 Converter, Basilica"},
  { name = "Large", size = 6, tooltip = "e.g.: AFUS, T3 Con. Turret, T2 Wind, Olympus, Basilisk" },
  { name = "Chunk", size = 12, tooltip = "e.g.: EFUS" },
}


-- Control Variables
local drawingToGame = false;

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

local function TranslateLayout(dx, dz)
  local newSelectedBuildings = {}
  for key, value in pairs(selectedBuildings) do
    local bx, bz = key:match("([^,]+),([^,]+)")
    bx, bz = tonumber(bx), tonumber(bz)
    if bx and bz then
      local newBx, newBz = bx + dx, bz + dz
      local newKey = newBx .. "," .. newBz
      newSelectedBuildings[newKey] = value
    end
  end
  selectedBuildings = newSelectedBuildings
end

local function ToggleBuilding(bx, bz, size)
  local key = bx .. "," .. bz
  if selectedBuildings[key] then
    selectedBuildings[key] = nil
  else
    selectedBuildings[key] = { size = size }
  end
end

local function ClearLayout()
	selectedBuildings = {}
	Spring.Echo("[LayoutPlanner] Clear layout")
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
		if rotation == 0 or rotation == 180 then
			newDx = 2 * cx - newDx - b.size
		else
			newDz = 2 * cz - newDz - b.size
		end
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

  local filename = "LuaUI/Widgets/layout_"..slot..".txt"
  local file = io.open(filename, "w")
  if not file then
    Spring.Echo("[LayoutPlanner] Failed to open file. \'"..filename.."\'")
    return
  end

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
  
  for key, data in pairs(selectedBuildings) do
    if type(key) == "string" then
      local x, z = key:match("(-?%d+),(-?%d+)")
      x, z = tonumber(x), tonumber(z)
      file:write((x - minX) .. "," .. (z - minZ) .. "," .. data.size .. "\n")
    end
  end
  file:close()
  Spring.Echo("[LayoutPlanner] Layout saved at slot "..tostring(slot))
end

local loadedMaxX = 0
local loadedMaxZ = 0
local smallest = math.huge

local function LoadBuildings(slot)
  local filename = "LuaUI/Widgets/layout_"..slot..".txt"
  local file = io.open(filename, "r")
  if not file then
    Spring.Echo("[LayoutPlanner] No saved layout found.")
    return
  end

  layoutToPlace = {}
  smallest = math.huge
  loadedMaxX = - math.huge
  loadedMaxZ = - math.huge

  for line in file:lines() do
	local dx, dz, size = line:match("(-?%d+),(-?%d+),(%d+)")
	dx, dz, size = tonumber(dx), tonumber(dz), tonumber(size)
	if dx and dz and size then
	  table.insert(layoutToPlace, {dx = dx, dz = dz, size = size})
	  if size < smallest then
		smallest = size
	  end
	  if dx > loadedMaxX then
		loadedMaxX = dx
	  end
	  if dz > loadedMaxZ then
		loadedMaxZ = dz
	  end
	end
  end
  Spring.Echo("loaded "..tostring(loadedMaxX).." "..tostring(loadedMaxZ))
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

local GRID_COLOR = {1,1, 1, 1}  -- Yellow with transparency
local LINE_WIDTH = 2
local HEIGHT_OFFSET = 5         -- raise lines above ground
local RADIUS_CHUNKS = 8         -- how many chunks out from center

local function DrawChunkGrid(cx, cz)
  gl.PushAttrib(GL.ALL_ATTRIB_BITS)
  gl.Color(GRID_COLOR)
  gl.DepthTest(true)
  gl.LineWidth(LINE_WIDTH)

  gl.BeginEnd(GL.LINES, function()
    local centerChunkX = math.floor(cx / CHUNK_SIZE)
    local centerChunkZ = math.floor(cz / CHUNK_SIZE)

    local minChunkX = centerChunkX - RADIUS_CHUNKS
    local maxChunkX = centerChunkX + RADIUS_CHUNKS
    local minChunkZ = centerChunkZ - RADIUS_CHUNKS
    local maxChunkZ = centerChunkZ + RADIUS_CHUNKS

    -- Vertical lines (x lines, varying z)
    for chunkX = minChunkX, maxChunkX do
      local x = chunkX * CHUNK_SIZE
      for chunkZ = minChunkZ, maxChunkZ - 1 do
        local z1 = chunkZ * CHUNK_SIZE
        local z2 = z1 + CHUNK_SIZE
        local midX = x + CHUNK_SIZE / 2
        local midZ = z1 + CHUNK_SIZE / 2
        local dx = midX - cx
        local dz = midZ - cz
        if dx * dx + dz * dz <= (RADIUS_CHUNKS * CHUNK_SIZE) ^ 2 then
          local y1 = Spring.GetGroundHeight(x, z1) + HEIGHT_OFFSET
          local y2 = Spring.GetGroundHeight(x, z2) + HEIGHT_OFFSET
          gl.Vertex(x, y1, z1)
          gl.Vertex(x, y2, z2)
        end
      end
    end

    -- Horizontal lines (z lines, varying x)
    for chunkZ = minChunkZ, maxChunkZ do
      local z = chunkZ * CHUNK_SIZE
      for chunkX = minChunkX, maxChunkX - 1 do
        local x1 = chunkX * CHUNK_SIZE
        local x2 = x1 + CHUNK_SIZE
        local midX = x1 + CHUNK_SIZE / 2
        local midZ = z + CHUNK_SIZE / 2
        local dx = midX - cx
        local dz = midZ - cz
        if dx * dx + dz * dz <= (RADIUS_CHUNKS * CHUNK_SIZE) ^ 2 then
          local y1 = Spring.GetGroundHeight(x1, z) + HEIGHT_OFFSET
          local y2 = Spring.GetGroundHeight(x2, z) + HEIGHT_OFFSET
          gl.Vertex(x1, y1, z)
          gl.Vertex(x2, y2, z)
        end
      end
    end
  end)

  gl.LineWidth(1)
  gl.Color(1, 1, 1, 1)
  gl.DepthTest(true)
  gl.PopAttrib()
end



local gl = gl
local glColor = gl.Color
local glRect = gl.Rect
local glText = gl.Text
local glGetTextWidth = gl.GetTextWidth
local currentToolTip = nil
--------------------------------------------------------------------------------
-- Base Component

local function BaseElement(params)
  return {
    x = params.x or 0,
    y = params.y or 0,
    width = params.width or 100,
    height = params.height or 30,
    bgColor = params.bgColor or {0.1, 0.1, 0.1, 0.8},
    margin = params.margin or 2,
    tooltip = params.tooltip,
    Draw = function(self) end,
    MousePress = function(self, mx, my, button) return false end,
    KeyPress = function(self, char) end,
    GetSize = function(self)
      return self.width + 2 * self.margin, self.height + 2 * self.margin
    end,
	Hover = function(self, mx, my)
		if self.tooltip ~= nil and self.tooltip ~= "" and
		mx >= self.x and mx <= self.x + self.width and
		my >= self.y and my <= self.y + self.height then
			currentToolTip = self.tooltip
			return true
		else
		    return false
		end
	end
  }
end

--------------------------------------------------------------------------------
-- Box (Container)

local function Box(params)
  local box = BaseElement(params)
  box.orientation = params.orientation or "vertical"
  box.padding = params.padding or 4
  box.spacing = params.spacing or 4
  box.children = {}

  function box:Add(child)
    table.insert(self.children, child)
  end
  
  local superHover = box.Hover
  
function box:Hover(mx, my)
  for _, child in ipairs(self.children) do
	if child:Hover(mx, my) then
	  return true
	end
  end
  return superHover(box, mx, my)
end

function box:Draw()
  glColor(self.bgColor)
  glRect(self.x, self.y, self.x + self.width, self.y + self.height)

  local cx = self.x + self.padding
  local cy = self.y + self.height - self.padding

  for _, child in ipairs(self.children) do
    local cw, ch = child:GetSize()

    -- Update child's position
    if self.orientation == "vertical" then
      cy = cy - ch - child.margin
      child.x = cx + child.margin
      child.y = cy
      cy = cy - self.spacing
    else
      child.x = cx + child.margin
      child.y = cy - ch - child.margin
      cx = cx + cw + self.spacing
    end

    child:Draw()
  end
end

function box:GetSize()
  local totalWidth = 0
  local totalHeight = 0
  for _, child in ipairs(self.children) do
    local cw, ch = child:GetSize()
    if self.orientation == "vertical" then
      totalHeight = totalHeight + ch + self.spacing
      totalWidth = math.max(totalWidth, cw)
    else
      totalWidth = totalWidth + cw + self.spacing
      totalHeight = math.max(totalHeight, ch)
    end
  end
  totalWidth = totalWidth + 2 * self.padding
  totalHeight = totalHeight + 2 * self.padding
  self.width = totalWidth
  self.height = totalHeight
  return totalWidth, totalHeight
end


  function box:MousePress(mx, my, button)
    for _, child in ipairs(self.children) do
      if mx >= child.x and mx <= child.x + child.width and
         my >= child.y and my <= child.y + child.height then
        if child:MousePress(mx, my, button) then
          return true
        end
      end
    end
    return false
  end

  function box:KeyPress(char)
    for _, child in ipairs(self.children) do
      if child.KeyPress then child:KeyPress(char) end
    end
  end

  return box
end

--------------------------------------------------------------------------------
-- Label

local function MakeLabel(params)
  local label = BaseElement(params)
  label.text = params.text or ""
  label.fontSize = params.fontSize or 14
  label.fontColor = params.fontColor or {1, 1, 1, 1}

  function label:GetSize()
    local textWidth = glGetTextWidth(self.text) * self.fontSize
    local textHeight = self.fontSize
    self.width = textWidth + 10
    self.height = textHeight + 18
    return self.width + 2 * self.margin, self.height + 2 * self.margin
  end

  function label:Draw()
    glColor(self.bgColor)
    glRect(self.x, self.y, self.x + self.width, self.y + self.height)
    glColor(self.fontColor)
    glText(self.text, self.x + 5, self.y + (self.height - self.fontSize) / 2 + 2, self.fontSize, "")
  end

  return label
end

--------------------------------------------------------------------------------
-- Button

local function MakeButton(params)
  local button = MakeLabel(params)
  button.onClick = params.onClick or function() end

  function button:MousePress(mx, my, buttonNum)
    if mx >= self.x and mx <= self.x + self.width and
       my >= self.y and my <= self.y + self.height then
      self.onClick()
      return true
    end
    return false
  end

  return button
end

--------------------------------------------------------------------------------
-- Checkbox

local function MakeCheckbox(params)
  local cb = MakeLabel(params)
  cb.checked = params.checked or false
  cb.onToggle = params.onToggle or function() end

  function cb:Draw()
	--background
    glColor(self.bgColor)
    glRect(self.x, self.y, self.x + self.width, self.y + self.height)
	--selection box
    local boxSize = self.height * 1
    local boxX = self.x + 5
    local boxY = self.y + (self.height - boxSize) / 2
    glColor(0.2, 0.2, 0.2, 1)
    glRect(boxX, boxY, boxX + boxSize, boxY + boxSize)
    if self.checked then
      local inset = 2
      glColor(0, 0.8, 0.1, 1)
      glRect(boxX + inset, boxY + inset, boxX + boxSize - inset, boxY + boxSize - inset)
    end
    --text 
    glColor(self.fontColor)
    glText(self.text, boxSize + self.x + 10 , self.y + (self.height - self.fontSize) / 2 + 2, self.fontSize, "")
  end
  
  function cb:GetSize()
    local textWidth = glGetTextWidth(self.text) * self.fontSize
    local textHeight = self.fontSize
    self.height = textHeight + 4
	self.width = textWidth + 10 + 20
    return self.width + 2 * self.margin + self.height + 10, self.height + 2 * self.margin
  end
    
  function cb:MousePress(mx, my, buttonNum)
    if mx >= self.x and mx <= self.x + self.width and
       my >= self.y and my <= self.y + self.height then
      self.checked = not self.checked
      self.onToggle(self.checked)
      return true
    end
    return false
  end

  return cb
end
--------------------------------------------------------------------------------
-- Selection Group

local function MakeSelectionGroup(params)
  local group = BaseElement(params)
  group.options = params.options or {}
  group.selected = params.selected or nil
  group.onSelect = params.onSelect or function(index) end
  group.fontSize = params.fontSize or 14
  group.itemBgColor = params.itemBgColor or {0.2, 0.2, 0.2, 1}
  group.fontColor = params.fontColor or {1, 1, 1, 1}
  group.optionTooltips = params.optionTooltips or {}
  
  function group:GetSize()
    local height = 0
    local width = 0
    for _, opt in ipairs(self.options) do
      local w = glGetTextWidth(opt) * self.fontSize + 30
      width = math.max(width, w)
      height = height + self.fontSize + 10
    end
    self.width = width
    self.height = height
    return self.width + 2 * self.margin, self.height + 2 * self.margin
  end

function group:Hover(mx, my)
	if not group.optionTooltips then
		return false
	end

	local boxSize = self.fontSize + 4
	local spacing = 6
	local offsetY = self.y + self.height - boxSize

	for i = 1, #self.options do
		local boxX = self.x -2
		local boxY = offsetY-2
		local text = self.options[i]
		local textWidth = glGetTextWidth(text) * self.fontSize  + 5+2
		local totalWidth = boxSize + 5 + textWidth+2
		local areaX2 = boxX + totalWidth
		local areaY2 = boxY + boxSize

		if mx >= boxX and mx <= areaX2 and
		  my >= boxY and my <= areaY2 and
		  #group.optionTooltips >= i then
			currentToolTip = group.optionTooltips[i]
			return true
		end

		offsetY = offsetY - (boxSize + spacing)
	end
	return false
end

  function group:Draw()
    glColor(self.bgColor)
    glRect(self.x, self.y, self.x + self.width, self.y + self.height)

    local boxSize = self.fontSize + 4
    local spacing = 6
    local offsetY = self.y + self.height - boxSize

    for i, option in ipairs(self.options) do
      local isSelected = (i == self.selected)
      local boxX = self.x
      local boxY = offsetY
      glColor(0.2, 0.2, 0.2, 1)
      glRect(boxX, boxY, boxX + boxSize, boxY + boxSize)
      if isSelected then
        glColor(0, 0.8, 0.8, 1)
        glRect(boxX + 2, boxY + 2, boxX + boxSize - 2, boxY + boxSize - 2)
      end
      glColor(self.fontColor)
      glText(option, boxX + boxSize + 5, boxY + (boxSize - self.fontSize) / 2 + 2, self.fontSize, "")
      offsetY = offsetY - (boxSize + spacing)
    end
  end

  function group:MousePress(mx, my, buttonNum)
    local boxSize = self.fontSize + 4
    local spacing = 6
    local offsetY = self.y + self.height - boxSize - spacing

    for i = 1, #self.options do
      local boxX = self.x + 5 - 2
      local boxY = offsetY - 2
      local text = self.options[i]
      local textWidth = glGetTextWidth(text) * self.fontSize + 5 + 2
      local totalWidth = boxSize + 5 + textWidth +2
      local areaX2 = boxX + totalWidth
      local areaY2 = boxY + boxSize

      if mx >= boxX and mx <= areaX2 and
         my >= boxY and my <= areaY2 then
        self.selected = i
        self.onSelect(i)
        return true
      end

      offsetY = offsetY - (boxSize + spacing)
    end
    return false
  end

  return group
end
--------------------------------------------------------------------------------
-- Window

local function MakeWindow(params)
  local window = BaseElement(params)
  window.title = params.title or "Window"
  window.dragging = false
  window.fontSize = params.fontSize or 18
  window.fontColor = params.fontColor or {1, 1, 1, 1}
  window.bgColor = params.bgColor or {0.2, 0.2, 0.2, 0.9}
  window.offsetX = 0
  window.offsetY = 0
  window.content = params.content

  local titleBarHeight = 24
  local closeButton = MakeButton{
	bgColor = {0.6, 0.1, 0.0, 1.0}, height = titleBarHeight, text = "Close Widget", onClick = params.onClose
  }
  window.closeButton = closeButton

  function window:Draw()
  

  
    if self.closed then return end
    glColor(self.bgColor)
    glRect(self.x, self.y, self.x + self.width, self.y + self.height)

    -- Draw title bar
    glColor(unpack(self.bgColor))
    glRect(self.x, self.y + self.height - titleBarHeight, self.x + self.width, self.y + self.height + 8)
    glColor(unpack(self.fontColor))
    glText(self.title, self.x + 5, self.y + self.height - titleBarHeight + 7, self.fontSize, "")

    -- Position and draw close button
    self.closeButton.x = self.x + self.width - 104
    self.closeButton.y = self.y + self.height - titleBarHeight + 4
    self.closeButton:Draw()

    -- Position and draw content
    if self.content then
      self.content.x = self.x
      self.content.y = self.y - titleBarHeight
     -- self.content.width = self.width
     -- self.content.height = self.height - titleBarHeight
      self.content:Draw()
    end
	
	if currentToolTip then
	   local mx, my = Spring.GetMouseState()
	   my = my + 6;
	   
	   local tooltipFontSize = 16
	   local border = 2
	   local width = glGetTextWidth(currentToolTip) * tooltipFontSize
	   
	   glColor(0.9, 0.5, 0.1, 0.9) --tiolltip bgColor
       glRect(mx-border, my-border-4, mx + width + border, my + tooltipFontSize + border)
	   
	   glColor(1, 1, 1, 1) --tooltip text color
       glText(currentToolTip, mx, my, tooltipFontSize, "")
	end
	
	local cw, ch = self.content:GetSize()
    self.width = cw
	self.height = ch
  end

  function window:Hover(mx, my)
    self.content:Hover(mx, my)
  end

  function window:MousePress(mx, my, button)
	if self.closeButton:MousePress(mx, my, button) then
		return true
	elseif mx >= self.x and mx <= self.x + self.width and
       my >= self.y + self.height - titleBarHeight and my <= self.y + self.height then
      self.dragging = true
      self.offsetX = mx - self.x
      self.offsetY = my - self.y
      return true
    elseif self.content and self.content:MousePress(mx, my, button) then
      return true
	end
    return false
  end

  function window:MouseMove(mx, my)
    if self.dragging then
      self.x = mx - self.offsetX
      self.y = my - self.offsetY
    end
  end

  function window:MouseRelease()
    self.dragging = false
  end

  return window
end


--------------------------------------------------------------------------------
-- UI Instance


local myUI = nil


function widget:Initialize()
	if slots < 0 then
	  Spring.Echo("[LayoutPlanner] Slot amount cannot be negative")
	  DisableWidget()
	  return
	end
	if slotsPerRow < 1 then
	  Spring.Echo("[LayoutPlanner] Slots per row must be greater than 0")
	  DisableWidget()
	  return
	end

  local drawBox = Box({ orientation = "horizontal", spacing = 6, padding = 4})
    
  drawBox:Add(MakeCheckbox({
    text = "Enable layout draw",
	checked = drawingMode,
	fontSize = 16,
    onToggle = function(state) 
			     drawingMode = not drawingMode
				 Spring.Echo("[LayoutPlanner] Drawing: " .. (drawingMode and "ON" or "OFF"))
			   end
  }))
  
  drawBox:Add(MakeCheckbox({
    text = "Snap",
	checked = snapBuilding,
	tooltip = "Snap the building to the grid according to the selected size",
	fontSize = 16,
    onToggle = function(state) 
			     snapBuilding = not snapBuilding
				 Spring.Echo("[LayoutPlanner] Snap: " .. (snapBuilding and "ON" or "OFF"))
			   end
  }))
  --Building sizes
	local buildingOptions = {}
	local buildingTooltips = {}

	for _, b in ipairs(buildingTypes) do
	  table.insert(buildingOptions, b.name)
	  table.insert(buildingTooltips, b.tooltip)
	end
  
  
  drawBox:Add(MakeSelectionGroup({
    options = buildingOptions,
	selected = currentSizeIndex,
	fontSize = 16,
	optionTooltips = buildingTooltips,
    onSelect = function(i) Spring.Echo("[LayoutPlanner] Current Size: " .. i) currentSizeIndex = i	end
  }))
  
  
  local layoutButtons = Box({ orientation = "horizontal", spacing = 6, padding = 4})
  layoutButtons:Add(MakeButton({
    text = "Clear Layout",
	bgColor = {0.8, 0.4, 0.1, 1.0},
	fontSize = 20,
    onClick = function() ClearLayout() end
  }))
  layoutButtons:Add(MakeButton({
    text = "Render",
	fontSize = 20,
	bgColor = {0.0, 0.2, 0.8, 1.0},
    onClick = function() CollectAndDraw() end
  }))
  
  local content = Box({ 	orientation = "vertical", spacing = 6, padding = 4})
  content:Add(drawBox)
  
  local shiftAndGridBox =  Box({orientation = "horizontal", spacing = 6, padding = 4})
  content:Add(shiftAndGridBox)
  shiftAndGridBox:Add(MakeCheckbox({
    text = "Shift Layout",
	checked = allowTranslationByKeys,
	tooltip = "Whether the (green) layout can be shifted using the keyboard WASD keys",
	fontSize = 16,
    onToggle = function(state) 
			     allowTranslationByKeys = not allowTranslationByKeys
				 Spring.Echo("[LayoutPlanner] Shift: " .. (allowTranslationByKeys and "ON" or "OFF"))
			   end
  }))
  shiftAndGridBox:Add(MakeCheckbox({
    text = "Draw Chunk Grid",
	checked = drawChunkGrid,
	tooltip = "Display a chunk aligned grid around mouse",
	fontSize = 16,
    onToggle = function(state) 
			     drawChunkGrid = not drawChunkGrid
				 Spring.Echo("[LayoutPlanner] Draw chunk grid: " .. (drawChunkGrid and "ON" or "OFF"))
			   end
  }))
  
  content:Add(layoutButtons)
  content:Add(MakeLabel({ bgColor = {0,0,0,0}, text = "Layout Slots:", fontSize = 14 }))
  

	local rows = math.ceil(slots / slotsPerRow)

	for h = 0, rows - 1 do
	  local row = Box({ orientation = "horizontal", spacing = 6, padding = 4 })

	  for i = 1, slotsPerRow do
		local slotId = h * slotsPerRow + i
		if slotId > slots then break end

		local slot = Box({ orientation = "vertical", spacing = 6, padding = 4 })
		slot:Add(MakeButton({
		  text = "Save " .. slotId,
		  bgColor =  {0.15, 0.6, 0.25, 1.0},
		  onClick = function() SaveBuildings(slotId) end
		}))
		slot:Add(MakeButton({
		  text = "Load " .. slotId,
		  bgColor =  {0.3, 0.4, 1, 1.0},
		  onClick = function() LoadBuildings(slotId)  end
		}))
		row:Add(slot)
	  end

	  content:Add(row)
	end
  
  myUI = MakeWindow({
    title = "Layout Planner",
	fontSize = 22,
	fontColor = {1, 0.6, 0.0, 1.0},
    content = content,
    onClose = DisableWidget,
  })
 local vsx, vsy = gl.GetViewSizes()
 local w, h = myUI:GetSize()
  myUI.x, myUI.y = 50, vsy/ 2 - h - 300
end

--------------------------------------------------------------------------------
-- Drawing and Input

function widget:DrawScreen()
  if myUI then
    myUI:Draw()
  end
    -- Placement hint text
  if layoutToPlace then
    local vsx, vsy = gl.GetViewSizes()
	local textWidth = 19 * 18
    gl.Color(1, 1, 0.5, 1)
    gl.Text("Press [R] to rotate", (vsx - textWidth) / 2, vsy * 0.4, 18, "o")
	gl.Text("Press [I] to invert", (vsx - textWidth) / 2, vsy * 0.4-20, 18, "o")
  elseif allowTranslationByKeys then
	local vsx, vsy = gl.GetViewSizes()
	local textWidth = 19 * 18
    gl.Color(1, 1, 0.5, 1)
    gl.Text("Translate layout using WASD keys", (vsx - textWidth) / 2, vsy * 0.4, 18, "o")
  end
  
end

function widget:MousePress(mx, my, button)
  if myUI and myUI:MousePress(mx, my, button) then
	return true
  end
  
  local _, pos = Spring.TraceScreenRay(mx, my, true)
  if not pos then return false end

  local bx, bz = WorldToBU(pos[1], pos[3])
  local size = buildingTypes[currentSizeIndex].size
	
  if layoutToPlace then
    ClearLayout()
    for _, b in ipairs(layoutToPlace) do
      local dx, dz = b.dx - ((loadedMaxX+smallest)/2), b.dz - ((loadedMaxZ+smallest)/2)
      local s = b.size
      local rx, rz = dx, dz
	  local pbx, pbz = math.floor(bx + rx), math.floor(bz + rz)
      selectedBuildings[pbx .. "," .. pbz] = { size = s }
    end
    layoutToPlace = nil
    originalLayoutToPlace = nil
    Spring.Echo("[LayoutPlanner] Layout placed.")
    return true
  elseif drawingMode then 
	if snapBuilding then
	  bx = math.floor(bx / size) * size
	  bz = math.floor(bz / size) * size
	end
    dragging = true
    dragStart = { bx = bx, bz = bz, size = size }
    return true
  end

  return false
end

function widget:MouseRelease(mx, my, button)
  if myUI and myUI:MouseRelease(mx, my, button) then
	return true
  end
  
  if not dragging or not dragStart then return end

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

function widget:MouseMove(x, y, dx, dy, button)
  if myUI then
    return myUI:MouseMove(x, y)
  end
end


function widget:KeyPress(key, mods, isRepeat)
--a 97
--s 115
--w 119
--d 100

--up 273
--down 274
--left 276
--right 275

  if layoutToPlace then  
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

if allowTranslationByKeys and selectedBuildings then
--translation in world space
	local dx, dz = 0, 0 

	if key == 119 then dz = dz + 1 end -- W
	if key == 115 then dz = dz - 1 end -- S
	if key == 97  then dx = dx - 1 end -- A
	if key == 100 then dx = dx + 1 end -- D

	if dx ~= 0 or dz ~= 0 then
	-- d = input as input vector
	-- get camera basis vector in XZ plane
	-- transfrom "d" to camera space
	
		--Normalize translation direcction
		local inputLen = math.sqrt(dx * dx + dz * dz)
		dx = dx / inputLen
		dz = dz / inputLen

		-- Get camera direction and project to XZ plane
		local dirX, _, dirZ = Spring.GetCameraDirection()
		local camLen = math.sqrt(dirX * dirX + dirZ * dirZ)

		-- Avoid divide by zero if camera is looking straight down
		if camLen < 0.0001 then
			Spring.Echo("Camera facing straight down — movement is ambiguous")
			return
		end

		-- Forward direction (projected onto XZ plane)
		local forwardX = dirX / camLen
		local forwardZ = dirZ / camLen

		-- Right vector (perpendicular on XZ plane) (x, y)->(-y, x) cheap 90degrees rotation
		local rightX = -forwardZ
		local rightZ = forwardX

		-- Transform world space t input to world space
		local worldDX = dx * rightX + dz * forwardX
		local worldDZ = dx * rightZ + dz * forwardZ

		-- Snap to nearest integer step
		local tx = math.floor(worldDX + 0.5)
		local tz = math.floor(worldDZ + 0.5)

		if tx ~= 0 or tz ~= 0 then
			TranslateLayout(tx, tz)
		end
	end
end

  
end


function widget:DrawWorld()
  if drawingToGame then return end
  
  gl.DepthTest(true)

  if drawChunkGrid then
  
    local mx, mz = Spring.GetMouseState()
	local _, pos = Spring.TraceScreenRay(mx, mz, true)
	if pos then
		DrawChunkGrid(pos[1], pos[3])
	end
  end

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

    gl.Color(1, 1, 0, 0.4)

    if layoutToPlace then
      for _, b in ipairs(layoutToPlace) do
        local dx, dz = b.dx -  ((loadedMaxX+smallest)/2), b.dz - ((loadedMaxZ+smallest)/2)
		local s = b.size
        local rx, rz = dx, dz
		
        local pbx, pbz = math.floor(bx + rx), math.floor(bz + rz)
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
	  if snapBuilding then
	    bx = math.floor(bx / size) * size
	    bz = math.floor(bz / size) * size
	  end
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

function widget:Update(dt)
  if not renderinToGame then 
  	if myUI then
	  currentToolTip = nil
	  local mx, my = Spring.GetMouseState()
	  myUI:Hover(mx, my)
	end
    return 
  end
  timer = timer + dt
  if timer > 0.1 then
    for i = 1, 10 do
      if #drawLineQueue == 0 then
        Spring.Echo("[LayoutPlanner] All lines rendered..")
		renderinToGame = false
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
