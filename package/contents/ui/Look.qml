import QtQuick
import org.kde.kirigami as Kirigami

// Opacities and colors shared by the card's parts. Each part creates its own as `Look { id:
// look }`; the card's rows are handed the card's instead, since most are layouts where an
// extra item would take a place.
//
// It is an Item, though it draws nothing, because Kirigami.Theme's colors follow the item
// tree: inside a part, it has the colors of the popup or desktop the part is in, which can
// differ from the panel's, where the widget's root item lives. It must stay visible: in a
// panel's popup, Kirigami gives an invisible item black for every color.
Item {

    // Secondary text (labels, captions, units), and unknown values.
    readonly property real secondary: 0.7
    readonly property real faint: 0.5

    // The surface behind a row, and thin lines.
    readonly property color surface: tint(Kirigami.Theme.textColor, 0.05)
    readonly property color hairline: tint(Kirigami.Theme.textColor, 0.12)

    // Kirigami.Units.cornerRadius needs KDE Frameworks 6.2; Plasma 6.0 runs on 6.0.
    readonly property real radius: Kirigami.Units.cornerRadius ?? 5

    // The color c at opacity a. Always a tint of a theme color, never an imitation of the
    // background, so it works on a translucent popup.
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

    // The battery ring: green while charging, red then orange when low.
    function batteryColor(level, charging) {
        if (charging) return Kirigami.Theme.positiveTextColor
        if (level >= 0 && level < 10) return Kirigami.Theme.negativeTextColor
        if (level >= 0 && level < 20) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.highlightColor
    }
}
