require("states")

function StartRecording(state, gfx, send_message)
    if state:on_entry() then
        frame.microphone.record(0.05, 8000, 8)
        if state.previous_state == State.SendImage then
            send_message("ien:") -- continue image-and-prompt flow
        else
            send_message("ast:") -- *prompt only* (erases image data)
        end
        gfx:clear_response()
        gfx:set_prompt("Listening [     ]")
    end
    state:after(1, State.SendAudio)
end

function SendAudio(state, gfx, send_message)
    if state:has_been() > 5 then
        gfx:set_prompt("Waiting for openAI")
    elseif state:has_been() > 4 then
        gfx:set_prompt("Listening [=====]")
    elseif state:has_been() > 3 then
        gfx:set_prompt("Listening [==== ]")
    elseif state:has_been() > 2 then
        gfx:set_prompt("Listening [===  ]")
    elseif state:has_been() > 1 then
        gfx:set_prompt("Listening [==   ]")
    else
        gfx:set_prompt("Listening [=    ]")
    end

    local samples = (frame.bluetooth.max_length() - 4) // 10
    local chunk1 = frame.microphone.read(samples)
    local chunk2 = frame.microphone.read(samples)

    if chunk1 == nil then
        send_message("aen:")
        state:after(0, State.WaitForPing)
    elseif chunk2 == nil then
        local dt = "dat:" .. table.concat(chunk1)
        print(#dt)
        send_message(dt)
    else
        local dt = "dat:" .. table.concat(chunk1) .. table.concat(chunk2)
        print(#dt)
        send_message(dt)
    end
end
