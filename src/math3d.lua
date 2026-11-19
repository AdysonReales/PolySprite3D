local M = {}

function M.rotate(x, y, z, yaw, pitch)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local rx, rz = x * cy + z * sy, -x * sy + z * cy
  return rx, y * cp - rz * sp, y * sp + rz * cp
end

function M.project(x, y, z, width, height, zoom, pan_x, pan_y)
  local depth = z + 5
  if depth <= 0.1 then return nil end
  local scale = math.min(width, height) * zoom / depth
  return width * 0.5 + pan_x + x * scale, height * 0.5 + pan_y - y * scale, depth
end

return M
