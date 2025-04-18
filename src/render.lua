---@diagnostic disable: missing-fields

local magic                = require "magic"
local utils                = require "utils"
local vec2                 = require "vector"

local fcPixelcode          = [[
  uniform vec2 playerPos;
  uniform vec2 playerDir;
  uniform vec2 camPlane;
  uniform sampler2D floorTex;
  uniform sampler2D ceilTex;
  uniform float heightScale;

  vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
  {
    // Calculate ray directions for the left and right edges of the screen
    float rayDirX0 = playerDir.x - camPlane.x;
    float rayDirY0 = playerDir.y - camPlane.y;
    float rayDirX1 = playerDir.x + camPlane.x;
    float rayDirY1 = playerDir.y + camPlane.y;
    float aspectRatio = love_ScreenSize.x / love_ScreenSize.y;

    // Calculate the vertical position relative to the center of the screen
    float p = love_PixelCoord.y - love_ScreenSize.y / 2.0;

    // Calculate the distance to the row being rendered
    float posZ = 0.5 * love_ScreenSize.y; // Distance from the player to the projection plane

    // Adjust the distance based on the height scale and aspect ratio
    posZ *= heightScale * aspectRatio;
    float rowDistance = posZ / abs(p);    // Use absolute value to handle both top and bottom halves

    // Interpolate the ray direction based on the horizontal screen position
    float screenPosX = love_PixelCoord.x / love_ScreenSize.x;
    float rayDirX = rayDirX0 + screenPosX * (rayDirX1 - rayDirX0);
    float rayDirY = rayDirY0 + screenPosX * (rayDirY1 - rayDirY0);

    // Calculate the world position of the floor/ceiling at this distance
    float floorX = playerPos.x + rowDistance * rayDirX;
    float floorY = playerPos.y + rowDistance * rayDirY;

    // Calculate texture coordinates
    vec2 texCoord = vec2(floorX - floor(floorX), floorY - floor(floorY));
    vec4 texColor;

    // Determine whether to draw the ceiling or the floor
    if (p < 0.0) {
      texColor = texture2D(ceilTex, texCoord);
    } else {
      texColor = texture2D(floorTex, texCoord);
    }

    // Apply distance-based shading for realism
    float brightness = clamp(1.0 / (rowDistance * rowDistance) * 0.95 + 0.05, 0.0, 1.0);
    return vec4(texColor.rgb * brightness, 1);
  }
]]

local fcVertexcode         = [[
  vec4 position(mat4 transform_projection, vec4 vertex_position)
  {
    return transform_projection * vertex_position;
  }
]]

-- Draws a single vertical line of the wall at the depth given
local wallSpriteVertexcode = [[
  uniform highp float hitDist;
  uniform highp float maxDist;

  vec4 position(mat4 transform_projection, vec4 vertex_position)
  {
    vec4 outpos = transform_projection * vertex_position;
    outpos.z = hitDist / maxDist;
    return outpos;
  }
]]

-- Draws a single vertical line of the wall
local wallSpritePixelcode  = [[
  uniform highp float hitDist;
  uniform highp float maxDepth;

  vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
  {
    vec4 texColor = texture2D(tex, texture_coords);

    if (texColor.a < 0.1) { discard; }

    float brightness = clamp(1.3 / (hitDist * hitDist) * 0.95 + 0.05, 0.0, 1.3);
    return vec4(texColor.rgb * brightness, texColor.a);
  }
]]

local tileWidth            = 32
local tileHeight           = 32

-- Initialize rendering settings here
local function init(tileSetName, tileSize)
  FCShader = love.graphics.newShader(fcPixelcode, fcVertexcode)
  WallShader = love.graphics.newShader(wallSpritePixelcode, wallSpriteVertexcode)

  WallShader:send("maxDist", 32.0) --magic.maxDDA)

  FloorImage = love.graphics.newImage("assets/tilesets/" .. tileSetName .. "/floor.png")
  FloorImage:setFilter("nearest", "nearest")
  FloorImage:setWrap("repeat", "repeat")
  CeilImage = love.graphics.newImage("assets/tilesets/" .. tileSetName .. "/ceil.png")
  CeilImage:setFilter("nearest", "nearest")
  CeilImage:setWrap("repeat", "repeat")

  tileHeight = tileSize
  tileWidth = tileSize
end

