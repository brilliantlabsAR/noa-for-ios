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

frame.bluetooth.receive_callback(bluetooth_callback)

i = 0
while true do
    frame.sleep(5 * 60)    -- sleep 5 minutes
    send_data(MESSAGE_START_FLAG)
    send_data(MESSAGE_TEXT_FLAG .. "Hello! " .. tostring(i))
    send_data(MESSAGE_END_FLAG)
    i = i + 1
end

