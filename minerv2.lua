--[[
GeoMiner v2.0 - Fleet Edition
Copyright (C) 2024 Alexander Blinov (Modified for Mining Squad)
]]

local basalt = require("basalt")

local w, h = term.getSize()
local currentFrameName = nil
local frames = {}

-- Hardware
local scanner = peripheral.find("geo_scanner")
-- NOTE: Modem is expected in Slot 16!

-- Tracking & Mining State
local scanRadius = 16 -- Default to max for column mining
local blocks = {}
local blocksNamesSet = {}
local blocksToMine = {}
local visitedSectors = {} -- Tracks X,Z coordinates we have already cleared
local MIN_FUEL_THRESHOLD = 1000
local TARGET_X = nil
local TARGET_Z = nil

-- ORE MAPPING (Auto-add Deepslate)
local ORE_MAP = {
    ["iron_ore"] = "deepslate_iron_ore",
    ["gold_ore"] = "deepslate_gold_ore",
    ["copper_ore"] = "deepslate_copper_ore",
    ["coal_ore"] = "deepslate_coal_ore",
    ["lapis_ore"] = "deepslate_lapis_ore",
    ["diamond_ore"] = "deepslate_diamond_ore",
    ["redstone_ore"] = "deepslate_redstone_ore",
    ["emerald_ore"] = "deepslate_emerald_ore"
}

-- Utils
local minerStatusLabel, minerStartButton, minerProgressBar, minerProgressLabel
local minerDirectionLabel, minerDirectionDropdown
local currentBlockName = ""
local movesSincePing = 0

local JUNK_LIST = {
    ["stone"] = true, ["cobblestone"] = true, ["dirt"] = true, ["gravel"] = true,
    ["diorite"] = true, ["granite"] = true, ["deepslate"] = true, ["cobbled_deepslate"] = true,
    ["tuff"] = true, ["netherrack"] = true, ["sand"] = true, ["sandstone"] = true,
    ["red_sand"] = true, ["red_sandstone"] = true, ["end_stone"] = true, ["andesite"] = true
}

-- LOGGING
local logList = nil
local MAX_LOG_LINES = 100

function addLog(message)
    if logList then
        logList:addItem(tostring(message))
        if #logList:getAll() > MAX_LOG_LINES then logList:removeItem(1) end
    end
    -- print("[LOG] " .. tostring(message))
end

-- =============================================================================
-- FLEET COMMUNICATION & TRACKING
-- =============================================================================

local MISSION_ABORTED = false

