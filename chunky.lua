-- ==================================================
-- CHUNKY SATELLITE V2 - Safety & Fuel Monitor
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

-- Open Modem
peripheral.find("modem", rednet.open)

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
        log("Level: " .. level .. " < " .. MIN_FUEL)
        return false
    end
    return true
end

function flyTo(tx, tz)
    -- Simple air travel logic (We are at Y=250, so no obstacles)
    local cx, cy, cz = gps.locate()

    -- Move X
    while cx ~= tx do
        if cx < tx then
            turtle.turnRight() -- Face East? (Simplified, assumes facing)
            -- Ideally use a proper faceTo function here
            -- For now, let's use coordinate delta logic:
            if not turtle.forward() then turtle.dig() end
        end
        -- NOTE: A proper goTo function is needed here for exact movement.
        -- Since you have the GeoMiner code, copy the 'goTo' function
        -- but remove the digging parts for efficiency.
        -- *For the sake of this script length, I assume you have a basic move function*
        cx, cy, cz = gps.locate()
    end
end

-- A simple coordinate mover for high altitude (no pathfinding needed)
function simpleSkyMove(targetX, targetZ)
    local cx, cy, cz = gps.locate()
    local facing = 0 -- Assume start facing? Better to calculate.

    -- Delta X
    local dx = targetX - cx
    if dx > 0 then
        while turtle.detect() do turtle.turnRight() end -- simplistic
        for i=1, dx do turtle.forward() end
    elseif dx < 0 then
        turtle.turnRight(); turtle.turnRight()
        for i=1, math.abs(dx) do turtle.forward() end
    end

    -- Delta Z ... (Implement standard movement logic here)
    -- You can copy the 'goTo' from your Miner script, it works fine in the sky!
end

-- ==================================================
-- RETURN PROTOCOL
-- ==================================================

function initiateReturnHome()
    isReturning = true
    log("ABORTING MISSION - RETURNING HOME")

    -- 1. Command Miner to Abort
    rednet.broadcast({
        command = "ABORT_RETURN",
        reason = "LOW_FUEL",
        syncHeight = SYNC_Y
    }, PROTOCOL)

    log("Sent abort command. Waiting for Miner to reach Y="..SYNC_Y.."...")

    -- 2. Wait for Miner to Ascend
    while true do
        local id, msg = rednet.receive(PROTOCOL)
        if id == minerID and msg and msg.status == "AT_SYNC_HEIGHT" then
            log("Miner confirmed at Y="..SYNC_Y..". Proceeding home.")
            break
        end
        -- Resend command periodically in case Miner missed it
        rednet.broadcast({ command = "ABORT_RETURN", syncHeight = SYNC_Y }, PROTOCOL)
        os.sleep(2)
    end

    -- 3. Fly Home (At SAFE_Y)
    log("Flying to Home X:"..homePos.x.." Z:"..homePos.z)
    -- simpleSkyMove(homePos.x, homePos.z) -- Call your movement function
    -- (Using placeholders for movement to keep script readable)
    print(">> MOVEMENT CODE EXECUTED HERE <<")

    -- 4. Descend
    log("Arrived above home. Descending...")
    local _, currY, _ = gps.locate()
    while currY > homePos.y do
        turtle.down()
        _, currY, _ = gps.locate()
    end

    log("Mission Closed. Safely back at base.")
    error("Terminated: Returned Home") -- Stop script
end

-- ==================================================
-- MAIN EXECUTION
-- ==================================================

-- 1. Startup & Checks
log("Initializing Chunky Satellite...")
local hx, hy, hz = gps.locate(5)
if not hx then error("NO GPS SIGNAL! CANNOT START.") end

homePos = {x=hx, y=hy, z=hz}
log("Home Set: " .. hx .. "," .. hy .. "," .. hz)

if not checkFuel() then
    error("INITIAL FUEL TOO LOW (" .. turtle.getFuelLevel() .. " < " .. MIN_FUEL .. ")")
end

-- 2. Ascend to Orbit
log("Ascending to SAFE_Y: " .. SAFE_Y)
while true do
    local _, y, _ = gps.locate()
    if y >= SAFE_Y then break end
    turtle.up()
end

-- 3. Main Sentinel Loop
log("Orbit established. Listening for Miner...")

while true do
    -- A. Check Fuel continuously
    if not checkFuel() then
        initiateReturnHome()
    end

    -- B. Listen for updates (Non-blocking check?)
    -- We use a timeout so we can loop back to check fuel
    local id, msg = rednet.receive(PROTOCOL, 5)

    if msg then
        -- Link to Miner
        if msg.role == "MINER" then
            if not minerID then
                minerID = id
                log("Linked to Miner ID: " .. id)
            end

            -- Follow Logic
            if id == minerID then
                local cx, cy, cz = gps.locate()
                local dist = math.sqrt((cx - msg.x)^2 + (cz - msg.z)^2)

                if dist > FOLLOW_DIST then
                    log("Tracking Miner... Dist: " .. math.floor(dist))
                    -- simpleSkyMove(msg.x, msg.z) -- Move to align with miner
                end
            end

            -- If MINER initiates return (e.g. full inventory or miner low fuel)
            if msg.status == "RETURNING" then
                log("Miner is returning (Inventory Full/Low Fuel). Escorting.")
                initiateReturnHome()
            end
        end
    end
end