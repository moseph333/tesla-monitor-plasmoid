import QtQuick
import org.kde.kirigami as Kirigami

// The looks the card's parts share, so the ring, the car and the rows around them agree.
// Each part creates its own inside itself, as `Look { id: look }`. It is an item, though it
// draws nothing, because Kirigami.Theme's colors follow the tree of items: created inside a
// part, it has the colors of the popup or desktop that part is shown in, which can differ
// from the panel's, where the widget's root item lives.
// It has no size, and it stays visible: in a panel's popup, Kirigami gives an item that is
// not visible black for every theme color.
Item {

    // Secondary text, such as labels, captions and units, and a value that isn't known.
    readonly property real secondary: 0.7
    readonly property real faint: 0.5

    // The surface that groups a row, and the thin lines on it and under the ring.
    readonly property color surface: tint(Kirigami.Theme.textColor, 0.05)
    readonly property color hairline: tint(Kirigami.Theme.textColor, 0.12)

    // Kirigami.Units.cornerRadius came with KDE Frameworks 6.2, and Plasma 6.0 runs on 6.0.
    readonly property real radius: Kirigami.Units.cornerRadius ?? 5

    // The color c at opacity a. A tint is always of a theme color, never a stand-in for the
    // background, so it also works on a translucent popup.
    function tint(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // The dot beside the car's state in the header.
    function stateColor(state) {
        switch (state) {
        case "charging": return Kirigami.Theme.positiveTextColor
        case "driving": return Kirigami.Theme.highlightColor
        case "online": return Kirigami.Theme.positiveTextColor
        case "updating": return Kirigami.Theme.neutralTextColor
        case "offline": return Kirigami.Theme.negativeTextColor
        default: return tint(Kirigami.Theme.textColor, 0.35)
        }
    }

    // The battery ring: green while charging, red and then orange when the level is low.
    function batteryColor(level, charging) {
        if (charging) return Kirigami.Theme.positiveTextColor
        if (level >= 0 && level < 10) return Kirigami.Theme.negativeTextColor
        if (level >= 0 && level < 20) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.highlightColor
    }
}
