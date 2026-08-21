import Carbon
import Foundation

enum KeyboardLayoutKeyNameResolver {
    static func name(for keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
