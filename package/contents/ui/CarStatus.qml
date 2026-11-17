pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic
import "models.js" as Models

// The car from above: a pressure reading at each wheel, doors that swing out when open,
// windows, frunk, trunk, charge port, lock and Sentry. Hovering lists the same as text. The
// car lies nose right or stands nose up, whichever draws it larger.
//
// Shapes come from models.js as a plan in real dimensions (1 unit = 10 mm), in a box that
// ends at the mirror tips. The wheels sit further out than the real track so they show from
// above. Colors come from CarPalette.
Item {
    id: root

    // Raw TeslaMate values, keyed by topic suffix.
    property var car: ({})
    // Each tire: {value: "42", unit: "psi", text: "42 psi", warn: bool}
    property var fl: ({ value: "—", unit: "", text: "—", warn: false })
    property var fr: ({ value: "—", unit: "", text: "—", warn: false })
    property var rl: ({ value: "—", unit: "", text: "—", warn: false })
    property var rr: ({ value: "—", unit: "", text: "—", warn: false })
    // The recommended cold pressures as a line of text, or "" if the source doesn't say.
    property string recommendedPressure: ""
    // The body color as "#rrggbb", or "" for theme colors.
    property string paint: ""
    // TeslaMate names doors and windows by driver and passenger, not left and right.
    property bool rightHandDrive: false
    // A key from Models.KEYS.
    property string model: "3"
    readonly property var plan: Models.plan(model)
    // The plan's data for rear doors that lift like wings, or null for ordinary doors.
    readonly property var falcon: plan.falcon

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

    // ---------- lines ----------

    // The charge port: green when plugged in, orange when open and empty, otherwise not
    // drawn.
    readonly property color portFill: pluggedIn ? colors.pluggedColor : portOpen ? colors.openColor : "transparent"
    readonly property color portLine: pluggedIn ? Qt.darker(colors.pluggedColor, 1.3) : portOpen ? colors.openEdge : "transparent"

    // Stroke widths in pixels: around a part, around the body, and the cable.
    readonly property real lineWidth: 1
    readonly property real bodyLineWidth: 1.5
    readonly property real cableWidth: 2
    // The line drawn for a door when only the total says some door is open, and its inset
    // from the door's outer edge, to clear the body's outline.
    readonly property real doorEdgeWidth: 2
    readonly property real doorEdgeInset: 1
    readonly property real lightWidth: 1.5

    // ---------- the car, in units, nose up ----------

    readonly property real boxWidth: plan.boxWidth
    readonly property real boxHeight: plan.boxHeight
    readonly property real frontAxle: plan.frontAxle
    readonly property real rearAxle: plan.rearAxle
    // How far the wheels' outer faces are inside the box.
    readonly property real wheelInset: plan.wheelInset
    // A door spans from just inside the body's side to just short of its window. Open, it
    // swings doorSwing degrees around its front edge. doorReach is how far its rear corner
    // then sticks out of the box: for a Model 3's front door, 116 × sin 30° − 16 = 42.
    readonly property real doorOuter: plan.flank + 1.75
    readonly property real doorWidth: plan.belt - 2 - doorOuter
    // An open door is drawn 19 wide whatever its real width, widened towards the cabin, so
    // it reads as a panel. Its outer edge, and so doorReach, is unchanged.
    readonly property real leafExtra: 19 - doorWidth
    readonly property real doorSwing: 30
    readonly property real swingSin: Math.sin(doorSwing * Math.PI / 180)
    readonly property real swingCos: Math.cos(doorSwing * Math.PI / 180)
    readonly property real swingTan: Math.tan(doorSwing * Math.PI / 180)
    readonly property real doorReach: (plan.frontDoor[1] - plan.frontDoor[0]) * swingSin - doorOuter
    // How far a reading above or below a wheel may extend towards the middle of the car:
    // the distance from the rear axle to where an open rear door ends. For a Model 3, 371.5
    // − 270 − 9 × sin 30° − 70 × cos 30° = 36.4. A wing door ends where its plan says.
    readonly property real readingReach: falcon ? rearAxle - falcon.back
                                                : rearAxle - plan.rearDoor[0] - doorWidth * swingSin
                                                  - (plan.rearDoor[1] - plan.rearDoor[0]) * swingCos

    // The [start, end] across the car of a part spanning x0 to x1 on the left side, or its
    // mirror image on the right, snapped to whole pixels. The right side is mirrored after
    // snapping: snapping each side separately can leave one part a pixel wider.
    function side(onLeft, x0, x1) {
        return onLeft ? [snap(x0), snap(x1)] : [boxWidth - snap(x1), boxWidth - snap(x0)]
    }

    // SVG paths for a rounded rectangle (x across the car, y along it) and a circle.
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
    // A rounded rectangle snapped to whole pixels and inset by half its line width, so its
    // straight edges are sharp.
    function box(x0, y0, x1, y1, radius, line) {
        const d = inUnits(line / 2)
        return roundedRect(snap(x0) + d, snap(y0) + d, snap(x1) - d, snap(y1) - d, radius)
    }

    // The body's side and the side windows' outer edge are long straight lines. Each is
    // nudged by under half a pixel so the line fills whole pixels.
    readonly property real flank: crisp(plan.flank, bodyLineWidth)
    readonly property real belt: snap(plan.belt)
    readonly property string bodyPath: plan.bodyPath(flank)
    readonly property string frunkPath: plan.frunkPath
    readonly property string trunkPath: plan.trunkPath
    // The windshield and roof glass, and the rear window (part of the trunk lid on a
    // hatchback).
    readonly property string glassPath: plan.glassPath
    readonly property string rearGlassPath: plan.rearGlassPath
    // The beams across the roof, between the panes.
    readonly property string beamPath: plan.beamPath
    // For a translucent body: bodyPath with holes for the cabin glass and beams, the side
    // windows and the doorways of open doors.
    readonly property string openBodyPath: [
        bodyPath, plan.canopyPath, plan.quarterPath,
        windowPath(true, plan.frontWindow, 0), windowPath(true, plan.rearWindow, 0),
        windowPath(false, plan.frontWindow, 0), windowPath(false, plan.rearWindow, 0),
        doorwaysPath
    ].join(" ")
    // The doorways of all open doors as one path.
    readonly property string doorwaysPath: [leftFrontDoor, leftRearDoor, rightFrontDoor, rightRearDoor]
        .filter(door => door.open === true && !door.wing).map(door => doorwayPath(door.onLeft, door.from, door.to)).join(" ")

    // The x of the body's left edge at y.
    function flankAt(y) { return Models.edgeAt(plan.bodyLeft(flank), y) }
    // x on the left side, or mirrored onto the right.
    function reflect(onLeft, x) { return onLeft ? x : boxWidth - x }

    // The visible part of a tire: its outer face and two ends, outside the body's edge.
    function tirePath(onLeft, axle) {
        const face = snap(wheelInset)
        const front = snap(axle - plan.tire)
        const rear = snap(axle + plan.tire)
        const r = 4.5
        return ["M", reflect(onLeft, flankAt(front)), front, "H", reflect(onLeft, face + r),
                "Q", reflect(onLeft, face), front, reflect(onLeft, face), front + r, "V", rear - r,
                "Q", reflect(onLeft, face), rear, reflect(onLeft, face + r), rear,
                "H", reflect(onLeft, flankAt(rear)), "Z"].join(" ")
    }
    // A side window from the plan, shifted so its outer edge sits on the snapped belt,
    // inset by half its line width. With line 0 it is the window's full area.
    function windowPath(onLeft, points, line) {
        return Models.placed(points, belt + inUnits(line / 2) - plan.belt, onLeft ? undefined : boxWidth)
    }
    // The leaf of an open door w wide and l long, in the door's own coordinates (origin at
    // its front left corner). It is widened towards the cabin by leafExtra. The extra
    // width's corner at the hinge is cut along the flank, or a rear door's leaf would touch
    // the window behind its hinge.
    function leafPath(onLeft, w, l) {
        const d = inUnits(lineWidth / 2)
        const r = 4
        const cut = leafExtra / swingTan
        const x0 = snap(onLeft ? 0 : -leafExtra) + d
        const x1 = snap(onLeft ? w + leafExtra : w) - d
        const y0 = d
        const y1 = snap(l) - d
        return onLeft
            ? ["M", x0 + r, y0, "H", x1 - leafExtra, "L", x1, y0 + cut,
               "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
               "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
               "V", y0 + r, "A", r, r, 0, 0, 1, x0 + r, y0, "Z"].join(" ")
            : ["M", x0 + leafExtra, y0, "H", x1 - r, "A", r, r, 0, 0, 1, x1, y0 + r,
               "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
               "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
               "V", y0 + cut, "Z"].join(" ")
    }
    // A line along a door's outer edge, inside the door. Its round ends stop short of the
    // door's ends so that two doors' lines don't meet across the seam.
    function doorEdgePath(onLeft, w, l) {
        const half = inUnits(doorEdgeWidth / 2)
        const x = inUnits(doorEdgeInset) + half
        return ["M", onLeft ? x : w - x, 3 + half, "V", l - 3 - half].join(" ")
    }
    // The opening an open door leaves in the flank: the closed door's area, short of the
    // seams at both ends and doorwayGap pixels short of the window. It starts behind the
    // leaf's slanted front edge.
    readonly property real doorwayGap: 2
    function doorwayPath(onLeft, from, to) {
        const left = snap(doorOuter)
        const right = Math.max(left, belt - inUnits(doorwayGap))
        const front = from + 2 + (right - left) * swingTan
        return box(reflect(onLeft, onLeft ? left : right), Math.min(front, to - 2), reflect(onLeft, onLeft ? right : left), to - 2, 2, 0)
    }
    // A mirror's outline starts and ends on the flank and isn't closed, so its stroke
    // doesn't cross the body's outline.
    function mirrorPath(onLeft, w) {
        return Models.mirrorPath(plan.mirror, snap(doorOuter) - flank - inUnits(bodyLineWidth / 2), w, onLeft)
    }
    // Each light is a lens with a line of light in it.
    readonly property string headlightPath: plan.headlightPath
    readonly property string headlightLine: plan.headlightLine
    readonly property string taillightPath: plan.taillightPath
    readonly property string taillightLine: plan.taillightLine
    // The seams between doors, from the flank to the glass. A wing door's seams continue
    // across the roof.
    readonly property string seamPath: [plan.frontDoor[0], (plan.frontDoor[1] + plan.rearDoor[0]) / 2,
                                        plan.rearDoor[1]].map((y, i) => {
        const at = crisp(y, lineWidth)
        const to = falcon && i > 0 ? falcon.seam : belt
        return ["M", flank, at, "H", to, "M", boxWidth - flank, at, "H", boxWidth - to].join(" ")
    }).join(" ")
    // The charge port, left rear. It has a minimum size on screen, and moves back when that
    // would touch the rear wheel.
    readonly property real portRadius: Math.max(5.5, inUnits(Kirigami.Units.smallSpacing * 0.75))
    readonly property real portX: plan.port[0]
    readonly property real portY: Math.max(plan.port[1], rearAxle + plan.tire + inUnits(1) + portRadius)
    readonly property string portPath: circle(portX, portY, portRadius)
    // The cable, from the port out to the side.
    readonly property string cablePath: ["M", portX - 6, portY, "C", portX - 14, portY + 1,
                                         portX - 20, portY + 10, portX - 22, portY + 28].join(" ")

    // Glyphs on a 20 × 20 grid: a padlock, an open padlock, and a camera lens for Sentry.
    readonly property string padlockBody: "M 6 9 H 14 A 2 2 0 0 1 16 11 V 16 A 2 2 0 0 1 14 18 H 6 A 2 2 0 0 1 4 16 V 11 A 2 2 0 0 1 6 9 Z M 9 13 A 1 1 0 0 1 11 13 V 14 A 1 1 0 0 1 9 14 Z"
    readonly property string lockPath: "M 6 9 V 6 A 4 4 0 0 1 14 6 V 9 H 12 V 6 A 2 2 0 0 0 8 6 V 9 Z " + padlockBody
    readonly property string unlockPath: "M 6 9 V 4 A 4 4 0 0 1 14 4 V 6 H 12 V 4 A 2 2 0 0 0 8 4 V 9 Z " + padlockBody
    readonly property string sentryPath: "M 2 10 A 8 8 0 1 0 18 10 A 8 8 0 1 0 2 10 Z M 4 10 A 6 6 0 1 0 16 10 A 6 6 0 1 0 4 10 Z M 7 10 A 3 3 0 1 0 13 10 A 3 3 0 1 0 7 10 Z"

    // ---------- scale and orientation ----------

    // The item's size in whole pixels.
    readonly property int wholeWidth: Math.floor(width)
    readonly property int wholeHeight: Math.floor(height)
    // Margin for strokes, which extend half outside their shape, and for pixel snapping.
    readonly property real pad: 2
    // The space between a wheel and the reading beside it. lineGap is the smaller space for
    // a reading above or below its wheel, where the text's line height adds its own.
    readonly property real gap: Kirigami.Units.smallSpacing * 2
    readonly property real lineGap: Kirigami.Units.smallSpacing
    readonly property real readingWidth: Math.max(flReading.width, frReading.width,
                                                  rlReading.width, rrReading.width)
    readonly property real readingHeight: flReading.height

    // Pixels per unit with the nose up, and lying sideways. Both leave room for the
    // readings and an open front door, so the car doesn't resize when a door opens. They
    // depend only on the item's and the readings' sizes, so choosing between them can't
    // loop.
    readonly property real unitUp: Math.min((wholeHeight - 2 * pad) / boxHeight,
                                            (wholeWidth - 2 * pad) / (boxWidth + 2 * doorReach),
                                            (wholeWidth - 2 * (pad + readingWidth + gap))
                                            / (boxWidth - 2 * wheelInset))
    // The last term leaves room past the wheels for a reading pushed away from the doors
    // (see Reading).
    readonly property real unitSide: Math.min((wholeWidth - 2 * pad) / boxHeight,
                                              (wholeHeight - 2 * pad) / (boxWidth + 2 * doorReach),
                                              (wholeHeight - 2 * (readingHeight + lineGap))
                                              / (boxWidth - 2 * wheelInset),
                                              (wholeWidth / 2 - pad - readingWidth - lineGap)
                                              / (boxHeight / 2 - frontAxle - readingReach))
    readonly property bool sideways: unitSide > unitUp
    // The smallest height at which the car lies sideways in a wide item. Below it the car
    // is larger standing nose up. This solves (h − readings) / car width = (h − pad) / car
    // length for h.
    readonly property real sidewaysHeight: {
        const across = boxWidth - 2 * wheelInset
        return Math.floor((2 * (readingHeight + lineGap) * boxHeight - 2 * pad * across)
                          / (boxHeight - across)) + 1
    }
    // Rounded down so the car is a whole number of pixels wide, which keeps its two sides
    // symmetric on the pixel grid.
    readonly property real unit: Math.max(0, Math.floor((sideways ? unitSide : unitUp) * boxWidth) / boxWidth)
    readonly property size pathScale: Qt.size(unit, unit)
    function u(v) { return v * unit }
    // Converts pixels to units, for things with a fixed size on screen.
    function inUnits(px) { return unit > 0 ? px / unit : 0 }
    // snap() moves v to a whole pixel. crisp() moves it to where a line of the given width
    // must be centered to cover whole pixels.
    function snap(v) { return inUnits(Math.round(u(v))) }
    function crisp(v, line) { return inUnits(Math.round(u(v) - line / 2) + line / 2) }

    // A point on the car, in this item's pixels. Used to place what stays upright when the
    // car turns.
    function at(x, y) {
        return sideways ? Qt.point(Math.round(drawing.x - u(y)), Math.round(drawing.y + u(x)))
                        : Qt.point(Math.round(drawing.x + u(x)), Math.round(drawing.y + u(y)))
    }

    // A small icon's size, growing with a large car in even steps up to 32 px, and never
    // longer than the windshield.
    readonly property real glyphSize: Math.min(Math.floor(u(plan.windshieldLength)), Math.max(20, Math.min(32, 2 * Math.floor(u(15)))))

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
        if (recommendedPressure) lines.push(recommendedPressure)
        return lines.join("\n")
    }

    Texts { id: texts }
    Look { id: look }
    CarPalette {
        id: colors
        paint: root.paint
    }

    implicitWidth: 2 * (readingWidth + gap) + Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 7

    // ---------- parts ----------

    // One piece of the car: a path in units, filled, stroked or both.
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
        fillColor: low ? colors.lowColor : colors.tireColor
    }

    // Filled when open. If TeslaMate only reports the total, all four get an outline.
    component SideWindow: Part {
        property bool onLeft
        property var points
        property var open
        path: root.windowPath(onLeft, points, root.lineWidth)
        fillColor: colors.openFill(open, open === null ? colors.faintGlassColor : colors.glassColor)
        strokeColor: colors.openLine(open, colors.glassLine, colors.faintGlassColor)
    }

    // A door, hinged at its front edge. It swings out, filled, when TeslaMate says this
    // door is open. If only the total is known, all four get a line along their outer edge
    // instead: outlining every door would be busier than the known states.
    component Door: Shape {
        id: door
        property bool onLeft
        property real from
        property real to
        property var open
        // A wing door is drawn by Wing when open: it has no leaf and leaves no doorway.
        property bool wing: false
        readonly property var across: root.side(onLeft, root.doorOuter, root.doorOuter + root.doorWidth)
        property real swing: open === true && !wing ? root.doorSwing : 0
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
            // The total-only line never swings, even where a door was open before.
            angle: door.open === "some" ? 0 : door.onLeft ? door.swing : -door.swing
        }

        // A closed door isn't drawn: the body's seams show it.
        Part {
            readonly property real w: root.inUnits(door.width)
            readonly property real l: root.inUnits(door.height)
            path: door.open === true ? (door.wing ? "" : root.leafPath(door.onLeft, w, l))
                : door.open === "some" ? root.doorEdgePath(door.onLeft, w, l) : ""
            fillColor: colors.openFill(door.open, "transparent")
            strokeColor: colors.openLine(door.open, "transparent", "transparent")
            strokeWidth: door.open === "some" ? root.doorEdgeWidth : root.lineWidth
            capStyle: ShapePath.RoundCap
        }
    }

    // A Model X rear door: hinged along the middle of the roof, lifting in two leaves. From
    // above, an open one covers its half of the roof and its side window and reaches out
    // past the body's side. It shows the fold between its leaves and the glass in each.
    component Wing: Shape {
        id: wing
        property bool onLeft
        property var open
        // How far it has opened, 0 to 1.
        property real lift: open === true ? 1 : 0
        Behavior on lift {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        readonly property bool shown: root.falcon !== null && open === true
        // For Models.reached(): undefined on the left, the car's width on the right.
        readonly property var mirrorWidth: onLeft ? undefined : root.boxWidth
        width: root.u(root.boxWidth)
        height: root.u(root.boxHeight)
        visible: shown

        Part {
            path: wing.shown ? Models.reached(root.falcon.wing, root.flank, wing.lift, wing.mirrorWidth, true) : ""
            fillColor: colors.openColor
            strokeColor: colors.openEdge
        }
        Part {
            path: wing.shown ? root.falcon.glass.map(pane => Models.reached(pane, root.flank, 1, wing.mirrorWidth, true)).join(" ") : ""
            fillColor: Qt.rgba(colors.openEdge.r, colors.openEdge.g, colors.openEdge.b, 0.3)
            strokeColor: colors.openEdge
        }
        Part {
            path: wing.shown ? Models.reached(root.falcon.fold, root.flank, 1, wing.mirrorWidth, false) : ""
            strokeColor: colors.openEdge
            capStyle: ShapePath.FlatCap
        }
    }

    // A front door carries its mirror, which swings with it.
    component FrontDoor: Door {
        id: frontDoor
        from: root.plan.frontDoor[0]
        to: root.plan.frontDoor[1]

        Part {
            path: root.mirrorPath(frontDoor.onLeft, root.inUnits(frontDoor.width))
            fillColor: colors.mirrorColor
            strokeColor: colors.outlineColor
        }
    }

    // A filled glyph centered on a point of the car. It stays upright when the car turns.
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

    // A tire's pressure and unit. It stays upright: beside its wheel when the car is nose
    // up, above or below it when the car lies sideways.
    component Reading: Item {
        id: reading
        property var tire
        property bool onLeft
        property bool front
        // No unit means the pressure is unknown and value is a dash.
        readonly property bool known: tire.unit !== ""
        readonly property real axle: front ? root.frontAxle : root.rearAxle
        // The middle of the wheel's outer face.
        readonly property point wheel: root.at(onLeft ? root.wheelInset : root.boxWidth - root.wheelInset, axle)
        // Above or below its wheel, a reading is centered on it, unless that is too close
        // to where an open rear door ends. Then it moves towards the end of the car, by the
        // same amount front and rear.
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
        // Text widths are rarely whole pixels, so the unit's position is rounded.
        readonly property real unitX: Math.round(valueLabel.implicitWidth + Kirigami.Units.smallSpacing / 2)
        width: known ? unitX + Math.ceil(unitLabel.implicitWidth) : Math.ceil(valueLabel.implicitWidth)
        height: Math.ceil(valueLabel.implicitHeight)

        PlasmaComponents3.Label {
            id: valueLabel
            text: reading.tire.value
            color: reading.tire.warn ? colors.lowColor : colors.textColor
            opacity: reading.known ? 1 : look.faint
            font.weight: reading.tire.warn && reading.known ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
            // For screen readers: pressure and unit as one text.
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

    // The tooltip covers the whole item, including the readings and any open door.
    HoverHandler { id: hover }

    PlasmaComponents3.ToolTip {
        visible: hover.hovered
        text: root.summary()
    }

    // ---------- the car ----------

    PixelLayer {
        target: root

        // Drawn nose up and rotated as a whole. Bottom to top: tires, body, frunk and
        // trunk, door seams, cabin glass and beams, lights, side windows, doors and
        // mirrors, charge port and cable.
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

                // Black parts outside the body, such as fender flares.
                Part {
                    path: root.plan.trimPath
                    fillColor: colors.trimColor
                }

                // The body, shaded across the car. A gradient is in the Shape's own pixels,
                // whatever the path's scale, and needs a non-transparent fillColor to be
                // drawn at all.
                Part {
                    path: colors.painted ? root.bodyPath : root.openBodyPath
                    fillColor: colors.bodySide
                    fillGradient: LinearGradient {
                        x1: root.u(root.flank)
                        y1: 0
                        x2: root.u(root.boxWidth - root.flank)
                        y2: 0
                        GradientStop { position: 0; color: colors.bodyEdge }
                        GradientStop { position: 0.035; color: colors.bodyTurn }
                        GradientStop { position: 0.09; color: colors.bodyShoulder }
                        GradientStop { position: 0.22; color: colors.bodySide }
                        GradientStop { position: 0.36; color: colors.bodyHigh }
                        GradientStop { position: 0.5; color: colors.bodyCrown }
                        GradientStop { position: 0.64; color: colors.bodyHigh }
                        GradientStop { position: 0.78; color: colors.bodySide }
                        GradientStop { position: 0.91; color: colors.bodyShoulder }
                        GradientStop { position: 0.965; color: colors.bodyTurn }
                        GradientStop { position: 1; color: colors.bodyEdge }
                    }
                }
                // Shading along the car, over the paint, and the body's outline.
                LinearGradient {
                    id: endShading
                    x1: 0
                    y1: 0
                    x2: 0
                    y2: root.u(root.plan.length)
                    GradientStop { position: 0; color: colors.tipShade }
                    GradientStop { position: 0.035; color: colors.endShade }
                    GradientStop { position: 0.11; color: colors.noShade }
                    GradientStop { position: 0.86; color: colors.noShade }
                    GradientStop { position: 0.955; color: colors.endShade }
                    GradientStop { position: 1; color: colors.tipShade }
                }
                Part {
                    path: root.bodyPath
                    // Always filled (with a transparent gradient in theme colors). A fill
                    // that only appeared with paint would be drawn over the lights instead
                    // of under them.
                    fillColor: "black"
                    fillGradient: endShading
                    strokeColor: colors.outlineColor
                    strokeWidth: root.bodyLineWidth
                }
                // Hood and trunk lid: a soft highlight when closed, solid when open.
                LinearGradient {
                    id: hoodSheen
                    x1: 0
                    y1: root.u(root.plan.hoodSpan[0])
                    x2: 0
                    y2: root.u(root.plan.hoodSpan[1])
                    GradientStop { position: 0; color: colors.noSheen }
                    GradientStop { position: 0.4; color: colors.sheenColor }
                    GradientStop { position: 1; color: colors.noSheen }
                }
                LinearGradient {
                    id: trunkSheen
                    x1: 0
                    y1: root.u(root.plan.trunkSpan[0])
                    x2: 0
                    y2: root.u(root.plan.trunkSpan[1])
                    GradientStop { position: 0; color: colors.noSheen }
                    GradientStop { position: 0.55; color: colors.sheenColor }
                    GradientStop { position: 1; color: colors.noSheen }
                }
                Part {
                    path: root.frunkPath
                    fillColor: colors.openFill(root.frunkOpen, colors.painted ? "white" : "transparent")
                    fillGradient: colors.painted && root.frunkOpen !== true ? hoodSheen : null
                    strokeColor: colors.openLine(root.frunkOpen, colors.seamColor, colors.faintSeamColor)
                }
                Part {
                    path: root.trunkPath
                    fillColor: colors.openFill(root.trunkOpen, colors.painted ? "white" : "transparent")
                    fillGradient: colors.painted && root.trunkOpen !== true ? trunkSheen : null
                    strokeColor: colors.openLine(root.trunkOpen, colors.seamColor, colors.faintSeamColor)
                }
                // Creases in the hood, and the slats of a bed cover.
                Part {
                    path: root.plan.creasePath
                    strokeColor: colors.faintSeamColor
                    capStyle: ShapePath.RoundCap
                }
                Part {
                    path: root.plan.slatPath
                    strokeColor: root.trunkOpen === true ? colors.openEdge : colors.faintSeamColor
                    capStyle: ShapePath.FlatCap
                }
                Part {
                    path: root.seamPath
                    strokeColor: colors.seamColor
                    capStyle: ShapePath.FlatCap
                }
                // The flank behind an open door, dark like the cabin glass.
                Part {
                    path: root.doorwaysPath
                    fillColor: colors.glassColor
                }
                Part {
                    path: root.beamPath
                    fillColor: colors.beamColor
                }
                LinearGradient {
                    id: glassShade
                    x1: 0
                    y1: root.u(root.plan.glassSpan[0])
                    x2: 0
                    y2: root.u(root.plan.glassSpan[1])
                    GradientStop { position: 0; color: colors.glassFront }
                    GradientStop { position: 0.3; color: colors.glassColor }
                    GradientStop { position: 0.66; color: colors.glassColor }
                    GradientStop { position: 1; color: colors.glassRear }
                }
                Part {
                    path: root.glassPath
                    fillColor: colors.glassColor
                    fillGradient: glassShade
                    strokeColor: colors.glassLine
                }
                // A hatchback's rear window opens with the trunk lid.
                Part {
                    readonly property var open: root.plan.hatch ? root.trunkOpen : false
                    path: root.rearGlassPath
                    fillColor: colors.openFill(open, colors.glassColor)
                    fillGradient: open === true ? null : glassShade
                    strokeColor: colors.openLine(open, colors.glassLine, colors.glassLine)
                }
                Part {
                    path: root.headlightPath
                    fillColor: colors.lensColor
                    strokeColor: colors.lensLine
                }
                Part {
                    path: root.headlightLine
                    strokeColor: colors.headlightColor
                    strokeWidth: root.lightWidth
                    capStyle: ShapePath.RoundCap
                }
                Part {
                    path: root.taillightPath
                    fillColor: colors.tailLensColor
                }
                Part {
                    path: root.taillightLine
                    strokeColor: colors.taillightColor
                    capStyle: ShapePath.RoundCap
                }

                // The fixed side glass.
                Part {
                    path: root.plan.quarterPath
                    fillColor: colors.glassColor
                    strokeColor: colors.glassLine
                }
                SideWindow { onLeft: true; points: root.plan.frontWindow; open: root.windowState(root.leftSeat, "front") }
                SideWindow { onLeft: true; points: root.plan.rearWindow; open: root.windowState(root.leftSeat, "rear") }
                SideWindow { onLeft: false; points: root.plan.frontWindow; open: root.windowState(root.rightSeat, "front") }
                SideWindow { onLeft: false; points: root.plan.rearWindow; open: root.windowState(root.rightSeat, "rear") }
            }

            FrontDoor { id: leftFrontDoor; onLeft: true; open: root.doorState(root.leftSeat, "front") }
            Door { id: leftRearDoor; onLeft: true; from: root.plan.rearDoor[0]; to: root.plan.rearDoor[1]; open: root.doorState(root.leftSeat, "rear"); wing: root.falcon !== null }
            FrontDoor { id: rightFrontDoor; onLeft: false; open: root.doorState(root.rightSeat, "front") }
            Door { id: rightRearDoor; onLeft: false; from: root.plan.rearDoor[0]; to: root.plan.rearDoor[1]; open: root.doorState(root.rightSeat, "rear"); wing: root.falcon !== null }
            Wing { onLeft: true; open: leftRearDoor.open }
            Wing { onLeft: false; open: rightRearDoor.open }

            // The charge port and cable.
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
                    strokeColor: root.pluggedIn ? colors.pluggedColor : "transparent"
                    strokeWidth: root.cableWidth
                    capStyle: ShapePath.RoundCap
                }
            }
        }

        // Sentry on the windshield, the lock on the roof.
        Glyph {
            visible: root.sentry
            centerX: root.boxWidth / 2
            centerY: root.plan.sentryY
            path: root.sentryPath
            color: colors.sentryColor
        }
        Glyph {
            visible: root.locked !== null
            centerX: root.boxWidth / 2
            centerY: root.plan.lockY
            path: root.locked ? root.lockPath : root.unlockPath
            color: root.locked ? colors.lockedColor : colors.unlockedColor
        }
    }

    // ---------- tire readings ----------

    Reading { id: flReading; tire: root.fl; onLeft: true; front: true }
    Reading { id: frReading; tire: root.fr; onLeft: false; front: true }
    Reading { id: rlReading; tire: root.rl; onLeft: true; front: false }
    Reading { id: rrReading; tire: root.rr; onLeft: false; front: false }
}
