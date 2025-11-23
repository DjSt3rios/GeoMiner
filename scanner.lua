local geo = peripheral.find("geo_scanner")
if not geo then error("No Geo Scanner attached!") end

-- --- INPUT ---
local tArgs = { ... }
local target_input = tArgs[1]

if not target_input then
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.yellow)
    print("--- UNIVERSAL SCANNER ---")
    term.setTextColor(colors.white)
    print("Enter partial name.")
    print("Examples: 'diamond', 'log', 'chest'")
    write("Target: ")
    target_input = read()
end
-- -------------

local radius = 16
local cooldown = 1

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

    -- For the "Did you mean?" feature
    local nearby_samples = {}

    if data then
        for _, block in pairs(data) do
            local name = string.lower(block.name)
            local search = string.lower(target_input)

            -- CAPTURE SAMPLES (Grab the first 3 unique blocks we see)
            if #nearby_samples < 3 then
                local known = false
                for _, s in pairs(nearby_samples) do if s == block.name then known = true end end
                if not known then table.insert(nearby_samples, block.name) end
            end

            -- CHECK FOR MATCH
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
    print("SEARCHING: " .. string.upper(target_input))
    print("Radius: " .. radius)
    print("----------------")

    if nearest then
        -- SUCCESS MODE
        term.setTextColor(colors.lime)
        print("TARGET ACQUIRED!")
        print("Count:   " .. count)
        print("Nearest: " .. math.floor(min_dist) .. "m")
        print("")

        term.setTextColor(colors.white)
        -- Height
        if nearest.y > 0 then print("  UP:   " .. nearest.y)
        elseif nearest.y < 0 then print("  DOWN: " .. math.abs(nearest.y))
        else print("  LEVEL HEIGHT") end

        -- Direction
        local dirStr = ""
        if nearest.z < 0 then dirStr = "NORTH"
        elseif nearest.z > 0 then dirStr = "SOUTH" end

        if nearest.x < 0 then dirStr = dirStr .. " WEST"
        elseif nearest.x > 0 then dirStr = dirStr .. " EAST" end

        if dirStr == "" then dirStr = "Here" end
        print("  DIR:  " .. dirStr)

    else
        -- FAILURE / DEBUG MODE
        term.setTextColor(colors.red)
        print("No exact match for '"..target_input.."'")
        print("")

        term.setTextColor(colors.yellow)
        print("I did see these nearby:")
        term.setTextColor(colors.gray)
        for _, name in pairs(nearby_samples) do
            -- Strip the 'minecraft:' part to make it readable
            local cleanName = name:gsub("minecraft:", ""):gsub("deepslate:", "")
            print("- " .. cleanName)
        end

        print("")
        print("Try typing one of those!")
    end

    sleep(cooldown)
end