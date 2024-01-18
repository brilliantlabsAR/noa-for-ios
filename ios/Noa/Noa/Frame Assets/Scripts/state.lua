State = {}
State.__index = State

function State.new()
    local self = setmetatable({}, State)
    self.__previous_state = "START"
    self.__current_state = "START"
    self.__next_state = "START"
    self.__entry_time = frame.time.utc()
    self.__entered = true
    print("State: " .. tostring(self.__current_state))
    return self
end

function State:is(state)
    if self.__current_state == state then
        return true
    end
    return false
end

function State:switch_after(wait_time, __next_state)
    if __next_state ~= self.__next_state then
        self.__next_state = __next_state
    end
    if self.__current_state ~= self.__next_state then
        if frame.time.utc() - self.__entry_time >= wait_time then
            self.__previous_state = self.__current_state
            self.__current_state = self.__next_state
            self.__entry_time = frame.time.utc()
            self.__entered = true
            print("State: " .. tostring(self.__current_state))
        end
    end
end

function State:switch(state)
    self:switch_after(0, state)
end

function State:has_been()
    return frame.time.utc() - self.__entry_time
end

function State:on_entry(func)
    if self.__entered == true then
        self.__entered = false
        pcall(func)
    end
end
