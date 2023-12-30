State = {}
State.__index = State
State.Init = "Init"
State.Welcome = "Welcome"
State.Connected = "Connected"
State.WaitForTap = "WaitForTap"
State.DetectSingleTap = "DetectSingleTap"
State.DetectHold = "DetectHold"
State.StartRecording = "StartRecording"
State.SendAudio = "SendAudio"
State.WaitForPing = "WaitForPing"
State.WaitForResponse = "WaitForResponse"
State.AskToCancel = "AskToCancel"
State.PrintResponse = "PrintResponse"
State.CaptureImage = "CaptureImage"
State.SendImage = "SendImage"
State.Undefined = "Undefined"

function State.new()
    local self = setmetatable({}, State)
    self.previous_state = State.Init
    self.current_state = State.Init
    self.next_state = State.Init
    self.entry_time = frame.time.date()['second']
    self.entered = true
    return self
end

-- comment
-- Method to transition to the next state after a certain wait time
function State:after(wait_time, next_state)
    if next_state ~= self.next_state then
        self.next_state = next_state
    end
    if self.current_state ~= self.next_state then
        if frame.time.date()['second'] - self.entry_time >= wait_time then
            self.previous_state = self.current_state
            self.current_state = self.next_state
            self.entry_time = frame.time.date()['second']
            self.entered = true
            print("State: " .. tostring(self.current_state))
        end
    end
end

function State:has_been()
    return frame.time.date()['second'] - self.entry_time
end

function State:on_entry()
    if self.entered == true then
        self.entered = false
        return true
    end
    return false
end
