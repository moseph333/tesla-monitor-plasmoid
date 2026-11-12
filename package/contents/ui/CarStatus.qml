pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// Top-down Model 3 showing everything about the car's body at once: a pressure reading at
// each wheel, doors that swing out when open, windows, frunk, trunk, charge port, lock and
// Sentry. Hovering lists the same status as text.
// The car lies on its side with its nose to the right, like the panel icon, or stands nose
// up, whichever draws it larger in the room the item has.
// Its body is filled with the car's own paint, or with tints of the theme's text color when
// no paint is given. Either way orange means open, green plugged in, and red a low tire or
// Sentry, so nothing else on the car uses those colors.
// The body, mirrors and axles use the car's real dimensions: 1 unit = 10 mm, the body is
// 185 × 469.4 and starts 12 units in from the left so the mirrors fit. The wheels sit
// further out than the real track so they stay visible from above.
Item {
    id: root

    // Raw TeslaMate values keyed by topic suffix
    property var car: ({})
    // Each: { value: "42", unit: "psi", text: "42 psi", warn: bool }
    property var fl: ({ value: "—", unit: "", text: "—", warn: false })
    property var fr: ({ value: "—", unit: "", text: "—", warn: false })
    property var rl: ({ value: "—", unit: "", text: "—", warn: false })
    property var rr: ({ value: "—", unit: "", text: "—", warn: false })
    // The body color as "#rrggbb", or "" to draw the car in theme colors.
    property string paint: ""
    // TeslaMate names doors and windows by driver and passenger, not left and right.
    property bool rightHandDrive: false

    // Whether the body is drawn in the car's paint, or in theme colors.
    readonly property bool painted: paint !== ""

    // ---------- state ----------

    readonly property string leftSeat: rightHandDrive ? "passenger" : "driver"
    readonly property string rightSeat: rightHandDrive ? "driver" : "passenger"
    readonly property var frunkOpen: Logic.triState(car, "frunk_open")
    readonly property var trunkOpen: Logic.triState(car, "trunk_open")
    readonly property var portOpen: Logic.triState(car, "charge_port_door_open")
    readonly property bool pluggedIn: Logic.bool(car, "plugged_in")
    readonly property var locked: Logic.triState(car, "locked")
    readonly property bool sentry: Logic.bool(car, "sentry_mode")

    function doorState(seat, row) {
        return Logic.partOpen(car, seat + "_" + row + "_door_open", "doors_open")
    }
    function windowState(seat, row) {
        return Logic.partOpen(car, seat + "_" + row + "_window_open", "windows_open")
    }

    // ---------- colors and lines ----------

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
    // around a pane.
    readonly property color glassFront: painted ? "#222931" : look.tint(textColor, darkScheme ? 0.10 : 0.86)
    readonly property color glassColor: painted ? "#0c0e11" : look.tint(textColor, darkScheme ? 0.03 : 0.97)
    readonly property color glassRear: painted ? "#1a2027" : look.tint(textColor, darkScheme ? 0.08 : 0.90)
    readonly property color beamColor: painted ? "#2a2e33" : look.tint(textColor, darkScheme ? 0.14 : 0.72)
    readonly property color glassLine: painted ? "#24282d" : glassColor
    readonly property color faintGlassColor: Qt.rgba(glassColor.r, glassColor.g, glassColor.b, glassColor.a * 0.45)
    // What is written on the glass.
    readonly property color glassInk: darkScheme ? textColor : "#f4f5f6"
    // Tires are rubber in both looks: dark in a light scheme, and in a dark one just light
    // enough to show beside the popup.
    readonly property color tireColor: look.tint(textColor, darkScheme ? 0.25 : 0.85)
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

    // A part that can be open is solid when it is, outlined when only the total says that
    // some part of its kind is open, and faint while nothing is known about it.
    function openFill(open, closed) { return open === true ? openColor : closed }
    function openLine(open, closed, unknown) {
        return open === true ? openEdge : open === "some" ? openColor : open === null ? unknown : closed
    }
    // The charge port is green with a cable in it, orange when open and empty, and not
    // drawn when closed or while TeslaMate hasn't reported it.
    readonly property color portFill: pluggedIn ? pluggedColor : portOpen ? openColor : "transparent"
    readonly property color portLine: pluggedIn ? Qt.darker(pluggedColor, 1.3) : portOpen ? openEdge : "transparent"

    // The width of the line around a part, around the body, and of the cable.
    readonly property real lineWidth: 1
    readonly property real bodyLineWidth: 1.5
    readonly property real cableWidth: 2
    readonly property real lightWidth: 1.5

    // ---------- the car, in units, nose up ----------

    readonly property real boxWidth: 209
    readonly property real boxHeight: 470
    readonly property real frontAxle: 84
    readonly property real rearAxle: 371.5
    // The box ends at the mirror tips. The wheels' outer faces are this far inside it.
    readonly property real wheelInset: 4
    // A door is this wide. An open one swings doorSwing degrees around its front edge: the
    // rear corner of a front door, which is 114 long and hinged 14 inside the box, is then
    // doorReach outside the box (114 × sin 30° − 14).
    readonly property real doorWidth: 13
    readonly property real doorSwing: 30
    readonly property real doorReach: 43
    // How far a reading above or below a wheel may reach towards the middle of the car: an
    // open rear door, 13 wide and 66 long from its hinge at 270, ends this far ahead of the
    // rear axle (371.5 − 270 − 13 × sin 30° − 66 × cos 30°).
    readonly property real readingReach: 37.8

    // The car's two sides mirror each other. A part of the left side that reaches from x0
    // to x1 across the car lies between these two places on either side, on whole pixels.
    // The right side's part is the left one's mirror image, taken after rounding: rounded
    // on its own, an edge that falls on half a pixel goes the same way on both sides, and
    // one of the two parts ends up a pixel wider than the other.
    function side(onLeft, x0, x1) {
        return onLeft ? [snap(x0), snap(x1)] : [boxWidth - snap(x1), boxWidth - snap(x0)]
    }

    // The outline of a rectangle with rounded corners, from x0 to x1 across the car and
    // from y0 to y1 along it, and of a circle, as SVG paths.
    function roundedRect(x0, y0, x1, y1, radius) {
        const r = Math.max(0, Math.min(radius, (x1 - x0) / 2, (y1 - y0) / 2))
        return ["M", x0 + r, y0, "H", x1 - r, "A", r, r, 0, 0, 1, x1, y0 + r,
                "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
                "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
                "V", y0 + r, "A", r, r, 0, 0, 1, x0 + r, y0, "Z"].join(" ")
    }
    function circle(cx, cy, r) {
        return ["M", cx - r, cy, "A", r, r, 0, 1, 0, cx + r, cy,
                "A", r, r, 0, 1, 0, cx - r, cy, "Z"].join(" ")
    }
    // The same rectangle with its edges on whole pixels, and half the width of the line
    // around it further in, so that the straight edges fill whole pixels and are sharp.
    function box(x0, y0, x1, y1, radius, line) {
        const d = inUnits(line / 2)
        return roundedRect(snap(x0) + d, snap(y0) + d, snap(x1) - d, snap(y1) - d, radius)
    }

    // The body's flanks and the edges of the roof are long straight lines along the car.
    // They are moved, by less than half a pixel, to where such a line fills whole pixels.
    readonly property real flank: crisp(12.25, bodyLineWidth)
    readonly property real roofEdge: crisp(46, lineWidth)
    readonly property string bodyPath: [
        "M 104.5 0 C 64 0 29 6 20.5 34 C 15.5 50 13 72", flank, "104 L", flank, "330",
        "C", flank, "385 13.5 422 16.5 441 C 20.5 459 44 466.5 74 468.5 C 86 469.4 96 469.4 104.5 469.4",
        "C 113 469.4 123 469.4 135 468.5 C 165 466.5 188.5 459 192.5 441",
        "C 195.5 422", boxWidth - flank, "385", boxWidth - flank, "330 L", boxWidth - flank, "104",
        "C 196 72 193.5 50 188.5 34 C 180 6 145 0 104.5 0 Z"
    ].join(" ")
    readonly property string frunkPath: "M 104.5 9 C 70 9 40 14 33 38 L 35 110 C 67 116 142 116 174 110 L 176 38 C 169 14 139 9 104.5 9 Z"
    readonly property string trunkPath: "M 50 397 C 75 402 134 402 159 397 L 174 436 C 164 453 137 459 104.5 459 C 72 459 45 453 35 436 Z"
    // Windshield, roof and rear window
    readonly property string glassPath: [
        "M 37 118 C 67 124 142 124 172 118 L", boxWidth - roofEdge, "198 C 134 202 75 202", roofEdge, "198 Z",
        "M", roofEdge, "204 C 75 208 134 208", boxWidth - roofEdge, "204",
        "L", boxWidth - roofEdge, "292 C 134 295 75 295", roofEdge, "292 Z",
        "M", roofEdge, "298 C 75 301 134 301", boxWidth - roofEdge, "298 L 159 390 C 134 395 75 395 50 390 Z"
    ].join(" ")
    // The two beams across the roof, between the panes of glass.
    readonly property string beamPath: [
        "M", roofEdge, "198 C 75 202 134 202", boxWidth - roofEdge, "198",
        "L", boxWidth - roofEdge, "204 C 134 208 75 208", roofEdge, "204 Z",
        "M", roofEdge, "292 C 75 295 134 295", boxWidth - roofEdge, "292",
        "L", boxWidth - roofEdge, "298 C 134 301 75 301", roofEdge, "298 Z"
    ].join(" ")
    // The body with the glass left out of it, for a body that is not opaque: all of
    // bodyPath, and inside it, as holes, the panes, the beams and the side windows.
    readonly property string openBodyPath: [
        bodyPath, glassPath, beamPath,
        windowHole(true, 178, 264), windowHole(true, 272, 330),
        windowHole(false, 178, 264), windowHole(false, 272, 330)
    ].join(" ")

    // The body's left edge beside a wheel, from the two curves of bodyPath that pass the
    // axles. Along both of them y only grows, so the place on a curve is found by halving.
    function flankAt(y) {
        const curve = y < boxHeight / 2 ? [[20.5, 34], [15.5, 50], [13, 72], [flank, 104]]
                                        : [[flank, 330], [flank, 385], [13.5, 422], [16.5, 441]]
        const along = (axis, t) => {
            const s = 1 - t
            return s * s * s * curve[0][axis] + 3 * s * s * t * curve[1][axis]
                    + 3 * s * t * t * curve[2][axis] + t * t * t * curve[3][axis]
        }
        let before = 0
        let after = 1
        for (let i = 0; i < 16; i++) {
            const t = (before + after) / 2
            if (along(1, t) < y)
                before = t
            else
                after = t
        }
        return along(0, (before + after) / 2)
    }
    // A place across the car on the left side, or its reflection on the right.
    function reflect(onLeft, x) { return onLeft ? x : boxWidth - x }
    // A chain of curves through points given as [x, y]: the first, then three for each
    // curve. Drawn on the left side of the car and again, mirrored, on the right.
    function onBothSides(points, closed) {
        const one = onLeft => points.map((p, i) => (i === 0 ? "M " : i % 3 === 1 ? "C " : "")
                                                  + reflect(onLeft, p[0]) + " " + p[1]).join(" ")
        return one(true) + (closed ? " Z " : " ") + one(false) + (closed ? " Z" : "")
    }

    // What shows of a tire: its outer face and its two ends, from the body's edge outwards.
    function tirePath(onLeft, axle) {
        const face = snap(wheelInset)
        const front = snap(axle - 33)
        const rear = snap(axle + 33)
        const r = 4.5
        return ["M", reflect(onLeft, flankAt(front)), front, "H", reflect(onLeft, face + r),
                "Q", reflect(onLeft, face), front, reflect(onLeft, face), front + r, "V", rear - r,
                "Q", reflect(onLeft, face), rear, reflect(onLeft, face + r), rear,
                "H", reflect(onLeft, flankAt(rear)), "Z"].join(" ")
    }
    // Windows and doors are rounded at their corners by a share of their width.
    function windowPath(onLeft, from, to) {
        const w = 14
        const [left, right] = side(onLeft, 29, 29 + w)
        return box(left, from, right, to, w * 0.4, lineWidth)
    }
    // All that a window covers, its line included.
    function windowHole(onLeft, from, to) {
        const w = 14
        const [left, right] = side(onLeft, 29, 29 + w)
        return box(left, from, right, to, w * 0.4, 0)
    }
    // A door that is w wide and l long once it is on whole pixels, and the mirror on a
    // front door, both measured from the door's own front left corner.
    function doorPath(w, l) {
        return box(0, 0, w, l, doorWidth * 0.35, lineWidth)
    }
    // A mirror grows out of the body: 12 out, swept back at the front and straight at the
    // rear, where its glass is. Its path starts and ends on the flank and is not closed, so
    // its line leaves the body's own line whole.
    function mirrorPath(onLeft, w) {
        const base = snap(14) - flank - inUnits(bodyLineWidth / 2)
        const x = out => onLeft ? -out : w + out
        return ["M", x(base), 3, "C", x(base + 4), 3.4, x(9.5), 6.2, x(11.8), 9.4,
                "C", x(13.6), 11.8, x(12.6), 14.4, x(10.4), 14.4, "L", x(base), 14.4].join(" ")
    }
    // Lights follow the corners of the car between its outline and the hood or the trunk:
    // a lens, and a line of light inside it.
    readonly property string headlightPath: onBothSides([[70.3, 3.8], [52, 6.7], [30.1, 11.6], [22.2, 34.5],
                                                         [21.2, 38], [20.4, 41.5], [19.7, 45.5],
                                                         [23.5, 43.5], [28.5, 41], [31.6, 37.6],
                                                         [37.3, 20.1], [51.8, 13.8], [68.7, 10.3]], true)
    readonly property string headlightLine: onBothSides([[64.5, 7.7], [51.9, 10.3], [33.7, 15.9], [27.2, 33.5]], false)
    readonly property string taillightPath: onBothSides([[16.2, 420], [16.7, 428], [17.4, 435], [18.3, 440.7],
                                                         [23.7, 459.9], [48, 464.7], [74.1, 466.7],
                                                         [74.1, 466.7], [73.2, 459.2], [73.2, 459.2],
                                                         [52, 457.5], [31.5, 451.5], [25, 436.5],
                                                         [22.5, 430.5], [18.5, 424.5], [16.2, 420]], true)
    readonly property string taillightLine: onBothSides([[21, 434], [25.5, 455], [49, 461], [70, 462.8]], false)
    // Where one door ends and the next begins, across the shoulder from the flank to the glass.
    readonly property string seamPath: [152, 268, 336].map(y => {
        const at = crisp(y, lineWidth)
        return ["M", flank, at, "H 29 M", boxWidth - flank, at, "H", boxWidth - 29].join(" ")
    }).join(" ")
    // The charge port is always on the left rear. It keeps a size that can be seen when the
    // car gets small, and then moves back to stay clear of the rear wheel.
    readonly property real portRadius: Math.max(5.5, inUnits(Kirigami.Units.smallSpacing * 0.75))
    readonly property real portY: Math.max(422, rearAxle + 33 + inUnits(1) + portRadius)
    readonly property string portPath: circle(20, portY, portRadius)
    // From the port out to the side
    readonly property string cablePath: "M 14 422 C 6 423 0 432 -2 450"

    // The signs on the glass, on a grid of 20 × 20: a padlock, the same with its shackle
    // lifted out, and a camera's lens for Sentry.
    readonly property string padlockBody: "M 6 9 H 14 A 2 2 0 0 1 16 11 V 16 A 2 2 0 0 1 14 18 H 6 A 2 2 0 0 1 4 16 V 11 A 2 2 0 0 1 6 9 Z M 9 13 A 1 1 0 0 1 11 13 V 14 A 1 1 0 0 1 9 14 Z"
    readonly property string lockPath: "M 6 9 V 6 A 4 4 0 0 1 14 6 V 9 H 12 V 6 A 2 2 0 0 0 8 6 V 9 Z " + padlockBody
    readonly property string unlockPath: "M 6 9 V 4 A 4 4 0 0 1 14 4 V 6 H 12 V 4 A 2 2 0 0 0 8 4 V 9 Z " + padlockBody
    readonly property string sentryPath: "M 2 10 A 8 8 0 1 0 18 10 A 8 8 0 1 0 2 10 Z M 4 10 A 6 6 0 1 0 16 10 A 6 6 0 1 0 4 10 Z M 7 10 A 3 3 0 1 0 13 10 A 3 3 0 1 0 7 10 Z"

    // ---------- scale and orientation ----------

    // The item's size in whole pixels: what the car and its readings have to fit in.
    readonly property int wholeWidth: Math.floor(width)
    readonly property int wholeHeight: Math.floor(height)
    // A line is drawn half outside its shape, and a part can be a pixel off once it's on
    // whole pixels. This keeps what is on the edge of the drawing inside the item.
    readonly property real pad: 2
    // The space between a wheel and the reading beside it. A reading above or below its
    // wheel is closer, since a line of text brings space of its own, and stays that far
    // from an open door too.
    readonly property real gap: Kirigami.Units.smallSpacing * 2
    readonly property real lineGap: Kirigami.Units.smallSpacing
    readonly property real readingWidth: Math.max(flReading.width, frReading.width,
                                                  rlReading.width, rrReading.width)
    readonly property real readingHeight: flReading.height

    // Pixels per unit with the nose up and on its side. Both leave room for the readings and
    // for an open front door, so the car keeps its size when a door opens. They depend on
    // nothing but the item's size and the size of the readings, so choosing between them
    // can't loop.
    readonly property real unitUp: Math.min((wholeHeight - 2 * pad) / boxHeight,
                                            (wholeWidth - 2 * pad) / (boxWidth + 2 * doorReach),
                                            (wholeWidth - 2 * (pad + readingWidth + gap))
                                            / (boxWidth - 2 * wheelInset))
    // The last term keeps room beyond the wheels for a reading that had to move away from
    // the doors: see Reading.
    readonly property real unitSide: Math.min((wholeWidth - 2 * pad) / boxHeight,
                                              (wholeHeight - 2 * pad) / (boxWidth + 2 * doorReach),
                                              (wholeHeight - 2 * (readingHeight + lineGap))
                                              / (boxWidth - 2 * wheelInset),
                                              (wholeWidth / 2 - pad - readingWidth - lineGap)
                                              / (boxHeight / 2 - frontAxle - readingReach))
    readonly property bool sideways: unitSide > unitUp
    // The least height at which the car lies on its side, in an item that is wider than
    // high. In less, the readings above and below the wheels leave the car less room than
    // it has standing nose up: this is where (h - readings) / the car's width passes
    // (h - pad) / the car's length.
    readonly property real sidewaysHeight: {
        const across = boxWidth - 2 * wheelInset
        return Math.floor((2 * (readingHeight + lineGap) * boxHeight - 2 * pad * across)
                          / (boxHeight - across)) + 1
    }
    // Rounded down to a car that is a whole number of pixels wide. It sits on whole pixels,
    // so its two sides fall on the pixel grid alike and are drawn alike.
    readonly property real unit: Math.max(0, Math.floor((sideways ? unitSide : unitUp) * boxWidth) / boxWidth)
    readonly property size pathScale: Qt.size(unit, unit)
    function u(v) { return v * unit }
    // Pixels in units, for what keeps its size on screen.
    function inUnits(px) { return unit > 0 ? px / unit : 0 }
    // v moved to a whole number of pixels from the car's corner, and to where the middle of
    // a straight line of some width has to be for the line to start on a whole pixel.
    function snap(v) { return inUnits(Math.round(u(v))) }
    function crisp(v, line) { return inUnits(Math.round(u(v) - line / 2) + line / 2) }

    // Where a point of the car is in this item, on a whole pixel. Everything that stays
    // upright while the car turns is placed with it.
    function at(x, y) {
        return sideways ? Qt.point(Math.round(drawing.x - u(y)), Math.round(drawing.y + u(x)))
                        : Qt.point(Math.round(drawing.x + u(x)), Math.round(drawing.y + u(y)))
    }

    // The signs are as large as a small icon. They grow with a car that is larger than the
    // popup's, in even sizes so that they stay centered on a pixel, up to 32 pixels, and
    // they are never larger than the windshield is long.
    readonly property real glyphSize: Math.min(Math.floor(u(78)), Math.max(20, Math.min(32, 2 * Math.floor(u(15)))))

    // ---------- tooltip text ----------

    function openText(open) {
        return open === null ? "—" : (open ? i18n("Open") : i18n("Closed"))
    }

    function summary() {
        const lines = []
        if (locked !== null) lines.push(locked ? i18n("Locked") : i18n("Unlocked"))
        lines.push(i18n("Doors: %1", texts.partsText(Logic.parts(car, "door"))))
        lines.push(i18n("Windows: %1", texts.partsText(Logic.parts(car, "window"))))
        lines.push(i18n("Frunk: %1", openText(frunkOpen)))
        lines.push(i18n("Trunk: %1", openText(trunkOpen)))
        lines.push(i18n("Charge port: %1", pluggedIn ? i18n("Plugged in") : openText(portOpen)))
        const sentryState = Logic.triState(car, "sentry_mode")
        lines.push(i18n("Sentry: %1", sentryState === null ? "—" : (sentryState ? i18n("On") : i18n("Off"))))
        const low = [["fl", fl], ["fr", fr], ["rl", rl], ["rr", rr]]
            .filter(t => t[1].warn).map(t => texts.tireName(t[0]))
        if (low.length > 0) lines.push(i18n("Low tire pressure: %1", low.join(", ")))
        return lines.join("\n")
    }

    Texts { id: texts }
    Look { id: look }

    implicitWidth: 2 * (readingWidth + gap) + Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 7

    // ---------- parts ----------

    // One piece of the car: an outline in units that is filled, stroked or both.
    component Part: ShapePath {
        id: part
        property string path
        fillColor: "transparent"
        strokeColor: "transparent"
        strokeWidth: root.lineWidth
        joinStyle: ShapePath.RoundJoin
        scale: root.pathScale
        PathSvg { path: part.path }
    }

    component Tire: Part {
        property bool onLeft
        property real axle
        property bool low
        path: root.tirePath(onLeft, axle)
        fillColor: low ? root.lowColor : root.tireColor
    }

    // Filled when this window is open. When TeslaMate only reports that some window is open,
    // all four get an orange outline but no fill.
    component SideWindow: Part {
        property bool onLeft
        property real from
        property real to
        property var open
        path: root.windowPath(onLeft, from, to)
        fillColor: root.openFill(open, open === null ? root.faintGlassColor : root.glassColor)
        strokeColor: root.openLine(open, root.glassLine, root.faintGlassColor)
    }

    // Hinged at its front edge. Swings out and fills only when TeslaMate says which door is
    // open; when it only reports that some door is open, all four get an orange outline.
    // It sits on whole pixels, like the parts that don't move.
    component Door: Shape {
        id: door
        property bool onLeft
        property real from
        property real to
        property var open
        readonly property var across: root.side(onLeft, 14, 14 + root.doorWidth)
        property real swing: open === true ? root.doorSwing : 0
        Behavior on swing {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        x: root.u(across[0])
        y: root.u(root.snap(from))
        width: root.u(across[1]) - x
        height: root.u(root.snap(to)) - y
        transform: Rotation {
            origin.x: door.onLeft ? 0 : door.width
            origin.y: 0
            angle: door.onLeft ? door.swing : -door.swing
        }

        // A closed door is not drawn: the seams on the body show where it is.
        Part {
            path: root.doorPath(root.inUnits(door.width), root.inUnits(door.height))
            fillColor: root.openFill(door.open, "transparent")
            strokeColor: root.openLine(door.open, "transparent", "transparent")
        }
    }

    // The mirrors sit on the front doors and swing with them.
    component FrontDoor: Door {
        id: frontDoor
        from: 152
        to: 266

        Part {
            path: root.mirrorPath(frontDoor.onLeft, root.inUnits(frontDoor.width))
            fillColor: root.mirrorColor
            strokeColor: root.outlineColor
        }
    }

    // A filled sign that stays upright whichever way the car lies, centered on a point of
    // the car.
    component Glyph: Shape {
        id: glyph
        property real centerX
        property real centerY
        property string path
        property color color
        readonly property point center: root.at(centerX, centerY)
        x: center.x - Math.floor(width / 2)
        y: center.y - Math.floor(height / 2)
        width: root.glyphSize
        height: root.glyphSize

        ShapePath {
            fillColor: glyph.color
            strokeColor: "transparent"
            scale: Qt.size(glyph.width / 20, glyph.height / 20)
            PathSvg { path: glyph.path }
        }
    }

    // What the car is drawn in: a multisampled layer over the whole item, placed so that
    // its texture reaches the screen pixel for pixel. Whatever is put in it is placed from
    // the item's corner.
    // Not Shape.CurveRenderer: on Qt 6.7 and 6.8 it can keep showing the paths at an old
    // scale when the row is resized several times in a row while the card lays out
    // (QTBUG-133267). A multisampled layer gives the same smooth edges, and the same ones
    // on every part. It is never turned; the car turns inside it.
    // It does not lie on the item's own area, because at a scale factor such as 125 % or
    // 150 % that rarely starts on a device pixel. A layer there reaches the screen blurred
    // if it is smoothed (layer.smooth), and with rows left out or repeated if it is not.
    // It starts on a multiple of 20 pixels of the window instead and is a multiple of 20
    // pixels wide and high, which is a whole number of device pixels at every scale factor
    // in steps of 5 %.
    // The software renderer draws nothing for a Shape inside a layer at scale factors
    // above 1, and doesn't need one (it anti-aliases on its own), so it skips it.
    component PixelLayer: Item {
        id: pixelLayer
        default property alias content: corner.data
        readonly property int grid: 20
        // Where the item is in the window, unless something above it is scaled or turned,
        // and how far that is past the grid.
        readonly property point origin: {
            let x = 0
            let y = 0
            for (let item = root; item; item = item.parent) {
                x += item.x
                y += item.y
            }
            return Qt.point(x, y)
        }
        readonly property point past: Qt.point(origin.x - Math.floor(origin.x / grid) * grid,
                                               origin.y - Math.floor(origin.y / grid) * grid)
        x: -past.x
        y: -past.y

        // The layer is on an item of its own at 0, 0, because Qt 6.12 makes a layer a
        // device pixel larger when its item is not on a device pixel of its parent.
        Item {
            width: Math.ceil((pixelLayer.past.x + root.wholeWidth) / pixelLayer.grid) * pixelLayer.grid
            height: Math.ceil((pixelLayer.past.y + root.wholeHeight) / pixelLayer.grid) * pixelLayer.grid
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.samples: 4

            // The item's corner in the layer. It is on a whole pixel even when the item
            // itself is not, so that the drawing is as sharp there.
            Item {
                id: corner
                x: Math.round(pixelLayer.past.x)
                y: Math.round(pixelLayer.past.y)
            }
        }
    }

    // A pressure with its unit beside it as a note. It never turns with the car: with the
    // nose up it is beside its wheel, and on the car's side it is above or below it.
    component Reading: Item {
        id: reading
        property var tire
        property bool onLeft
        property bool front
        // Without a unit there is no pressure either, only the dash that stands for it.
        readonly property bool known: tire.unit !== ""
        readonly property real axle: front ? root.frontAxle : root.rearAxle
        // The middle of the wheel's outer face.
        readonly property point wheel: root.at(onLeft ? root.wheelInset : root.boxWidth - root.wheelInset, axle)
        // Above or below its wheel, a reading is centered on it unless that brings it too
        // close to where an open rear door ends. Then it moves towards the end of the car,
        // at the front as far as at the rear so that both ends look alike.
        readonly property real centered: wheel.x - Math.round(width / 2)
        readonly property real limit: root.at(0, axle + (front ? root.readingReach : -root.readingReach)).x

        x: {
            let left
            if (!root.sideways)
                left = onLeft ? wheel.x - root.gap - width : wheel.x + root.gap
            else if (front)
                left = Math.max(centered, limit + root.lineGap)
            else
                left = Math.min(centered, limit - root.lineGap - width)
            return Math.max(0, Math.min(root.wholeWidth - width, left))
        }
        y: {
            let top
            if (!root.sideways)
                top = wheel.y - Math.round(height / 2)
            else
                top = onLeft ? wheel.y - root.lineGap - height : wheel.y + root.lineGap
            return Math.max(0, Math.min(root.wholeHeight - height, top))
        }
        // Text is as wide as its letters, which is rarely a whole number of pixels. The
        // unit starts on a whole pixel all the same, and so does what is beside the reading.
        readonly property real unitX: Math.round(valueLabel.implicitWidth + Kirigami.Units.smallSpacing / 2)
        width: known ? unitX + Math.ceil(unitLabel.implicitWidth) : Math.ceil(valueLabel.implicitWidth)
        height: Math.ceil(valueLabel.implicitHeight)

        PlasmaComponents3.Label {
            id: valueLabel
            text: reading.tire.value
            color: reading.tire.warn ? root.lowColor : root.textColor
            opacity: reading.known ? 1 : look.faint
            font.weight: reading.tire.warn && reading.known ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
            // A screen reader gets the pressure and its unit as one text.
            Accessible.name: reading.tire.text
        }
        PlasmaComponents3.Label {
            id: unitLabel
            x: reading.unitX
            y: Math.round(valueLabel.baselineOffset - baselineOffset)
            text: reading.tire.unit
            opacity: look.secondary
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            Accessible.ignored: true
        }
    }

    // The tooltip covers the whole row: the readings and any swung-open door, not just the car.
    HoverHandler { id: hover }

    PlasmaComponents3.ToolTip {
        visible: hover.hovered
        text: root.summary()
    }

    // ---------- the car ----------

    PixelLayer {
        // Drawn nose up and turned as a whole. From bottom to top: tires, body, frunk and
        // trunk, door seams, the glass over the cabin with its beams, lights, side windows,
        // doors with their mirrors, charge port and cable.
        Item {
            id: drawing
            x: Math.round(root.sideways ? (root.wholeWidth + height) / 2 : (root.wholeWidth - width) / 2)
            y: Math.round(root.sideways ? (root.wholeHeight - width) / 2 : (root.wholeHeight - height) / 2)
            width: root.u(root.boxWidth)
            height: root.u(root.boxHeight)
            rotation: root.sideways ? 90 : 0
            transformOrigin: Item.TopLeft

            Shape {
                width: drawing.width
                height: drawing.height

                Tire { onLeft: true; axle: root.frontAxle; low: root.fl.warn }
                Tire { onLeft: false; axle: root.frontAxle; low: root.fr.warn }
                Tire { onLeft: true; axle: root.rearAxle; low: root.rl.warn }
                Tire { onLeft: false; axle: root.rearAxle; low: root.rr.warn }

                // The body, shaded across the car. A gradient is laid out in the Shape's own
                // pixels, whatever the path's scale. A path with a gradient keeps a fill
                // color that is not transparent, or it would not be filled at all.
                Part {
                    path: root.painted ? root.bodyPath : root.openBodyPath
                    fillColor: root.bodySide
                    fillGradient: LinearGradient {
                        x1: root.u(root.flank)
                        y1: 0
                        x2: root.u(root.boxWidth - root.flank)
                        y2: 0
                        GradientStop { position: 0; color: root.bodyEdge }
                        GradientStop { position: 0.035; color: root.bodyTurn }
                        GradientStop { position: 0.09; color: root.bodyShoulder }
                        GradientStop { position: 0.22; color: root.bodySide }
                        GradientStop { position: 0.36; color: root.bodyHigh }
                        GradientStop { position: 0.5; color: root.bodyCrown }
                        GradientStop { position: 0.64; color: root.bodyHigh }
                        GradientStop { position: 0.78; color: root.bodySide }
                        GradientStop { position: 0.91; color: root.bodyShoulder }
                        GradientStop { position: 0.965; color: root.bodyTurn }
                        GradientStop { position: 1; color: root.bodyEdge }
                    }
                }
                // The same along the car, over the paint, and the line around the body.
                LinearGradient {
                    id: endShading
                    x1: 0
                    y1: 0
                    x2: 0
                    y2: root.u(469.4)
                    GradientStop { position: 0; color: root.tipShade }
                    GradientStop { position: 0.035; color: root.endShade }
                    GradientStop { position: 0.11; color: root.noShade }
                    GradientStop { position: 0.86; color: root.noShade }
                    GradientStop { position: 0.955; color: root.endShade }
                    GradientStop { position: 1; color: root.tipShade }
                }
                Part {
                    path: root.bodyPath
                    // Always filled, with a shade of nothing in theme colors: a fill that
                    // only comes with the paint is drawn over the lights instead of under them.
                    fillColor: "black"
                    fillGradient: endShading
                    strokeColor: root.outlineColor
                    strokeWidth: root.bodyLineWidth
                }
                // Hood and trunk lid: a soft light on the closed panel, solid when open.
                LinearGradient {
                    id: hoodSheen
                    x1: 0
                    y1: root.u(9)
                    x2: 0
                    y2: root.u(116)
                    GradientStop { position: 0; color: root.noSheen }
                    GradientStop { position: 0.4; color: root.sheenColor }
                    GradientStop { position: 1; color: root.noSheen }
                }
                LinearGradient {
                    id: trunkSheen
                    x1: 0
                    y1: root.u(397)
                    x2: 0
                    y2: root.u(459)
                    GradientStop { position: 0; color: root.noSheen }
                    GradientStop { position: 0.55; color: root.sheenColor }
                    GradientStop { position: 1; color: root.noSheen }
                }
                Part {
                    path: root.frunkPath
                    fillColor: root.openFill(root.frunkOpen, root.painted ? "white" : "transparent")
                    fillGradient: root.painted && root.frunkOpen !== true ? hoodSheen : null
                    strokeColor: root.openLine(root.frunkOpen, root.seamColor, root.faintSeamColor)
                }
                Part {
                    path: root.trunkPath
                    fillColor: root.openFill(root.trunkOpen, root.painted ? "white" : "transparent")
                    fillGradient: root.painted && root.trunkOpen !== true ? trunkSheen : null
                    strokeColor: root.openLine(root.trunkOpen, root.seamColor, root.faintSeamColor)
                }
                Part {
                    path: root.seamPath
                    strokeColor: root.seamColor
                    capStyle: ShapePath.FlatCap
                }
                Part {
                    path: root.beamPath
                    fillColor: root.beamColor
                }
                Part {
                    path: root.glassPath
                    fillColor: root.glassColor
                    fillGradient: LinearGradient {
                        x1: 0
                        y1: root.u(118)
                        x2: 0
                        y2: root.u(395)
                        GradientStop { position: 0; color: root.glassFront }
                        GradientStop { position: 0.3; color: root.glassColor }
                        GradientStop { position: 0.66; color: root.glassColor }
                        GradientStop { position: 1; color: root.glassRear }
                    }
                    strokeColor: root.glassLine
                }
                Part {
                    path: root.headlightPath
                    fillColor: root.lensColor
                    strokeColor: root.lensLine
                }
                Part {
                    path: root.headlightLine
                    strokeColor: root.headlightColor
                    strokeWidth: root.lightWidth
                    capStyle: ShapePath.RoundCap
                }
                Part {
                    path: root.taillightPath
                    fillColor: root.tailLensColor
                }
                Part {
                    path: root.taillightLine
                    strokeColor: root.taillightColor
                    capStyle: ShapePath.RoundCap
                }

                SideWindow { onLeft: true; from: 178; to: 264; open: root.windowState(root.leftSeat, "front") }
                SideWindow { onLeft: true; from: 272; to: 330; open: root.windowState(root.leftSeat, "rear") }
                SideWindow { onLeft: false; from: 178; to: 264; open: root.windowState(root.rightSeat, "front") }
                SideWindow { onLeft: false; from: 272; to: 330; open: root.windowState(root.rightSeat, "rear") }
            }

            FrontDoor { onLeft: true; open: root.doorState(root.leftSeat, "front") }
            Door { onLeft: true; from: 270; to: 336; open: root.doorState(root.leftSeat, "rear") }
            FrontDoor { onLeft: false; open: root.doorState(root.rightSeat, "front") }
            Door { onLeft: false; from: 270; to: 336; open: root.doorState(root.rightSeat, "rear") }

            // An open port is expected while plugged in.
            Shape {
                width: drawing.width
                height: drawing.height

                Part {
                    path: root.portPath
                    fillColor: root.portFill
                    strokeColor: root.portLine
                }
                Part {
                    path: root.cablePath
                    strokeColor: root.pluggedIn ? root.pluggedColor : "transparent"
                    strokeWidth: root.cableWidth
                    capStyle: ShapePath.RoundCap
                }
            }
        }

        // Sentry watches through the windshield, and the lock is on the roof.
        Glyph {
            visible: root.sentry
            centerX: root.boxWidth / 2
            centerY: 162
            path: root.sentryPath
            color: root.sentryColor
        }
        Glyph {
            visible: root.locked !== null
            centerX: root.boxWidth / 2
            centerY: 250
            path: root.locked ? root.lockPath : root.unlockPath
            color: root.locked ? root.lockedColor : root.unlockedColor
        }
    }

    // ---------- tire readings ----------

    Reading { id: flReading; tire: root.fl; onLeft: true; front: true }
    Reading { id: frReading; tire: root.fr; onLeft: false; front: true }
    Reading { id: rlReading; tire: root.rl; onLeft: true; front: false }
    Reading { id: rrReading; tire: root.rr; onLeft: false; front: false }
}
