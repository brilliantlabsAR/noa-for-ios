Graphics = {}
Graphics.__index = Graphics

function Graphics.new()
    local self = setmetatable({}, Graphics)
    self.MAX_LINES = 7
    self.WORD_SPEED = 300
    self.FRAME_RATE = 15
    self.error_flag = false
    self.done_printing = false
    self:clear_response()
    self.__last_frame_time = frame.time.date()['second']
    self.__last_word_time = frame.time.date()['second']
    return self
end

function Graphics:clear_response()
    self.__current_response = ""
    self.__current_response_word = 0
    self.__current_response_line_offset = 0
    self.done_printing = false
end

function Graphics:append_response(response)
    self.__current_response = string.gsub(response, "\n+", "  ")
end

function Graphics:set_prompt(prompt)
    if self.__current_prompt ~= prompt then
        self.__current_prompt = prompt
    end
end

function Graphics:__split_lines(words)
    local word_arrays = {}
    local current_array = {}
    local current_length = 0
    local max_characters = 600 / 11

    for _, word in ipairs(words) do
        local word_length = string.len(word)
        if word == "" then
            table.insert(word_arrays, current_array)
            current_array = {}
            current_length = max_characters
        elseif current_length + word_length + #current_array <= max_characters then
            table.insert(current_array, word)
            current_length = current_length + word_length
        else
            table.insert(word_arrays, current_array)
            current_array = { word }
            current_length = word_length
        end
    end

    if #current_array > 0 then
        table.insert(word_arrays, current_array)
    end

    return word_arrays
end

function Graphics:run()
    -- if frame.time.date()['second'] - self.__last_frame_time > self.FRAME_RATE then
    --     self.__last_frame_time = frame.time.date()['second']
    --     local response_words = string.gmatch(self.__current_response, "%S+")
    --     local response_words_table = {}
    --     for word in response_words do
    --         table.insert(response_words_table, word)
    --     end

    --     -- Special case to zero out empty buffer
    --     if #response_words_table == 1 and response_words_table[1] == "" then
    --         response_words_table = {}
    --     end

    --     local partial_response_words = {}
    --     for i = 1, self.__current_response_word do
    --         table.insert(partial_response_words, response_words_table[i])
    --     end

    --     local response_lines = self:__split_lines(partial_response_words)

    --     if #response_lines > self.MAX_LINES then
    --         self.__current_response_line_offset = #response_lines - self.MAX_LINES
    --     end

    --     local text_objects = {}
    --     -- local response_color = self.error_flag and display.RED or display.WHITE

    --     for line = 1, self.MAX_LINES do
    --         if #response_lines >= line then
    --             local text = table.concat(response_lines[self.__current_response_line_offset + line], " ")
    --             -- table.insert(text_objects, display.Text(text, 0, 50 * (line - 1), response_color))
    --             table.insert(text_objects, text)
    --         end
    --     end

    --     if #response_words_table == #partial_response_words then
    --         table.insert(
    --             text_objects,
    --             self.__current_prompt
    --         )
    --     end

    --     for key, value in pairs(text_objects) do
    --         print(value)
    --     end

    --     if frame.time.date()['second'] - self.__last_word_time > self.WORD_SPEED then
    --         self.__last_word_time = frame.time.date()['second']
    --         if self.__current_response_word == #response_words_table then
    --             if #response_words_table > 0 then
    --                 self.done_printing = true
    --             end
    --             return
    --         end
    --         self.__current_response_word = self.__current_response_word + 1
    --     end
    -- end
end
