function BluetoothSendMessage(message)
    while true do
        local success, error_message = pcall(frame.bluetooth.send, message)
        if success then
            break
        end
        if error_message then
            print(error_message)
            break
        end
    end
end

function SendMMStart()
    BluetoothSendMessage(string.char(0x00))
end

function SendMMEnd()
    BluetoothSendMessage(string.char(0x04))
end

function SendMMTextChunk(message)
    BluetoothSendMessage(string.char(0x01) .. message)
end

function SendTestImage()
    local red = string.char(0xe0)
    local green = string.char(0x1c)
    local blue = string.char(0x03)
    local black = string.char(0x00)
    local max_pixels_per_send = 100

    -- Send top line of red pixels in small chunks
    local lineBuffer = ""
    for i=1,200 do
        lineBuffer = lineBuffer .. red
    end
    BluetoothSendMessage(string.char(0x03) .. lineBuffer)

    -- Send 198 lines with green pixels on left and right edges with diagonal blue line
    for y=1,198 do
        lineBuffer = ""
        for x=1,200 do
            local color = black
            if x == 1 or x == 200 then
                color = green
            elseif x == y then
                color = blue
            end
            -- Lua memory issues force us to send one byte at a time
            -- lineBuffer = lineBuffer .. color
            -- BluetoothSendMessage(string.char(0x03) .. color)
        end
        -- BluetoothSendMessage(string.char(0x03) .. lineBuffer)
    end

    -- Send bottom line red pixels
    lineBuffer = ""
    for i=1,200 do
        lineBuffer = lineBuffer .. red
    end
    BluetoothSendMessage(string.char(0x03) .. lineBuffer)

end

SendMMStart()
SendMMTextChunk("what is ")
SendMMTextChunk("this?")
-- SendTestImage()
SendMMEnd()

a = {}    -- new array, test [] escape
for i=1, 1000 do
    a[i] = 0
end
