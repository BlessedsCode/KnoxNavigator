from pathlib import Path
import sys, math, time, json
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/runtime'))
from lupa.lua51 import LuaRuntime

MEDIA=ROOT/'KnoxNavigator/42/media'
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('require=function() end; isServer=function() return false end')
loader=lua.eval('function(s) local f,e=loadstring(s); return f~=nil,e end')
files=list((MEDIA/'lua').rglob('*.lua'))
for file in files:
    ok,error=loader(file.read_text(encoding='utf-8'))
    assert ok,(file,error)
print('Lua 5.1 syntax:',len(files),'files pass',flush=True)

readers={};seq=0
def open_data(path):
    global seq
    seq+=1;readers[seq]=(MEDIA.parent/path).open(encoding='utf-8');return seq
def read_data(key):
    line=readers[key].readline()
    return line.rstrip('\n\r') if line else None
def close_data(key): readers.pop(key).close()
lua.globals().open_data=open_data;lua.globals().read_data=read_data;lua.globals().close_data=close_data
lua.execute('''getModFileReader=function(id,path)
 local token=open_data(path)
 return {readLine=function() return read_data(token) end,close=function() close_data(token) end}
end''')
lua.execute((MEDIA/'lua/shared/KnoxNavigator/Core.lua').read_text(encoding='utf-8'))
lua.execute((MEDIA/'lua/client/KnoxNavigator/Router.lua').read_text(encoding='utf-8'))
N=lua.globals().KnoxNavigator;R=N.Router
assert N.loadPOIs()
results=N.search('Gift Shop',6450,5430)
assert len(results)==24,len(results)
assert len(N.search('СУВЕНИРЫ',6450,5430))==24
assert len(N.search('  gift shop\t ',6450,5430))==24
assert N.normalize(' \t\r\n')==''
assert N.normalize('  СУВЕНИРЫ \t')=='сувениры'
lua.execute('''
local original=string.gsub
string.gsub=function() error("normalization must not use Kahlua gsub") end
assert(KnoxNavigator.normalize('  100% GIFT SHOP СУВЕНИРЫ  ')== '100% gift shop сувениры')
assert(KnoxNavigator.normalize('Wholesale 50%')=='wholesale 50%')
KnoxNavigator.pois=nil
assert(KnoxNavigator.loadPOIs())
assert(#KnoxNavigator.search('Gift Shop',6450,5430)==24)
string.gsub=original
''')
assert '%' not in (MEDIA/'lua/client/KnoxNavigator/Options.lua').read_text(encoding='utf-8'), 'Raw percent signs in option labels crash the game Translator'
assert len(N.search('gift shop riverside',6450,5430))>0
assert len(N.search('doesnotexist_xyz',6450,5430))==0
assert all(results[i].distance<=results[i+1].distance for i in range(1,len(results)))
print('POI search: all 24 Gift Shops, Russian aliases, town filter, nearest sorting pass',flush=True)

start=time.perf_counter();R.beginLoad(R)
while R.loading: R.loadTick(R)
print('Road load:',round(time.perf_counter()-start,3),'seconds',flush=True)
route_test=lua.eval('''function(sx,sy,tx,ty)
 local R=KnoxNavigator.Router
 R.error=nil;R.result=nil
 local ok,err=R:start(sx,sy,{x=tx,y=ty,name="test"})
 if not ok then return nil,err end
 local ticks=0
 while R.job do R:tick();ticks=ticks+1 end
 if not R.result then return nil,R.error end
 local route=R.result
 for _,p in ipairs(route.points) do
   local id=math.floor(p.y/R.step)*R.width+math.floor(p.x/R.step)
   assert(R.grid[id],"route leaves the road network")
 end
 return route,ticks
end''')

cases=[('Riverside local',6450,5430,results[1].poi.x,results[1].poi.y),
       ('West Point to Muldraugh',11654,6864,10754,9926),
       ('Rosewood to Muldraugh',8200,11700,10754,9926),
       ('Riverside to West Point',6450,5430,11654,6864),
       ('Muldraugh to Louisville',10754,9926,13077,2238)]
report=[]
for name,sx,sy,tx,ty in cases:
    started=time.perf_counter();route,ticks=route_test(sx,sy,tx,ty)
    if route:
        g=R.guidance(R,route,sx,sy)
        assert g.deviation>=0
        detail={'case':name,'points':len(route.points),'distance':route.remaining[1]+route.connector,'ticks':ticks,'seconds':round(time.perf_counter()-started,3)}
        report.append(detail);print(detail,flush=True)
    else:
        report.append({'case':name,'error':ticks});print('ROUTE FAILED:',name,ticks,flush=True)
