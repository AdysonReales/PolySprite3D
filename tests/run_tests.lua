local math3d = dofile("src/math3d.lua")
local mesh = dofile("src/mesh.lua")
local rasterizer = dofile("src/rasterizer.lua")
local function near(a,b) assert(math.abs(a-b) < 0.00001) end
local x,y,z = math3d.rotate(1,2,3,0,0)
near(x,1); near(y,2); near(z,3)
local sx,sy = math3d.project(0,0,0,100,80,2,0,0)
near(sx,50); near(sy,40)
assert(math3d.project(0,0,-5,100,80,2,0,0) == nil)
for _, name in ipairs({"cube","pyramid","plane","cylinder"}) do
  local m = mesh[name]()
  assert(#m.vertices > 0 and #m.faces > 0)
  for _, face in ipairs(m.faces) do
    for _, i in ipairs(face) do assert(m.vertices[i]) end
  end
end
local obj, err = mesh.parse_obj("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf -4 -3 -2 -1\n")
assert(obj, err); assert(#obj.faces == 2)
assert(not mesh.parse_obj("v 0 0 0\nf 1 2 3\n"))
local camera = {yaw=0.65,pitch=-0.4,zoom=2.2,pan_x=0,pan_y=0}
for _, mode in ipairs({"Flat","Unlit","Wireframe"}) do
  local count = 0
  rasterizer.render(mesh.cube(), math3d, camera, 64,64,mode,
    function(px,py,value) assert(px>=0 and px<64 and py>=0 and py<64 and value); count=count+1 end,
    function(shade) return shade end)
  assert(count>0, mode .. " rendered nothing")
end
print("All PolySprite3D tests passed")
local textured = assert(mesh.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0 0\nvt 1 0\nvt 0 1\nf 1/1 2/2 3/3\n"))
assert(textured.faces[1].uv[1][2] == 1)
assert(textured.faces[1].uv[3][2] == 0)
mesh.default_uv(textured)
local sampled = 0
rasterizer.render(textured, math3d, {yaw=0,pitch=0,zoom=2,pan_x=0,pan_y=0}, 64,64,"Texture",
  function(x,y,value) assert(value == 123) end,
  function() return 99 end,
  function(u,v) assert(u >= -0.01 and u <= 1.01 and v >= -0.01 and v <= 1.01); sampled=sampled+1; return 123 end)
assert(sampled>0)
assert(rasterizer.pick(textured, math3d, {yaw=0,pitch=0,zoom=2,pan_x=0,pan_y=0}, 64,64, 35,29) == 1)
print("Texture and face selection tests passed")
local editor = dofile("src/editor.lua")
local camera2={yaw=0,pitch=0,zoom=1.35,pan_x=0,pan_y=0}
local handles=editor.axis_handles(math3d,camera2,{0,0,0},320,320)
assert(#handles == 3)
local h=handles[1]
assert(editor.hit_axis(handles,(h.x+h.ex)/2,(h.y+h.ey)/2).axis == 1)
local moved=editor.drag_axis(h,2,h.ex-h.x,h.ey-h.y,nil)
near(moved,2.6)
near(editor.drag_axis(h,2,(h.ex-h.x)*0.6,(h.ey-h.y)*0.6,0.25),2.25)
local roundtrip=assert(mesh.parse_obj(mesh.export_obj(textured)))
assert(#roundtrip.faces == 1 and #roundtrip.vertices == 3)
near(roundtrip.faces[1].uv[3][2],textured.faces[1].uv[3][2])
print("Editor controls and OBJ round-trip tests passed")
local c,e=editor.bounds({{-2,-1,4},{2,3,8}})
near(c[1],0); near(c[2],1); near(c[3],6); near(e,2)
local verts={{2,0,0},{1,1,0}}
editor.transform(verts,{1,0,0},{2,1,1},{0,0,math.pi/2})
near(verts[1][1],1); near(verts[1][2],2)
near(verts[2][1],0); near(verts[2][2],0)
assert(editor.snap_vertex(verts,1,2)); near(verts[1][1],verts[2][1]); near(verts[1][2],verts[2][2])
assert(not editor.snap_vertex(verts,1,1))
print("Framing, pivot transforms and vertex snap tests passed")
local face_mesh={vertices={},faces={}}
local c3={0,0,0}
local cam3={yaw=0.3,pitch=-0.2,zoom=1,pan_x=0,pan_y=0}
local points={}
points[1]=editor.view_plane_point(cam3,c3,1,600,480,200,100)
points[2]=editor.view_plane_point(cam3,c3,1,600,480,300,100)
points[3]=editor.view_plane_point(cam3,c3,1,600,480,300,200)
points[4]=editor.view_plane_point(cam3,c3,1,600,480,200,200)
for i,p in ipairs(points) do
  local x,y=editor.project_point(math3d,cam3,p,600,480)
  near(x,(i==1 or i==4) and 200 or 300); near(y,i<=2 and 100 or 200)
end
editor.add_textured_quad(face_mesh,points,{x=4,y=8,width=16,height=8},64,32)
assert(#face_mesh.vertices==4 and #face_mesh.faces==2)
near(face_mesh.faces[1].uv[1][1],4/64); near(face_mesh.faces[1].uv[3][2],16/32)
local reimport=assert(mesh.parse_obj(mesh.export_obj(face_mesh)))
near(reimport.faces[1].uv[1][1],4/64)
print("Tile placement and UV export tests passed")
local overlap={vertices={
  {-1,-1,-1},{1,-1,1},{0,1,0},
  {-1,-1,1},{1,-1,-1},{0,1,0}
},faces={
  {1,2,3,uv={{0.2,0},{0.2,0},{0.2,0}}},
  {4,5,6,uv={{0.8,0},{0.8,0},{0.8,0}}}
}}
local cam4={yaw=0,pitch=0,zoom=2,pan_x=0,pan_y=0}
local pixels={}
rasterizer.render(overlap,math3d,cam4,80,80,"Texture",function(x,y,v) pixels[y*80+x]=v end,function() return -1 end,function(u) return u<0.5 and 1 or 2 end)
for y=30,45 do
  for x=30,50 do
    local face=rasterizer.hit(overlap,math3d,cam4,80,80,x+0.5,y+0.5)
    if face then assert(pixels[y*80+x]==face, "depth selection disagrees with rasterized pixel") end
  end
end
assert(editor.distance_to_segment(5,1,0,0,10,0)==1)
print("Overlapping triangles and selection geometry tests passed")
