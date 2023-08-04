import time


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
