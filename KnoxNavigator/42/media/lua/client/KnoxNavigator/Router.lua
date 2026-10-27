require "KnoxNavigator/Core"
local N = KnoxNavigator
N.Router = {}
local R = N.Router

function R:beginLoad()
    if self.grid or self.reader then return end
    self.reader = N.readData("roads.tsv")
    if not self.reader then self.error = "\208\157\208\181 \208\189\208\176\208\185\208\180\208\181\208\189\209\139 \208\180\208\190\209\128\208\190\208\182\208\189\209\139\208\181 \208\180\208\176\208\189\208\189\209\139\208\181"; return end
    local header = N.split(self.reader:readLine() or "", "\t")
    self.step, self.width, self.height = tonumber(header[1]), tonumber(header[2]), tonumber(header[3])
    if not self.step or not self.width or not self.height then
        self.reader:close(); self.reader=nil; self.error="\208\159\208\190\208\178\209\128\208\181\208\182\208\180\208\181\208\189\209\139 \208\180\208\190\209\128\208\190\208\182\208\189\209\139\208\181 \208\180\208\176\208\189\208\189\209\139\208\181"; return
    end
    self.grid = {}; self.loading=true
end

function R:loadTick()
    self:beginLoad()
    if not self.loading then return end
    for _ = 1, 100 do
        local line = self.reader:readLine()
        if not line then
            self.reader:close(); self.reader=nil; self.loading=false; return
        end
        local parts=N.split(line,"\t"); local y=tonumber(parts[1])
        for i=2,#parts,2 do
            for x=tonumber(parts[i]),tonumber(parts[i+1]) do self.grid[y*self.width+x]=true end
        end
    end
end

function R:xy(id)
    return id % self.width * self.step, math.floor(id / self.width) * self.step
end

function R:nearest(x,y)
    if not self.grid or self.loading then return nil end
    local gx,gy=math.floor(x/self.step+0.5),math.floor(y/self.step+0.5)
    local best,bestD=nil,math.huge
    -- Bound the off-road connector to 160 squares. Never fabricate a road.
    for radius=0,40 do
        for dx=-radius,radius do
            for _,dy in ipairs(radius==0 and {0} or {-radius,radius}) do
                local xx,yy=gx+dx,gy+dy
                if xx>=0 and xx<self.width and yy>=0 and yy<self.height then
                    local id=yy*self.width+xx
                    if self.grid[id] then
                        local d=(xx*self.step-x)^2+(yy*self.step-y)^2
                        if d<bestD then best,bestD=id,d end
                    end
                end
            end
        end
        for dy=-radius+1,radius-1 do
            for _,dx in ipairs({-radius,radius}) do
                local xx,yy=gx+dx,gy+dy
                if xx>=0 and xx<self.width and yy>=0 and yy<self.height then
                    local id=yy*self.width+xx
                    if self.grid[id] then
                        local d=(xx*self.step-x)^2+(yy*self.step-y)^2
                        if d<bestD then best,bestD=id,d end
                    end
                end
            end
        end
        if best and radius*self.step > math.sqrt(bestD)+self.step then return best end
    end
    return best
end

local function push(heap,node)
    local i=#heap+1
    while i>1 do
        local parent=math.floor(i/2)
        if heap[parent].f<=node.f then break end
        heap[i]=heap[parent]; i=parent
    end
    heap[i]=node
end
local function pop(heap)
    local result=heap[1]; local last=table.remove(heap)
    if #heap==0 then return result end
    local i=1
    while i*2<=#heap do
        local child=i*2
        if child+1<=#heap and heap[child+1].f<heap[child].f then child=child+1 end
        if last.f<=heap[child].f then break end
        heap[i]=heap[child]; i=child
    end
    heap[i]=last; return result
end

