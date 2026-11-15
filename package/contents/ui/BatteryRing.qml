import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// The battery level as a 270° arc, open at the bottom, around the level, the range and (for
// a cold battery) how much is usable. A gap in the track marks the charge limit. While
// charging, a bolt sits above the level and the stretch up to the limit pulses.
//
// value and marker are 0..1. A marker below 0 means the limit is unknown. Set faded when
// the ring is drawn with opacity below 1, so the overlapping arcs fade as one picture.
Item {
    id: ring

    property real value: 0
    property real marker: -1
    property color color: Kirigami.Theme.highlightColor
    // The level and its unit, e.g. "72" and "%", or "—" and "" when unknown.
    property string numberText
    property string unitText
    // The range, e.g. "361 km", and a note under it, e.g. "65% usable".
    property string subText
    property string noteText
    // animated allows continuous animation. The card sets it only while the popup is open.
    property bool charging: false
    property bool animated: false
    // Whether the ring, or an item above it, has an opacity below 1.
    property bool faded: false

    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: implicitWidth

    // All measures are fractions of the diameter, so the ring scales.
    readonly property real diameter: Math.min(width, height)
    readonly property real thickness: Math.max(4, Math.round(diameter * 0.06))
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // One pixel inside the edge, so the antialiased outer edge isn't clipped.
    readonly property real radius: (diameter - thickness) / 2 - 1
    // The arc runs from lower left over the top to lower right. Degrees are PathAngleArc's:
    // clockwise from three o'clock.
    readonly property real arcStart: 135
    readonly property real arcSweep: 270
    // The angle on the arc for a share of the battery, 0 to 1.
    function angleOf(share) { return arcStart + arcSweep * share }

    // An unknown level is given as a dash (or no text). There is then no arc and no stretch
    // to the limit.
    readonly property string dash: "—"
    readonly property bool levelKnown: numberText !== "" && numberText !== dash

    // Nearly empty and not charging: the number turns red, like the ring. Same threshold as
    // Look.batteryColor()'s red.
    readonly property bool critical: !charging && levelKnown && value < 0.1

    readonly property real clamped: Math.max(0, Math.min(1, value))
    property real shown: clamped
    Behavior on shown {
        NumberAnimation { duration: Kirigami.Units.longDuration * 2; easing.type: Easing.OutCubic }
    }

    // The color as drawn, animated between states.
    property color shownColor: color
    Behavior on shownColor {
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    // The stretch from the level to the limit. While charging it takes the ring's color at
    // reduced strength. Otherwise it is a light shade of the track, so that color always
    // means charge that is there.
    property color targetColor: charging ? look.tint(color, 0.4) : look.tint(Kirigami.Theme.textColor, 0.1)
    Behavior on targetColor {
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    readonly property real limit: Math.min(1, marker)
    readonly property real limitRadians: angleOf(limit) * Math.PI / 180
    // The length of that stretch along the middle of the stroke. Next to a notch, a stretch
    // shorter than the stroke width is hidden: it would be a speck beside the level's round
    // end. Before a gap it is always drawn.
    readonly property real toLimit: (limit - shown) * arcSweep * Math.PI / 180 * radius
    readonly property bool targetShown: marker >= 0 && levelKnown && (split ? toLimit > 0 : toLimit >= thickness)

    // The charge limit is a real gap in the track (not a patch in the background color, so
    // a translucent popup shows through). capDegrees is how far a round cap extends past
    // its arc's end. Where a gap doesn't work, the track stays whole and a notch marks the
    // limit: with the level above the limit, or a limit from 95%, which would leave only a
    // dot of track after it. The 0.001 margin keeps a level exactly at the limit, which
    // arrives as a sum of fractions, from counting as above it.
    readonly property real capDegrees: thickness / 2 / radius * 180 / Math.PI
    readonly property real gapDegrees: Math.max(2, thickness * 0.35) / radius * 180 / Math.PI
    readonly property bool split: marker >= 0 && limit < 0.95 && shown < limit + 0.001

    Look { id: look }

    // The arcs. They overlap, so fading each by opacity would show the level's round end
    // over the stretch behind it. While faded they share a layer and fade together. Only
    // then, because Qt 6.6 doesn't redraw such a layer when only a color changes. The
    // software renderer draws nothing for a Shape in a layer at scale factors above 1, so
    // it goes without.
    Item {
        anchors.fill: parent
        layer.enabled: ring.faded && GraphicsInfo.api !== GraphicsInfo.Software

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: look.hairline
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: ring.arcStart; sweepAngle: ring.arcSweep * (ring.split ? ring.limit : 1)
                }
            }

            // The track beyond the gap. Transparent while the track is whole: some
            // renderers draw a zero-length stroke as a dot.
            ShapePath {
                id: beyond
                readonly property real start: ring.angleOf(ring.limit) + 2 * ring.capDegrees + ring.gapDegrees

                fillColor: "transparent"
                strokeColor: ring.split ? look.hairline : "transparent"
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: ring.split ? beyond.start : ring.angleOf(1) - 1; sweepAngle: ring.angleOf(1) - startAngle
                }
            }

            // The limit as a notch, where the track has no gap: it points inwards from the
            // track's inner edge, where no arc covers it. A limit of 100% gets none: the
            // end of the track marks it.
            ShapePath {
                id: tick
                readonly property bool drawn: ring.marker >= 0 && ring.limit < 1 && !ring.split
                readonly property real outer: ring.radius - ring.thickness * 0.5
                readonly property real inner: outer - ring.thickness * 0.9

                fillColor: "transparent"
                strokeColor: drawn ? look.tint(Kirigami.Theme.textColor, look.secondary) : "transparent"
                strokeWidth: Math.max(1.5, ring.thickness * 0.25)
                capStyle: ShapePath.FlatCap
                startX: ring.cx + outer * Math.cos(ring.limitRadians)
                startY: ring.cy + outer * Math.sin(ring.limitRadians)
                PathLine {
                    x: ring.cx + tick.inner * Math.cos(ring.limitRadians)
                    y: ring.cy + tick.inner * Math.sin(ring.limitRadians)
                }
            }
        }

        // The stretch from the level to the limit. It ends like the track under it: round
        // at the gap or at 100%, flat at a notch. It is a separate item so the pulse can
        // animate opacity, which needs no new geometry per frame.
        Shape {
            id: targetArc
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: ring.targetShown

            // Pulses slowly while charging. The pace is fixed, like a spinner's, and
            // doesn't follow the animation speed setting. longDuration is 1 (Plasma's
            // minimum) when animations are turned off.
            states: State {
                name: "pulsing"
                when: ring.animated && ring.charging && targetArc.visible && Kirigami.Units.longDuration > 1
            }
            transitions: [
                Transition {
                    to: "pulsing"
                    SequentialAnimation {
                        loops: Animation.Infinite
                        NumberAnimation {
                            target: targetArc; property: "opacity"; to: 0.45
                            duration: Kirigami.Units.humanMoment; easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            target: targetArc; property: "opacity"; to: 1
                            duration: Kirigami.Units.humanMoment; easing.type: Easing.InOutSine
                        }
                    }
                },
                Transition {
                    from: "pulsing"
                    NumberAnimation {
                        target: targetArc; property: "opacity"; to: 1
                        duration: Kirigami.Units.longDuration
                    }
                }
            ]

            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.targetColor
                strokeWidth: ring.thickness
                capStyle: ring.split || ring.limit >= 1 ? ShapePath.RoundCap : ShapePath.FlatCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: ring.angleOf(ring.shown); sweepAngle: ring.arcSweep * (ring.limit - ring.shown)
                }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The level. A zero-length stroke draws nothing, so an empty battery keeps a
            // sliver, which shows as a dot.
            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.levelKnown ? ring.shownColor : "transparent"
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: ring.arcStart; sweepAngle: ring.arcSweep * Math.max(ring.shown, 0.001)
                }
            }
        }
    }

    // The center. Each part has a fixed offset from the center, so the level doesn't move
    // when the bolt or the note appears. Text is placed on whole pixels.

    // The panel icon's bolt (boltPath in CarBattery.qml) moved to the origin: 44 × 90.
    Shape {
        id: bolt
        readonly property real unit: Math.round(ring.diameter * 0.13) / 90

        visible: ring.charging
        x: ring.cx - width / 2
        y: Math.round(ring.cy - ring.diameter * 0.19) - height
        width: 44 * unit
        height: 90 * unit
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: ring.shownColor
            strokeColor: "transparent"
            scale: Qt.size(bolt.unit, bolt.unit)
            PathSvg { path: "M 36 0 L 0 52 L 18 52 L 8 90 L 44 36 L 26 36 Z" }
        }
    }

    // The level and its unit, centered together. "72%" keeps this order in right-to-left
    // layouts.
    Row {
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(ring.cy + ring.diameter * 0.02 - number.baselineOffset)

        PlasmaComponents3.Label {
            id: number
            // Rounded up so the unit starts on a whole pixel.
            width: Math.ceil(implicitWidth)
            text: ring.numberText
            font.pixelSize: Math.round(ring.diameter * 0.235)
            font.weight: ring.levelKnown ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
            color: ring.critical ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            opacity: ring.levelKnown ? 1 : look.faint
            Accessible.name: ring.numberText + ring.unitText
        }

        PlasmaComponents3.Label {
            y: Math.round(number.baselineOffset - baselineOffset)
            text: ring.unitText
            font.pixelSize: Math.round(ring.diameter * 0.105)
            opacity: look.secondary
            Accessible.ignored: true
        }
    }

    // The range. Hidden when both it and the level are unknown: two dashes would look like
    // an equals sign.
    PlasmaComponents3.Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(ring.cy + ring.diameter * 0.15 - baselineOffset)
        visible: text !== "" && (ring.levelKnown || text !== ring.dash)
        text: ring.subText
        font.pixelSize: Math.round(ring.diameter * 0.10)
        font.features: { "tnum": 1 }
        opacity: text !== ring.dash ? 1 : look.faint
    }

    // A note about the numbers above, such as how much of a cold battery is usable.
    PlasmaComponents3.Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(ring.cy + ring.diameter * 0.245 - baselineOffset)
        visible: text !== ""
        text: ring.noteText
        font.pixelSize: Math.round(ring.diameter * 0.075)
        font.features: { "tnum": 1 }
        color: Kirigami.Theme.neutralTextColor
    }
}
