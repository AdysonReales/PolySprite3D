local command, canvas
local old_dofile=dofile
local placed=0
local chosen_rect
function dofile(path)
  local result=old_dofile(path)
  if path:match("src/editor.lua$") then
    local add=result.add_textured_quad
    result.add_textured_quad=function(mesh,points,rect,w,h)
      placed=placed+1; chosen_rect=rect; return add(mesh,points,rect,w,h)
    end
  end
  return result
end
app={isUIAvailable=true,fgColor={red=255,green=255,blue=255,alpha=255},fs={joinPath=function(...) return table.concat({...},"/") end},pixelColor={rgba=function() return 1 end,rgbaA=function() return 255 end}}
ColorMode={RGB=1}; MouseButton={LEFT=1,RIGHT=2,MIDDLE=3}
Color=function(t) return t end
Rectangle=function(...) return {...} end
local sampled=0
Image=function(w,h) return {width=w,height=h,drawPixel=function() end,drawSprite=function() end,getPixel=function() sampled=sampled+1; return 1 end} end
local saved=0
app.activeSprite={width=32,height=32,selection={bounds={x=4,y=4,width=8,height=8}},
  newLayer=function() return {} end,
  newCel=function() saved=saved+1 end}
app.transaction=function(_,fn) fn() end
app.refresh=function() end
app.alert=function(message) error(message) end
Point=function(x,y) return {x=x,y=y} end
app.activeFrame={frameNumber=1}
Dialog=function()
  local d={data={}}
  function d:canvas(t) canvas=t; return self end
  function d:show() end
  function d:repaint() end
  return d
end
local p={path=".",newCommand=function(self,c) command=c end}
dofile("main.lua"); init(p); assert(command); command.onclick(); assert(canvas)
local gc={fillRect=function() end,strokeRect=function() end,fillText=function() end,drawImage=function() end,beginPath=function() end,moveTo=function() end,lineTo=function() end,stroke=function() end,closePath=function() end}
canvas.onpaint({context=gc})
canvas.onmousedown({x=120,y=125,button=MouseButton.LEFT})
canvas.onpaint({context=gc})
canvas.onwheel({x=400,y=200,deltaY=-1})
canvas.onkeydown({code="KeyX"})
canvas.onpaint({context=gc})
canvas.onmousedown({x=40,y=100,button=MouseButton.LEFT})
canvas.onpaint({context=gc})
canvas.onmousedown({x=410,y=280,button=MouseButton.LEFT})
canvas.onmousemove({x=450,y=320})
canvas.onmouseup({x=450,y=320})
canvas.onmousedown({x=30,y=130,button=MouseButton.LEFT})
canvas.onmousedown({x=300,y=100,button=MouseButton.LEFT})
canvas.onmousemove({x=380,y=180})
canvas.onpaint({context=gc})
canvas.onmouseup({x=380,y=180})
assert(sampled>0 and placed==1 and chosen_rect.width>1 and chosen_rect.width<32)
canvas.onmousedown({x=150,y=390,button=MouseButton.LEFT})
canvas.onmousedown({x=350,y=140,button=MouseButton.LEFT})
canvas.onmousedown({x=30,y=420,button=MouseButton.LEFT})
canvas.onmousedown({x=350,y=140,button=MouseButton.LEFT})
canvas.onmouseup({x=350,y=140})
canvas.onmousedown({x=150,y=420,button=MouseButton.LEFT})
assert(saved==1)
canvas.onmousedown({x=230,y=10,button=MouseButton.LEFT})
canvas.onpaint({context=gc})
print("Editor dialog and tile placement smoke test passed")
