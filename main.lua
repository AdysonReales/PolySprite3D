local function open_viewport(plugin)
  if not app.isUIAvailable then return end
  local function module(name) return dofile(app.fs.joinPath(plugin.path,"src",name..".lua")) end
  local math3d, meshes, raster, editor = module("math3d"),module("mesh"),module("rasterizer"),module("editor")
  local mesh=meshes.cube(); meshes.default_uv(mesh)
  local camera={yaw=0.65,pitch=-0.4,zoom=0.8,pan_x=0,pan_y=0}
  local center,extent=editor.bounds(mesh.vertices)
  local pivot={0,0,0}
  local texture,selected_vertex,selected_face,snap_source=nil,nil,nil,nil
  local tile_rect,place_x,place_y=nil,nil,nil
  local texture_source,placed_tiles=nil,0
  local texture_frame,paint_overlay,paint_dirty=nil,nil,false
  local selected_edge,selection_kind=nil,nil
  local tool,mode,profile="Orbit","Flat","Mouse"
  local layout="Build"
  local atlas_x,atlas_y,atlas_w,atlas_h=0,0,0,0
  local atlas_start_x,atlas_start_y=nil,nil
  local wire_views={}
  local dlg,preview,display_mesh,handles,outline
  local action,drag_handle,drag_start,down_x,down_y,last_x,last_y
  local w,h,left,top=600,480,220,32
  local white=Color{r=255,g=241,b=229}; local panel=Color{r=79,g=65,b=93}
  local background=Color{r=24,g=20,b=29}; local button=Color{r=111,g=91,b=126}
  local active=Color{r=255,g=0,b=77}; local accent=Color{r=255,g=204,b=170}
  local workspace=Color{r=129,g=114,b=151}; local wire=Color{r=218,g=207,b=220}
  local grid=Color{r=104,g=91,b=119}; local black=Color{r=0,g=0,b=0}
  local axis_colors={Color{r=255,g=75,b=75},Color{r=85,g=225,b=105},Color{r=85,g=160,b=255}}
  local buttons={
    {"Import OBJ",8,28},{"Export OBJ",112,28},
    {"Primitive",8,58},{"Clear Mesh",112,58},
    {"Select Current File",8,88,198},
    {"Place Tile",8,118},{"Orbit",112,118},
    {"Vertices",8,148},{"Face UV",112,148},
    {"Scale",8,178},{"Rotate",112,178},
    {"Pivot",8,208},{"Snap",112,208},
    {"Front",8,250},{"Side",112,250},
    {"Top",8,280},{"Frame",112,280},
    {"Camera",8,322},{"XYZ",112,322},
    {"Render",8,352},{"Bake",112,352},
    {"Edges",8,382},{"Faces",112,382},
    {"Paint",8,412},{"Save Paint",112,412}
  }
  local function reset_frame()
    center,extent=editor.bounds(mesh.vertices)
    camera.pan_x,camera.pan_y=0,0
    camera.zoom=0.8
  end
  local function display_data()
    local verts={}
    for i,v in ipairs(mesh.vertices) do verts[i]={(v[1]-center[1])/extent,(v[2]-center[2])/extent,(v[3]-center[3])/extent} end
    return {vertices=verts,faces=mesh.faces}
  end
  local function draw_model(width,height,shown)
    local img=Image(width,height,ColorMode.RGB)
    local base=app.fgColor
    raster.render(display_mesh,math3d,camera,width,height,mode,
      function(x,y,p) img:drawPixel(x,y,p) end,
      function(shade) return app.pixelColor.rgba(math.floor(base.red*shade),math.floor(base.green*shade),math.floor(base.blue*shade),255) end,
      texture and function(u,v)
        local x=math.max(0,math.min(texture.width-1,math.floor(u*texture.width)))
        local y=math.max(0,math.min(texture.height-1,math.floor(v*texture.height)))
        local p=texture:getPixel(x,y)
        if app.pixelColor.rgbaA(p)>0 then return p end
      end or nil)
    if shown and (tool=="Vertices" or tool=="Snap") then
      local normal=app.pixelColor.rgba(255,255,255,255)
      local chosen=app.pixelColor.rgba(255,90,60,255)
      for i,v in ipairs(display_mesh.vertices) do
        local x,y=editor.project_point(math3d,camera,v,width,height)
        if x then
          x,y=math.floor(x+0.5),math.floor(y+0.5)
          for dy=-2,2 do for dx=-2,2 do
            if x+dx>=0 and x+dx<width and y+dy>=0 and y+dy<height then img:drawPixel(x+dx,y+dy,(i==selected_vertex or i==snap_source) and chosen or normal) end
          end end
        end
      end
    end
    return img
  end
  local function update()
    display_mesh=display_data()
    wire_views={{},{},{}}
    for i,v in ipairs(display_mesh.vertices) do
      wire_views[1][i]={150+v[1]*82,120+v[3]*82}
      wire_views[2][i]={150+v[1]*82,120-v[2]*82}
      wire_views[3][i]={150+v[3]*82,120-v[2]*82}
    end
    if texture then
      local scale=math.min(600/texture.width,240/texture.height)
      atlas_w=math.max(1,math.floor(texture.width*scale)); atlas_h=math.max(1,math.floor(texture.height*scale))
      atlas_x=left+math.floor((600-atlas_w)/2); atlas_y=top+240+math.floor((240-atlas_h)/2)
    end
    preview=draw_model(w,h,true)
    handles={}; outline=nil
    if tool=="Vertices" and selected_vertex then handles=editor.axis_handles(math3d,camera,display_mesh.vertices[selected_vertex],w,h) end
    if (tool=="Face UV" or selection_kind=="face") and selected_face then
      for _,t in ipairs(raster.project(display_mesh,math3d,camera,w,h)) do if t.face_index==selected_face then outline=t; break end end
    end
    dlg:repaint()
  end
  local function choose_file(save, callback)
    local box=Dialog{title=save and "Export OBJ" or "Import OBJ"}
    box:file{id="file",label="OBJ",save=save,open=not save,filetypes={"obj"}}
    box:button{text=save and "Export" or "Import",onclick=function()
      local filename=box.data.file
      if not filename or filename=="" then return end
      callback(filename); box:close()
    end}
    box:button{text="Cancel"}; box:show{wait=false}
  end
  local function number_dialog(title, labels, defaults, callback)
    local box=Dialog{title=title}
    for i=1,#labels do box:number{id="n"..i,label=labels[i],text=string.format("%.4f",defaults[i]),decimals=4} end
    box:button{text="Apply",onclick=function()
      local values={}
      for i=1,#labels do
        values[i]=box.data["n"..i]
        if not values[i] then app.alert("Enter a number for "..labels[i]); return end
      end
      callback(values); box:close(); update()
    end}
    box:button{text="Cancel"}; box:show{wait=false}
  end
  local function do_button(name)
    if (name=="Import OBJ" or name=="Primitive" or name=="Clear Mesh") and paint_dirty then
      app.alert("Save Paint before replacing the current mesh."); return
    end
    if name=="Import OBJ" then
      choose_file(false,function(filename)
        local f,err=io.open(filename,"r"); if not f then app.alert(tostring(err)); return end
        local data=f:read("*a"); f:close()
        local result,msg=meshes.parse_obj(data); if not result then app.alert(msg); return end
        mesh=result; meshes.default_uv(mesh); selected_vertex=nil; selected_face=nil; snap_source=nil; selected_edge=nil; selection_kind=nil; placed_tiles=0; texture_source=nil; paint_overlay=nil; paint_dirty=false
        reset_frame(); pivot={center[1],center[2],center[3]}; update()
      end)
    elseif name=="Export OBJ" then
      choose_file(true,function(filename)
        local f,err=io.open(filename,"w"); if not f then app.alert(tostring(err)); return end
        local ok,msg=f:write(meshes.export_obj(mesh)); local closed,close_err=f:close()
        if not ok or not closed then app.alert(tostring(msg or close_err)) end
      end)
    elseif name=="Primitive" then
      local box=Dialog{title="Choose Primitive"}
      for _,kind in ipairs({"Cube","Pyramid","Cylinder","Plane"}) do
        box:button{text=kind,onclick=function()
          mesh=meshes[kind:lower()](); meshes.default_uv(mesh); pivot={0,0,0}; placed_tiles=0; texture_source=nil
          selected_vertex=nil; selected_face=nil; snap_source=nil; reset_frame(); box:close(); update()
        end}
      end
      box:show{wait=false}
    elseif name=="Clear Mesh" then
      local box=Dialog{title="Clear current mesh?"}
      box:label{text="This removes the current mesh from the editor."}
      box:button{text="Clear",onclick=function()
        mesh={vertices={},faces={}}; selected_vertex=nil; selected_face=nil; snap_source=nil; selected_edge=nil; selection_kind=nil; placed_tiles=0; texture_source=nil; paint_overlay=nil; paint_dirty=false
        center={0,0,0}; extent=1; pivot={0,0,0}; camera.pan_x=0; camera.pan_y=0
        box:close(); update()
      end}
      box:button{text="Cancel"}; box:show{wait=false}
    elseif name=="Select Current File" then
      local sprite,frame=app.activeSprite,app.activeFrame
      if not sprite or not frame then app.alert("Open an Aseprite sprite first, then select a rectangular area on its canvas."); return end
      if placed_tiles>0 and texture_source~=sprite then
        app.alert("Placed tiles use another texture file. Export and clear the mesh, or open a new editor to use a different file."); return
      end
      if paint_dirty then app.alert("Save Paint before loading or refreshing a texture."); return end
      local bounds=sprite.selection.bounds
      local x,y,x2,y2=0,0,sprite.width,sprite.height
      if bounds.width>0 and bounds.height>0 then
        x=math.max(0,bounds.x); y=math.max(0,bounds.y)
        x2=math.min(sprite.width,bounds.x+bounds.width); y2=math.min(sprite.height,bounds.y+bounds.height)
      end
      if x2<=x or y2<=y then app.alert("The selection is outside the sprite."); return end
      texture=Image(sprite.width,sprite.height,ColorMode.RGB); texture:drawSprite(sprite,frame.frameNumber)
      texture_frame=frame; paint_overlay=Image(sprite.width,sprite.height,ColorMode.RGB); paint_dirty=false
      tile_rect={x=x,y=y,width=x2-x,height=y2-y}; texture_source=sprite; mode="Texture"; tool="Place Tile"; layout="Texture"
    elseif name=="Save Paint" then
      if not paint_dirty or not paint_overlay or not texture_source or not texture_frame then app.alert("There are no unsaved painted pixels."); return end
      local ok,err=pcall(function()
        app.transaction("PolySprite3D: Save Paint",function()
          local layer=texture_source:newLayer(); layer.name="PolySprite3D Paint"
          texture_source:newCel(layer,texture_frame,paint_overlay,Point(0,0))
        end)
      end)
      if not ok then app.alert("Could not save paint. Is the source sprite still open? "..tostring(err)); return end
      paint_overlay=Image(texture.width,texture.height,ColorMode.RGB); paint_dirty=false; app.refresh()
    elseif name=="Paint" then
      if not texture then app.alert("Select Current File first to load a texture."); return end
      tool="Paint"; layout="3D"; mode="Texture"
    elseif name=="Edges" or name=="Faces" then tool=name; layout="3D"
    elseif name=="Place Tile" then
      if not tile_rect then app.alert("Select Current File first."); return end
      tool=name; layout="3D"; snap_source=nil
    elseif name=="Orbit" or name=="Vertices" or name=="Face UV" then tool=name; layout="3D"; snap_source=nil
    elseif name=="Snap" then tool="Snap"; layout="3D"; selected_vertex=nil; snap_source=nil
    elseif name=="Scale" then
      number_dialog("Scale model around pivot",{"X factor","Y factor","Z factor"},{1,1,1},function(v) editor.transform(mesh.vertices,pivot,v,{0,0,0}) end)
    elseif name=="Rotate" then
      number_dialog("Rotate model around pivot",{"X degrees","Y degrees","Z degrees"},{0,0,0},function(v)
        editor.transform(mesh.vertices,pivot,{1,1,1},{math.rad(v[1]),math.rad(v[2]),math.rad(v[3])})
      end)
    elseif name=="Pivot" then
      number_dialog("Set model pivot",{"X","Y","Z"},pivot,function(v) pivot=v end)
    elseif name=="XYZ" then
      if not selected_vertex then app.alert("Select a vertex first."); return end
      number_dialog("Selected vertex",{"X","Y","Z"},mesh.vertices[selected_vertex],function(v) mesh.vertices[selected_vertex]=v end)
    elseif name=="Render" then
      local box=Dialog{title="Render mode"}
      for _,m in ipairs({"Flat","Unlit","Wireframe","Texture"}) do box:button{text=m,onclick=function() mode=m; box:close(); update() end} end
      box:show{wait=false}
    elseif name=="Front" then camera.yaw=0; camera.pitch=0
    elseif name=="Side" then camera.yaw=math.pi/2; camera.pitch=0
    elseif name=="Top" then camera.yaw=0; camera.pitch=-math.pi/2
    elseif name=="Frame" then reset_frame()
    elseif name=="Camera" then profile=profile=="Mouse" and "Trackpad" or "Mouse"
    elseif name=="Bake" then
      local sprite,frame=app.activeSprite,app.activeFrame
      if not sprite or not frame then app.alert("Open an RGB sprite first."); return end
      if sprite.colorMode~=ColorMode.RGB then app.alert("Bake currently supports RGB sprites only."); return end
      local img=draw_model(sprite.width,sprite.height,false)
      app.transaction("PolySprite3D: Bake Frame",function()
        local layer=sprite:newLayer(); layer.name="PolySprite3D"; sprite:newCel(layer,frame,img,Point(0,0))
      end); app.refresh()
    end
    update()
  end
  local function nearest(x,y)
    local best,index=100,nil
    for i,v in ipairs(display_mesh.vertices) do
      local px,py,depth=editor.project_point(math3d,camera,v,w,h)
      if px then
        local d=(px-x)^2+(py-y)^2
        if d<best then
          local _,_,_,front=raster.hit(display_mesh,math3d,camera,w,h,px,py)
          if not front or depth<=front+0.0001 then best=d; index=i end
        end
      end
    end
    return index
  end
  local function sample_texture(u,v)
    if not texture then return nil end
    local x=math.max(0,math.min(texture.width-1,math.floor(u*texture.width)))
    local y=math.max(0,math.min(texture.height-1,math.floor(v*texture.height)))
    local pixel=texture:getPixel(x,y)
    if app.pixelColor.rgbaA(pixel)>0 then return pixel end
  end
  local function paint_at(x,y)
    local face,u,v=raster.hit(display_mesh,math3d,camera,w,h,x,y)
    if not face or not u or not v then return end
    local f=mesh.faces[face]
    if selection_kind=="face" and face~=selected_face then return end
    if selection_kind=="vertex" then
      local found=false; for i=1,3 do if f[i]==selected_vertex then found=true end end
      if not found then return end
      local px,py=editor.project_point(math3d,camera,display_mesh.vertices[selected_vertex],w,h)
      if not px or (x-px)^2+(y-py)^2>144 then return end
    elseif selection_kind=="edge" then
      local found_a,found_b=false,false
      for i=1,3 do if f[i]==selected_edge[1] then found_a=true end; if f[i]==selected_edge[2] then found_b=true end end
      if not found_a or not found_b then return end
      local ax,ay=editor.project_point(math3d,camera,display_mesh.vertices[selected_edge[1]],w,h)
      local bx,by=editor.project_point(math3d,camera,display_mesh.vertices[selected_edge[2]],w,h)
      if not ax or not bx or editor.distance_to_segment(x,y,ax,ay,bx,by)>144 then return end
    end
    local tx=math.max(0,math.min(texture.width-1,math.floor(u*texture.width)))
    local ty=math.max(0,math.min(texture.height-1,math.floor(v*texture.height)))
    local c=app.fgColor; local pixel=app.pixelColor.rgba(c.red,c.green,c.blue,c.alpha)
    texture:drawPixel(tx,ty,pixel); paint_overlay:drawPixel(tx,ty,pixel); paint_dirty=true
  end
  dlg=Dialog{title="PolySprite3D Model Editor"}
  dlg:canvas{id="editor",width=832,height=530,autoscaling=false,
    onpaint=function(ev)
      local gc=ev.context
      gc.color=background; gc:fillRect(Rectangle(0,0,832,530))
      gc.color=panel; gc:fillRect(Rectangle(0,0,214,530))
      gc.color=active; gc:fillRect(Rectangle(0,0,832,24))
      gc.color=white; gc:fillText("POLYSPRITE 3D",8,5)
      gc:fillText("BUILD",left+8,5); gc:fillText("3D EDIT",left+95,5); gc:fillText("TEXTURE",left+190,5)
      gc:fillText("["..layout.."]",left+335,5)
      for _,b in ipairs(buttons) do
        gc.color=(b[1]==tool) and active or button; gc:fillRect(Rectangle(b[2],b[3],b[4] or 96,25))
        gc.color=white; gc:fillText(b[1],b[2]+6,b[3]+5)
      end
      local status=tool=="Paint" and (paint_dirty and "Paint: unsaved" or "Paint with foreground") or (tool=="Place Tile" and "Drag to place tile" or (tool=="Snap" and (snap_source and "Click target vertex" or "Click source vertex") or (selection_kind=="edge" and "Edge selected" or (selection_kind=="face" and "Face selected" or (selected_vertex and ("Vertex: "..selected_vertex) or "No selection")))))
      gc:fillText(status,8,451)
      gc:fillText("Camera: "..profile.."  "..mode,8,473)
      gc:fillText("Pivot: "..string.format("%.1f %.1f %.1f",pivot[1],pivot[2],pivot[3]),8,495)
      if layout=="Build" then
        local locations={{left,top},{left,top+240},{left+300,top+240}}
        local names={"TOP","FRONT","SIDE"}
        for n,loc in ipairs(locations) do
          local ox,oy=loc[1],loc[2]
          gc.color=workspace; gc:fillRect(Rectangle(ox,oy,298,238))
          gc.color=grid; gc:beginPath(); gc:moveTo(ox+150,oy); gc:lineTo(ox+150,oy+238); gc:moveTo(ox,oy+120); gc:lineTo(ox+298,oy+120); gc:stroke()
          gc.color=wire; gc:beginPath()
          for _,f in ipairs(display_mesh.faces) do
            local a,b,c=wire_views[n][f[1]],wire_views[n][f[2]],wire_views[n][f[3]]
            if a and b and c then gc:moveTo(ox+a[1],oy+a[2]); gc:lineTo(ox+b[1],oy+b[2]); gc:lineTo(ox+c[1],oy+c[2]); gc:lineTo(ox+a[1],oy+a[2]) end
          end
          gc:stroke(); gc.color=white; gc:fillText(names[n],ox+6,oy+6)
        end
        gc.color=black; gc:fillRect(Rectangle(left+300,top,300,240))
        if preview then gc:drawImage(preview,0,0,w,h,left+300,top,300,240) end
        gc.color=white; gc:fillText("3D PREVIEW",left+306,top+6)
      elseif layout=="Texture" then
        gc.color=black; gc:fillRect(Rectangle(left,top,600,480))
        if preview then gc:drawImage(preview,0,0,w,h,left+150,top,300,240) end
        if texture then
          gc:drawImage(texture,0,0,texture.width,texture.height,atlas_x,atlas_y,atlas_w,atlas_h)
          if tile_rect then
            gc.color=accent; gc:strokeRect(Rectangle(atlas_x+math.floor(tile_rect.x*atlas_w/texture.width),atlas_y+math.floor(tile_rect.y*atlas_h/texture.height),math.max(1,math.ceil(tile_rect.width*atlas_w/texture.width)),math.max(1,math.ceil(tile_rect.height*atlas_h/texture.height))))
          end
        else gc.color=white; gc:fillText("Select Current File to load a texture",left+10,top+270) end
      else
        gc.color=black; gc:fillRect(Rectangle(left,top,w,h))
        if preview then gc:drawImage(preview,left,top) end
      end
      if layout=="3D" then for _,a in ipairs(handles) do
        gc.color=axis_colors[a.axis]; gc:beginPath(); gc:moveTo(left+a.x,top+a.y); gc:lineTo(left+a.ex,top+a.ey); gc:stroke()
      end end
      if layout=="3D" and action=="place" and place_x and place_y then
        gc.color=accent; gc:strokeRect(Rectangle(left+math.min(down_x,place_x),top+math.min(down_y,place_y),math.abs(place_x-down_x),math.abs(place_y-down_y)))
      end
      if layout=="3D" and selected_edge and selection_kind=="edge" then
        local a,b=display_mesh.vertices[selected_edge[1]],display_mesh.vertices[selected_edge[2]]
        if a and b then
          local x1,y1=editor.project_point(math3d,camera,a,w,h); local x2,y2=editor.project_point(math3d,camera,b,w,h)
          if x1 and x2 then gc.color=accent; gc:beginPath(); gc:moveTo(left+x1,top+y1); gc:lineTo(left+x2,top+y2); gc:stroke() end
        end
      end
      if layout=="3D" and outline then
        gc.color=accent; gc:beginPath(); gc:moveTo(left+outline.a.x,top+outline.a.y); gc:lineTo(left+outline.b.x,top+outline.b.y); gc:lineTo(left+outline.c.x,top+outline.c.y); gc:closePath(); gc:stroke()
      end
    end,
    onmousedown=function(ev)
      if ev.y<24 and ev.x>=left then
        local x=ev.x-left
        if x<85 then layout="Build" elseif x<180 then layout="3D" elseif x<285 then layout="Texture" end
        action=nil; update(); return
      end
      if ev.x<214 then
        for _,b in ipairs(buttons) do if ev.x>=b[2] and ev.x<b[2]+(b[4] or 96) and ev.y>=b[3] and ev.y<b[3]+25 then do_button(b[1]); return end end
        return
      end
      local x,y=ev.x-left,ev.y-top
      if x<0 or x>=w or y<0 or y>=h then return end
      if layout=="Build" then
        if x<300 and y<240 then camera.yaw=0; camera.pitch=-math.pi/2
        elseif x<300 then camera.yaw=0; camera.pitch=0
        elseif y>=240 then camera.yaw=math.pi/2; camera.pitch=0 end
        layout="3D"; update(); return
      elseif layout=="Texture" then
        if texture and ev.button==MouseButton.LEFT and ev.x>=atlas_x and ev.x<atlas_x+atlas_w and ev.y>=atlas_y and ev.y<atlas_y+atlas_h then
          action="atlas"; atlas_start_x=ev.x; atlas_start_y=ev.y
        end
        return
      end
      down_x,down_y,last_x,last_y=x,y,x,y; action=nil
      local l=ev.button==MouseButton.LEFT; local m=ev.button==MouseButton.MIDDLE; local r=ev.button==MouseButton.RIGHT
      if profile=="Mouse" and m then action=ev.shiftKey and "pan" or ((ev.ctrlKey or ev.metaKey) and "zoom" or "orbit")
      elseif profile=="Trackpad" and r then action="pan"
      elseif profile=="Trackpad" and l and ev.shiftKey then action="zoom"
      elseif l and tool=="Place Tile" and tile_rect then
        action="place"; place_x=x; place_y=y
      elseif l and tool=="Vertices" then
        local hit=editor.hit_axis(handles,x,y)
        if hit and selected_vertex then drag_handle=hit; drag_start=mesh.vertices[selected_vertex][hit.axis]; action="axis"
        else selected_vertex=nearest(x,y); selection_kind=selected_vertex and "vertex" or nil; selected_edge=nil; selected_face=nil; update() end
      elseif l and tool=="Edges" then
        selected_edge=editor.pick_edge(display_mesh,math3d,camera,raster,w,h,x,y)
        selection_kind=selected_edge and "edge" or nil; selected_vertex=nil; selected_face=nil; update()
      elseif l and tool=="Faces" then
        selected_face=raster.hit(display_mesh,math3d,camera,w,h,x,y,mode=="Texture" and sample_texture or nil)
        selection_kind=selected_face and "face" or nil; selected_vertex=nil; selected_edge=nil; update()
      elseif l and tool=="Paint" then
        action="paint"; paint_at(x,y); update()
      elseif l and tool=="Snap" then
        local index=nearest(x,y)
        if index then
          if not snap_source then snap_source=index
          elseif editor.snap_vertex(mesh.vertices,snap_source,index) then selected_vertex=snap_source; snap_source=nil end
          update()
        end
      elseif l and tool=="Face UV" then
        selected_face=raster.pick(display_mesh,math3d,camera,w,h,x,y); selection_kind=selected_face and "face" or nil; selected_vertex=nil; selected_edge=nil; update()
        if selected_face and texture then
          number_dialog("Texture rectangle in pixels",{"X","Y","Width","Height"},{0,0,texture.width,texture.height},function(v)
            if v[3]<=0 or v[4]<=0 then app.alert("Width and height must be positive."); return end
            local f=mesh.faces[selected_face]; local base=f.base_uv or f.uv; f.base_uv=base; f.uv={}
            for i=1,3 do f.uv[i]={(v[1]+base[i][1]*v[3])/texture.width,(v[2]+base[i][2]*v[4])/texture.height} end
          end)
        end
      elseif profile=="Trackpad" and l then action="orbit" end
    end,
    onmousemove=function(ev)
      if not action then return end
      if action=="atlas" and texture then
        local function coord(value,start,size,limit)
          return math.max(0,math.min(limit-1,math.floor((value-start)*limit/size)))
        end
        local x0=coord(atlas_start_x,atlas_x,atlas_w,texture.width); local x1=coord(ev.x,atlas_x,atlas_w,texture.width)
        local y0=coord(atlas_start_y,atlas_y,atlas_h,texture.height); local y1=coord(ev.y,atlas_y,atlas_h,texture.height)
        tile_rect={x=math.min(x0,x1),y=math.min(y0,y1),width=math.abs(x1-x0)+1,height=math.abs(y1-y0)+1}
        dlg:repaint(); return
      end
      local x,y=ev.x-left,ev.y-top; local dx,dy=x-last_x,y-last_y; last_x,last_y=x,y
      if action=="paint" then
        local distance=math.max(math.abs(dx),math.abs(dy)); local steps=math.max(1,math.ceil(distance/3))
        for i=1,steps do paint_at(x-dx+dx*i/steps,y-dy+dy*i/steps) end
        update(); return
      elseif action=="place" then place_x=x; place_y=y; dlg:repaint(); return
      elseif action=="pan" then camera.pan_x=camera.pan_x+dx*320/w; camera.pan_y=camera.pan_y+dy*320/h
      elseif action=="zoom" then camera.zoom=math.max(0.05,math.min(10,camera.zoom*math.exp(-dy*0.01)))
      elseif action=="orbit" then camera.yaw=camera.yaw+dx*0.01; camera.pitch=camera.pitch+dy*0.01
      elseif action=="axis" and selected_vertex then
        local step=(ev.ctrlKey or ev.metaKey) and 0.1 or (ev.shiftKey and 0.25 or nil)
        local val=editor.drag_axis(drag_handle,drag_start/extent,x-down_x,y-down_y,step and step/extent or nil)*extent
        mesh.vertices[selected_vertex][drag_handle.axis]=val
      end
      update()
    end,
    onmouseup=function(ev)
      if action=="atlas" and texture then
        local function coord(value,start,size,limit) return math.max(0,math.min(limit-1,math.floor((value-start)*limit/size))) end
        local x0=coord(atlas_start_x,atlas_x,atlas_w,texture.width); local x1=coord(ev.x,atlas_x,atlas_w,texture.width)
        local y0=coord(atlas_start_y,atlas_y,atlas_h,texture.height); local y1=coord(ev.y,atlas_y,atlas_h,texture.height)
        tile_rect={x=math.min(x0,x1),y=math.min(y0,y1),width=math.abs(x1-x0)+1,height=math.abs(y1-y0)+1}
        action=nil; tool="Place Tile"; dlg:repaint(); return
      end
      if action=="place" and tile_rect then
        local x,y=ev.x-left,ev.y-top
        if math.abs(x-down_x)<4 or math.abs(y-down_y)<4 then
          x=down_x+80; y=down_y+80*tile_rect.height/tile_rect.width
        end
        local x0,x1=math.min(down_x,x),math.max(down_x,x)
        local y0,y1=math.min(down_y,y),math.max(down_y,y)
        local points={}
        points[1]=editor.view_plane_point(camera,center,extent,w,h,x0,y0)
        points[2]=editor.view_plane_point(camera,center,extent,w,h,x1,y0)
        points[3]=editor.view_plane_point(camera,center,extent,w,h,x1,y1)
        points[4]=editor.view_plane_point(camera,center,extent,w,h,x0,y1)
        editor.add_textured_quad(mesh,points,tile_rect,texture.width,texture.height); placed_tiles=placed_tiles+1
        action=nil; place_x=nil; place_y=nil; update(); return
      end
      action=nil
    end,
    onwheel=function(ev) if layout=="3D" and ev.x>=left and ev.x<left+w and ev.y>=top and ev.y<top+h and ev.deltaY~=0 then camera.zoom=math.max(0.05,math.min(10,camera.zoom*(ev.deltaY<0 and 1.15 or 1/1.15))); update() end end,
    onkeydown=function(ev)
      if ev.code=="KeyV" then tool="Vertices"; layout="3D" elseif ev.code=="KeyX" then tool="Snap"; layout="3D"; snap_source=nil
      elseif ev.code=="KeyS" then do_button("Scale") elseif ev.code=="KeyR" then do_button("Rotate") elseif ev.code=="KeyP" then do_button("Pivot") end
      update()
    end
  }
  update(); dlg:show{wait=false}
end
function init(plugin)
  if not app.isUIAvailable then return end
  plugin:newCommand{id="PolySprite3D",title="PolySprite3D",group="file_scripts",onclick=function() open_viewport(plugin) end}
end
function exit(plugin) end
