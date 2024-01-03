function BluetoothSendMessage(message)
    while true do
        local success, error_message = pcall(frame.bluetooth.send, message)
        if success then
            break
        end
        if error_message then
            print(error_message)
            break
        end
    end
end

BluetoothSendMessage("pon:hello")

a = {}    -- new array, test [] escape
for i=1, 1000 do
    a[i] = 0
end