-- This function draws the floor and ceiling using a GLSL shader
local function floorCeil(player)
  love.graphics.setDepthMode("always", false)

  FCShader:send("playerPos", { player.pos.x, player.pos.y })
  FCShader:send("playerDir", { player.facing.x, player.facing.y })
  FCShader:send("camPlane", { player.camPlane.x, player.camPlane.y })
  FCShader:send("heightScale", magic.heightScale)
  FCShader:send("floorTex", FloorImage)
  FCShader:send("ceilTex", CeilImage)

  love.graphics.setShader(FCShader)
  love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
  love.graphics.setShader()
end

-- This function draws the sprites in the order of their distance from the player
local function sprites(player, map)
  -- Order the sprites by distance to the player
  -- NOTE: This could be removed if it becomes slow, and we rely on the depth buffer
  -- But sorting allows for semi opaque & alpha in sprites to render correctly
  table.sort(map.sprites, function(a, b)
    return (a.pos - player.pos):length() > (b.pos - player.pos):length()
  end)

  love.graphics.setShader(WallShader)
  love.graphics.setDepthMode("lequal", false) -- would be true if removed sort

  for s = 1, #map.sprites do
    local sprite = map.sprites[s]
    sprite:draw(player.pos, player.facing, player.camPlane, WallShader)
  end

  love.graphics.setShader()
end

-- Cast a ray from the player position in the direction of facing
-- And update the hit list with the cells we hit
local function castRay(pos, dir, map, hitList)
  -- Current grid position
  local gridPos = { x = math.floor(pos.x), y = math.floor(pos.y) }

  -- Length of ray from current position to next x or y-side
  local sideDistX, sideDistY

  -- Length of ray from one x or y-side to next x or y-side
  local deltaDistX = math.abs(1 / dir.x)
  local deltaDistY = math.abs(1 / dir.y)
  local hitDist

  -- What direction to step in x or y direction (either +1 or -1)
  local stepX, stepY

  -- Determine step direction and initial sideDist
  if dir.x < 0 then
    stepX = -1
    sideDistX = (pos.x - gridPos.x) * deltaDistX
  else
    stepX = 1
    sideDistX = (gridPos.x + 1.0 - pos.x) * deltaDistX
  end
  if dir.y < 0 then
    stepY = -1
    sideDistY = (pos.y - gridPos.y) * deltaDistY
  else
    stepY = 1
    sideDistY = (gridPos.y + 1.0 - pos.y) * deltaDistY
  end

  -- Perform DDA
  local hit = false
  local side
  local steps = 0 -- A simple counter to limit the number of DDA loops
  local thinWallMove = 0
  local doorSide = false
  while not hit and steps < magic.maxDDA do
    -- Jump to next grid square, either in x-direction, or in y-direction
    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      gridPos.x = gridPos.x + stepX
      side = 0
    else
      sideDistY = sideDistY + deltaDistY
      gridPos.y = gridPos.y + stepY
      side = 1
    end

    -- Check if ray has hit something
    local cell = map:get(gridPos.x, gridPos.y)
    if cell ~= nil and cell.render then
      hit = true

      -- Code for thin walls, if we hit a wall, we need to make some more checks & adjustments
      if cell ~= nil and cell.thin then
        local offsetPos = vec2:new(pos.x, pos.y)
        local shiftAmount = 0.5

        -- Next pos is checking ahead 0.5 units in the direction of the ray
        local nextPos = vec2:new()
        if side == 0 then
          nextPos.x = offsetPos.x + dir.x * (sideDistX - deltaDistX * (1 - shiftAmount))
          nextPos.y = offsetPos.y + dir.y * (sideDistX - deltaDistX * (1 - shiftAmount))
        else
          nextPos.x = offsetPos.x + dir.x * (sideDistY - deltaDistY * (1 - shiftAmount))
          nextPos.y = offsetPos.y + dir.y * (sideDistY - deltaDistY * (1 - shiftAmount))
        end

        -- This is the *next* cell we hit, we need to check if it matches the current cell
        local nextCellPos = vec2:new(math.floor(nextPos.x), math.floor(nextPos.y))

        -- If we're still in the same cell, we've hit the thin wall, so adjust the hit distance
        if nextCellPos.x == gridPos.x and nextCellPos.y == gridPos.y then
          if side == 0 then
            if dir.x > 0 then
              thinWallMove = ((gridPos.x + shiftAmount) - pos.x) / dir.x - ((gridPos.x) - pos.x) / dir.x
            else
              thinWallMove = ((gridPos.x) - pos.x) / dir.x - ((gridPos.x + shiftAmount) - pos.x) / dir.x
            end
          else
            if dir.y > 0 then
              thinWallMove = ((gridPos.y + shiftAmount) - pos.y) / dir.y - ((gridPos.y) - pos.y) / dir.y
            else
              thinWallMove = ((gridPos.y) - pos.y) / dir.y - ((gridPos.y + shiftAmount) - pos.y) / dir.y
            end
          end
        end

        -- If we're in a different cell, we hit the side of the wall next to the thin wall
        -- NOTE: Thin walls should *ALWAYS* have walls either side of them, so this should be safe
        if (nextCellPos.x ~= gridPos.x or nextCellPos.y ~= gridPos.y) then
          cell = map:get(gridPos.x, gridPos.y)
          if cell and cell.door then
            doorSide = true
          end

          if side == 0 then
            side = 1
            if (dir.y > 0) then
              gridPos.y = gridPos.y + 1
            else
              gridPos.y = gridPos.y - 1
            end
          else
            side = 0
            if (dir.x > 0) then
              gridPos.x = gridPos.x + 1
            else
              gridPos.x = gridPos.x - 1
            end
          end
        end
      end
      -- END of thin wall code
    elseif cell == nil then
      -- Check for out of bounds, should not happen in a closed map
      hit = true
    end

    -- This is a simple counter to put a max distance on the ray
    steps = steps + 1
    if steps >= magic.maxDDA then
      return { worldPos = nil, side = nil, cell = nil }
    end
  end

  -- Finally, calculate distance projected on camera direction
  if side == 0 then
    hitDist = (gridPos.x - pos.x + (1 - stepX) / 2) / dir.x + thinWallMove
  else
    hitDist = (gridPos.y - pos.y + (1 - stepY) / 2) / dir.y + thinWallMove
  end

  -- World position of the hit
  local worldPos = vec2:new(pos.x + dir.x * hitDist, pos.y + dir.y * hitDist)
  local cellHitPos = vec2:new(utils.frac(worldPos.x), utils.frac(worldPos.y))
  local cell = map:get(gridPos.x, gridPos.y)

  -- Check if the cell is thin, we might need to carry on
  if cell.thin then
    hitList[#hitList + 1] = {
      worldPos = worldPos,
      side = side,
      cell = cell,
      cellHitPos = cellHitPos,
      doorSide = doorSide,
    }

    return castRay(worldPos, dir, map, hitList)
  end

  -- If we hit a wall, return the cell and the side we hit
  hitList[#hitList + 1] = {
    worldPos = worldPos,
    side = side,
    cell = cell,
    cellHitPos = cellHitPos,
    doorSide = doorSide,
  }