function reportLocation(status)
    -- 1. Check if we already aborted
    if MISSION_ABORTED then return end

    local x, y, z = gps.locate()
    if not x then return end

    -- 2. Throttle: Only run every 5 moves (unless it's a status change)
    if status == "Mining" or status == "Moving" then
        movesSincePing = movesSincePing + 1
        if movesSincePing < 5 then return end
    end
    movesSincePing = 0

    -- 3. HOT SWAP & CHECK MAILBOX
    turtle.select(16)
    if turtle.equipRight() then
        rednet.open("right")

        -- A. Send our status
        rednet.broadcast({
            role="MINER",
            x=x, y=y, z=z,
            status=status or "Mining"
        }, "MINING_SQUAD")

        -- B. CHECK FOR MESSAGES (The Fix)
        -- We listen for 0.2 seconds while the modem is up
        local senderId, message = rednet.receive("MINING_SQUAD", 0.2)

        if message and message.command == "ABORT_RETURN" then
            addLog("!!! ABORT SIGNAL RECEIVED !!!")
            MISSION_ABORTED = true

            -- Send Confirmation so Chunky stops screaming
            rednet.broadcast({
                role="MINER",
                status="CONFIRM_ABORT"
            }, "MINING_SQUAD")
        end

        rednet.close("right")
        turtle.equipRight() -- Swap Scanner back
    end
    turtle.select(1)
end

function checkAborts()
    -- Quick listen for Abort command from Satellite without swapping modem
    -- (Requires modem to be equipped, which it isn't usually during mining)
    -- So we skip this for now unless we want to swap every loop, which is slow.
    -- Instead, we rely on fuel checks.
    if turtle.getFuelLevel() < MIN_FUEL_THRESHOLD then
        return "LOW_FUEL"
    end
    return nil
end

-- =============================================================================
-- STANDARD UTILS
-- =============================================================================

function splitString(input, delimiter)
    if delimiter == nil then delimiter = "%s" end
    local t = {}
    for str in string.gmatch(input, "([^"..delimiter.."]+)") do table.insert(t, str) end
    return t
end

function manhattanDist(x1, y1, z1, x2, y2, z2)
    return math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)
end

function directionFromTo(x1, y1, z1, x2, y2, z2)
    if x1 < x2 then return "E"
    elseif x1 > x2 then return "W"
    elseif z1 < z2 then return "S"
    elseif z1 > z2 then return "N"
    elseif y1 < y2 then return "up"
    elseif y1 > y2 then return "down"
    end
end

function turnTo(newDirection, direction)
    if direction[1] == newDirection then return end
    -- Simple turning logic
    local turns = {N=0, E=1, S=2, W=3}
    local curr = turns[direction[1]]
    local target = turns[newDirection]
    local diff = (target - curr) % 4

    if diff == 1 then turtle.turnRight()
    elseif diff == 2 then turtle.turnRight(); turtle.turnRight()
    elseif diff == 3 then turtle.turnLeft() end

    direction[1] = newDirection
end

-- =============================================================================
-- MOVEMENT ENGINE
-- =============================================================================

function smartMove(action, direction)
    if MISSION_ABORTED then return false end -- STOP MOVING IMMEDIATELY

    local result = false
    if action == "up" then
        while turtle.detectUp() do turtle.digUp() end
        result = turtle.up()
    elseif action == "down" then
        while turtle.detectDown() do turtle.digDown() end
        result = turtle.down()
    elseif action == "forward" then
        while turtle.detect() do turtle.dig() end
        result = turtle.forward()
    end

    if result then reportLocation("Moving") end
    return result
end

function skyTravel(tx, ty, tz, direction)
    -- Used for commuting at height
    local cx, cy, cz = gps.locate()
    if not cx then addLog("No GPS for SkyTravel!"); return false end

    addLog("Commuting to: "..tx..","..ty..","..tz)

    -- 1. Match Height
    while cy < ty do smartMove("up"); _, cy = gps.locate() end
    while cy > ty do smartMove("down"); _, cy = gps.locate() end

    -- 2. Match X
    if cx < tx then turnTo("E", direction) while cx < tx do smartMove("forward", direction); cx=cx+1 end
    elseif cx > tx then turnTo("W", direction) while cx > tx do smartMove("forward", direction); cx=cx-1 end end

    -- 3. Match Z
    if cz < tz then turnTo("S", direction) while cz < tz do smartMove("forward", direction); cz=cz+1 end
    elseif cz > tz then turnTo("N", direction) while cz > tz do smartMove("forward", direction); cz=cz-1 end end

    return true
end

-- A* Logic omitted for brevity, standard simple digging logic used for local ores
function findClosestBlock(blocksToMine, blocks, startPos)
    local closestBlock = nil
    local min_distance = math.huge

    for _, block in ipairs(blocks) do
        local blockType = splitString(block.name, ":")[2]
        if blocksToMine[blockType] then
            local distance = manhattanDist(startPos[1], startPos[2], startPos[3], block.x, block.y, block.z)
            if distance < min_distance then
                min_distance = distance
                closestBlock = block
            end
        end
    end
    return closestBlock
end

-- =============================================================================
-- INVENTORY MANAGEMENT
-- =============================================================================

function manageInventory()
    for i = 1, 15 do -- Avoid slot 16 (Modem)
        local item = turtle.getItemDetail(i)
        if item then
            local itemName = splitString(item.name, ":")[2]
            if JUNK_LIST[itemName] then
                turtle.select(i)
                turtle.drop()
            end
        end
    end
    -- Check if full (ignoring fuel/modem)
    if turtle.getItemCount(15) > 0 then
        -- Compact items
        for i=1,15 do turtle.select(i); for j=i+1,15 do turtle.transferTo(j) end end
    end
    turtle.select(1)
end

-- SAFE GPS LOCATOR (Auto-Swaps Modem)
function getLocate()
    -- 1. Try standard locate first (in case modem is already active)
    local x, y, z = gps.locate(2)
    if x then return x, y, z end

    -- 2. If failed, perform the Hot-Swap
    local previousSlot = turtle.getSelectedSlot()

    -- Select Modem Slot (16)
    turtle.select(16)

    -- Swap: Modem goes to Right Hand, Scanner goes to Slot 16
    if not turtle.equipRight() then
        addLog("GPS Error: No Modem in Slot 16!")
        return nil, nil, nil
    end

    -- Open Rednet and Locate
    rednet.open("right")
    x, y, z = gps.locate(2) -- 2 second timeout

    -- Swap Back: Scanner goes to Right Hand, Modem goes to Slot 16
    turtle.equipRight()

    -- Restore slot
    turtle.select(previousSlot)

    return x, y, z
end

-- =============================================================================
-- MAIN LOGIC: THE SECTOR MINER
-- =============================================================================

function clearLocalArea(localBlocks, direction)
    -- This is the "Local Area" miner (moves relative to start of scan)
    local currentPos = {0,0,0} -- Relative

    while true do
        local target = findClosestBlock(blocksToMine, localBlocks, currentPos)
        if not target then break end -- Done with this cluster

        -- Move to Target Logic (Simple Manhattan Dig)
        local dx = target.x - currentPos[1]
        local dy = target.y - currentPos[2]
        local dz = target.z - currentPos[3]

        -- X
        if dx ~= 0 then
            turnTo(dx > 0 and "E" or "W", direction)
            for _=1, math.abs(dx) do smartMove("forward", direction) end
        end
        -- Z
        if dz ~= 0 then
            turnTo(dz > 0 and "S" or "N", direction)
            for _=1, math.abs(dz) do smartMove("forward", direction) end
        end
        -- Y
        while dy ~= 0 do
            if dy > 0 then smartMove("up"); dy=dy-1
            else smartMove("down"); dy=dy+1 end
        end

        -- Dig the block (it's adjacent now, find which side)
        -- Actually, previous loop puts us IN the block.
        -- Correct logic: Move adjacent, then dig.
        -- SIMPLIFICATION: Just move into it (smartMove digs).

        currentPos = {target.x, target.y, target.z}

        -- Remove from list
        for i,b in ipairs(localBlocks) do
            if b.x == target.x and b.y == target.y and b.z == target.z then
                table.remove(localBlocks, i)
                break
            end
        end
    end

    -- Return to relative 0,0,0 (center of shaft)
    -- Reverse X, Z, Y movements...
    if currentPos[1] ~= 0 then
         turnTo(currentPos[1] > 0 and "W" or "E", direction)
         for _=1, math.abs(currentPos[1]) do smartMove("forward", direction) end
    end
    if currentPos[3] ~= 0 then
         turnTo(currentPos[3] > 0 and "N" or "S", direction)
         for _=1, math.abs(currentPos[3]) do smartMove("forward", direction) end
    end
    while currentPos[2] > 0 do smartMove("down"); currentPos[2]=currentPos[2]-1 end
    while currentPos[2] < 0 do smartMove("up"); currentPos[2]=currentPos[2]+1 end
end

function SectorMinerLogic()
    addLog("Mission Started: Sector Mining")
    local COMMUTE_Y = 120
    local direction = {"S"}

    -- FIX: Use safe getLocate() instead of raw gps.locate()
    local cx, cy, cz = getLocate()

    if not cx then
        addLog("CRITICAL: No GPS Signal. Aborting.")
        return
    end

    -- 1. Commute to Initial Target
    if TARGET_X and TARGET_Z then
        addLog("Commuting to Start Zone...")
        -- Optimization: Equip Modem PERMANENTLY for the long flight
        turtle.select(16)
        turtle.equipRight()
        rednet.open("right")

        skyTravel(TARGET_X, COMMUTE_Y, TARGET_Z, direction)

        -- Swap Scanner back for mining
        turtle.equipRight()
        turtle.select(1)
    end

    -- MAIN LOOP: Infinite Sector Hopping
    while true do
        -- FIX: Use getLocate() here
        if MISSION_ABORTED then
                addLog("Mission Aborted. returning home...")
                -- Add logic here to ascend and fly home
                -- (You can copy the return logic from the previous script)
                return
            end
        local startX, _, startZ = getLocate()

        if not startX then
            addLog("GPS Lost! Pausing...")
            os.sleep(5)
            startX, _, startZ = getLocate() -- Retry once
            if not startX then return end -- Abort if still lost
        end

        local sectorKey = math.floor(startX)..","..math.floor(startZ)
        visitedSectors[sectorKey] = true

        addLog("Starting Column: " .. sectorKey)

        -- DESCEND AND MINE LOOP
        local layerY = 65 -- Start scanning at surface

        -- Go down to surface first
        -- Optimization: Use Dead Reckoning (Math) instead of GPS to avoid tool swapping lag
        local _, currY, _ = getLocate()

        while currY > layerY do
            if smartMove("down") then currY = currY - 1 end
        end

        while layerY > -58 do -- Bedrock limit
            addLog("Scanning Layer Y="..layerY)

            -- A. Scan (Scanner is already equipped)
            local scanned = scanner.scan(scanRadius)
            if scanned then
                clearLocalArea(scanned, direction)
            end
            manageInventory()

            -- B. Check Fuel/Abort
            if checkAborts() then return end

            -- C. Drop to next layer (Shift down 32 blocks)
            addLog("Dropping to next layer...")
            for i=1, 32 do
                if smartMove("down") then layerY = layerY - 1 end
                if layerY <= -59 then break end
            end
        end

        addLog("Column Complete. Ascending...")

        -- ASCEND
        local _, checkY, _ = getLocate() -- Get one real fix before ascending
        local currentY = checkY or -60

        while currentY < COMMUTE_Y do
            if smartMove("up") then currentY = currentY + 1 end
        end

        -- FIND NEW SECTOR
        addLog("Calculating new sector...")

        -- Get fresh GPS for calculation
        startX, _, startZ = getLocate()

        local foundNew = false
        local offsets = {{32,0}, {-32,0}, {0,32}, {0,-32}}

        -- Equip Modem for travel again
        turtle.select(16)
        turtle.equipRight()
        rednet.open("right")

        -- Try random directions
        for i=1, 10 do
            local r = math.random(1, 4)
            local off = offsets[r]
            local nx = startX + off[1]
            local nz = startZ + off[2]
            local key = math.floor(nx)..","..math.floor(nz)

            if not visitedSectors[key] then
                addLog("Moving to new sector: "..key)
                skyTravel(nx, COMMUTE_Y, nz, direction)
                foundNew = true
                break
            end
        end

        if not foundNew then
            addLog("All neighbors visited! Moving further East.")
            skyTravel(startX + 32, COMMUTE_Y, startZ, direction)
        end

        -- Swap Scanner back for the next loop
        turtle.equipRight()
        turtle.select(1)
    end
end

-- =============================================================================
-- UI SETUP
-- =============================================================================

local main = basalt.createFrame()
main:addPane():setPosition(1, 1):setSize(w, 1):setBackground(colors.gray)
main:addLabel():setText("GeoMiner Fleet"):setForeground(colors.lime):setPosition(1, 1)

local menubar = main:addMenubar():setPosition(1, 2):setSize(w, 1)
menubar:addItem("Fuel")
menubar:addItem("Blocks")
menubar:addItem("Mission")
menubar:addItem("Logs")
menubar:onChange(function(self, event, item)
    for _, f in pairs(frames) do f:hide() end
    if frames[item.text] then frames[item.text]:show() end
end)

frames["Fuel"] = main:addScrollableFrame():setPosition(1, 3):setSize(w, h - 2)
frames["Blocks"] = main:addScrollableFrame():setPosition(1, 3):setSize(w, h - 2):hide()
frames["Mission"] = main:addScrollableFrame():setPosition(1, 3):setSize(w, h - 2):hide()
frames["Logs"] = main:addScrollableFrame():setPosition(1, 3):setSize(w, h - 2):hide()

-- FUEL TAB
frames["Fuel"]:addLabel():setText("Refuel with Coal/Lava"):setPosition(2,2)
frames["Fuel"]:addButton():setText("Refuel All"):setPosition(2,4):setSize(12,3):onClick(function() turtle.refuel() end)
local fuelDisplay = frames["Fuel"]:addLabel():setPosition(2, 8)
main:addThread():start(function() while true do fuelDisplay:setText("Level: "..turtle.getFuelLevel()) os.sleep(1) end end)

-- BLOCKS TAB (With Deepslate Logic)
local blocksDropdown = frames["Blocks"]:addDropdown():setPosition(2, 2):setSize(20, 1)
local blocksToMineList = frames["Blocks"]:addList():setSize(20, h - 4):setPosition(w - 20, 2)

-- Populate Dropdown with likely ores immediately
for k,v in pairs(ORE_MAP) do blocksDropdown:addItem(k) end
blocksDropdown:addItem("ancient_debris")

frames["Blocks"]:addButton():setText("+"):setSize(3, 1):setPosition(2, 4):onClick(function()
    local item = blocksDropdown:getItem(blocksDropdown:getItemIndex())
    if item then
        local name = item.text
        if not blocksToMine[name] then
            blocksToMine[name] = true
            blocksToMineList:addItem(name)
            addLog("Added: "..name)
            -- Auto Add Deepslate
            if ORE_MAP[name] then
                blocksToMine[ORE_MAP[name]] = true
                blocksToMineList:addItem(ORE_MAP[name])
                addLog("Auto-Added: "..ORE_MAP[name])
            end
        end
    end
end)

frames["Blocks"]:addButton():setText("-"):setSize(3, 1):setPosition(6, 4):onClick(function()
    local item = blocksToMineList:getItem(blocksToMineList:getItemIndex())
    if item then
        blocksToMine[item.text] = nil
        blocksToMineList:removeItem(blocksToMineList:getItemIndex())
    end
end)

-- MISSION TAB
local missionFrame = frames["Mission"]
missionFrame:addLabel():setText("Target X:"):setPosition(2, 2)
local inputX = missionFrame:addInput():setPosition(2, 3):setSize(8, 1):setInputType("number")
missionFrame:addLabel():setText("Target Z:"):setPosition(12, 2)
local inputZ = missionFrame:addInput():setPosition(12, 3):setSize(8, 1):setInputType("number")

missionFrame:addButton():setText("START MISSION"):setPosition(2, 6):setSize(20, 3):setBackground(colors.lime):onClick(function()
    local tx = tonumber(inputX:getValue())
    local tz = tonumber(inputZ:getValue())

    if not tx or not tz then
        addLog("Error: Invalid Coords")
        return
    end

    TARGET_X = tx
    TARGET_Z = tz

    -- Start the thread
    main:addThread():start(SectorMinerLogic)
    addLog("Mission Thread Started.")
end)

-- LOGS TAB
logList = frames["Logs"]:addList():setSize(w - 2, h - 4):setPosition(1, 2)

basalt.autoUpdate()