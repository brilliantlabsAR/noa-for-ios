Graphics = {}
Graphics.__index = Graphics

function Graphics.new()
    local self = setmetatable({}, Graphics)
    self.MAX_LINES = 7
    self.WORD_SPEED = 300
    self.FRAME_RATE = 15
    self:clear_response()
    self.__last_frame_time = frame.time.utc()
    self.__last_word_time = frame.time.utc()
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
    print("Graphics: " .. self.__current_response)
end

function Graphics:__split_lines(words)
    local word_arrays = {}
    local current_array = {}
    local current_length = 0
    local max_characters = 26 -- TODO make this dynamic

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
    frame.sleep(0.02)
end
