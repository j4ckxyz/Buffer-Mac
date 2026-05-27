import Carbon
import AppKit

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var hotKeyRef: EventHotKeyRef? = nil
    private var eventHandlerRef: EventHandlerRef? = nil
    
    var onTrigger: (() -> Void)? = nil
    
    init() {}
    
    func registerCurrentShortcut() {
        unregister()
        
        let modifierName = UserDefaults.standard.string(forKey: "hotkey_modifier") ?? "Option"
        let keyName = UserDefaults.standard.string(forKey: "hotkey_key") ?? "Space"
        
        let carbonModifiers = getCarbonModifiers(for: modifierName)
        let keyCode = getKeyCode(for: keyName)
        
        print("[Hotkey] ⚡️ Registering hotkey: \(modifierName) + \(keyName) (Modifiers: \(carbonModifiers), KeyCode: \(keyCode))")
        
        // Dynamic OSType conversion for HotKey signature (warning-free)
        let signature = fourCharCode("BfMc")
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        
        let eventHandler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                GlobalHotkeyManager.shared.onTrigger?()
            }
            return noErr
        }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), eventHandler, 1, &eventType, nil, &eventHandlerRef)
        
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status != noErr {
            print("[Hotkey] ❌ Failed to register hotkey with status: \(status)")
        } else {
            print("[Hotkey] ✅ Hotkey registered successfully!")
        }
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
    
    private func getCarbonModifiers(for name: String) -> Int {
        switch name {
        case "Command": return cmdKey
        case "Option": return optionKey
        case "Control": return controlKey
        case "Shift": return shiftKey
        case "Cmd + Opt": return cmdKey | optionKey
        case "Cmd + Shift": return cmdKey | shiftKey
        case "Opt + Shift": return optionKey | shiftKey
        case "Ctrl + Opt": return controlKey | optionKey
        case "Ctrl + Cmd": return controlKey | cmdKey
        case "Hyperkey": return cmdKey | optionKey | controlKey | shiftKey
        default: return optionKey
        }
    }
    
    private func getKeyCode(for name: String) -> Int {
        switch name.uppercased() {
        case "A": return 0
        case "B": return 11
        case "C": return 8
        case "D": return 2
        case "E": return 14
        case "F": return 3
        case "G": return 5
        case "H": return 4
        case "I": return 34
        case "J": return 38
        case "K": return 40
        case "L": return 37
        case "M": return 46
        case "N": return 45
        case "O": return 31
        case "P": return 35
        case "Q": return 12
        case "R": return 15
        case "S": return 1
        case "T": return 17
        case "U": return 32
        case "V": return 9
        case "W": return 13
        case "X": return 7
        case "Y": return 16
        case "Z": return 6
        case "ENTER": return 36
        case "SPACE": return 49
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "0": return 29
        default: return 49
        }
    }
    
    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for char in string.utf8 {
            result = (result << 8) + OSType(char)
        }
        return result
    }
}
