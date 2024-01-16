State = {}
State.__index = State
State.Init = "Init"
State.TapTutorial = "TapTutorial"
State.WaitingForTap = "WaitingForTap"
State.RecordAudio = "RecordAudio"
State.WaitForResponse = "WaitForResponse"

function State.new()
    local self = setmetatable({}, State)
    self.previous_state = State.Init
    self.current_state = State.Init
    self.next_state = State.Init
    self.entry_time = frame.time.utc()
    self.entered = true
    return self
end

function State:is(state)
    if self.current_state == state then
        return true
    end
    return false
end

function State:switch_after(wait_time, next_state)
    if next_state ~= self.next_state then
        self.next_state = next_state
    end
    if self.current_state ~= self.next_state then
        if frame.time.utc() - self.entry_time >= wait_time then
            self.previous_state = self.current_state
            self.current_state = self.next_state
            self.entry_time = frame.time.utc()
            self.entered = true
            print("State: " .. tostring(self.current_state))
        end
    end
end

function State:switch(state)
    self:switch_after(0, state)
end

function State:has_been()
    return frame.time.utc() - self.entry_time
end

function State:on_entry(func)
    if self.entered == true then
        self.entered = false
        pcall(func)
    end
end
