--
-- test_restore.lua
--
-- A test script that periodically (every 10 seconds) sends a text request to the iOS app. This is
-- for testing Bluetooth restoration.
--

MESSAGE_START_FLAG = "\x10"
MESSAGE_TEXT_FLAG = "\x11"
MESSAGE_AUDIO_FLAG = "\x12"
MESSAGE_IMAGE_332_FLAG = "\x13"
MESSAGE_PALETTE_FLAG = "\x14"
MESSAGE_IMAGE_4_FLAG = "\x15"
MESSAGE_END_FLAG = "\x16"

function bluetooth_callback(message)
    -- Nothing to do
end

function send_data(data)
    while true do
        if pcall(frame.bluetooth.send, data) then
            break
        end
    end
end

function send_fake_image_data()
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
    send_data(MESSAGE_IMAGE_332_FLAG .. lineBuffer)

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
            lineBuffer = lineBuffer .. color
        end
        -- Line is complete, send it
        send_data(MESSAGE_IMAGE_332_FLAG .. lineBuffer)
    end

    -- Send bottom line red pixels
    lineBuffer = ""
    for i=1,200 do
        lineBuffer = lineBuffer .. red
    end
        send_data(MESSAGE_IMAGE_332_FLAG .. lineBuffer)

end

frame.bluetooth.receive_callback(bluetooth_callback)

i = 0
frame.sleep(10) -- initial 10 second sleep before starting
while true do
    send_data(MESSAGE_START_FLAG)
    send_fake_image_data()
    send_data(MESSAGE_TEXT_FLAG .. "Hello! " .. tostring(i))
    send_data(MESSAGE_END_FLAG)
    i = i + 1
    frame.sleep(5 * 60)    -- sleep 5 minutes
end

