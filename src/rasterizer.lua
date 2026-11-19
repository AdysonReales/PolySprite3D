local M = {}

-- Returns triangles in back-to-front order in screen space.
function M.project(mesh, math3d, camera, width, height)
  local points, triangles = {}, {}
  for i, v in ipairs(mesh.vertices) do
    local x, y, z = math3d.rotate(v[1], v[2], v[3], camera.yaw, camera.pitch)
    local sx, sy, depth = math3d.project(x, y, z, width, height, camera.zoom, camera.pan_x * width / 320, camera.pan_y * height / 320)
    points[i] = {x=sx, y=sy, depth=depth, rx=x, ry=y, rz=z}
  end
  for face_index, f in ipairs(mesh.faces) do
    local a, b, c = points[f[1]], points[f[2]], points[f[3]]
    if a.x and b.x and c.x then
      local ux, uy, uz = b.rx-a.rx, b.ry-a.ry, b.rz-a.rz
      local vx, vy, vz = c.rx-a.rx, c.ry-a.ry, c.rz-a.rz
      local nx, ny, nz = uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx
      local len = math.sqrt(nx*nx+ny*ny+nz*nz)
      if len > 0 then
        local light = math.max(0, (nx*-0.3 + ny*0.6 + nz*-0.74) / len)
        triangles[#triangles+1] = {a=a,b=b,c=c, depth=(a.depth+b.depth+c.depth)/3,
          shade=0.3 + light*0.7, face_index=face_index}
      end
    end
  end
  table.sort(triangles, function(a,b) return a.depth > b.depth end)
  return triangles
end

local function edge(a, b, x, y)
  return (x-a.x)*(b.y-a.y) - (y-a.y)*(b.x-a.x)
end

-- Return the closest surface at a screen position and its perspective-correct UV.
function M.hit(mesh, math3d, camera, width, height, x, y, sample_texture)
  local triangles=M.project(mesh,math3d,camera,width,height)
  local best_depth,best_face,best_u,best_v
  for _,t in ipairs(triangles) do
    local a,b,c=t.a,t.b,t.c
    local area=edge(a,b,c.x,c.y)
    if area ~= 0 then
      local e1,e2,e3=edge(a,b,x,y),edge(b,c,x,y),edge(c,a,x,y)
      if (e1>=0 and e2>=0 and e3>=0) or (e1<=0 and e2<=0 and e3<=0) then
        local wa,wb,wc=e2/area/a.depth,e3/area/b.depth,e1/area/c.depth
        local sum=wa+wb+wc
        if sum>0 then
          local depth=1/sum
          local uv=mesh.faces[t.face_index].uv
          local u,v
          if uv then u=(uv[1][1]*wa+uv[2][1]*wb+uv[3][1]*wc)/sum; v=(uv[1][2]*wa+uv[2][2]*wb+uv[3][2]*wc)/sum end
          if (not sample_texture or not uv or sample_texture(u,v)) and (not best_depth or depth<best_depth) then
            best_depth,best_face,best_u,best_v=depth,t.face_index,u,v
          end
        end
      end
    end
  end
  return best_face,best_u,best_v,best_depth
end
function M.pick(mesh, math3d, camera, width, height, x, y)
  return M.hit(mesh,math3d,camera,width,height,x,y)
end

function M.render(mesh, math3d, camera, width, height, mode, set_pixel, color, sample_texture)
  local triangles = M.project(mesh, math3d, camera, width, height)
  local depths = {}
  local function line(a,b, value)
    local x0,y0,x1,y1 = math.floor(a.x+0.5),math.floor(a.y+0.5),math.floor(b.x+0.5),math.floor(b.y+0.5)
    local dx,dy = math.abs(x1-x0),math.abs(y1-y0)
    local sx,sy = x0<x1 and 1 or -1,y0<y1 and 1 or -1
    local err = dx-dy
    while true do
      if x0>=0 and y0>=0 and x0<width and y0<height then set_pixel(x0,y0,value) end
      if x0==x1 and y0==y1 then break end
      local e = 2*err
      if e > -dy then err=err-dy; x0=x0+sx end
      if e < dx then err=err+dx; y0=y0+sy end
    end
  end
  for _, t in ipairs(triangles) do
    local value = color(mode == "Flat" and t.shade or 1)
    if mode == "Wireframe" then
      line(t.a,t.b,value); line(t.b,t.c,value); line(t.c,t.a,value)
    else
      local a,b,c = t.a,t.b,t.c
      local area = edge(a,b,c.x,c.y)
      if area ~= 0 then
        local minx = math.max(0, math.floor(math.min(a.x,b.x,c.x)))
        local maxx = math.min(width-1, math.ceil(math.max(a.x,b.x,c.x)))
        local miny = math.max(0, math.floor(math.min(a.y,b.y,c.y)))
        local maxy = math.min(height-1, math.ceil(math.max(a.y,b.y,c.y)))
        for y = miny,maxy do
          for x = minx,maxx do
            local e1,e2,e3 = edge(a,b,x+0.5,y+0.5),edge(b,c,x+0.5,y+0.5),edge(c,a,x+0.5,y+0.5)
            if (e1>=0 and e2>=0 and e3>=0) or (e1<=0 and e2<=0 and e3<=0) then
              local wa,wb,wc = e2/area/a.depth, e3/area/b.depth, e1/area/c.depth
              local sum=wa+wb+wc
              local depth=1/sum
              local index=y*width+x+1
              local pixel = value
              if mode == "Texture" and sample_texture then
                local f = mesh.faces[t.face_index]
                local uv = f.uv
                if uv then
                  local u = (uv[1][1]*wa+uv[2][1]*wb+uv[3][1]*wc)/sum
                  local v = (uv[1][2]*wa+uv[2][2]*wb+uv[3][2]*wc)/sum
                  pixel = sample_texture(u,v)
                end
              end
              if pixel and sum>0 and (not depths[index] or depth<depths[index]) then
                depths[index]=depth; set_pixel(x,y,pixel)
              end
            end
          end
        end
      end
    end
  end
end
return M
