require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISScrollingListBox"
require "KnoxNavigator/Core"
require "KnoxNavigator/MapMeta"
require "KnoxNavigator/Options"
require "KnoxNavigator/Router"
local N=KnoxNavigator

KnoxNavigatorMap = ISPanel:derive("KnoxNavigatorMap")
local Map=KnoxNavigatorMap
function Map:new(x,y,w,h)
    local o=ISPanel.new(self,x,y,w,h)
    o.zoom=2.6;o.textures={};o.cx=10620;o.cy=9550;o.pan=false;o.backgroundColor={r=.04,g=.06,b=.055,a=1}
    return o
end
function Map:project(x,y)
    local meta=N.MapMeta
    if N.option("view")==1 then
        return (x-y)*meta.sqr/(2*meta.scale),(x+y)*meta.sqr/(4*meta.scale)
    end
    return x*meta.topTile/meta.block,y*meta.topTile/meta.block
end
function Map:screen(x,y)
    local px,py=self:project(x,y);local cx,cy=self:project(self.cx,self.cy)
    return self.width/2+(px-cx)*self.zoom,self.height/2+(py-cy)*self.zoom
end
function Map:world(x,y)
    local cx,cy=self:project(self.cx,self.cy)
    local px=cx+(x-self.width/2)/self.zoom;local py=cy+(y-self.height/2)/self.zoom
    if N.option("view")==1 then
        local a=px*2*N.MapMeta.scale/N.MapMeta.sqr;local b=py*4*N.MapMeta.scale/N.MapMeta.sqr
        return (a+b)/2,(b-a)/2
    end
    return px*N.MapMeta.block/N.MapMeta.topTile,py*N.MapMeta.block/N.MapMeta.topTile
end
function Map:loadTexture(path)
    if self.textures[path]==nil then self.textures[path]=getTexture(path) or false end
    return self.textures[path]
end
function Map:drawTiles()
    local meta=N.MapMeta;local isIso=N.option("view")==1
    local tile=isIso and meta.tile or meta.topTile
    local cx,cy=self:project(self.cx,self.cy)
    if isIso then cx=cx+meta.x0/meta.scale;cy=cy+meta.y0/meta.scale end
    local left=cx-self.width/(2*self.zoom);local top=cy-self.height/(2*self.zoom)
    local folder=isIso and "iso" or "top"
    if self.zoom<.6 then
        local overview=self:loadTexture("media/textures/KnoxNavigator/"..folder.."_overview.png")
        if overview then
            self:drawTextureScaled(overview,-left*self.zoom,-top*self.zoom,
                overview:getWidth()*16*self.zoom,overview:getHeight()*16*self.zoom,1,1,1,1)
            return
        end
    end
    local factor=1
    if meta.highFactor then
        factor=meta.highFactor
        folder=isIso and "iso_high" or "top_high"
        tile=(isIso and meta.highTile or meta.highTopTile)/factor
    end
    local firstX,lastX=math.floor(left/tile),math.floor((left+self.width/self.zoom)/tile)
    local firstY,lastY=math.floor(top/tile),math.floor((top+self.height/self.zoom)/tile)
    for x=firstX,lastX do
        for y=firstY,lastY do
            if x>=0 and y>=0 then
                local texture=self:loadTexture("media/textures/KnoxNavigator/"..folder.."/"..x.."_"..y..".png")
                if texture then
                    self:drawTextureScaled(texture,(x*tile-left)*self.zoom,(y*tile-top)*self.zoom,
                        texture:getWidth()*self.zoom/factor,texture:getHeight()*self.zoom/factor,1,1,1,1)
                end
            end
        end
    end
end
function Map:marker(x,y,label,r,g,b,large)
    local sx,sy=self:screen(x,y)
    if sx< -8 or sy< -8 or sx>self.width+8 or sy>self.height+8 then return end
    local size=large and 10 or 7
    self:drawRect(sx-size/2-2,sy-size/2-2,size+4,size+4,.9,.03,.04,.05)
    self:drawRect(sx-size/2,sy-size/2,size,size,1,r,g,b)
    if label then self:drawText(label,sx+9,sy-8,1,1,1,1,UIFont.Small) end