end

-- This function draws the walls using raycasting
local function walls(player, map)
  love.graphics.setDepthMode("lequal", true)
  love.graphics.setShader(WallShader)

  -- Draw walls using raycasting
  for screenX = 0, love.graphics.getWidth() do
    -- Create a ray from the player position to the screen position
    local ray = player:getRay(screenX)

    -- Cast the ray from player pos, out to find the list of hits
    local hitList = {}
    castRay(player.pos, ray, map, hitList)

    for i = #hitList, 1, -1 do
      local hit = hitList[i]

      if hit.cell and hit.cell.render and hit.cell.texture then
        local hitDist = hit.worldPos - player.pos
        hitDist = hitDist:length()

        -- Correct the distance to the wall for the fish-eye effect
        local wallHeightDist = hitDist *
            math.cos(math.atan2(ray.y, ray.x) - math.atan2(player.facing.y, player.facing.x))

        -- The height of the wall on the screen is inversely proportional to the distance
        local wallHeight = love.graphics.getHeight() / wallHeightDist
        -- Correct for the aspect ratio of the screen
        wallHeight = wallHeight * (love.graphics.getWidth() / love.graphics.getHeight()) * magic.heightScale
        local wallY = (love.graphics.getHeight() - wallHeight) / 2

        -- Texture mapping, get fraction of the world pos to use as the u coordinate of the texture
        local texU
        if hit.side == 0 then
          texU = hit.cellHitPos.y
        else
          texU = hit.cellHitPos.x
        end

        local tex = hit.cell.texture
        if hit.doorSide then
          tex = map.tileSet.images["door_sides"]
        end

        -- Call the shader to draw the wall slice (1 px wide) at the correct position & distance
        WallShader:send("hitDist", hitDist)
        local quad = love.graphics.newQuad(texU * tileWidth, 0, 1, tileHeight, tileWidth, tileHeight)
        love.graphics.draw(tex, quad, screenX, wallY, 0, 1, wallHeight / tileHeight, 0, 0)
      end
    end
  end
end

return {
  init = init,
  walls = walls,
  floorCeil = floorCeil,
  sprites = sprites
}