assert all('error' not in item for item in report),report
# Synthetic networks test failures and actual bends independent of game map.
lua.execute('''
local R=KnoxNavigator.Router
local originalGrid,originalWidth,originalHeight,originalStep=R.grid,R.width,R.height,R.step
R.width=20;R.height=20;R.step=4;R.grid={}
for x=2,12 do R.grid[2*20+x]=true end
for y=2,12 do R.grid[y*20+12]=true end
R:start(8,8,{x=48,y=48,name="corner"})
while R.job do R:tick() end
assert(R.result and #R.result.points>=3,"corner must be preserved")
local guidance=R:guidance(R.result,8,8)
assert(guidance.text=="Направо","turn instruction must be right")
R.grid[17*20+17]=true;R.result=nil
R:start(8,8,{x=68,y=68,name="disconnected"})
while R.job do R:tick() end
assert(not R.result and R.error,"disconnected roads must not fabricate a route")
R.grid=originalGrid;R.width=originalWidth;R.height=originalHeight;R.step=originalStep
''')
print('Routing: right turn, disconnected roads and road-only paths pass',flush=True)
(ROOT/'tools/test-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('All algorithm checks passed.',flush=True)

# Integration checks exercise the actual mod handlers in a Lua 5.1 runtime.
lua.execute((ROOT/'tools/ui_harness.lua').read_text(encoding='utf-8'))
def get_texture(path):
    p=MEDIA.parent/path
    if not p.exists(): return None
    from PIL import Image
    with Image.open(p) as im: w,h=im.size
    return lua.table_from({'path':str(p),'w':w,'h':h})
lua.globals().PythonTexture=get_texture
lua.execute('''getTexture=function(path)
 local t=PythonTexture(path)
 if t then t.getWidth=function(self) return self.w end;t.getHeight=function(self) return self.h end end
 return t
end''')
for path in ['shared/KnoxNavigator/MapMeta.lua','client/KnoxNavigator/Options.lua','client/KnoxNavigator/UI.lua','client/KnoxNavigator/Main.lua']:
    lua.execute((MEDIA/'lua'/path).read_text(encoding='utf-8'))
lua.execute('''
KnoxNavigator.Router.result=nil;KnoxNavigator.Router.error=nil
Events.OnGameStart.handler()
Events.OnTickEvenPaused.handler()
assert(KnoxNavigator.window.visible,"GPS must show in a vehicle")
TestPlayer.vehicle=nil;Events.OnTickEvenPaused.handler()
assert(not KnoxNavigator.window.visible,"GPS must hide outside the vehicle")
TestPlayer.vehicle={};Events.OnTickEvenPaused.handler()
local map=KnoxNavigator.window.map
for _,mode in ipairs({1,2}) do
 KnoxNavigator.setOption('view',mode)
 for _,point in ipairs({{6450,5430},{6000,5700},{13000,2300}}) do
  local sx,sy=map:screen(point[1],point[2]);local wx,wy=map:world(sx,sy)
  assert(math.abs(wx-point[1])<0.00001 and math.abs(wy-point[2])<0.00001,"map coordinates must round-trip")
 end
 map:render()
end
KnoxNavigator.showSearch()
local search=KnoxNavigator.searchWindow
search.entry:setText('gift shop');search:search()
assert(#search.list.items==24,"UI must list all matches")
search:select(search.list.items[2].item)
assert(KnoxNavigator.previewPOI==search.list.items[2].item.poi,"selection must preview the exact object")
search.list.selected=2;search:routeSelected()
while KnoxNavigator.Router.job do Events.OnTickEvenPaused.handler() end
assert(KnoxNavigator.route,"UI selection must produce a road route")
assert(KnoxNavigator.target.name=='Gift Shop')
KnoxNavigator.headingX=nil
map:render();assert(TestRouteLines>0 and TestLineThickness==1.5,'route must use a thin native line')
local window=KnoxNavigator.window
local expanded=window.height
window.collapseButton.onclick(window)
assert(window.isCollapsed and window.height==window:titleBarHeight() and not map.visible)
window:uncollapse();assert(window.isCollapsed,'hover must not undo manual collapse')
window.pinButton.onclick(window)
assert(not window.isCollapsed and map.visible and window.height==expanded)
local x,y=window:getX(),window:getY()
window.resizeWidget.resizeFunction(window,window.width-60,window.height-60)
assert(map.width==240 and map.height==240 and window:getX()==x and window:getY()==y)
TestSaved=false
window.resizeWidget.onMouseUp(window.resizeWidget,0,0)
assert(TestSaved and KnoxNavigator.option('size')==240)
window:applyOptions();assert(math.abs(window:getX()-x)<0.001 and math.abs(window:getY()-y)<0.001)
window.resizeWidget.resizeFunction(window,window.width,window.height-100)
assert(map.width==220 and map.height==220,'vertical drag must resize square and respect minimum')
window.resizeWidget.onMouseUpOutside(window.resizeWidget,0,0)
window:setX(1600);window:setY(100)
local grip=window.resizeWidget
TestGlobalMouseX=1800;TestGlobalMouseY=350;grip:onMouseDown()
TestGlobalMouseX=1900;TestGlobalMouseY=450;grip:onMouseMove()
assert(map.width==320,'resize must grow at the screen edge')
local stableX=window:getX()
grip:onMouseMoveOutside();assert(map.width==320 and window:getX()==stableX,'stationary pointer must not drift')
TestGlobalMouseX=1840;TestGlobalMouseY=390;grip:onMouseMove()
assert(map.width==260,'reversing drag must follow the original pointer position')
grip:onMouseUpOutside(0,0)
TestFacingAngle=math.pi/2;Events.OnTickEvenPaused.handler()
assert(math.abs(KnoxNavigator.headingX)<0.0001 and math.abs(KnoxNavigator.headingY-1)<0.0001)
TestFacingAngle=math.pi;Events.OnTickEvenPaused.handler()
assert(math.abs(KnoxNavigator.headingX+1)<0.0001,'facing must update without movement')
KnoxNavigator.showSettings()
local settings=KnoxNavigator.settingsWindow
settings.sizeEntry:setText('400');settings.xEntry:setText('80');settings.yEntry:setText('20');settings:apply()
assert(KnoxNavigator.window.map.width==400 and KnoxNavigator.window.map.height==400,"map must stay square")
assert(TestSaved,"settings must persist")
settings:close();assert(not KnoxNavigator.settingsPreview)
Events.OnServerCommand.handler('KnoxNavigator','positions',{players={{name='Me',x=1,y=1},{name='Friend1',x=6200,y=5500},{name='Friend2',x=6300,y=5400},{name='Friend3',x=6100,y=5300}}})
assert(#KnoxNavigator.remotePlayers==3,"all three friends must be visible")
KnoxNavigator.setOption('friends','Friend1, Friend3')
assert(KnoxNavigator.friendAllowed('Friend1') and not KnoxNavigator.friendAllowed('Friend2'))
KnoxNavigator.setOption('friends','')
TestNow=TestNow+10000;Events.OnTickEvenPaused.handler()
assert(#KnoxNavigator.remotePlayers==0,"stale friends must disappear")
KnoxNavigator.cancelRoute();assert(not KnoxNavigator.route and not KnoxNavigator.target)
local N=KnoxNavigator;local originalLine=map.routeLine
local route={points={{x=0,y=0},{x=100,y=0},{x=100,y=100}},remaining={200,100,0},connector=30,target={x=130,y=100}}
N.route=route
local lines={}
map.routeLine=function(self,a,b,r,g,blue,dashed) lines[#lines+1]={a=a,b=b,dashed=dashed} end
for _,view in ipairs({1,2}) do
 N.options:getOption('view'):setValue(view)
 lines={};map:drawRemainingRoute(40,0)
 assert(lines[1].a.x==40 and lines[1].b.x==100,'line must start partway along the current segment')
 local before=N.Router:guidance(route,40,0).total
 lines={};map:drawRemainingRoute(100,35)
 assert(lines[1].a.x==100 and lines[1].a.y==35 and lines[1].b.y==100,'passed road and corner must disappear')
 assert(N.Router:guidance(route,100,35).total<before,'remaining distance must decrease')
 lines={};map:drawRemainingRoute(115,100)
 assert(#lines==1 and lines[1].dashed and lines[1].a.x==115 and lines[1].b.x==130,'final connector must also be consumed')
 lines={};map:drawRemainingRoute(40,12)
 assert(lines[1].a.y==12 and lines[1].b.y==0 and lines[1].dashed,'off-road connector must start at current position')
end
TestPlayer.x=40;TestPlayer.y=0;N.target=route.target;N.lastReroute=TestNow
Events.OnTickEvenPaused.handler();assert(N.guidance.x==40)
TestPlayer.x=100;TestPlayer.y=35;Events.OnTickEvenPaused.handler()
assert(N.guidance.segment==2 and N.guidance.y==35,'tick must update progress immediately')
local originalStart=N.Router.start;local rerouted=false
N.Router.start=function(self,x,y,target) rerouted=x==130 and y==35;return true end
TestPlayer.x=130;TestPlayer.y=35;TestNow=TestNow+2000;Events.OnTickEvenPaused.handler()
assert(rerouted,'deviation must recalculate from the current position')
N.Router.start=originalStart;map.routeLine=originalLine;N.cancelRoute()
''')
print('UI integration: vehicle visibility, both views, 24 matches, chosen destination, settings, three friends, stale positions and cancel pass',flush=True)

# Render the real Map:render draw calls into a reviewable offline preview.
from PIL import Image, ImageDraw, ImageFont
canvas=Image.new('RGB',(720,430),(18,23,26))
font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',12)
clip=None
def color(a,r,g,b): return tuple(max(0,min(255,round(c*255))) for c in (r,g,b))+ (max(0,min(255,round(a*255))),)
def paint(draw):
    layer=Image.new('RGBA',canvas.size);draw(ImageDraw.Draw(layer))
    if clip:
        mask=Image.new('L',canvas.size);ImageDraw.Draw(mask).rectangle(clip,fill=255)
        layer.putalpha(Image.composite(layer.getchannel('A'),Image.new('L',canvas.size),mask))
    canvas.paste(layer,(0,0),layer)
def draw_rect(x,y,w,h,a,r,g,b):
    if w>0 and h>0: paint(lambda d:d.rectangle((x,y,x+w,y+h),fill=color(a,r,g,b)))
def draw_border(x,y,w,h,a,r,g,b): paint(lambda d:d.rectangle((x,y,x+w,y+h),outline=color(a,r,g,b)))
def draw_text(text,x,y,r,g,b,a): paint(lambda d:d.text((x,y),text,font=font,fill=color(a,r,g,b)))
def draw_line(x,y,xx,yy,a,r,g,b,thickness=1): paint(lambda d:d.line((x,y,xx,yy),fill=color(a,r,g,b),width=round(thickness)))
def draw_polygon(x1,y1,x2,y2,x3,y3,x4,y4,r,g,b,a): paint(lambda d:d.polygon([(x1,y1),(x2,y2),(x3,y3),(x4,y4)],fill=color(a,r,g,b)))
def set_clip(x,y,w,h):
    global clip
    clip=(int(x),int(y),int(x+w),int(y+h))
def clear_clip():
    global clip
    clip=None
def draw_texture(path,x,y,w,h):
    with Image.open(path) as original: image=original.resize((max(1,round(w)),max(1,round(h))),Image.Resampling.BILINEAR)
    bounds=clip or (0,0,canvas.width,canvas.height)
    left=max(0,int(x),bounds[0]);top=max(0,int(y),bounds[1]);right=min(canvas.width,int(x)+image.width,bounds[2]);bottom=min(canvas.height,int(y)+image.height,bounds[3])
    if right>left and bottom>top: canvas.paste(image.crop((left-int(x),top-int(y),right-int(x),bottom-int(y))),(left,top))
for name,fn in [('DrawRect',draw_rect),('DrawBorder',draw_border),('DrawText',draw_text),('DrawLine',draw_line),('DrawPolygon',draw_polygon),('DrawClip',set_clip),('ClearClip',clear_clip),('DrawTexture',draw_texture)]: lua.globals()[name]=fn
lua.execute('''
local N=KnoxNavigator
N.setOption('size',300);N.window:setX(20);N.window:setY(50)
N.searchResults=N.search('Gift Shop',6450,5430)
TestPlayer.x=6450;TestPlayer.y=5430
N.beginRoute(N.searchResults[1].poi)
while N.Router.job do Events.OnTickEvenPaused.handler() end
N.guidance=N.Router:guidance(N.route,TestPlayer.x,TestPlayer.y)
N.window.map.cx=6450;N.window.map.cy=5430;N.window.map.zoom=1.7
for _,mode in ipairs({1,2}) do
 N.options:getOption('view'):setValue(mode)
 N.window:setX(mode==1 and 20 or 380)
 N.window.map:render()
 for _,child in ipairs(N.window.children) do
  if child.text then child:drawRect(0,0,child.width,child.height,1,.07,.12,.14);child:drawRectBorder(0,0,child.width,child.height,1,.25,.35,.38);child:drawText(child.text,5,3,1,1,1,1,UIFont.Small) end
 end
end
''')
draw_text('Вид как на сайте',22,16,.9,.95,1,1);draw_text('Вид сверху',382,16,.9,.95,1,1)
draw_text('Предпросмотр отрисовки Lua; это не скриншот из игры.',22,399,.6,.7,.75,1)
canvas.save(ROOT/'preview.png')
print('Review preview:',ROOT/'preview.png',flush=True)
