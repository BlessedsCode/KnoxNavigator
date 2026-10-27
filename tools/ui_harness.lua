-- A Lua 5.1 UI test double. This verifies our handlers and math, not the
-- native game's drawing/input implementation. Real ISUI signatures are
-- checked against the installed Build 42 source.
local Base={}
function Base:derive(name)
 local class={Type=name};class.__index=class;setmetatable(class,{__index=self});return class
end
function Base:new(x,y,w,h)
 local obj={x=x or 0,y=y or 0,width=w or 0,height=h or 0,children={},visible=true}
 setmetatable(obj,self);self.__index=self;return obj
end
function Base:initialise() end
function Base:instantiate() end
function Base:addToUIManager() if not self.created then self.created=true;self:createChildren() end end
function Base:removeFromUIManager() self.visible=false end
function Base:createChildren() end
function Base:addChild(child) child.parent=self;self.children[#self.children+1]=child end
function Base:setVisible(value) assert(type(value)=='boolean','native setVisible requires a boolean');self.visible=value end
function Base:getIsVisible() return self.visible end
function Base:bringToTop() end
function Base:setX(value) self.x=value end
function Base:setY(value) self.y=value end
function Base:setWidth(value) self.width=value end
function Base:setHeight(value) self.height=value end
function Base:getX() return self.x end
function Base:getY() return self.y end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
function Base:getBottom() return self.y+self.height end
function Base:getRight() return self.x+self.width end
function Base:getAbsoluteX() return self.x+(self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y+(self.parent and self.parent:getAbsoluteY() or 0) end
function Base:setCapture(value) self.capture=value end
function Base:setAnchorRight(value) self.anchorRight=value end
function Base:setAnchorBottom(value) self.anchorBottom=value end
getMouseX=function() return TestGlobalMouseX or 0 end
getMouseY=function() return TestGlobalMouseY or 0 end
function Base:getMouseX() return TestMouseX or 0 end
function Base:getMouseY() return TestMouseY or 0 end
function Base:setStencilRect(x,y,w,h) if DrawClip then DrawClip(self:getAbsoluteX()+x,self:getAbsoluteY()+y,w,h) end end
function Base:clearStencilRect() if ClearClip then ClearClip() end end
function Base:repaintStencilRect(x,y,w,h) TestRepaintCount=(TestRepaintCount or 0)+1 end
function Base:drawTextureScaled(texture,x,y,w,h,a,r,g,b) if DrawTexture then DrawTexture(texture.path,self:getAbsoluteX()+x,self:getAbsoluteY()+y,w,h) end end
function Base:drawRect(x,y,w,h,a,r,g,b) if DrawRect then DrawRect(self:getAbsoluteX()+x,self:getAbsoluteY()+y,w,h,a,r,g,b) end end
function Base:drawRectBorder(x,y,w,h,a,r,g,b) if DrawBorder then DrawBorder(self:getAbsoluteX()+x,self:getAbsoluteY()+y,w,h,a,r,g,b) end end
function Base:drawText(text,x,y,r,g,b,a,font) if DrawText then DrawText(text,self:getAbsoluteX()+x,self:getAbsoluteY()+y,r,g,b,a) end end
function Base:drawLine2(x,y,xx,yy,a,r,g,b) if DrawLine then DrawLine(self:getAbsoluteX()+x,self:getAbsoluteY()+y,self:getAbsoluteX()+xx,self:getAbsoluteY()+yy,a,r,g,b) end end
function Base:drawLine(texture,x,y,xx,yy,thickness,a,r,g,b)
 TestRouteLines=(TestRouteLines or 0)+1;TestLineThickness=thickness
 if DrawLine then DrawLine(self:getAbsoluteX()+x,self:getAbsoluteY()+y,self:getAbsoluteX()+xx,self:getAbsoluteY()+yy,a,r,g,b,thickness) end
end
function Base:drawPolygon(texture,x1,y1,x2,y2,x3,y3,x4,y4,r,g,b,a)
 if DrawPolygon then
  local x,y=self:getAbsoluteX(),self:getAbsoluteY()
  DrawPolygon(x+x1,y+y1,x+x2,y+y2,x+x3,y+y3,x+x4,y+y4,r,g,b,a)
 end
end
function Base:render() end
function Base:prerender() end
ISPanel=Base:derive('ISPanel')
ISCollapsableWindow=Base:derive('ISCollapsableWindow')
function ISCollapsableWindow:titleBarHeight() return 24 end
function ISCollapsableWindow:resizeWidgetHeight() return 16 end
function ISCollapsableWindow:createChildren()
 self.closeButton={setVisible=function() end}
 self.collapseButton=Base:new();self.pinButton=Base:new()
 self.resizeWidget=Base:new();self.resizeWidget.target=self
 self.resizeWidget2=Base:new()
end
ISButton=Base:derive('ISButton')
function ISButton:new(x,y,w,h,text,target,callback)
 local obj=Base.new(self,x,y,w,h);obj.text=text;obj.target=target;obj.callback=callback;return obj
end
ISTextEntryBox=Base:derive('ISTextEntryBox')
function ISTextEntryBox:new(text,x,y,w,h) local obj=Base.new(self,x,y,w,h);obj.text=text;return obj end
function ISTextEntryBox:getText() return self.text end
function ISTextEntryBox:setText(value) self.text=value end
function ISTextEntryBox:setOnlyNumbers() end
ISScrollingListBox=Base:derive('ISScrollingListBox')
function ISScrollingListBox:new(x,y,w,h) local obj=Base.new(self,x,y,w,h);obj.items={};obj.selected=1;return obj end
function ISScrollingListBox:setOnMouseDownFunction(target,fn) self.target=target;self.down=fn end
function ISScrollingListBox:setOnMouseDoubleClick(target,fn) self.target=target;self.double=fn end
function ISScrollingListBox:clear() self.items={} end
function ISScrollingListBox:addItem(text,item) self.items[#self.items+1]={index=#self.items+1,text=text,item=item} end
UIFont={Small=1}
local options={data={}}
function options:getOption(id) return self.data[id] end
function options:addDescription() end
local function option(self,id,value)
 local obj={value=value,getValue=function(o) return o.value end,setValue=function(o,v) o.value=v end}
 self.data[id]=obj;return obj
end
function options:addTickBox(id,name,value) return option(self,id,value) end
function options:addSlider(id,name,min,max,step,value) return option(self,id,value) end
function options:addTextEntry(id,name,value) return option(self,id,value) end
function options:addComboBox(id,name)
 local obj=option(self,id,1);obj.items={}
 obj.addItem=function(o,label,selected) o.items[#o.items+1]=label;if selected then o.value=#o.items end end
 return obj
end
function options:addButton(id,name,tooltip,callback) self.data[id]={onclick=callback} end
PZAPI={ModOptions={create=function() return options end,save=function() TestSaved=true end}}
local core={getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end}
getCore=function() return core end
TestPlayer={x=6450,y=5430,vehicle={}}
function TestPlayer:getX() return self.x end
function TestPlayer:getY() return self.y end
function TestPlayer:getVehicle() return self.vehicle end
function TestPlayer:getForwardDirection() return {getDirection=function() return TestFacingAngle or 0 end} end
function TestPlayer:getUsername() return 'Me' end
getSpecificPlayer=function() return TestPlayer end
isClient=function() return false end
TestNow=100000
getTimestampMs=function() return TestNow end
Events={}
for _,name in ipairs({'OnTick','OnTickEvenPaused','OnGameStart','OnServerCommand','OnClientCommand'}) do
 local event={};event.Add=function(fn) event.handler=fn end;Events[name]=event
end
sendClientCommand=function() end
