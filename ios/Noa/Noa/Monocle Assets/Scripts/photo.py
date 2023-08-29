import bluetooth
import camera
import states

def capture_image(state, gfx, send_message):
    if state.on_entry():
        camera.capture()
        send_message(b"ist:")
        gfx.clear_response()
        gfx.set_prompt("Sending photo [     ]")
    state.after(250, state.SendImage)

def send_image(state, gfx, send_message):
    #TODO: come up with some estimates for progress bar based on actual observed JPEG sizes
    samples = bluetooth.max_length() - 4
    chunk = camera.read(samples)
    if chunk == None:
        # Finished, start microphone recording next. The microphone recording state will
        # send the "ien:" command!
        state.after(0, state.StartRecording)
    else:
        send_message(b"idt:" + chunk)
