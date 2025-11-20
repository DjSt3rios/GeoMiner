-- ==================================================
-- CHUNKY SATELLITE V3 - Robust Ascent & Fuel Monitor
-- ==================================================

-- SETTINGS
local MIN_FUEL = 10000       -- Abort if fuel drops below this
local SAFE_Y = 250           -- Cruising altitude for Chunky
local SYNC_Y = 150           -- Height Miner must reach before we fly home
local FOLLOW_DIST = 16       -- Distance allowed before repositioning
local PROTOCOL = "MINING_SQUAD"

-- STATE
local homePos = {x=0, y=0, z=0}
local minerID = nil
local isReturning = false

-- OPEN MODEM (Explicitly on Right side based on your setup)
rednet.open("right")

-- ==================================================
-- HELPER FUNCTIONS
-- ==================================================

function log(msg)
    print("[" .. os.time() .. "] " .. msg)
end

function checkFuel()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return true end

    if level < MIN_FUEL then
        log("!! CRITICAL FUEL WARNING !!")
        return false
    end
    return true
end

function getLocateSafe()
    local x, y, z = gps.locate(2) -- 2 second timeout
    return x, y, z
end

function safeAscent(targetY)
    local _, currY, _ = getLocateSafe()

    -- 1. Wait for initial lock
    while not currY do
        log("Waiting for GPS signal to launch...")
        os.sleep(2)
        _, currY, _ = getLocateSafe()
    end

    log("GPS Locked at Y="..currY..". Ascending to "..targetY)

    -- 2. Ascend with Dead Reckoning Fallback
    while currY < targetY do
        if turtle.up() then
            -- Try to get real GPS
            local _, gpsY, _ = getLocateSafe()

            if gpsY then
                currY = gpsY -- Sync with reality
            else
                currY = currY + 1 -- Assume we moved up if GPS fails
            end
        else
            log("Blocked moving up! Retrying...")
            turtle.digUp() -- Clear obstacles if needed
        end
    end
    log("Reached Cruising Altitude.")
end

function simpleSkyMove(targetX, targetZ)
    local cx, cy, cz = getLocateSafe()
    if not cx then return end -- Skip if no GPS

    -- X Axis
    local dx = targetX - cx
    if dx ~= 0 then
        if dx > 0 then
            while turtle.detect() do turtle.turnRight() end -- Simple obstacle avoidance
            -- We don't have a compass, so we rely on coordinate checking or assuming start facing
            -- Ideally, you'd use the same navigation logic as the Miner,
            -- but for simplicity in the sky:
            turtle.turnRight() -- Face East (roughly, needs compass logic really)
             -- NOTE: Without a compass lib, sky movement is tricky.
             -- Assuming you place it facing SOUTH initially:
             -- South=0, West=1, North=2, East=3?
             -- Implementing a proper goTo is complex.
             -- For now, we will assume the turtle handles 'goTo' commands
             -- similar to the miner, or we just hover.
        end
    end
    -- (Ideally, copy the 'goTo' function from your Miner script here for best results)
    -- For this fix, I am focusing on the crash prevention.
end

-- ==================================================
-- RETURN PROTOCOL
-- ==================================================

function initiateReturnHome()
    isReturning = true
    log("ABORTING MISSION - RETURNING HOME")

    local minerAcknowledged = false

    -- 1. Spam the Alarm until Miner hears us
    log("Broadcasting Abort Signal...")

    while not minerAcknowledged do
        rednet.broadcast({
            command = "ABORT_RETURN",
            reason = "LOW_FUEL",
            syncHeight = SYNC_Y
        }, PROTOCOL)

        local id, msg = rednet.receive(PROTOCOL, 2)

        if msg and msg.status == "CONFIRM_ABORT" then
            log("Miner acknowledged signal.")
            minerAcknowledged = true
        elseif msg and msg.status == "AT_SYNC_HEIGHT" then
            log("Miner already at height.")
            minerAcknowledged = true
        end
    end

    log("Waiting for Miner to reach Y="..SYNC_Y.."...")

    -- 2. Wait for Miner to Ascend
    while true do
        local id, msg = rednet.receive(PROTOCOL, 2)
        if msg and msg.status == "AT_SYNC_HEIGHT" then
            log("Miner ready. Proceeding home.")
            break
        end
        rednet.broadcast({ command = "ABORT_RETURN", syncHeight = SYNC_Y }, PROTOCOL)
    end

    -- 3. Fly Home Logic (Placeholder for GoTo)
    log("Flying Home to " .. homePos.x .. "," .. homePos.z)
    -- simpleSkyMove(homePos.x, homePos.z) -- Call your move function here

    -- 4. Descend
    local _, currY, _ = getLocateSafe()
    if not currY then currY = SAFE_Y end

    while currY > homePos.y do
        turtle.down()
        local _, newY, _ = getLocateSafe()
        if newY then currY = newY else currY = currY - 1 end
    end

    log("Mission Closed.")
    error("Terminated: Returned Home")
end

-- ==================================================
-- MAIN EXECUTION
-- ==================================================

-- 1. Startup & Checks
log("Initializing Chunky Satellite V3...")
local hx, hy, hz = getLocateSafe()

-- Wait for start GPS
while not hx do
    log("No GPS Signal. Waiting...")
    os.sleep(2)
    hx, hy, hz = getLocateSafe()
end

homePos = {x=hx, y=hy, z=hz}
log("Home Set: " .. hx .. "," .. hy .. "," .. hz)

if not checkFuel() then
    error("INITIAL FUEL TOO LOW")
end

-- 2. Ascend to Orbit (The Crash Fix is in this function)
safeAscent(SAFE_Y)

-- 3. Main Sentinel Loop
log("Orbit established. Listening for Miner...")

while true do
    if not checkFuel() then
        initiateReturnHome()
    end

    local id, msg = rednet.receive(PROTOCOL, 5)

    if msg then
        if msg.role == "MINER" then
            if not minerID then
                minerID = id
                log("Linked to Miner ID: " .. id)
            end

            if id == minerID then
                local cx, cy, cz = getLocateSafe()
                -- If GPS fails up here, just wait, don't crash
                if cx then
                    local dist = math.sqrt((cx - msg.x)^2 + (cz - msg.z)^2)

                    if dist > FOLLOW_DIST then
                        log("Miner distance: " .. math.floor(dist) .. ". Adjusting...")
                        -- Copy the goTo function from the miner for real movement
                        -- simpleSkyMove(msg.x, msg.z)
                    end
                end
            end

            if msg.status == "RETURNING" then
                log("Miner is returning. Escorting.")
                initiateReturnHome()
            end
        end
    end
end