function R:start(x,y,target)
    if self.loading or not self.grid then return false,"\208\151\208\176\208\179\209\128\209\131\208\183\208\186\208\176 \208\180\208\190\209\128\208\190\208\182\208\189\208\190\208\185 \209\129\208\181\209\130\208\184\226\128\166" end
    local first,last=self:nearest(x,y),self:nearest(target.x,target.y)
    if not first then return false,"\208\148\208\190 \208\177\208\187\208\184\208\182\208\176\208\185\209\136\208\181\208\185 \208\180\208\190\209\128\208\190\208\179\208\184 \209\129\208\187\208\184\209\136\208\186\208\190\208\188 \208\180\208\176\208\187\208\181\208\186\208\190" end
    if not last then return false,"\208\163 \209\134\208\181\208\187\208\184 \208\189\208\181\209\130 \208\180\208\190\209\128\208\190\208\179\208\184 \208\191\208\190\208\177\208\187\208\184\208\183\208\190\209\129\209\130\208\184" end
    local tx,ty=self:xy(last)
    local sx,sy=self:xy(first)
    self.job={heap={},g={[first]=0},parent={},closed={},goal=last,tx=tx,ty=ty,target=target,expanded=0}
    push(self.job.heap,{id=first,g=0,f=N.distance(sx,sy,tx,ty)})
    self.error=nil
    return true
end

local neighbors={{1,0,1},{-1,0,1},{0,1,1},{0,-1,1},{1,1,1.41421356237},{1,-1,1.41421356237},{-1,1,1.41421356237},{-1,-1,1.41421356237}}

