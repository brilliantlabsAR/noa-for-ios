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
    if string.sub(message, 1, 1) == MESSAGE_START_FLAG then
        graphics:clear()
    elseif string.sub(message, 1, 1) == MESSAGE_TEXT_FLAG then
        state:switch("PRINT_RESPONSE")
        graphics:append_text(string.sub(message, 2))
    elseif string.sub(message, 1, 1) == MESSAGE_IMAGE_4_FLAG then
        state:switch("PRINT_IMAGE")
        graphics:append_image(string.sub(message, 2))
    elseif string.sub(message, 1, 1) == MESSAGE_PALETTE_FLAG then
        for color = 0, 15 do
            local red = string.byte(message, 2 + color * 3)
            local green = string.byte(message, 2 + color * 3 + 1)
            local blue = string.byte(message, 2 + color * 3 + 2)
            graphics:set_color(color + 1, red, green, blue)
        end
    end
end

function tap_callback()
    if state:is("TUTORIAL") or
        state:is("WAIT_FOR_TAP") or
        state:is("HOLD_RESPONSE") or
        state:is("HOLD_IMAGE") then
        state:switch("CAPTURE")
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
    if state:is("START") then
        state:on_entry(function()
            graphics:append_text("Hi! I'm Noa. Your helpful AI companion")
        end)
        state:switch_after(5, "TUTORIAL")
    elseif state:is("TUTORIAL") then
        state:on_entry(function()
            graphics:clear()
            graphics:append_text("Tap the side of your Frame and ask me something. I'm always standing by")
        end)
        state:switch_after(30, "WAIT_FOR_TAP")
    elseif state:is("WAIT_FOR_TAP") then
        state:on_entry(function()
            graphics:clear()
        end)
    elseif state:is("CAPTURE") then
        state:on_entry(function()
            frame.microphone.record(6, 8000, 8)
            frame.camera.auto(25)
            frame.camera.capture()
            graphics:clear()
            graphics:append_text("Listening . . .")
        end)
        state:switch_after(4, "UPLOAD_IMAGE_AND_AUDIO")
    elseif state:is("UPLOAD_IMAGE_AND_AUDIO") then
        state:on_entry(function()
            send_data(MESSAGE_START_FLAG)
        end)
        while true do
            local image_data = frame.camera.read(frame.bluetooth.max_length() - 1)
            if (image_data == nil) then
                break
            end
            send_data(MESSAGE_IMAGE_332_FLAG .. image_data)
        end
        while true do
            local samples = math.floor((frame.bluetooth.max_length() - 1) / 4) * 4
            local audio_data = frame.microphone.read(samples)
            if audio_data == nil then
                break
            end
            send_data(MESSAGE_AUDIO_FLAG .. audio_data)
        end
        send_data(MESSAGE_END_FLAG)
        state:switch("WAIT_FOR_RESPONSE")
    elseif state:is("WAIT_FOR_RESPONSE") then
        state:on_entry(function()
            graphics:clear()
            graphics:append_text("I'm on it . . .")
        end)
    elseif state:is("PRINT_RESPONSE") then
        graphics:on_complete(function()
            state:switch("HOLD_RESPONSE")
        end)
        state:switch_after(30, "WAIT_FOR_TAP")
    elseif state:is("PRINT_IMAGE") then
        graphics:on_complete(function()
            state:switch("HOLD_IMAGE")
        end)
        state:switch_after(30, "WAIT_FOR_TAP")
    elseif state:is("HOLD_RESPONSE") then
        state:switch_after(20, "WAIT_FOR_TAP")
    elseif state:is("HOLD_IMAGE") then
        state:switch_after(20, "WAIT_FOR_TAP")
    end

    -- Run graphics
    if state:is("PRINT_IMAGE") or state:is("HOLD_IMAGE") then
        graphics:print_image()
    else
        graphics:print_text()
    end

    -- Keep memory usage down
    collectgarbage("collect")
end
