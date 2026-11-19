local M = {}

function M.project_point(math3d, camera, vertex, width, height)
  local x,y,z = math3d.rotate(vertex[1],vertex[2],vertex[3],camera.yaw,camera.pitch)
  return math3d.project(x,y,z,width,height,camera.zoom,camera.pan_x*width/320,camera.pan_y*height/320)
end

function M.axis_handles(math3d, camera, vertex, width, height)
  local x,y = M.project_point(math3d,camera,vertex,width,height)
  if not x then return {} end
  local handles = {}
  for axis=1,3 do
    local p={vertex[1],vertex[2],vertex[3]}
    p[axis]=p[axis]+0.6
    local ex,ey=M.project_point(math3d,camera,p,width,height)
    if ex then handles[#handles+1]={axis=axis,x=x,y=y,ex=ex,ey=ey} end
  end
  return handles
end

function M.hit_axis(handles, x, y)
  local best, best_distance = nil, 64
  for _, h in ipairs(handles) do
    local dx,dy=h.ex-h.x,h.ey-h.y
    local len=dx*dx+dy*dy
    if len > 16 then
      local t=((x-h.x)*dx+(y-h.y)*dy)/len
      if t>=0.25 and t<=1.15 then
        local px,py=h.x+t*dx,h.y+t*dy
        local d=(px-x)^2+(py-y)^2
        if d<best_distance then best,best_distance=h,d end
      end
    end
  end
  return best
end

function M.drag_axis(handle, start_value, dx, dy, step)
  local vx,vy=handle.ex-handle.x,handle.ey-handle.y
  local length=vx*vx+vy*vy
  if length<16 then return start_value end
  local delta=(dx*vx+dy*vy)/length*0.6
  if step then delta=math.floor(delta/step+0.5)*step end
  return start_value+delta
end
function M.bounds(vertices)
  if #vertices == 0 then return {0,0,0}, 1 end
  local lo={vertices[1][1],vertices[1][2],vertices[1][3]}
  local hi={lo[1],lo[2],lo[3]}
  for _,v in ipairs(vertices) do
    for i=1,3 do lo[i]=math.min(lo[i],v[i]); hi[i]=math.max(hi[i],v[i]) end
  end
  local center={(lo[1]+hi[1])/2,(lo[2]+hi[2])/2,(lo[3]+hi[3])/2}
  return center, math.max(hi[1]-lo[1],hi[2]-lo[2],hi[3]-lo[3],0.000001)/2
end

function M.transform(vertices, pivot, scale, angles)
  local sx,cx=math.sin(angles[1]),math.cos(angles[1])
  local sy,cy=math.sin(angles[2]),math.cos(angles[2])
  local sz,cz=math.sin(angles[3]),math.cos(angles[3])
  for _,v in ipairs(vertices) do
    local x,y,z=(v[1]-pivot[1])*scale[1],(v[2]-pivot[2])*scale[2],(v[3]-pivot[3])*scale[3]
    y,z=y*cx-z*sx,y*sx+z*cx
    x,z=x*cy+z*sy,-x*sy+z*cy
    x,y=x*cz-y*sz,x*sz+y*cz
    v[1],v[2],v[3]=x+pivot[1],y+pivot[2],z+pivot[3]
  end
end

function M.snap_vertex(vertices, source, target)
  if not vertices[source] or not vertices[target] or source==target then return false end
  for i=1,3 do vertices[source][i]=vertices[target][i] end
  return true
end
-- Convert a viewport point to the camera-facing plane through the framing center.
function M.view_plane_point(camera, center, extent, width, height, x, y)
  local scale=math.min(width,height)*camera.zoom/5
  local rx=(x-width/2-camera.pan_x*width/320)/scale
  local ry=-(y-height/2-camera.pan_y*height/320)/scale
  local cp,sp=math.cos(camera.pitch),math.sin(camera.pitch)
  local cy,sy=math.cos(camera.yaw),math.sin(camera.yaw)
  local z=-ry*sp
  return {center[1]+(rx*cy-z*sy)*extent, center[2]+ry*cp*extent, center[3]+(rx*sy+z*cy)*extent}
end

function M.add_textured_quad(mesh, points, rect, texture_width, texture_height)
  local first=#mesh.vertices
  for i=1,4 do mesh.vertices[first+i]=points[i] end
  local u0,v0=rect.x/texture_width,rect.y/texture_height
  local u1,v1=(rect.x+rect.width)/texture_width,(rect.y+rect.height)/texture_height
  local a={first+1,first+2,first+3,uv={{u0,v0},{u1,v0},{u1,v1}}}
  local b={first+1,first+3,first+4,uv={{u0,v0},{u1,v1},{u0,v1}}}
  mesh.faces[#mesh.faces+1]=a; mesh.faces[#mesh.faces+1]=b
end
function M.distance_to_segment(x,y,ax,ay,bx,by)
  local dx,dy=bx-ax,by-ay
  local length=dx*dx+dy*dy
  if length==0 then return (x-ax)^2+(y-ay)^2 end
  local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/length))
  return (x-ax-t*dx)^2+(y-ay-t*dy)^2
end

function M.pick_edge(mesh,math3d,camera,raster,width,height,x,y)
  local face_index=raster.pick(mesh,math3d,camera,width,height,x,y)
  if not face_index then return nil end
  local face=mesh.faces[face_index]
  local best,result=100,nil
  for i=1,3 do
    local a,b=face[i],face[i%3+1]
    local ax,ay=M.project_point(math3d,camera,mesh.vertices[a],width,height)
    local bx,by=M.project_point(math3d,camera,mesh.vertices[b],width,height)
    if ax and bx then
      local d=M.distance_to_segment(x,y,ax,ay,bx,by)
      if d<best then best=d; result={a,b} end
    end
  end
  return result
end
return M
