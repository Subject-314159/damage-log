-- Data model
-- storage = {
--     [force.index] = {
--         damage = {
--             [surface.index] = {
--                 [x] = {
--                     [y] = {
--                         damage_decayed = double, -- The remaining decayed damage at the last_tick
--                         last_tick = int
--                     }
--                 }
--             }
--         }
--     }
-- }
-- Internal constants
-- Some numbers for reference
-- 30 minutes = 108.000 ticks
-- 1 legendary gun turret (1000h) per minute for 30 minutes = 30.000 health
-- 1 legendary wall (850h) per minute for 30 minutes = 26.250 health
-- 1 normal wall (350h) per 5 minutes for 30 minutes = 2.100 health
local DECAY_CONSTANT = 314159 -- bigger = slower decay
local MIN_TICK_DELTA = 60 -- Minimum tick delay before we need to start calculating the decay
local MAX_TICK_DELTA = 108000 -- Maximum tick delay cut-off
local kernel = {{1, 2, 1}, {2, 4, 2}, {1, 2, 1}}
local KSUM = 16

local STRIDE = 2200000
local BUCKET_SIZE = 64

local damage = {}
--------------------------------------------------
-- Storage interfaces
--------------------------------------------------

local get_storage = function(force_index)
    if not storage.forces[force_index] then
        return
    end
    return storage.forces[force_index].damage
end
local get_cell = function(force_index, tick, surface_index, x, y)
    -- Ensure storage
    local dmg = get_storage(force_index)
    if not dmg then
        return
    end
    dmg[surface_index] = dmg[surface_index] or {}
    dmg[surface_index][x] = dmg[surface_index][x] or {}
    dmg[surface_index][x][y] = dmg[surface_index][x][y] or {}
    return dmg[surface_index][x][y]
end

local get_decayed_damage = function(value, old_tick, new_tick)
    -- Early exit if no (positive) value was passed
    if not value or value <= 0 then
        return 0
    end

    -- Get time delta or early exit if outside of range
    local dt = new_tick - old_tick
    if dt <= MIN_TICK_DELTA then
        return value
    elseif dt >= MAX_TICK_DELTA then
        return 0
    end

    -- Calculate new decayed value
    -- local decayed = value * math.exp(-dt / DECAY_CONSTANT) -- Option 1: Exponential decay
    local decayed = value * (1 - (dt / MAX_TICK_DELTA)) -- Option 2: Linear decay
    return decayed
end

