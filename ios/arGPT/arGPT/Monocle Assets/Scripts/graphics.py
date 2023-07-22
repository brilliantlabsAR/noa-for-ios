import display
import time
import re


class Graphics:
    def __init__(self):
        self.MAX_LINES = 7
        self.WORD_SPEED = 300
        self.FRAME_RATE = 20
        self.error_flag = False
        self.done_printing = False
        self.__current_response = ""
        self.__current_response_word = 0
        self.__current_response_line_offset = 0
        self.__current_prompt = ""
        self.__last_frame_time = time.ticks_ms()
        self.__last_word_time = time.ticks_ms()

    def clear_response(self):
        self.__current_response = ""
        self.__current_response_word = 0
        self.__current_response_line_offset = 0
        self.done_printing = False

    def append_response(self, response):
        self.__current_response += re.sub("""\n+""", "  ", response)

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
        if time.ticks_ms() - self.__last_frame_time > self.FRAME_RATE:
            self.__last_frame_time = time.ticks_ms()
            response_words = self.__current_response.split(" ")

            # Spacial case to zero out empty buffer
            if response_words == [""]:
                response_words = []

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

            display.show(text_objects)

            if time.ticks_ms() - self.__last_word_time > self.WORD_SPEED:
                self.__last_word_time = time.ticks_ms()
                if self.__current_response_word == len(response_words):
                    if len(response_words) > 0:
                        self.done_printing = True
                    return
                self.__current_response_word += 1
