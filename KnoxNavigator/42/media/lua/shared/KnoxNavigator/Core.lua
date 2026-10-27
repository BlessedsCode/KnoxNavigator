KnoxNavigator = KnoxNavigator or {}
local N = KnoxNavigator
N.MOD_ID = "KnoxNavigator"
N.remotePlayers = {}

function N.split(text, delimiter)
    local result = {}
    local start = 1
    for index = 1, #text + 1 do
        local char = string.sub(text, index, index)
        local separator = index > #text or char == delimiter
        if delimiter == "%s" then
            separator = index > #text or char == " " or char == "\t" or char == "\r" or char == "\n"
        end
        if separator then
            if index > start then result[#result + 1] = string.sub(text, start, index - 1) end
            start = index + 1
        end
    end
    return result
end

function N.distance(x, y, xx, yy)
    local dx, dy = x - xx, y - yy
    return math.sqrt(dx * dx + dy * dy)
end

function N.readData(name)
    return getModFileReader(N.MOD_ID, "media/data/KnoxNavigator/" .. name, false)
end

-- Lua's bytewise lowercase cannot lowercase Cyrillic. Explicit replacements
-- keep Russian category aliases usable on Kahlua/Lua 5.1.
local upper = {"\208\144","\208\145","\208\146","\208\147","\208\148","\208\149","\208\129","\208\150","\208\151","\208\152","\208\153","\208\154","\208\155","\208\156","\208\157","\208\158","\208\159","\208\160","\208\161","\208\162","\208\163","\208\164","\208\165","\208\166","\208\167","\208\168","\208\169","\208\170","\208\171","\208\172","\208\173","\208\174","\208\175"}
local lower = {"\208\176","\208\177","\208\178","\208\179","\208\180","\208\181","\209\145","\208\182","\208\183","\208\184","\208\185","\208\186","\208\187","\208\188","\208\189","\208\190","\208\191","\209\128","\209\129","\209\130","\209\131","\209\132","\209\133","\209\134","\209\135","\209\136","\209\137","\209\138","\209\139","\209\140","\209\141","\209\142","\209\143"}
function N.normalize(text)
    text = text or ""
    local chars = {}
    for index = 1, #text do
        local char = string.sub(text, index, index)
        local position = string.find("ABCDEFGHIJKLMNOPQRSTUVWXYZ", char, 1, true)
        if position then char = string.sub("abcdefghijklmnopqrstuvwxyz", position, position) end
        chars[#chars + 1] = char
    end
    text = table.concat(chars)
    -- Use literal searches only. Kahlua gsub can reinterpret replacement
    -- strings as patterns, including percent characters in POI names.
    for i = 1, #upper do
        local parts, start = {}, 1
        local first, last = string.find(text, upper[i], start, true)
        while first do
            parts[#parts + 1] = string.sub(text, start, first - 1)
            parts[#parts + 1] = lower[i]
            start = last + 1
            first, last = string.find(text, upper[i], start, true)
        end
        parts[#parts + 1] = string.sub(text, start)
        text = table.concat(parts)
    end
    -- Kahlua's pattern implementation differs from standard Lua on anchored
    -- whitespace patterns. Trim literal characters without a pattern.
    local first, last = 1, #text
    local function whitespace(c) return c == " " or c == "\t" or c == "\r" or c == "\n" end
    while first <= last and whitespace(string.sub(text, first, first)) do first = first + 1 end
    while last >= first and whitespace(string.sub(text, last, last)) do last = last - 1 end
    return string.sub(text, first, last)
end

N.aliases = {
    ["\209\129\209\131\208\178\208\181\208\189\208\184\209\128\209\139"] = "gift shop", ["\209\129\209\131\208\178\208\181\208\189\208\184\209\128"] = "gift shop", ["\208\188\208\176\208\179\208\176\208\183\208\184\208\189 \208\191\208\190\208\180\208\176\209\128\208\186\208\190\208\178"] = "gift shop",
    ["\208\183\208\176\208\191\209\128\208\176\208\178\208\186\208\176"] = "gas station", ["\208\176\208\183\209\129"] = "gas station", ["\208\176\208\191\209\130\208\181\208\186\208\176"] = "pharmacy",
    ["\208\177\208\190\208\187\209\140\208\189\208\184\209\134\208\176"] = "hospital", ["\208\191\208\190\208\187\208\184\209\134\208\184\209\143"] = "police", ["\208\190\209\128\209\131\208\182\208\184\208\181"] = "gun",
    ["\209\129\209\131\208\191\208\181\209\128\208\188\208\176\209\128\208\186\208\181\209\130"] = "supermarket", ["\208\191\209\128\208\190\208\180\209\131\208\186\209\130\209\139"] = "grocery", ["\208\186\208\189\208\184\208\179\208\184"] = "book",
    ["\208\177\208\184\208\177\208\187\208\184\208\190\209\130\208\181\208\186\208\176"] = "library", ["\209\136\208\186\208\190\208\187\208\176"] = "school", ["\208\179\208\176\209\128\208\176\208\182"] = "auto repair",
    ["\208\176\208\178\209\130\208\190\209\129\208\181\209\128\208\178\208\184\209\129"] = "auto repair", ["\208\177\208\176\209\128"] = "bar", ["\208\177\208\176\208\189\208\186"] = "bank",
    ["\209\128\208\181\209\129\209\130\208\190\209\128\208\176\208\189"] = "restaurant", ["\208\191\208\190\209\135\209\130\208\176"] = "post office", ["\209\129\208\186\208\187\208\176\208\180"] = "warehouse",
    ["\208\191\208\190\208\182\208\176\209\128\208\189\208\176\209\143"] = "fire station", ["\208\190\208\180\208\181\208\182\208\180\208\176"] = "clothing", ["\209\134\208\181\209\128\208\186\208\190\208\178\209\140"] = "church"
}

function N.loadPOIs()
    if N.pois then return true end
    local reader = N.readData("pois.tsv")
    if not reader then N.dataError = "\208\157\208\181 \208\189\208\176\208\185\208\180\208\181\208\189 \208\186\208\176\209\130\208\176\208\187\208\190\208\179 \208\190\208\177\209\138\208\181\208\186\209\130\208\190\208\178"; return false end
    N.pois = {}
    local line = reader:readLine()
    while line do
        local parts = N.split(line, "\t")
        local x, y = tonumber(parts[2]), tonumber(parts[3])
        if x and y then
            N.pois[#N.pois + 1] = {name=parts[1], x=x, y=y, town=parts[4] or "", index=#N.pois + 1,
                search=N.normalize(parts[1] .. " " .. (parts[4] or ""))}
        end
        line = reader:readLine()
    end
    reader:close()
    return true
end

function N.search(query, x, y)
    N.loadPOIs()
    local terms = N.normalize(query)
    terms = N.aliases[terms] or terms
    local tokens = N.split(terms, "%s")
    local results = {}
    for _, poi in ipairs(N.pois or {}) do
        local match = true
        for _, token in ipairs(tokens) do
            if not string.find(poi.search, token, 1, true) then match = false; break end
        end
        if match then results[#results + 1] = {poi=poi, distance=N.distance(x,y,poi.x,poi.y)} end
    end
    table.sort(results, function(a,b)
        if a.distance == b.distance then return a.poi.index < b.poi.index end
        return a.distance < b.distance
    end)
    return results
end

function N.formatDistance(distance)
    if distance >= 1000 then return string.format("%.1f \208\186\208\188", distance / 1000) end
    return tostring(math.floor(distance + 0.5)) .. " \208\188"
end

function N.friendAllowed(name)
    local text = N.options and N.options:getOption("friends"):getValue() or ""
    if N.normalize(text) == "" then return true end
    for _, entry in ipairs(N.split(text, ",")) do
        if N.normalize(entry) == N.normalize(name) then return true end
    end
    return false
end
