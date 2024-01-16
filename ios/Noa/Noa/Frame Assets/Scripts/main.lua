require("graphics")
require("state")

local graphics = Graphics.new()
local state = State.new()

function tap_callback()
    print('Tap')
    if state:is(state.WaitingForTap) or state:is(state.TapTutorial) then
        state:switch(state.RecordAudio)
    end
end

-- Setup
frame.imu.tap_callback(tap_callback)

-- Main loop
while true do
    -- Main state machine
    if state:is("Init") then
        state:switch("Welcome")
    elseif state:is("Welcome") then
        state:on_entry(function()
            graphics:append_response("Hi! I'm Noa. Your helpful AI companion")
        end)
        state:switch_after(2, "TapTutorial")
    elseif state:is("TapTutorial") then
        state:on_entry(function()
            graphics:clear_response()
            graphics:append_response("Tap the side of your Frame and ask me something. I'm always standing by")
        end)
        state:switch_after(30, "WaitingForTap")
    elseif state:is("WaitingForTap") then
        state:on_entry(function()
            graphics:clear_response()
        end)
    elseif state:is("RecordAudio") then
        state:on_entry(function()
            frame.microphone.record(5, 8000, 8)
        end)
        state:switch_after(5, "SendAudio")
    elseif state:is("SendAudio") then
        state:on_entry(function()
            frame.bluetooth.send("\x10") -- Start flag
        end)
        local samples = math.floor((frame.bluetooth.max_length() - 1) / 4) * 4
        local audio_data = frame.microphone.read(samples)
        --print("Sending " .. #audio_data .. " samples")
        if audio_data ~= nil then
            frame.bluetooth.send("\x12" .. audio_data)
        else
            frame.bluetooth.send("\x14") -- End flag
            state:switch("WaitForResponse")
        end
    elseif state:is("WaitForResponse") then

    else
        error("Invalid state: " .. state.current_state)
    end

    -- Run graphics printing
    graphics:run()
end
