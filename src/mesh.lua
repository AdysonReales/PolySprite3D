local M = {}

function M.cube()
  return { vertices = {
    {-1,-1,-1}, {1,-1,-1}, {1,1,-1}, {-1,1,-1},
    {-1,-1,1}, {1,-1,1}, {1,1,1}, {-1,1,1}
  }, faces = {
    {1,3,2}, {1,4,3}, {5,6,7}, {5,7,8},
    {1,2,6}, {1,6,5}, {4,8,7}, {4,7,3},
    {1,5,8}, {1,8,4}, {2,3,7}, {2,7,6}
  } }
end

function M.pyramid()
  return { vertices = {{-1,-1,-1},{1,-1,-1},{1,-1,1},{-1,-1,1},{0,1,0}},
    faces = {{1,2,3},{1,3,4},{1,5,2},{2,5,3},{3,5,4},{4,5,1}} }
end

function M.plane()
  return { vertices = {{-1,0,-1},{1,0,-1},{1,0,1},{-1,0,1}}, faces = {{1,3,2},{1,4,3}} }
end

function M.cylinder()
  local vertices, faces = {}, {}
  local n = 12
  for i = 0, n - 1 do
    local angle = i * 2 * math.pi / n
    local x, z = math.cos(angle), math.sin(angle)
    vertices[#vertices + 1] = {x,-1,z}
    vertices[#vertices + 1] = {x,1,z}
  end
  vertices[#vertices + 1] = {0,-1,0}
  vertices[#vertices + 1] = {0,1,0}
  for i = 0, n - 1 do
    local a, b = 2 * i + 1, 2 * ((i + 1) % n) + 1
    faces[#faces + 1] = {a,b,b+1}
    faces[#faces + 1] = {a,b+1,a+1}
    faces[#faces + 1] = {2*n+1,b,a}
    faces[#faces + 1] = {2*n+2,a+1,b+1}
  end
  return { vertices = vertices, faces = faces }
end

-- Project each triangle onto its dominant plane. UVs are stored per corner.
function M.default_uv(mesh)
  for _, f in ipairs(mesh.faces) do
    if not f.uv then
      local a,b,c = mesh.vertices[f[1]],mesh.vertices[f[2]],mesh.vertices[f[3]]
      local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
      local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
      local nx,ny,nz=math.abs(uy*vz-uz*vy),math.abs(uz*vx-ux*vz),math.abs(ux*vy-uy*vx)
      local ax,ay=1,2
      if nx>=ny and nx>=nz then ax,ay=3,2 elseif ny>=nz then ax,ay=1,3 end
      f.uv={}
      for i=1,3 do
        local v=mesh.vertices[f[i]]
        f.uv[i]={(v[ax]+1)/2, 1-(v[ay]+1)/2}
      end
    end
  end
end

-- Parse positions, texture coordinates and polygon faces; normals are ignored.
function M.parse_obj(text)
  local vertices, faces, texcoords = {}, {}, {}
  for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
    line = line:gsub("#.*$", "")
    local tag, rest = line:match("^%s*(%S+)%s+(.+)$")
    if tag == "v" then
      local x, y, z = rest:match("^(%S+)%s+(%S+)%s+(%S+)")
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      if not x or not y or not z then return nil, "Invalid vertex" end
      vertices[#vertices + 1] = {x,y,z}
    elseif tag == "vt" then
      local u,v = rest:match("^(%S+)%s+(%S+)")
      u,v=tonumber(u),tonumber(v)
      if not u or not v then return nil, "Invalid texture coordinate" end
      texcoords[#texcoords+1]={u,1-v}
    elseif tag == "f" then
      local indices, uvs = {}, {}
      for token in rest:gmatch("%S+") do
        local index = tonumber(token:match("^([+-]?%d+)"))
        if not index or index == 0 then return nil, "Invalid face index" end
        if index < 0 then index = #vertices + index + 1 end
        if index < 1 or index > #vertices then return nil, "Face index out of range" end
        indices[#indices + 1] = index
        local uv_index=tonumber(token:match("^[+-]?%d+/([+-]?%d+)"))
        if uv_index then
          if uv_index < 0 then uv_index=#texcoords+uv_index+1 end
          if not texcoords[uv_index] then return nil, "Texture index out of range" end
          uvs[#indices]=texcoords[uv_index]
        end
      end
      if #indices < 3 then return nil, "Face needs at least three vertices" end
      for i = 2, #indices - 1 do
        local face={indices[1], indices[i], indices[i+1]}
        if uvs[1] and uvs[i] and uvs[i+1] then face.uv={uvs[1],uvs[i],uvs[i+1]} end
        faces[#faces + 1] = face
      end
    end
  end
  if #vertices == 0 or #faces == 0 then return nil, "No mesh faces found" end
  return { vertices = vertices, faces = faces }
end
function M.export_obj(mesh)
  local lines = {"# PolySprite3D OBJ"}
  for _,v in ipairs(mesh.vertices) do
    lines[#lines+1]=string.format("v %.9g %.9g %.9g",v[1],v[2],v[3])
  end
  local texture_index=0
  for _,f in ipairs(mesh.faces) do
    if f.uv then
      for i=1,3 do
        lines[#lines+1]=string.format("vt %.9g %.9g",f.uv[i][1],1-f.uv[i][2])
      end
    end
  end
  for _,f in ipairs(mesh.faces) do
    if f.uv then
      lines[#lines+1]=string.format("f %d/%d %d/%d %d/%d",f[1],texture_index+1,f[2],texture_index+2,f[3],texture_index+3)
      texture_index=texture_index+3
    else lines[#lines+1]=string.format("f %d %d %d",f[1],f[2],f[3]) end
  end
  return table.concat(lines,"\n").."\n"
end
return M