-- AutoHelpers
local parent = {}
local rank = {}
local clusterValue = {}
local buckets = {}
local activeCells = {}
local offsets = {{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {0, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}
local clusters = {}

local function pack(x, y)
    return x * STRIDE + y
end

local function unpack(k)
    local x = math.floor(k / STRIDE)
    local y = k - x * STRIDE
    return x, y
end

local function find(x)
    local p = parent[x]
    if p ~= x then
        parent[x] = find(p)
    end
    return parent[x]
end

local function union(a, b)
    local ra = find(a)
    local rb = find(b)
    if ra == rb then
        return
    end

    if rank[ra] < rank[rb] then
        parent[ra] = rb
        clusterValue[rb] = clusterValue[rb] + clusterValue[ra]
    else
        parent[rb] = ra
        clusterValue[ra] = clusterValue[ra] + clusterValue[rb]
        if rank[ra] == rank[rb] then
            rank[ra] = rank[ra] + 1
        end
    end
end

local function bucketKey(x, y)
    local bx = math.floor(x / BUCKET_SIZE)
    local by = math.floor(y / BUCKET_SIZE)
    return bx * 100000 + by
end

local function addCell(x, y, value)
    local k = pack(x, y)

    activeCells[k] = value
    parent[k] = k
    rank[k] = 0
    clusterValue[k] = value

    local b = bucketKey(x, y)
    local list = buckets[b]
    if not list then
        list = {}
        buckets[b] = list
    end
    list[#list + 1] = k
end
local function shouldConnect(k1, k2, v1, v2)
    local x1, y1 = unpack(k1)
    local x2, y2 = unpack(k2)

    local dx = x1 - x2
    local dy = y1 - y2
    local r = math.min(v1, v2)

    return dx * dx + dy * dy <= r * r
end

local get_mock = function()
    for bkey, list in pairs(buckets) do
        local bx = math.floor(bkey / 100000)
        local by = bkey - bx * 100000

        for _, o in ipairs(offsets) do
            local nb = (bx + o[1]) * 100000 + (by + o[2])
            local other = buckets[nb]
            if other then
                for _, k1 in ipairs(list) do
                    local v1 = activeCells[k1]
                    for _, k2 in ipairs(other) do
                        local v2 = activeCells[k2]
                        if shouldConnect(k1, k2, v1, v2) then
                            union(k1, k2)
                        end
                    end
                end
            end
        end
    end

    for k in pairs(activeCells) do
        local r = find(k)
        local c = clusters[r]
        if not c then
            c = {
                value = 0,
                cells = 0
            }
            clusters[r] = c
        end
        c.cells = c.cells + 1
        c.value = clusterValue[r]
    end
end

--------------------------------------------------
-- Read
--------------------------------------------------

damage.get = function(force_index, surface_index, bounding_box)
    -- Get storage
    local dmg = get_storage(force_index)
    if not dmg or not dmg[surface_index] then
        return
    end
    local ds = dmg[surface_index]

    -- Get grid bounds
    local minX = bounding_box[1][1]
    local maxX = bounding_box[2][1]
    local minY = bounding_box[1][2]
    local maxY = bounding_box[2][2]
    -- game.print("BoundingBox=" .. serpent.line({{minX, minY}, {maxX, maxY}}))
    for x, col in pairs(ds) do
        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        for y, _ in pairs(col) do
            if y < minY then
                minY = y
            end
            if y > maxY then
                maxY = y
            end
        end
    end

    -- Make empty dense grid
    local mat = {}
    for x = minX - 1, maxX + 1 do
        mat[x] = {}
        for y = minY - 1, maxY + 1 do
            mat[x][y] = 0
        end
    end

    -- fill the grid
    for x, col in pairs(ds or {}) do
        for y, data in pairs(col or {}) do
            if x > minX and x < maxX and y > minY and y < maxY then
                local dam = get_decayed_damage(ds[x][y].damage_decayed, ds[x][y].last_tick, game.tick)
                -- game.print("(" .. game.tick .. ") {" .. x .. "," .. y .. "} has dmg " .. dam .. " based on " ..
                --                ds[x][y].damage_decayed .. " decayed damage at tick " .. ds[x][y].last_tick .. "(" ..
                --                ds[x][y].last_tick - game.tick .. ")")
                mat[x][y] = dam
            end
        end
    end

    -- Gaussian blur the grid
    local out = {}
    for x = minX - 1, maxX + 1 do
        out[x] = {}
        for y = minY - 1, maxY + 1 do
            local sum = 0
            for ky = -1, 1 do
                for kx = -1, 1 do
                    local yy = y + ky
                    local xx = x + kx
                    if mat[xx] and mat[xx][yy] then
                        sum = sum + mat[xx][yy] * kernel[kx + 2][ky + 2]
                    end
                end
            end
            local dam = sum / KSUM
            out[x][y] = dam
        end
    end

    return out
end

--------------------------------------------------
-- Create/update
--------------------------------------------------

damage.log = function(force_index, tick, surface_index, x, y, damage_amount)
    -- Get storage cell
    local dmg = get_cell(force_index, tick, surface_index, x, y)
    if not dmg then
        return
    end

    -- Update value decayed based on delta last tick
    local decayed_damage = 0
    if dmg.damage_decayed then
        decayed_damage = get_decayed_damage(dmg.damage_decayed, dmg.last_tick, game.tick)
    end
    dmg.damage_decayed = decayed_damage + damage_amount
    dmg.last_tick = tick
end

damage.init = function()
    for _, p in pairs(game.players) do
        if not storage.forces[p.force.index] then
            storage.forces[p.force.index] = {}
        end
        if not storage.forces[p.force.index].damage then
            storage.forces[p.force.index].damage = {}
        end
    end
end

return damage
