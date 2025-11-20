local modemSide = "top" -- Change to where your modem is
rednet.open(modemSide)

local logFile = "turtle_logs.txt"
print("Waiting for Mining Squad updates...")

while true do
    local id, message, protocol = rednet.receive("MINING_SQUAD")

    if message then
        local timestamp = os.date("%H:%M:%S")
        local logMsg = string.format("[%s] Turtle %d: X:%d Y:%d Z:%d | %s",
            timestamp, id, message.x, message.y, message.z, message.status or "Mining")

        print(logMsg)

        -- Save to file (Overwrites fast, or Appends? Let's Append)
        local file = fs.open(logFile, "a")
        file.writeLine(logMsg)
        file.close()

        -- Save absolute latest position to a separate file for quick reading
        local lastPos = fs.open("last_pos_"..id..".txt", "w")
        lastPos.write(textutils.serialize(message))
        lastPos.close()
    end
end