import bluetooth
import microphone
import states

def start_recording(state, gfx, send_message):
    if state.on_entry():
        microphone.record(seconds=6.0, bit_depth=8, sample_rate=8000)
        if state.previous_state == state.SendImage:
            send_message(b"ien:") # continue image-and-prompt flow
        else:
            send_message(b"ast:") # *prompt only* (erases image data)
        gfx.clear_response()
        gfx.set_prompt("Listening [     ]")
    state.after(1000, state.SendAudio)

def send_audio(state, gfx, send_message):
    if state.has_been() > 5000:
        gfx.set_prompt("Waiting for openAI")
    elif state.has_been() > 4000:
        gfx.set_prompt("Listening [=====]")
    elif state.has_been() > 3000:
        gfx.set_prompt("Listening [==== ]")
    elif state.has_been() > 2000:
        gfx.set_prompt("Listening [===  ]")
    elif state.has_been() > 1000:
        gfx.set_prompt("Listening [==   ]")
    else:
        gfx.set_prompt("Listening [=    ]")

    samples = (bluetooth.max_length() - 4) // 2
    chunk1 = microphone.read(samples)
    chunk2 = microphone.read(samples)

    if chunk1 == None:
        send_message(b"aen:")
        state.after(0, state.WaitForPing)
    elif chunk2 == None:
        send_message(b"dat:" + chunk1)
    else:
        send_message(b"dat:" + chunk1 + chunk2)
