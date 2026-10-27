require "KnoxNavigator/UI"
local N=KnoxNavigator
local R=N.Router
local ticks=0

function N.cancelRoute()
    N.target=nil;N.route=nil;N.guidance=nil;N.pendingTarget=nil;R.job=nil;R.result=nil;R.error=nil
    N.status="\208\156\208\176\209\128\209\136\209\128\209\131\209\130 \208\190\209\130\208\188\208\181\208\189\209\145\208\189";N.previewPOI=nil
end
function N.beginRoute(target)
    local player=getSpecificPlayer(0)
    if not player then return end
    N.target=target;N.route=nil;N.guidance=nil;R.job=nil;R.result=nil;R.error=nil
    N.previewPOI=nil;N.window.map.pan=false
    if N.window.map.zoom<.6 then N.window.map.zoom=2.6 end
    N.status="\208\160\208\176\209\129\209\135\209\145\209\130 \208\188\208\176\209\128\209\136\209\128\209\131\209\130\208\176\226\128\166"
    if R.loading or not R.grid then N.pendingTarget=target;return end
    local ok,message=R:start(player:getX(),player:getY(),target)
    if not ok then N.status=message end
end

local function init()
    if N.window then N.window:removeFromUIManager() end
    N.loadPOIs();R:beginLoad()
    N.window=KnoxNavigatorWindow:new();N.window:initialise();N.window:addToUIManager();N.window:applyOptions();N.window:setVisible(false)
    N.remotePlayers={};N.lastRequest=0;N.lastReroute=0;N.status="\208\159\209\128\208\176\208\178\209\139\208\185 \208\186\208\187\208\184\208\186 \226\128\148 \208\178\209\139\208\177\209\128\208\176\209\130\209\140 \209\134\208\181\208\187\209\140"
    N.target=nil;N.route=nil;N.guidance=nil;N.headingX=nil;N.lastX=nil
end

local function serverCommand(module,command,args)
    if module~=N.MOD_ID or command~="positions" or not args then return end
    N.remotePlayers={}
    local player=getSpecificPlayer(0)
    for _,entry in ipairs(args.players or {}) do
        if entry.name and type(entry.x)=="number" and type(entry.y)=="number" and (not player or entry.name~=player:getUsername()) then
            N.remotePlayers[#N.remotePlayers+1]=entry
        end
    end
    N.lastSnapshot=getTimestampMs()
end

local function tick()
    if not N.window then return end
    local player=getSpecificPlayer(0)
    if not player then return end
    ticks=ticks+1
    local x,y=player:getX(),player:getY()
    local visible=N.option("enabled")==true and (player:getVehicle()~=nil or N.settingsPreview==true)
    N.window:setVisible(visible)
    R:tick()
    if N.pendingTarget and R.grid and not R.loading then
        local target=N.pendingTarget;N.pendingTarget=nil;N.beginRoute(target)
    end
    if R.result then
        N.route=R.result;R.result=nil;N.status=nil
    end
    if R.error then N.status=R.error;R.error=nil;N.guidance=nil end
    local facing=player:getForwardDirection()
    if facing then
        local angle=facing:getDirection()
        N.headingX=math.cos(angle);N.headingY=math.sin(angle)
    end
    if not N.window.map.pan then N.window.map.cx=x;N.window.map.cy=y end
    local now=getTimestampMs()
    if N.route then
        N.guidance=R:guidance(N.route,x,y)
        if N.distance(x,y,N.target.x,N.target.y)<15 then
            N.route=nil;N.guidance=nil;N.target=nil;N.status="\208\146\209\139 \208\191\209\128\208\184\208\181\209\133\208\176\208\187\208\184!"
        elseif N.option("reroute") and N.guidance.deviation>20 and now-N.lastReroute>1500 and not R.job then
            N.lastReroute=now
            local ok,message=R:start(x,y,N.target)
            N.status=ok and "\208\159\208\181\209\128\208\181\209\129\209\135\209\145\209\130 \208\188\208\176\209\128\209\136\209\128\209\131\209\130\208\176\226\128\166" or message
        end
    end
    if isClient() and visible and now-N.lastRequest>2000 then
        N.lastRequest=now;sendClientCommand(player,N.MOD_ID,"getPositions",{})
    end
    if N.lastSnapshot and now-N.lastSnapshot>8000 then N.remotePlayers={} end
    if N.target and N.target.friendName then
        for _,friend in ipairs(N.remotePlayers) do
            if friend.name==N.target.friendName and N.distance(friend.x,friend.y,N.target.x,N.target.y)>60 and now-N.lastReroute>5000 and not R.job then
                N.target.x=friend.x;N.target.y=friend.y;N.lastReroute=now;R:start(x,y,N.target)
            end
        end
    end
    if ticks%120==0 then
        local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
        if sw~=N.screenWidth or sh~=N.screenHeight then
            N.screenWidth=sw;N.screenHeight=sh
            if not N.window.resizeWidget.resizing then N.window:applyOptions() end
        end
    end
    if not visible and not N.settingsPreview then
        if N.searchWindow then N.searchWindow:close() end
        if N.destinationWindow then N.destinationWindow:removeFromUIManager();N.destinationWindow=nil end
    end
end
Events.OnGameStart.Add(init)
local tickEvent=Events.OnTickEvenPaused or Events.OnTick
tickEvent.Add(tick)
Events.OnServerCommand.Add(serverCommand)
