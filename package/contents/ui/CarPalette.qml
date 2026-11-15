import QtQuick
import org.kde.kirigami as Kirigami

// The colors of the car drawing. Its body is filled with the car's own paint, or with tints
// of the theme's text color when no paint is given. Either way orange means open, green
// plugged in, and red a low tire or Sentry, so nothing else on the car uses those colors.
// It is an item, as Look is, so that the theme colors are those of where the car is shown.
Item {
    // The body color as "#rrggbb", or "" to draw the car in theme colors.
    property string paint: ""
    // Whether the body is drawn in the car's paint, or in theme colors.
    readonly property bool painted: paint !== ""

    Look { id: look }

    readonly property color textColor: Kirigami.Theme.textColor
    // Light text on a dark background. A tint of the text color darkens what is under it in
    // a light scheme and lightens it in a dark one, so the car in theme colors has to turn
    // its shading around to keep its glass darker than its body.
    readonly property bool darkScheme: luma(textColor) > luma(Kirigami.Theme.backgroundColor)
    readonly property color bodyColor: painted ? paint : textColor
    // How light the paint is, from 0 to 1.
    readonly property real paintLuma: luma(bodyColor)
    // A paint so dark that a darker line would not show on it.
    readonly property bool darkPaint: painted && paintLuma < 0.2

    function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    // A color mixed with black and with white.
    function shade(c, share) { return Qt.rgba(c.r * (1 - share), c.g * (1 - share), c.b * (1 - share), 1) }
    function glow(c, share) {
        return Qt.rgba(c.r + (1 - c.r) * share, c.g + (1 - c.g) * share, c.b + (1 - c.b) * share, 1)
    }

    // The body under a light from above: 0 is the paint itself, 1 is where the light falls
    // straight on it and -1 is where it turns away at the flank. A dark paint shows the
    // light more than the shade, and a light paint the other way round. In theme colors
    // the body is a tint of the text color, a stronger one where a paint would be darker
    // in a light scheme and where it would be lighter in a dark one.
    function bodyTone(level) {
        if (painted)
            return level > 0 ? glow(bodyColor, level * (0.03 + 0.08 * (1 - paintLuma)))
                             : shade(bodyColor, -level * 0.34)
        if (darkScheme)
            return look.tint(textColor, 0.46 + level * (level > 0 ? 0.08 : 0.18))
        return look.tint(textColor, 0.10 - level * (level > 0 ? 0.04 : 0.17))
    }
    // Across the car, from the flank to the middle.
    readonly property color bodyEdge: bodyTone(-1)
    readonly property color bodyTurn: bodyTone(-0.5)
    readonly property color bodyShoulder: bodyTone(-0.24)
    readonly property color bodySide: bodyTone(0)
    readonly property color bodyHigh: bodyTone(0.45)
    readonly property color bodyCrown: bodyTone(1)
    // The nose and the tail fall away from the light.
    readonly property color tipShade: painted ? Qt.rgba(0, 0, 0, 0.26) : noShade
    readonly property color endShade: painted ? Qt.rgba(0, 0, 0, 0.10) : noShade
    readonly property color noShade: Qt.rgba(0, 0, 0, 0)
    // The light on the hood and on the trunk lid.
    readonly property color sheenColor: Qt.rgba(1, 1, 1, 0.03 + 0.06 * (1 - paintLuma))
    readonly property color noSheen: Qt.rgba(1, 1, 1, 0)
    // The line around the body, in both looks: it is what tells a black car from a dark
    // popup and a white one from a light popup.
    readonly property color outlineColor: look.tint(textColor, 0.4)
    // Hood, trunk and door seams.
    readonly property color seamColor: !painted ? look.tint(textColor, 0.18)
                                                : darkPaint ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.22)
    readonly property color faintSeamColor: Qt.rgba(seamColor.r, seamColor.g, seamColor.b, seamColor.a * 0.4)
    // Glass along the car: lighter at the foot of the windshield and of the rear window,
    // where it slopes, than on the roof. Then the beams across the roof and the line
    // around a pane, which is light on a paint as dark as the glass itself: there it is
    // all that tells the panes from the body.
    readonly property color glassFront: painted ? "#222931" : look.tint(textColor, darkScheme ? 0.10 : 0.86)
    readonly property color glassColor: painted ? "#0c0e11" : look.tint(textColor, darkScheme ? 0.03 : 0.97)
    readonly property color glassRear: painted ? "#1a2027" : look.tint(textColor, darkScheme ? 0.08 : 0.90)
    readonly property color beamColor: painted ? "#2a2e33" : look.tint(textColor, darkScheme ? 0.14 : 0.72)
    readonly property color glassLine: !painted ? glassColor : darkPaint ? Qt.rgba(1, 1, 1, 0.17) : "#24282d"
    readonly property color faintGlassColor: Qt.rgba(glassColor.r, glassColor.g, glassColor.b, glassColor.a * 0.45)
    // What is written on the glass.
    readonly property color glassInk: darkScheme ? textColor : "#f4f5f6"
    // Tires are rubber in both looks: dark in a light scheme, and in a dark one just light
    // enough to show beside the popup.
    readonly property color tireColor: look.tint(textColor, darkScheme ? 0.25 : 0.85)
    // What is black on the car itself, such as fender flares.
    readonly property color trimColor: painted ? "#1d2024" : look.tint(textColor, darkScheme ? 0.36 : 0.7)
    // A low tire and its reading
    readonly property color lowColor: Kirigami.Theme.negativeTextColor
    // Lights are colorless. At the front a clear lens with a blade of light in it, at the
    // rear a smoked lens with a dim line: bright is the face and dark is the tail, on a
    // white car as on a black one.
    readonly property color lensColor: painted ? "#b9c3cd" : look.tint(textColor, 0.5)
    readonly property color lensLine: painted ? Qt.rgba(0, 0, 0, 0.28) : "transparent"
    readonly property color headlightColor: painted ? "#ffffff" : "transparent"
    readonly property color tailLensColor: painted ? Qt.rgba(0.03, 0.04, 0.05, 0.8) : look.tint(textColor, 0.3)
    readonly property color taillightColor: painted ? Qt.rgba(1, 1, 1, 0.38) : "transparent"
    // A mirror has the body's tone where the body turns down to the flank.
    readonly property color mirrorColor: bodyShoulder
    readonly property color openColor: Kirigami.Theme.neutralTextColor
    readonly property color openEdge: Qt.darker(openColor, 1.3)
    readonly property color pluggedColor: Kirigami.Theme.positiveTextColor
    readonly property color lockedColor: glassInk
    readonly property color unlockedColor: Kirigami.Theme.neutralTextColor
    readonly property color sentryColor: Kirigami.Theme.negativeTextColor

    // A part that can be open is solid when it is, and faint while nothing is known about
    // it. When only the total says that some part of its kind is open it gets a line and
    // no fill: around it, or for a door, whose outline would crowd the window's, along its
    // outer edge.
    function openFill(open, closed) { return open === true ? openColor : closed }
    function openLine(open, closed, unknown) {
        return open === true ? openEdge : open === "some" ? openColor : open === null ? unknown : closed
    }
}
