-- Save this as "refuel_station.lua"

-- CONFIGURATION
local MIN_FUEL_LIMIT = 9000000 -- Refuel if fuel is below this
local MAX_FUEL_LIMIT = 9000000 -- Stop refueling if above this (Max is 20k usually, or 100k for advanced)
local CHECK_DELAY = 5 -- Seconds to wait between checks

-- Function to find a specific item in the inventory
local function findSlot(itemName)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == itemName then
            return i
        end
    end
    return nil
end

-- Function to handle the refueling process
local function attemptRefuel()
    print("Attempting to refuel...")

    -- 1. Locate an Empty Bucket
    local bucketSlot = findSlot("minecraft:bucket")

    if not bucketSlot then
        print("Error: No empty bucket found!")
        return false
    end

    -- 2. Select the bucket
    turtle.select(bucketSlot)

    -- 3. Scoop the lava (placeDown with a bucket collects liquid)
    local success, reason = turtle.placeDown()

    if success then
        -- 4. Refuel using the now-filled bucket
        -- Note: turtle.placeDown() converts the empty bucket in hand to a lava bucket
        turtle.refuel()
        print("Refueled! Current Level: " .. turtle.getFuelLevel())
        return true
    else
        print("Could not scoop lava. Is the source empty?")
        return false
    end
end

-- Main Loop
while true do
    local currentLevel = turtle.getFuelLevel()

    if currentLevel == "unlimited" then
        print("Fuel is unlimited. Exiting.")
        break
    end

    print("Current Fuel: " .. currentLevel)

    if currentLevel < MIN_FUEL_LIMIT then
        print("Fuel low. Starting refuel cycle...")

        -- Keep refueling until we hit the max or run out of lava
        while turtle.getFuelLevel() < MAX_FUEL_LIMIT do
            local result = attemptRefuel()
            if not result then
                print("Waiting for lava to refill...")
                sleep(5) -- Wait longer if the tank flows slowly
            else
                sleep(0.5) -- Short pause to prevent glitching
            end
        end

        print("Refueling complete.")
    else
        print("Fuel sufficient. Sleeping.")
    end

    -- Wait before checking again
    sleep(CHECK_DELAY)
end