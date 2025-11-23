local geo = peripheral.find("geo_scanner")
if not geo then error("No Geo Scanner attached!") end

-- --- INPUT ---
local tArgs = { ... }
local target_input = tArgs[1]

if not target_input then
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.yellow)
    print("--- DIRECTIONAL SCANNER ---")
    term.setTextColor(colors.white)
    print("Enter partial name.")
    print("Examples: 'diamond', 'chest'")
    write("Target: ")
    target_input = read()
end
-- -------------

local radius = 16
local cooldown = 3

local function getDistance(x, y, z)
    return math.sqrt(x*x + y*y + z*z)
end

local function clear()
    term.clear()
    term.setCursorPos(1,1)
end

print("Scanning for: " .. target_input)
sleep(1)

while true do
    local data = geo.scan(radius)
    local nearest = nil
    local min_dist = 9999
    local count = 0

    local nearby_samples = {}

    if data then
        for _, block in pairs(data) do
            local name = string.lower(block.name)
            local search = string.lower(target_input)

            -- Sample nearby blocks for debug
            if #nearby_samples < 3 then
                local known = false
                for _, s in pairs(nearby_samples) do if s == block.name then known = true end end
                if not known then table.insert(nearby_samples, block.name) end
            end

            -- Check for match
            if string.find(name, search) then
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
    print("TARGET: " .. string.upper(target_input))
    print("----------------")

    if nearest then
        term.setTextColor(colors.lime)
        print("FOUND: " .. count .. " blocks")
        print("DIST:  " .. math.floor(min_dist) .. "m")
        print("")

        -- THE DIRECTIONAL LOGIC YOU ASKED FOR
        term.setTextColor(colors.white)

        -- 1. North/South (Z Axis)
        if nearest.z < 0 then
            print("NORTH: " .. math.abs(nearest.z))
        elseif nearest.z > 0 then
            print("SOUTH: " .. nearest.z)
        end

        -- 2. East/West (X Axis)
        if nearest.x < 0 then
            print("WEST:  " .. math.abs(nearest.x))
        elseif nearest.x > 0 then
            print("EAST:  " .. nearest.x)
        end

        -- 3. Up/Down (Y Axis)
        if nearest.y < 0 then
            print("DOWN:  " .. math.abs(nearest.y))
        elseif nearest.y > 0 then
            print("UP:    " .. nearest.y)
        end

        -- 4. If you are standing exactly on it
        if nearest.x == 0 and nearest.y == 0 and nearest.z == 0 then
            term.setTextColor(colors.yellow)
            print(">> YOU ARE HERE <<")
        end

    else
        -- FAILURE / DEBUG MODE
        term.setTextColor(colors.red)
        print("No match for '"..target_input.."'")
        print("")
        term.setTextColor(colors.gray)
        print("Nearby examples:")
        for _, name in pairs(nearby_samples) do
            local cleanName = name:gsub("minecraft:", ""):gsub("deepslate:", "")
            print("- " .. cleanName)
        end
    end

    sleep(cooldown)
end