import bluetooth
import graphics
import microphone
import time
import touch
import states

RECORD_LENGTH = 4.0

state = states.State()
gfx = graphics.Graphics()


def bluetooth_send_message(message):
    while True:
        try:
            bluetooth.send(message)
            break
        except OSError:
            pass


def bluetooth_message_handler(message):
    if state.current_state == state.WaitForPing:
        if message.startswith("pin:"):
            bluetooth_send_message(b"pon:" + message[4:])
            state.after(0, state.WaitForResponse)
        elif message.startswith("err:"):
            gfx.error_flag = True
            gfx.append_response(message[4:].decode("utf-8"))
            state.after(0, state.PrintResponse)

    elif state.current_state == state.WaitForResponse:
        if message.startswith("res:"):
            gfx.error_flag = False
            gfx.append_response(message[4:].decode("utf-8"))
            state.after(0, state.PrintResponse)
        elif message.startswith("err:"):
            gfx.error_flag = True
            gfx.append_response(message[4:].decode("utf-8"))
            state.after(0, state.PrintResponse)

    elif state.current_state == state.PrintResponse:
        gfx.append_response(message[4:].decode("utf-8"))


def touch_pad_handler(_):
    if state.current_state == state.WaitForTap:
        state.after(0, state.StartRecording)
    elif (
        state.current_state == state.WaitForPing
        or state.current_state == state.WaitForResponse
    ):
        state.after(0, state.AskToCancel)
    elif state.current_state == state.AskToCancel:
        state.after(0, state.WaitForTap)


bluetooth.receive_callback(bluetooth_message_handler)
touch.callback(touch.BOTH, touch_pad_handler)

while True:
    if state.current_state == state.Init:
        state.after(0, state.Welcome)

    elif state.current_state == state.Welcome:
        if state.on_entry():
            gfx.append_response(
                """Welcome to arGPT for Monocle.\nStart the arGPT iOS or Android app."""
            )
        if bluetooth.connected():
            state.after(5000, state.Connected)

    elif state.current_state == state.Connected:
        if state.on_entry():
            gfx.clear_response()
            gfx.set_prompt("Connected")
        state.after(2000, state.WaitForTap)

    elif state.current_state == state.WaitForTap:
        if state.on_entry():
            bluetooth_send_message(b"rdy:")
            gfx.set_prompt("Tap and speak")

    elif state.current_state == state.StartRecording:
        if state.on_entry():
            microphone.record(seconds=RECORD_LENGTH)
            bluetooth_send_message(b"ast:")
            gfx.clear_response()
            gfx.set_prompt("Listening [   ]")
        state.after(1000, state.SendAudio)

    elif state.current_state == state.SendAudio:
        if state.has_been() > 3000:
            if state.has_been() // 250 % 4 == 0:
                gfx.set_prompt("Sending   [=  ]")
            elif state.has_been() // 250 % 4 == 1:
                gfx.set_prompt("Sending   [ = ]")
            elif state.has_been() // 250 % 4 == 2:
                gfx.set_prompt("Sending   [  =]")
            elif state.has_been() // 250 % 4 == 3:
                gfx.set_prompt("Sending   [   ]")

        elif state.has_been() > 2000:
            gfx.set_prompt("Listening [===]")
        elif state.has_been() > 1000:
            gfx.set_prompt("Listening [== ]")
        else:
            gfx.set_prompt("Listening [=  ]")

        samples = microphone.__read_raw(bluetooth.max_length() // 2 - 6)

        if samples == None:
            bluetooth_send_message(b"aen:")
            state.after(0, state.WaitForPing)
        else:
            bluetooth_send_message(b"dat:" + samples)

    elif (
        state.current_state == state.WaitForPing
        or state.current_state == state.WaitForResponse
    ):
        gfx.set_prompt("Waiting for openAI")

    elif state.current_state == state.AskToCancel:
        gfx.set_prompt("Cancel?")
        state.after(3000, state.previous_state)

    elif state.current_state == state.PrintResponse:
        gfx.set_prompt("")
        if gfx.done_printing:
            state.after(0, state.WaitForTap)

    gfx.run()