end
function Map:routeLine(a,b,r,g,blue,dashed)
    local ax,ay=self:screen(a.x,a.y);local bx,by=self:screen(b.x,b.y)
    local function line(x,y,xx,yy)
        self:drawLine(nil,x,y,xx,yy,3,.65,.02,.04,.05)
        self:drawLine(nil,x,y,xx,yy,1.5,.95,r,g,blue)
    end
    if dashed then
        local length=math.sqrt((bx-ax)^2+(by-ay)^2)
        local steps=math.max(1,math.ceil(length/8))
        for i=0,steps-1,2 do
            local t,u=i/steps,math.min(1,(i+1)/steps)
            line(ax+(bx-ax)*t,ay+(by-ay)*t,ax+(bx-ax)*u,ay+(by-ay)*u)
        end
    else
        line(ax,ay,bx,by)
    end
end
function Map:render()
    self:setStencilRect(0,0,self.width,self.height)
    self:drawTiles()
    local player=getSpecificPlayer(0)
    if N.route and player then self:drawRemainingRoute(player:getX(),player:getY()) end
    for _,result in ipairs(N.searchResults or {}) do
        local poi=result.poi
        self:marker(poi.x,poi.y,nil,1,.48,.18,false)
    end
    if N.previewPOI then self:marker(N.previewPOI.x,N.previewPOI.y,N.previewPOI.name,1,.78,.2,true) end
    if N.target then self:marker(N.target.x,N.target.y,"\208\166\208\181\208\187\209\140",1,.28,.25,true) end
    local colours={{.45,.85,1},{.9,.5,1},{.45,1,.5},{1,.8,.3}}
    local index=0
    for _,friend in ipairs(N.remotePlayers) do
        if N.friendAllowed(friend.name) then
            index=index+1;local c=colours[(index-1)%#colours+1]
            self:marker(friend.x,friend.y,N.option("showNames") and friend.name or nil,c[1],c[2],c[3],true)
        end
    end
    if player then
        local x,y=player:getX(),player:getY()
        if N.headingX then
            local ax,ay=self:screen(x,y);local bx,by=self:screen(x+N.headingX*16,y+N.headingY*16)
            local len=math.sqrt((bx-ax)^2+(by-ay)^2)
            if len>0 then
                local dx,dy=(bx-ax)/len,(by-ay)/len
                local function arrow(front,back,wide,notch,r,g,b,a)
                    self:drawPolygon(nil,
                        ax+dx*front,ay+dy*front,
                        ax-dx*back-dy*wide,ay-dy*back+dx*wide,
                        ax-dx*notch,ay-dy*notch,
                        ax-dx*back+dy*wide,ay-dy*back-dx*wide,r,g,b,a)
                end
                arrow(16,11,11,5,.015,.035,.05,.85)
                arrow(13,8,8,3,.92,.99,1,1)
                arrow(10,6,5.5,2,.15,.82,.95,1)
            end
        else
            self:marker(x,y,nil,.15,.82,.95,true)
        end
    end
    self:clearStencilRect()
    -- Nested clipping leaves the map pixels at the old stencil depth.
    -- Restore the parent's mask before drawing HUD bars and sibling buttons.
    self:repaintStencilRect(0,0,self.width,self.height)
    self:drawRect(0,0,self.width,32,.86,.025,.04,.045)
    self:drawRect(0,self.height-78,self.width,78,.9,.025,.04,.045)
    local text=N.status or "\208\159\209\128\208\176\208\178\209\139\208\185 \208\186\208\187\208\184\208\186 \226\128\148 \208\178\209\139\208\177\209\128\208\176\209\130\209\140 \209\134\208\181\208\187\209\140"
    local distance=""
    if N.Router.job then text="\208\160\208\176\209\129\209\135\209\145\209\130 \208\188\208\176\209\128\209\136\209\128\209\131\209\130\208\176\226\128\166"
    elseif N.guidance then
        text=N.guidance.text.." \209\135\208\181\209\128\208\181\208\183 "..N.formatDistance(N.guidance.distance)
        distance="\208\148\208\190 \209\134\208\181\208\187\208\184: "..N.formatDistance(N.guidance.total or N.guidance.distance)
    end
    self:drawText(text,7,self.height-73,.85,.97,1,1,UIFont.Small)
    local secondary=distance~="" and distance or (N.target and N.target.name or "\208\154\208\190\208\187\209\145\209\129\208\184\208\186\208\190 \226\128\148 \208\188\208\176\209\129\209\136\209\130\208\176\208\177")
    self:drawText(secondary,7,self.height-53,.7,.78,.8,1,UIFont.Small)
    self:drawRectBorder(0,0,self.width,self.height,.9,.22,.3,.32)
end
function Map:drawRemainingRoute(x,y)
    local route=N.route;local points=route.points
    -- Project the current position every frame, including between guidance ticks.
    local progress=N.Router:guidance(route,x,y)
    local current={x=x,y=y}
    if progress.onConnector then
        self:routeLine(current,route.target,1,.75,.3,true)
        return
    end
    local projection={x=progress.x,y=progress.y}
    if progress.deviation>.5 then self:routeLine(current,projection,1,.75,.3,true) end
    self:routeLine(projection,points[progress.segment+1],.1,.85,1,false)
    for i=progress.segment+1,#points-1 do self:routeLine(points[i],points[i+1],.1,.85,1,false) end
    self:routeLine(points[#points],route.target,1,.75,.3,true)
end
function Map:onMouseWheel(delta)
    self.zoom=math.max(.25,math.min(4,self.zoom*(delta>0 and .8 or 1.25)))
    return true
end
function Map:onMouseDown(x,y)
    self.downX=x;self.downY=y;self.dragCX=self.cx;self.dragCY=self.cy;self.dragged=false;self.dragging=true
    self:setCapture(true);return true
end
function Map:onMouseMove(dx,dy)
    if not self.dragging then return end
    local x,y=self:getMouseX(),self:getMouseY()
    if math.abs(x-self.downX)+math.abs(y-self.downY)>4 then self.dragged=true end
    if self.dragged then
        self.cx=self.dragCX;self.cy=self.dragCY
        local wx,wy=self:world(self.downX,self.downY);local xx,yy=self:world(x,y)
        self.cx=self.dragCX+wx-xx;self.cy=self.dragCY+wy-yy;self.pan=true
    end
    return true
end
function Map:onMouseMoveOutside(dx,dy) return self:onMouseMove(dx,dy) end
function Map:onMouseUp(x,y)
    self:setCapture(false);self.dragging=false
    if self.dragged then return true end
    local best,bestDistance=nil,14
    for _,result in ipairs(N.searchResults or {}) do
        local sx,sy=self:screen(result.poi.x,result.poi.y);local d=N.distance(x,y,sx,sy)
        if d<bestDistance then best,bestDistance=result.poi,d end
    end
    for _,friend in ipairs(N.remotePlayers) do
        if N.friendAllowed(friend.name) then
            local sx,sy=self:screen(friend.x,friend.y);local d=N.distance(x,y,sx,sy)
            if d<bestDistance then best,bestDistance={name=friend.name,x=friend.x,y=friend.y,friendName=friend.name},d end
        end
    end
    if best then N.previewPOI=best;N.showDestination(best) end
    return true
end
function Map:onMouseUpOutside(x,y) self:setCapture(false);self.dragging=false;return true end
function Map:onRightMouseUp(x,y)
    local wx,wy=self:world(x,y)
    N.showDestination({name="\208\162\208\190\209\135\208\186\208\176 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181",x=math.floor(wx),y=math.floor(wy)})
    return true
end
function Map:onRightMouseDown() return true end

KnoxNavigatorWindow=ISCollapsableWindow:derive("KnoxNavigatorWindow")
local Window=KnoxNavigatorWindow
function Window:new()
    local size=N.option("size")
    local o=ISCollapsableWindow.new(self,0,0,size+12,size+36)
    o.title="Knox Navigator";o.resizable=true;o.pin=true;o.collapseCounter=0
    o.minimumWidth=232;o.minimumHeight=260
    o.backgroundColor={r=.035,g=.05,b=.055,a=.97};o.borderColor={r=.2,g=.3,b=.32,a=1}
    return o
end
local function button(parent,x,y,w,text,callback)
    local b=ISButton:new(x,y,w,24,text,parent,callback)
    b:initialise();parent:addChild(b);return b
end
function Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.closeButton:setVisible(false)
    local bar=self:titleBarHeight()
    self.map=Map:new(6,bar+4,self.width-12,self.width-12);self.map:initialise();self:addChild(self.map)
    self.searchButton=button(self,10,bar+8,72,"\208\159\208\190\208\184\209\129\208\186",function() N.showSearch() end)
    self.followButton=button(self,84,bar+8,65,"\208\151\208\176 \208\188\208\189\208\190\208\185",function() self.map.pan=false;N.previewPOI=nil end)
    self.settingsButton=button(self,self.width-80,bar+8,70,"\208\158\208\191\209\134\208\184\208\184",function() N.showSettings() end)
    self.cancelButton=button(self,6,self.height-28,82,"\208\158\209\130\208\188\208\181\208\189\208\176",function() N.cancelRoute() end)
    self.modeButton=button(self,self.width-76,self.height-28,70,"\208\146\208\184\208\180",function()
        N.setOption("view",N.option("view")==1 and 2 or 1)
    end)
    self.collapseButton.onclick=Window.toggleCollapsed
    self.pinButton.onclick=Window.toggleCollapsed
    self.resizeWidget.resizeFunction=Window.resizeSquare
    self.resizeWidget2:setVisible(false)
    self.resizeWidget:bringToTop()
    for _,child in ipairs({self.resizeWidget,self.collapseButton,self.pinButton}) do
        child:setAnchorRight(false);child:setAnchorBottom(false)
    end
    self.resizeWidget.onMouseDown=function(widget)
        widget.dragX=getMouseX();widget.dragY=getMouseY()
        widget.dragSize=widget.target.map.width
        widget.dragWindowX=widget.target:getX();widget.dragWindowY=widget.target:getY()
        widget.resizing=true;widget:setCapture(true);return true
    end
    local function drag(widget)
        if not widget.resizing then return end
        local dx=getMouseX()-widget.dragX;local dy=getMouseY()-widget.dragY
        local delta=math.abs(dx)>=math.abs(dy) and dx or dy
        widget.target:resizeTo(widget.dragSize+delta,widget.dragWindowX,widget.dragWindowY)
        return true
    end
    self.resizeWidget.onMouseMove=drag
    self.resizeWidget.onMouseMoveOutside=drag
    -- Save once when the native resize drag finishes.
    local function release(widget,x,y)
        widget.resizing=false;widget:setCapture(false)
        widget.target:saveGeometry()
        return true
    end
    self.resizeWidget.onMouseUp=release
    self.resizeWidget.onMouseUpOutside=release
end
function Window:layoutSize(size)
    local bar=self:titleBarHeight();local grip=self:resizeWidgetHeight()
    self:setWidth(size+12);self:setHeight(self.manualCollapsed and bar or bar+size+8+grip)
    if self.map then self.map:setWidth(size);self.map:setHeight(size) end
    if self.settingsButton then
        self.settingsButton:setX(self.width-80)
        self.cancelButton:setY(bar+size-24)
        self.modeButton:setX(self.width-76);self.modeButton:setY(bar+size-24)
        self.resizeWidget:setX(self.width-grip);self.resizeWidget:setY(self.height-grip)
        self.collapseButton:setX(self.width-self.collapseButton.width-1)
        self.pinButton:setX(self.width-self.pinButton.width-1)
    end
end
function Window:applyOptions()
    self:layoutSize(N.option("size"))
    self:setX(8+(getCore():getScreenWidth()-self.width-16)*N.option("x")/100)
    self:setY(8+math.max(0,getCore():getScreenHeight()-self.height-16)*N.option("y")/100)
end
function Window:resizeSquare(width,height)
    local dx=width-self.width;local dy=height-self.height
    local delta=math.abs(dx)>=math.abs(dy) and dx or dy
    self:resizeTo(self.map.width+delta,self:getX(),self:getY())
end
function Window:resizeTo(requested,x,y)
    local limit=math.min(600,getCore():getScreenWidth()-28,
        getCore():getScreenHeight()-self:titleBarHeight()-24-self:resizeWidgetHeight())
    local size=math.floor(math.max(220,math.min(limit,requested)))
    N.options:getOption("size"):setValue(size)
    self:layoutSize(size)
    self:setX(math.max(8,math.min(x,getCore():getScreenWidth()-self.width-8)))
    self:setY(math.max(8,math.min(y,getCore():getScreenHeight()-self.height-8)))
end
function Window:saveGeometry()
    local height=self:titleBarHeight()+N.option("size")+8+self:resizeWidgetHeight()
    local function position(value,range) return math.max(0,math.min(100,(value-8)*100/math.max(1,range))) end
    N.options:getOption("x"):setValue(position(self:getX(),getCore():getScreenWidth()-self.width-16))
    N.options:getOption("y"):setValue(position(self:getY(),getCore():getScreenHeight()-height-16))
    PZAPI.ModOptions:save()
end
function Window:toggleCollapsed()
    self.manualCollapsed=not self.manualCollapsed
    self.isCollapsed=self.manualCollapsed;self.pin=true;self.collapseCounter=0
    for _,child in ipairs({self.map,self.searchButton,self.followButton,self.settingsButton,self.cancelButton,self.modeButton,self.resizeWidget}) do
        child:setVisible(not self.manualCollapsed)
    end
    self.collapseButton:setVisible(not self.manualCollapsed)
    self.pinButton:setVisible(self.manualCollapsed)
    self:layoutSize(N.option("size"))
    self:bringToTop()
end
function Window:uncollapse()
    -- Expansion is explicit; hovering over the title must not undo a click.
    self.collapseCounter=0
end
function Window:render()
    ISCollapsableWindow.render(self)
end

KnoxNavigatorSearch=ISCollapsableWindow:derive("KnoxNavigatorSearch")
local Search=KnoxNavigatorSearch
function Search:new()
    local w=math.min(650,getCore():getScreenWidth()-40);local h=math.min(530,getCore():getScreenHeight()-40)
    local o=ISCollapsableWindow.new(self,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
    o.title="\208\157\208\176\208\185\209\130\208\184 \208\188\208\181\209\129\209\130\208\190 \226\128\148 \208\177\208\187\208\184\208\182\208\176\208\185\209\136\208\184\208\181 \208\191\208\181\209\128\208\178\209\139\208\188\208\184";o.resizable=false;o.pin=true;return o
end
function Search:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top=self:titleBarHeight()+10
    self.entry=ISTextEntryBox:new("",12,top,self.width-110,28)
    self.entry:initialise();self.entry:instantiate();self:addChild(self.entry)
    self.entry.onCommandEntered=function() self:search() end
    self.entry.onTextChange=function() self:search() end
    button(self,self.width-90,top,78,"\208\157\208\176\208\185\209\130\208\184",function() self:search() end)
    self.list=ISScrollingListBox:new(12,top+58,self.width-24,self.height-top-116)
    self.list:initialise();self.list:instantiate();self.list.itemheight=48;self.list.font=UIFont.Small
    self.list.doDrawItem=function(list,y,item,alt)
        local selected=list.selected==item.index
        if selected then list:drawRect(0,y,list.width,48,.8,.1,.3,.35) end
        local result=item.item
        list:drawText(tostring(item.index)..". "..result.poi.name,10,y+5,1,1,1,1,UIFont.Small)
        list:drawText(result.poi.town.."   "..N.formatDistance(result.distance).."   ["..result.poi.x..", "..result.poi.y.."]",10,y+25,.7,.82,.85,1,UIFont.Small)
        return y+48
    end
    self.list:setOnMouseDownFunction(self,self.select)
    self.list:setOnMouseDoubleClick(self,self.routeSelected)
    self:addChild(self.list)
    button(self,12,self.height-42,150,"\208\156\208\176\209\128\209\136\209\128\209\131\209\130 \208\186 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\208\190\208\188\209\131",function() self:routeSelected() end)
    button(self,170,self.height-42,135,"\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\178\209\129\208\181 \208\189\208\176 \208\186\208\176\209\128\209\130\208\181",function() self:showAll() end)
    button(self,self.width-96,self.height-42,84,"\208\151\208\176\208\186\209\128\209\139\209\130\209\140",function() self:close() end)
    self:search()
end
function Search:search()
    local player=getSpecificPlayer(0)
    if not player or not self.list then return end
    local selected=self.selectedPOI
    self.results=N.search(self.entry:getText(),player:getX(),player:getY())
    N.searchResults=self.results;self.list:clear();self.selectedPOI=nil
    for _,result in ipairs(self.results) do self.list:addItem(result.poi.name,result) end
    if selected then
        for i,result in ipairs(self.results) do
            if result.poi.index==selected.index then self.list.selected=i;self.selectedPOI=selected;break end
        end
    end
    if not self.selectedPOI and self.results[1] then self.list.selected=1;self.selectedPOI=self.results[1].poi end
end
function Search:select(result)
    if not result then return end
    self.selectedPOI=result.poi;N.previewPOI=result.poi
    N.window.map.cx=result.poi.x;N.window.map.cy=result.poi.y;N.window.map.pan=true
end
function Search:routeSelected()
    local item=self.list.items[self.list.selected]
    if item then N.beginRoute(item.item.poi);self:close() end
end
function Search:showAll()
    if #self.results==0 then return end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local map=N.window.map
    for _,result in ipairs(self.results) do
        local px,py=map:project(result.poi.x,result.poi.y)
        minX=math.min(minX,px);minY=math.min(minY,py);maxX=math.max(maxX,px);maxY=math.max(maxY,py)
    end
    -- Convert the projected midpoint through the same inverse used for clicks.
    map.cx=0;map.cy=0;map.zoom=1
    local wx,wy=map:world(map.width/2+(minX+maxX)/2,map.height/2+(minY+maxY)/2)
    map.cx=wx;map.cy=wy;map.zoom=math.max(.03,math.min(4,(map.width-40)/math.max(1,maxX-minX),(map.height-40)/math.max(1,maxY-minY)))
    map.pan=true;self:close()
end
function Search:render()
    ISCollapsableWindow.render(self)
    self:drawText("\208\157\208\176\208\185\208\180\208\181\208\189\208\190: "..tostring(#(self.results or {})).." \226\128\162 \209\128\208\176\209\129\209\129\209\130\208\190\209\143\208\189\208\184\208\181 \208\191\208\190 \208\191\209\128\209\143\208\188\208\190\208\185",12,self:titleBarHeight()+44,.8,.88,.9,1,UIFont.Small)
end
function Search:close()
    self:setVisible(false);self:removeFromUIManager();N.searchWindow=nil
end

KnoxNavigatorSettings=ISCollapsableWindow:derive("KnoxNavigatorSettings")
local Settings=KnoxNavigatorSettings
function Settings:new()
    local o=ISCollapsableWindow.new(self,math.max(10,getCore():getScreenWidth()/2-210),100,420,340)
    o.title="\208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184 \208\189\208\176\208\178\208\184\208\179\208\176\209\130\208\190\209\128\208\176";o.pin=true;o.resizable=false;return o
end
function Settings:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top=self:titleBarHeight()+14
    self.sizeEntry=ISTextEntryBox:new(tostring(N.option("size")),250,top,140,26)
    self.xEntry=ISTextEntryBox:new(tostring(N.option("x")),250,top+42,140,26)
    self.yEntry=ISTextEntryBox:new(tostring(N.option("y")),250,top+84,140,26)
    for _,entry in ipairs({self.sizeEntry,self.xEntry,self.yEntry}) do
        entry:initialise();entry:instantiate();entry:setOnlyNumbers(true);self:addChild(entry)
    end
    button(self,16,top+127,180,"\208\159\208\181\209\128\208\181\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\178\208\184\208\180 \208\186\208\176\209\128\209\130\209\139",function() N.setOption("view",N.option("view")==1 and 2 or 1) end)
    button(self,210,top+127,180,"\208\159\209\128\208\184\208\188\208\181\208\189\208\184\209\130\209\140 \208\184 \208\191\208\190\209\129\208\188\208\190\209\130\209\128\208\181\209\130\209\140",function() self:apply() end)
    button(self,16,top+169,374,"\208\151\208\176\208\191\208\190\208\188\208\189\208\184\209\130\209\140 \209\130\208\181\208\186\209\131\209\137\208\181\208\181 \208\191\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \208\190\208\186\208\189\208\176",function()
        local w=N.window
        local xrange=math.max(1,getCore():getScreenWidth()-w.width-16)
        local yrange=math.max(1,getCore():getScreenHeight()-w.height-16)
        N.setOption("x",math.max(0,math.min(100,(w:getX()-8)*100/xrange)))
        N.setOption("y",math.max(0,math.min(100,(w:getY()-8)*100/yrange)))
        self.xEntry:setText(tostring(math.floor(N.option("x"))))
        self.yEntry:setText(tostring(math.floor(N.option("y"))))
    end)
    button(self,16,top+211,180,"\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\190\208\186\208\189\208\190",function()
        N.setOption("size",300);N.setOption("x",100);N.setOption("y",12)
        self.sizeEntry:setText("300");self.xEntry:setText("100");self.yEntry:setText("12")
    end)
    button(self,210,top+211,180,"\208\147\208\190\209\130\208\190\208\178\208\190",function() self:apply();self:close() end)
end
function Settings:render()
    ISCollapsableWindow.render(self)
    local top=self:titleBarHeight()+16
    self:drawText("\208\160\208\176\208\183\208\188\208\181\209\128 \208\186\208\178\208\176\208\180\209\128\208\176\209\130\208\176: 220\226\128\147600 px",16,top,1,1,1,1,UIFont.Small)
    self:drawText("\208\159\208\190 \208\179\208\190\209\128\208\184\208\183\208\190\208\189\209\130\208\176\208\187\208\184: 0\226\128\147100%",16,top+42,1,1,1,1,UIFont.Small)
    self:drawText("\208\159\208\190 \208\178\208\181\209\128\209\130\208\184\208\186\208\176\208\187\208\184: 0\226\128\147100%",16,top+84,1,1,1,1,UIFont.Small)
    self:drawText("\208\146\209\129\208\181 \208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184: Esc \226\134\146 \208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184 \226\134\146 \208\156\208\190\208\180\209\139",16,self.height-32,.65,.85,.9,1,UIFont.Small)
end
function Settings:apply()
    N.setOption("size",math.max(220,math.min(600,tonumber(self.sizeEntry:getText()) or 300)))
    N.setOption("x",math.max(0,math.min(100,tonumber(self.xEntry:getText()) or 100)))
    N.setOption("y",math.max(0,math.min(100,tonumber(self.yEntry:getText()) or 12)))
end
function Settings:close()
    self:setVisible(false);self:removeFromUIManager();N.settingsWindow=nil;N.settingsPreview=false
end

function N.showSearch()
    if N.searchWindow then N.searchWindow:bringToTop();return end
    if not getSpecificPlayer(0) then return end
    N.searchWindow=Search:new();N.searchWindow:initialise();N.searchWindow:addToUIManager()
end
function N.showSettings()
    if not N.window then return end
    if N.settingsWindow then N.settingsWindow:bringToTop();return end
    N.settingsPreview=true;N.window:setVisible(true)
    N.settingsWindow=Settings:new();N.settingsWindow:initialise();N.settingsWindow:addToUIManager()
end
function N.showDestination(poi)
    N.previewPOI=poi
    if N.destinationWindow then N.destinationWindow:removeFromUIManager() end
    local w=ISCollapsableWindow:new(math.max(0,getCore():getScreenWidth()/2-180),getCore():getScreenHeight()/2-65,360,135)
    w.title=poi.name;w.resizable=false;w.pin=true
    w:initialise();w:addToUIManager()
    button(w,16,45,155,"\208\159\208\190\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\188\208\176\209\128\209\136\209\128\209\131\209\130",function() N.beginRoute(poi);w:removeFromUIManager();N.destinationWindow=nil end)
    button(w,186,45,155,"\208\158\209\130\208\188\208\181\208\189\208\176",function() w:removeFromUIManager();N.destinationWindow=nil end)
    w.render=function(self)
        ISCollapsableWindow.render(self)
        self:drawText((poi.town or "").."  ["..math.floor(poi.x)..", "..math.floor(poi.y).."]",16,85,.8,.9,.9,1,UIFont.Small)
    end
    N.destinationWindow=w
end
