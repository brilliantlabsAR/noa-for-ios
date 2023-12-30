require("graphics")
require("states")
require("audio")
require("photo")

local state = State.new()
local gfx = Graphics.new()

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

function BluetoothMessageHandler(message)
    if state.current_state == state.WaitForPing then
        if message:sub(1, 4) == "pin:" then
            BluetoothSendMessage("pon:" .. message:sub(5))
            state:after(0, state.WaitForResponse)
        elseif message:sub(1, 4) == "res:" or message:sub(1, 4) == "err:" then
            PrintResponse(message)
        elseif message:sub(1, 4) == "ick:" then
            state:after(0, state.WaitForTap)
        end
    elseif state.current_state == state.WaitForResponse then
        if message:sub(1, 4) == "res:" or message:sub(1, 4) == "err:" then
            PrintResponse(message)
        end
    elseif state.current_state == state.PrintResponse then
        gfx.append_response(message:sub(5))
    elseif state.current_state == state.WaitForTap then
        if message:sub(1, 4) == "res:" or message:sub(1, 4) == "err:" then
            PrintResponse(message)
        end
    end
end

function TouchPadHandler()
    if state.current_state == state.WaitForTap then
        state.after(0, state.DetectSingleTap)
    elseif state.current_state == state.WaitForPing or state.current_state == state.WaitForResponse then
        state.after(0, state.AskToCancel)
    elseif state.current_state == state.AskToCancel then
        state.after(0, state.WaitForTap)
    end
end

frame.bluetooth.receive_callback(BluetoothMessageHandler)
frame.imu.tap_callback(TouchPadHandler)
function PrintResponse(message)
    gfx.error_flag = message:sub(1, 4) == "err:"
    gfx.append_response(message:sub(5):decode("utf-8"))
    state:after(0, state.PrintResponse)
end

while true do
    if state.current_state == state.Init then
        state:after(0, state.Welcome)
    elseif state.current_state == state.Welcome then
        if state:on_entry() then
            gfx:append_response("Welcome to Noa for Monocle.\nStart the Noa iOS or Android app.")
        end
        state:after(2, state.Connected)
    elseif state.current_state == state.Connected then
        if state:on_entry() then
            gfx:clear_response()
            gfx:set_prompt("Connected")
        end
        state:after(2, state.WaitForTap)
    elseif state.current_state == state.WaitForTap then
        if state:on_entry() then
            BluetoothSendMessage("rdy:")
            gfx:set_prompt("Tap and speak")
        end
    elseif state.current_state == state.DetectSingleTap then
        if state:has_been() >= 1 then
            -- if touch.state(touch.EITHER) then
            --     state.after(0, state.DetectHold)
            --     frame.camera.wake()
            -- else
            state:after(0, state.StartRecording)
            -- end
        end
        -- elseif state.current_state == state.DetectHold then
        --     -- if state.has_been() >= 1000 and touch.state(touch.EITHER) then
        --     state:after(0, state.CaptureImage)
        --     -- elseif not touch.state(touch.EITHER) then
        --     --     frame.camera.sleep()
        --     --     state.after(0, state.WaitForTap)
        --     -- end
    elseif state.current_state == state.StartRecording then
        StartRecording(state, gfx, BluetoothSendMessage)
    elseif state.current_state == state.SendAudio then
        SendAudio(state, gfx, BluetoothSendMessage)
        -- elseif state.current_state == state.WaitForPing or state.current_state == state.WaitForResponse then
        --     gfx:set_prompt("Waiting for openAI")
        -- elseif state.current_state == state.AskToCancel then
        --     gfx:set_prompt("Cancel?")
        --     state:after(3000, state.previous_state)
        -- elseif state.current_state == state.PrintResponse then
        --     gfx:set_prompt("")
        --     if gfx.done_printing then
        --         state:after(0, state.WaitForTap)
        --     end
        -- elseif state.current_state == state.CaptureImage then
        --     CaptureImage(state, gfx, BluetoothSendMessage)
        -- elseif state.current_state == state.SendImage then
        --     SendImage(state, gfx, BluetoothSendMessage)
    end

    if state:has_been() > 5 then
        state:after(0, state.DetectSingleTap)
    elseif state:has_been() > 15 then
        print(tostring(state.current_state))
        break
    end
    gfx:run()
end