function R:finish(job)
    local reverse={}; local id=job.goal
    while id do
        local x,y=self:xy(id); reverse[#reverse+1]={x=x,y=y}; id=job.parent[id]
    end
    local raw={}
    for i=#reverse,1,-1 do raw[#raw+1]=reverse[i] end
    local path={raw[1]}
    -- Preserve corners, remove only collinear grid steps.
    for i=2,#raw-1 do
        local a,b,c=raw[i-1],raw[i],raw[i+1]
        if (b.x-a.x)*(c.y-b.y)~=(b.y-a.y)*(c.x-b.x) then path[#path+1]=b end
    end
    if #raw>1 then path[#path+1]=raw[#raw] end
    local remaining={}; remaining[#path]=0
    for i=#path-1,1,-1 do remaining[i]=remaining[i+1]+N.distance(path[i].x,path[i].y,path[i+1].x,path[i+1].y) end
    self.result={points=path,remaining=remaining,target=job.target,connector=N.distance(path[#path].x,path[#path].y,job.target.x,job.target.y)}
    self.job=nil
end

function R:tick()
    self:loadTick()
    local job=self.job
    if not job then return end
    -- Finite work budget per frame keeps long routes from freezing driving.
    for _=1,1200 do
        if #job.heap==0 then self.error="\208\161\208\178\209\143\208\183\208\176\208\189\208\189\209\139\208\185 \208\188\208\176\209\128\209\136\209\128\209\131\209\130 \208\191\208\190 \208\180\208\190\209\128\208\190\208\179\208\176\208\188 \208\189\208\181 \208\189\208\176\208\185\208\180\208\181\208\189";self.job=nil;return end
        local node=pop(job.heap)
        if not job.closed[node.id] and node.g==job.g[node.id] then
            if node.id==job.goal then self:finish(job);return end
            job.closed[node.id]=true;job.expanded=job.expanded+1
            if job.expanded>400000 then self.error="\208\156\208\176\209\128\209\136\209\128\209\131\209\130 \209\129\208\187\208\184\209\136\208\186\208\190\208\188 \209\129\208\187\208\190\208\182\208\189\209\139\208\185";self.job=nil;return end
            local gx,gy=node.id%self.width,math.floor(node.id/self.width)
            for _,offset in ipairs(neighbors) do
                local xx,yy=gx+offset[1],gy+offset[2]
                local nextId=yy*self.width+xx
                local diagonal=offset[1]~=0 and offset[2]~=0
                local cornerOK=not diagonal or self.grid[gy*self.width+xx] or self.grid[yy*self.width+gx]
                if xx>=0 and yy>=0 and xx<self.width and yy<self.height and cornerOK and self.grid[nextId] and not job.closed[nextId] then
                    local cost=node.g+self.step*offset[3]
                    if not job.g[nextId] or cost<job.g[nextId] then
                        job.g[nextId]=cost;job.parent[nextId]=node.id
                        push(job.heap,{id=nextId,g=cost,f=cost+N.distance(xx*self.step,yy*self.step,job.tx,job.ty)})
                    end
                end
            end
        end
    end
end

function R.project(x,y,a,b)
    local dx,dy=b.x-a.x,b.y-a.y
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((x-a.x)*dx+(y-a.y)*dy)/len)) or 0
    local px,py=a.x+t*dx,a.y+t*dy
    return N.distance(x,y,px,py),t,px,py
end

function R:guidance(route,x,y)
    local points=route.points
    if #points==1 then
        local distance=N.distance(x,y,route.target.x,route.target.y)
        local deviation=self.project(x,y,points[1],route.target)
        return {text="\208\154 \209\134\208\181\208\187\208\184",distance=distance,total=distance,deviation=deviation,segment=1,onConnector=true,x=x,y=y}
    end
    local best,bestI,bestT=math.huge,1,0
    for i=1,#points-1 do
        local d,t=self.project(x,y,points[i],points[i+1])
        if d<best or (math.abs(d-best)<.00001 and i==bestI+1 and bestT>.999) then best,bestI,bestT=d,i,t end
    end
    local endDistance,endT=self.project(x,y,points[#points],route.target)
    if bestI==#points-1 and (bestT>.999 or endDistance<best) and endT>0 then
        local distance=N.distance(x,y,route.target.x,route.target.y)
        return {text="\208\154 \209\134\208\181\208\187\208\184",distance=distance,total=distance,deviation=endDistance,segment=#points,onConnector=true,x=x,y=y}
    end
    local a,b=points[bestI],points[bestI+1]
    local toNext=N.distance(points[bestI].x,points[bestI].y,points[bestI+1].x,points[bestI+1].y)*(1-bestT)
    local result={text="\208\159\209\128\209\143\208\188\208\190",distance=toNext,deviation=best,segment=bestI,t=bestT,
        x=a.x+(b.x-a.x)*bestT,y=a.y+(b.y-a.y)*bestT,
        total=toNext+route.remaining[bestI+1]+route.connector}
    local accumulated=toNext
    -- Compare to a 24-square lookahead to avoid announcing every raster stair-step.
    for i=bestI+1,#points-1 do
        local before=i-1
        while before>1 and N.distance(points[before].x,points[before].y,points[i].x,points[i].y)<24 do before=before-1 end
        local after=i+1
        while after<#points and N.distance(points[after].x,points[after].y,points[i].x,points[i].y)<24 do after=after+1 end
        local a,b,c=points[before],points[i],points[after]
        local ax,ay=b.x-a.x,b.y-a.y;local bx,by=c.x-b.x,c.y-b.y
        local lengths=math.sqrt((ax*ax+ay*ay)*(bx*bx+by*by))
        if lengths>0 then
            local cosine=math.max(-1,math.min(1,(ax*bx+ay*by)/lengths))
            if cosine<0.72 then
                result.text=cosine < -0.7 and "\208\160\208\176\208\183\208\178\208\190\209\128\208\190\209\130" or (ax*by-ay*bx>0 and "\208\157\208\176\208\191\209\128\208\176\208\178\208\190" or "\208\157\208\176\208\187\208\181\208\178\208\190")
                result.distance=accumulated;result.turn=points[i];return result
            end
        end
        accumulated=accumulated+N.distance(points[i].x,points[i].y,points[i+1].x,points[i+1].y)
    end
    result.text="\208\154 \209\134\208\181\208\187\208\184";result.distance=result.total;return result
end
