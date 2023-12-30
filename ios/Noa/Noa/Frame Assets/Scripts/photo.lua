function CaptureImage(state, gfx, send_message)
    if state:on_entry() then
        frame.camera.capture()
        send_message("ist:")
        gfx:clear_response()
        gfx:set_prompt("Sending photo [     ]")
    end
    state:after(250, state.SendImage)
end

function SendImage(state, gfx, send_message)
    if state:on_entry() then
        state.current_state.bytes_sent = 0
    end
    local samples = frame.bluetooth.max_length() - 4
    local chunk = frame.camera.read(samples)
    if chunk == nil then
        -- Finished, start microphone recording next. The microphone recording state will
        -- send the "ien:" command!
        state:after(0, state.StartRecording)
    else
        send_message("idt:" .. chunk)
        state.current_state.bytes_sent = state.current_state.bytes_sent + #chunk
        local benchmark_size = 64000
        local percent = state.current_state.bytes_sent / benchmark_size
        if percent > 0.8 then
            gfx:set_prompt("Sending photo [=====]")
        elseif percent > 0.6 then
            gfx:set_prompt("Sending photo [==== ]")
        elseif percent > 0.4 then
            gfx:set_prompt("Sending photo [===  ]")
        elseif percent > 0.2 then
            gfx:set_prompt("Sending photo [==   ]")
        else
            gfx:set_prompt("Sending photo [=    ]")
        end
    end
end
