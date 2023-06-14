import bluetooth
import display
import microphone
import touch
import time
import re

#
# States
#


class State:
    class Init:
        pass

    class Welcome:
        pass

    class Connected:
        pass

    class WaitForTap:
        pass

    class StartRecording:
        pass

    class SendAudio:
        pass

    class WaitForPing:
        pass

    class WaitForResponse:
        pass

    class AskToCancel:
        pass

    class PrintResponse:
        pass

    class Undefined:
        pass

    def __init__(self):
        self.previous_state = self.Init
        self.current_state = self.Init
        self.__next_state = self.Init
        self.__entry_time = time.ticks_ms()
        self.__entered = True

    def after(self, wait_time, next_state):
        if next_state != self.__next_state:
            self.__next_state = next_state

        if self.current_state != self.__next_state:
            if time.ticks_diff(time.ticks_ms(), self.__entry_time) > wait_time:
                self.previous_state = self.current_state
                self.current_state = self.__next_state
                self.__entry_time = time.ticks_ms()
                self.__entered = True
                print("State: ", str(self.current_state.__name__))

    def has_been(self):
        return time.ticks_diff(time.ticks_ms(), self.__entry_time)

    def on_entry(self):
        if self.__entered == True:
            self.__entered = False
            return True
        return False


#
# Graphics
#


class Graphics:
    def __init__(self):
        self.MAX_LINES = 7
        self.WORD_SPEED = 300
        self.error_flag = False
        self.done_printing = False
        self.__current_response = ""
        self.__current_response_word = 0
        self.__current_response_line_offset = 0
        self.__current_prompt = ""
        self.__last_frame_time = time.ticks_ms()
        self.__last_word_time = time.ticks_ms()

    def reset_done_flag(self):
        self.done_printing = False

    def set_response(self, response):
        formatted_response = re.sub(r"""\n+""", "  ", response)
        if self.__current_response != formatted_response:
            self.__current_response = formatted_response
            self.__current_response_word = 0
            self.__current_response_line_offset = 0

    def set_prompt(self, prompt):
        if self.__current_prompt != prompt:
            self.__current_prompt = prompt

    def __split_lines(self, words):
        word_arrays = []
        current_array = []
        current_length = 0
        max_characters = display.WIDTH // display.FONT_WIDTH

        for word in words:
            word_length = len(word)
            if word == "":
                word_arrays.append(current_array)
                current_array = []
                current_length = max_characters
            elif current_length + word_length + len(current_array) <= max_characters:
                current_array.append(word)
                current_length += word_length
            else:
                word_arrays.append(current_array)
                current_array = [word]
                current_length = word_length

        if current_array:
            word_arrays.append(current_array)

        return word_arrays

    def run(self):
        if time.ticks_ms() - self.__last_frame_time > 20:
            self.__last_frame_time = time.ticks_ms()
            response_words = self.__current_response.split(" ")
            partial_response_words = response_words[: self.__current_response_word]
            response_lines = self.__split_lines(partial_response_words)
            if len(response_lines) > self.MAX_LINES:
                self.__current_response_line_offset = (
                    len(response_lines) - self.MAX_LINES
                )

            text_objects = []
            response_color = display.RED if self.error_flag else display.WHITE

            for line in range(self.MAX_LINES):
                if len(response_lines) > line:
                    text = " ".join(
                        response_lines[self.__current_response_line_offset + line]
                    )
                    text_objects.append(
                        display.Text(text, 0, 50 * line, response_color)
                    )

            if response_words == partial_response_words:
                text_objects.append(
                    display.Text(
                        self.__current_prompt,
                        320,
                        400,
                        display.YELLOW,
                        justify=display.BOTTOM_CENTER,
                    )
                )

                self.done_printing = True

            time.sleep_ms(1)  # TODO why is this needed?
            display.show(text_objects)

            if time.ticks_ms() - self.__last_word_time > self.WORD_SPEED:
                self.__last_word_time = time.ticks_ms()
                self.__current_response_word += 1


#
# Main app
#

RECORD_LENGTH = 4.0

state = State()
gfx = Graphics()


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
    elif state.current_state == state.WaitForResponse:
        if message.startswith("res:"):
            gfx.error_flag = False
            response = message[4:].decode("utf-8")
            gfx.set_response(response)
            gfx.set_prompt("")
            state.after(0, state.PrintResponse)

        elif message.startswith("err:"):
            gfx.error_flag = True
            response = message[4:].decode("utf-8")
            gfx.set_response(response)
            gfx.set_prompt("")
            state.after(0, state.PrintResponse)


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
            gfx.set_response(
                """Welcome to arGPT for Monocle.\nStart the arGPT iOS or Android app."""
            )
        if bluetooth.connected():
            state.after(5000, state.Connected)

    elif state.current_state == state.Connected:
        if state.on_entry():
            gfx.set_response("")
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
            gfx.set_response("")
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
        if state.on_entry():
            gfx.reset_done_flag()
        if gfx.done_printing:
            state.after(0, state.WaitForTap)

    gfx.run()
    time.sleep(0.001)
