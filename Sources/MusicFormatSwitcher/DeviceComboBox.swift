import SwiftUI
import AppKit

/// NSComboBox wrapper: shows available audio devices as suggestions,
/// but also accepts free-text input for partial name matching.
struct DeviceComboBox: NSViewRepresentable {
    @Binding var text: String
    let items: [String]

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox()
        combo.isEditable = true
        combo.completes = true
        combo.hasVerticalScroller = true
        combo.delegate = context.coordinator
        return combo
    }

    func updateNSView(_ combo: NSComboBox, context: Context) {
        combo.removeAllItems()
        combo.addItems(withObjectValues: items)
        if combo.stringValue != text {
            combo.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let combo = notification.object as? NSComboBox,
                  let selected = combo.objectValueOfSelectedItem as? String else { return }
            text = selected
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let combo = obj.object as? NSComboBox else { return }
            text = combo.stringValue
        }
    }
}
