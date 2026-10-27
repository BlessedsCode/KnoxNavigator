if not isServer() then return end
require "KnoxNavigator/Core"
local N=KnoxNavigator
local requests={}
local function command(module,name,player,args)
    if module~=N.MOD_ID or name~="getPositions" or not player then return end
    local now=getTimestampMs();local username=player:getUsername()
    if requests[username] and now-requests[username]<1500 then return end
    requests[username]=now
    -- Read authoritative server positions; clients never upload coordinates.
    local online=getOnlinePlayers();local snapshot={}
    for i=0,online:size()-1 do
        local friend=online:get(i)
        if friend and friend~=player and not friend:isDead() then
            snapshot[#snapshot+1]={name=friend:getUsername(),x=friend:getX(),y=friend:getY()}
        end
    end
    sendServerCommand(player,N.MOD_ID,"positions",{players=snapshot})
end
Events.OnClientCommand.Add(command)
