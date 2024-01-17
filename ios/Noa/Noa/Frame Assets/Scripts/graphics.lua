Graphics = {}
Graphics.__index = Graphics

function Graphics.new()
    local self = setmetatable({}, Graphics)
    self:clear()
    return self
end

function Graphics:clear()
    self.__current_text = ""
    self.__current_character = 0
    self.__current_image = ""
    frame.display.assign_color(1, 0x00, 0x00, 0x00)
    frame.display.assign_color(2, 0xFF, 0xFF, 0xFF)
end

function Graphics:append_text(response)
    self.__current_text = self.__current_text .. string.gsub(response, "\n+", " ")
end

function Graphics:append_image(response)
    self.__current_image = self.__current_image .. response
end

function Graphics:set_color(index, red, green, blue)
    frame.display.assign_color(index, red, green, blue)
end

function Graphics:on_complete(func)
    if self.__current_character > 0 and self.__current_character == #self.__current_text then
        pcall(func)
    end
end

function Graphics:run()
    -- Print out an image if valid
    if #self.__current_image == 80000 then
        frame.display.clear()
        frame.sleep(0.02)
        frame.display.bitmap(120, 0, 400, 16, 0, #self.__current_image)
        frame.display.show()
        frame.sleep(0.02)
        return
    end

    -- Otherwise print text
    local MAX_LINES = 3
    local Y_OFFSET = 150
    local SCREEN_WIDTH = 640
    local CHARACTER_WIDTH = 24
    local WORD_DELAY = 0.1

    -- Local variables
    local line_count = 1
    local lines = { "" }
    local accumulated_width = 0
    local trunkated_text = string.sub(self.__current_text, 1, self.__current_character)

    for word in string.gmatch(trunkated_text, "%S+") do
        for character in string.gmatch(word, "%S+") do
            if accumulated_width + (CHARACTER_WIDTH * #character) > SCREEN_WIDTH then
                accumulated_width = 0
                line_count = line_count + 1
                if line_count > MAX_LINES then
                    for shifted_line = 0, MAX_LINES - 1 do
                        lines[line_count - MAX_LINES + shifted_line] = lines[line_count - MAX_LINES + shifted_line + 1]
                    end
                    line_count = line_count - 1
                end
                lines[line_count] = ""
            end
            accumulated_width = accumulated_width + (CHARACTER_WIDTH * #character) + 24
            lines[line_count] = lines[line_count] .. " " .. word
        end
    end

    -- Print to the display
    frame.display.clear()
    frame.sleep(0.02)

    for i, line in pairs(lines) do
        local y = 1 + ((i - 1) * 58) + Y_OFFSET
        frame.display.text(line, 1, y)
    end

    frame.display.show()
    frame.sleep(0.02)


    -- Delay for appropriate time
    if string.sub(self.__current_text, self.__current_character, self.__current_character) == " " then
        frame.sleep(WORD_DELAY)
    end

    -- Increment for the next print
    if self.__current_character < #self.__current_text then
        self.__current_character = self.__current_character + 1
    end
end
