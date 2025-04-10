local vec2 = {}

function vec2:new(x, y)
  local obj = { x = x or 0, y = y or 0 }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function vec2:clone()
  return vec2:new(self.x, self.y)
end

function vec2:add(v)
  self.x = self.x + v.x
  self.y = self.y + v.y
end

function vec2:addNew(v)
  return vec2:new(self.x + v.x, self.y + v.y)
end

function vec2:__add(v)
  return vec2:new(self.x + v.x, self.y + v.y)
end

-- Subtract another vector from this vector in place
function vec2:sub(v)
  self.x = self.x - v.x
  self.y = self.y - v.y
end

-- Subtract another vector from this vector and return a new vector
function vec2:subNew(v)
  return vec2:new(self.x - v.x, self.y - v.y)
end

-- Subtract another vector from this vector and return a new vector
function vec2:__sub(v)
  return vec2:new(self.x - v.x, self.y - v.y)
end

-- Scale the vector in place by a scalar
function vec2:scale(f)
  self.x = self.x * f
  self.y = self.y * f
end

-- Scale the vector by a scalar and return a new scaled vector
function vec2:scaleNew(f)
  return vec2:new(self.x * f, self.y * f)
end

-- multiplication with a scalar or another vector
function vec2:__mul(o)
  if type(o) == "number" then
    return vec2:new(self.x * o, self.y * o)
  elseif getmetatable(o) == vec2 then
    return vec2:new(self.x * o.x, self.y * o.y)
  else
    error("Invalid operand for vec2 multiplication")
  end
end

-- Normalize the vector in place
function vec2:normalize()
  local length = math.sqrt(self.x ^ 2 + self.y ^ 2)
  if length > 0 then
    self.x = self.x / length
    self.y = self.y / length
  end
end

-- Normalize the vector and return a new normalized vector
function vec2:normalizeNew()
  local length = math.sqrt(self.x ^ 2 + self.y ^ 2)
  if length > 0 then
    return vec2:new(self.x / length, self.y / length)
  else
    return vec2:new(0, 0)
  end
end

-- Returns the dot product of two 2D vectors
function vec2:dot(v)
  return self.x * v.x + self.y * v.y
end

-- Returns the cross product of two 2D vectors
function vec2:cross(v)
  return self.x * v.y - self.y * v.x
end

-- Returns the length of the vector
function vec2:length()
  return math.sqrt(self.x ^ 2 + self.y ^ 2)
end

-- Returns the distance between two vectors
function vec2:distance(v)
  return math.sqrt((self.x - v.x) ^ 2 + (self.y - v.y) ^ 2)
end

-- Rotate the vector by a given angle in degrees
function vec2:rotate(deg)
  local rad = math.rad(deg)
  local cos = math.cos(rad)
  local sin = math.sin(rad)

  local x = self.x * cos - self.y * sin
  local y = self.x * sin + self.y * cos

  self.x = x
  self.y = y

  return self
end

-- tostring method for debugging
function vec2:__tostring()
  return string.format("vec2(%f, %f)", self.x, self.y)
end

function vec2:castRay(dir, hitFunc)
  -- current map position
  local mapPos = { x = math.floor(self.x), y = math.floor(self.y) }

  -- length of ray from current position to next x or y-side
  local sideDistX, sideDistY

  -- length of ray from one x or y-side to next x or y-side
  local deltaDistX = math.abs(1 / dir.x)
  local deltaDistY = math.abs(1 / dir.y)
  local hitDist

  -- what direction to step in x or y direction (either +1 or -1)
  local stepX, stepY

  -- determine step direction and initial sideDist
  if dir.x < 0 then
    stepX = -1
    sideDistX = (self.x - mapPos.x) * deltaDistX
  else
    stepX = 1
    sideDistX = (mapPos.x + 1.0 - self.x) * deltaDistX
  end
  if dir.y < 0 then
    stepY = -1
    sideDistY = (self.y - mapPos.y) * deltaDistY
  else
    stepY = 1
    sideDistY = (mapPos.y + 1.0 - self.y) * deltaDistY
  end

  -- perform DDA
  local hit = false
  local side
  local steps = 0
  while not hit and steps < 16 do
    -- jump to next map square, either in x-direction, or in y-direction
    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      mapPos.x = mapPos.x + stepX
      side = 0
    else
      sideDistY = sideDistY + deltaDistY
      mapPos.y = mapPos.y + stepY
      side = 1
    end

    -- check if ray has hit something
    hit = hitFunc(mapPos.x, mapPos.y)

    steps = steps + 1
  end

  -- calculate distance projected on camera direction
  if side == 0 then
    hitDist = (mapPos.x - self.x + (1 - stepX) / 2) / dir.x
  else
    hitDist = (mapPos.y - self.y + (1 - stepY) / 2) / dir.y
  end

  -- world position of the hit
  local worldPos = vec2:new(self.x + dir.x * hitDist, self.y + dir.y * hitDist)

  return { dist = hitDist, worldPos = worldPos, side = side, mapX = mapPos.x, mapY = mapPos.y }
end

return vec2
