require("graphics")
require("state")

local graphics = Graphics.new()
local state = State.new()

MESSAGE_START_FLAG = "\x10"
MESSAGE_TEXT_FLAG = "\x11"
MESSAGE_AUDIO_FLAG = "\x12"
MESSAGE_IMAGE_332_FLAG = "\x13"
MESSAGE_PALETTE_FLAG = "\x14"
MESSAGE_IMAGE_4_FLAG = "\x15"
MESSAGE_END_FLAG = "\x16"

function bluetooth_callback(message)
    if state:is("DisplayResponse") then
        if string.sub(message, 1, 1) == MESSAGE_START_FLAG then
            graphics:clear()
        elseif string.sub(message, 1, 1) == MESSAGE_TEXT_FLAG then
            graphics:append_text(string.sub(message, 2))
        elseif string.sub(message, 1, 1) == MESSAGE_PALETTE_FLAG then
            for color = 0, 15 do
                local red = string.byte(message, 2 + color * 3)
                local green = string.byte(message, 2 + color * 3 + 1)
                local blue = string.byte(message, 2 + color * 3 + 2)
                graphics:set_color(color + 1, red, green, blue)
            end
        elseif string.sub(message, 1, 1) == MESSAGE_IMAGE_4_FLAG then
            graphics:append_image(string.sub(message, 2))
        end
    end
end

function tap_callback()
    if state:is("TapTutorial") or state:is("WaitingForTap") or state:is("HoldResponse") then
        state:switch("Capture")
    end
end

function send_data(data)
    while true do
        if pcall(frame.bluetooth.send, data) then
            break
        end
    end
end

-- Setup
frame.bluetooth.receive_callback(bluetooth_callback)
frame.imu.tap_callback(tap_callback)

-- Main loop
while true do
    -- Main state machine
    if state:is("Init") then
        state:on_entry(function()
            graphics:append_text("Hi! I'm Noa. Your helpful AI companion")
        end)
        state:switch_after(5, "TapTutorial")
    elseif state:is("TapTutorial") then
        state:on_entry(function()
            graphics:clear()
            graphics:append_text("Tap the side of your Frame and ask me something. I'm always standing by")
        end)
        state:switch_after(30, "WaitingForTap")
    elseif state:is("WaitingForTap") then
        state:on_entry(function()
            graphics:clear()
        end)
    elseif state:is("Capture") then
        state:on_entry(function()
            frame.microphone.record(6, 8000, 8)
            frame.camera.capture()
            graphics:clear()
            graphics:append_text("Listening..")
        end)
        state:switch_after(4, "SendImage")
    elseif state:is("SendImage") then
        state:on_entry(function()
            send_data(MESSAGE_START_FLAG)
        end)
        while true do
            local image_data = frame.camera.read(frame.bluetooth.max_length() - 1)
            if (image_data ~= nil) then
                send_data(MESSAGE_IMAGE_332_FLAG .. image_data)
            else
                break
            end
        end
        state:switch("SendAudio")
    elseif state:is("SendAudio") then
        state:on_entry(function()
            graphics:clear()
            graphics:append_text(". . .")
        end)
        local samples = math.floor((frame.bluetooth.max_length() - 1) / 4) * 4
        while true do
            local audio_data = frame.microphone.read(samples)
            if audio_data ~= nil then
                send_data(MESSAGE_AUDIO_FLAG .. audio_data)
            else
                break
            end
        end
        state:switch("DisplayResponse")
    elseif state:is("DisplayResponse") then
        state:on_entry(function()
            graphics:clear()
            send_data(MESSAGE_END_FLAG)
        end)
        graphics:on_complete(function()
            state:switch("HoldResponse")
        end)
        state:switch_after(30, "WaitingForTap")
    elseif state:is("HoldResponse") then
        state:switch_after(20, "WaitingForTap")
    else
        error("Invalid state: " .. state.current_state)
    end

    -- Run graphics printing
    graphics:run()
end
