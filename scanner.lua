local geo = peripheral.find("geo_scanner")
if not geo then error("No Geo Scanner attached!") end

-- --- INPUT HANDLING ---
local tArgs = { ... } -- Check if user typed "radar iron" directly
local target_name = tArgs[1]

if not target_name then
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.yellow)
    print("--- ORE SCANNER SETUP ---")
    term.setTextColor(colors.white)
    write("Target Ore (e.g. iron): ")
    target_name = read() -- <--- This waits for you to type!
end
-- ----------------------

local radius = 8
local cooldown = 3

local function getDistance(x, y, z)
    return math.sqrt(x*x + y*y + z*z)
end

local function clear()
    term.clear()
    term.setCursorPos(1,1)
end

print("Initializing scan for: " .. target_name)
sleep(1)

while true do
    local data = geo.scan(radius)
    local nearest = nil
    local min_dist = 9999
    local count = 0 -- Counts how many blocks found total

    if data then
        for _, block in pairs(data) do
            -- 'string.find' allows "iron" to match "deepslate_iron_ore"
            if string.find(block.name, target_name) then
                count = count + 1
                local d = getDistance(block.x, block.y, block.z)
                if d < min_dist then
                    min_dist = d
                    nearest = block
                end
            end
        end
    end

    -- DRAW HUD
    clear()
    term.setTextColor(colors.orange)
    print("SCANNING FOR: " .. string.upper(target_name))
    print("----------------")

    if nearest then
        term.setTextColor(colors.lime)
        print("FOUND: " .. count .. " blocks nearby")
        print("NEAREST: " .. math.floor(min_dist) .. "m away")
        print("")

        term.setTextColor(colors.white)

        -- Height Guide
        if nearest.y > 0 then print("  UP:   " .. nearest.y)
        elseif nearest.y < 0 then print("  DOWN: " .. math.abs(nearest.y))
        else print("  LEVEL HEIGHT") end

        -- North/South (Z)
        if nearest.z < 0 then print("  NORTH: " .. math.abs(nearest.z))
        elseif nearest.z > 0 then print("  SOUTH: " .. nearest.z)
        end

        -- East/West (X)
        if nearest.x < 0 then print("  WEST:  " .. math.abs(nearest.x))
        elseif nearest.x > 0 then print("  EAST:  " .. nearest.x)
        end

    else
        term.setTextColor(colors.red)
        print("Status: SEARCHING...")
        print("")
        term.setTextColor(colors.gray)
        print("No " .. target_name .. " in range.")
        print("Move to a new spot.")
    end

    sleep(cooldown)
end