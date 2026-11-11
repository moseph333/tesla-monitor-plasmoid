import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// The battery level as a 270° arc that is open at the bottom, around the level in figures,
// the range and, while the battery is cold, how much of it is usable. A notch on the inside
// of the track marks the charge limit, and the track from the level up to it is a shade
// stronger than beyond it.
// While the car charges, a bolt sits above the level and that stretch takes the ring's
// color and pulses.
// value and marker are 0..1, and a marker below 0 means the limit isn't known.
// Its arcs lie over each other, so whoever fades the ring with opacity says so with faded,
// and the arcs then fade as one picture.
Item {
    id: ring

    property real value: 0
    property real marker: -1
    property color color: Kirigami.Theme.highlightColor
    // The level without its unit, such as "72" and "%", or "—" and "" while it's unknown.
    property string numberText
    property string unitText
    // The range, such as "361 km", and a caveat about it, such as "65% usable".
    property string subText
    property string noteText
    // Whether the car is charging, and whether anything may keep moving: only while the popup
    // is open, so a card on the desktop draws nothing while idle.
    property bool charging: false
    property bool animated: false
    // Whether the ring, or an item above it, is drawn with an opacity below 1.
    property bool faded: false

    implicitWidth: Kirigami.Units.gridUnit * 8
    implicitHeight: implicitWidth

    // Every measure is a share of the diameter, so the ring looks the same at any size.
    readonly property real diameter: Math.min(width, height)
    readonly property real thickness: Math.max(4, Math.round(diameter * 0.06))
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    // One pixel in from the edge, so the smoothed outer edge stays inside the item as well.
    readonly property real radius: (diameter - thickness) / 2 - 1

    // The card writes a value it doesn't have as a dash, and draws it faint and in regular
    // weight. Without a level there is no arc, and nothing to measure the way to the limit
    // from. A ring that was given no text has no level either.
    readonly property string dash: "—"
    readonly property bool levelKnown: numberText !== "" && numberText !== dash

    readonly property real clamped: Math.max(0, Math.min(1, value))
    property real shown: clamped
    Behavior on shown {
        NumberAnimation { duration: Kirigami.Units.longDuration * 2; easing.type: Easing.OutCubic }
    }

    // The color as drawn, which eases from one state's to the next's: normal, low, charging.
    property color shownColor: color
    Behavior on shownColor {
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    // The stretch to the limit is what the car will still fill. While it charges, that is
    // what is happening, and the stretch takes the ring's color at part of its strength.
    // Otherwise it is a shade over the track, so that color always means charge that is
    // there. The shade is a light one: a long stretch on a nearly empty battery mustn't
    // weigh more than the level, and without color to tell them apart it mustn't pass for it.
    property color targetColor: charging ? look.tint(color, 0.4) : look.tint(Kirigami.Theme.textColor, 0.1)
    Behavior on targetColor {
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    readonly property real limit: Math.min(1, marker)
    readonly property real limitRadians: (135 + 270 * limit) * Math.PI / 180
    // What is left to the limit, along the middle of the stroke. The arc to the limit is
    // left out while that is less than a stroke width: half of it lies under the level's
    // round end, and the rest would be a speck beside it.
    readonly property real toLimit: (limit - shown) * 270 * Math.PI / 180 * radius
    readonly property bool targetShown: marker >= 0 && levelKnown && toLimit >= thickness

    Look { id: look }

    // The arcs. The level's round end lies over the start of the stretch to the limit, and
    // opacity fades each arc by itself, which would show that end as a knob of another tone.
    // So while the ring is faded, the arcs share a layer and fade as one picture. Only then,
    // because Qt 6.6 doesn't redraw such a layer when nothing but a color changes. The
    // software renderer draws nothing for a Shape inside a layer at scale factors above 1,
    // so it goes without the layer and shows the knob.
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
                    startAngle: 135; sweepAngle: 270
                }
            }

            // The charge limit: a notch that starts on the track's inner edge and points to
            // the middle, where neither arc reaches it, so it also shows while the level is
            // above the limit. Away from the track it would read as a dash after the level's
            // "%", which it lies beside at the usual limit of 80%. A limit of 100% is the end
            // of the track, which marks it well enough: a notch there would sit right after
            // the note.
            ShapePath {
                id: tick
                readonly property bool drawn: ring.marker >= 0 && ring.limit < 1
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

        // From the level to the limit: what the car is charging, or would charge if it were
        // plugged in. It starts under the level's round end, which it follows while the
        // level sweeps, and is cut off flat at the limit, or ends round with the track at
        // 100%. It is an item of its own, so that the pulse can move its opacity, which
        // needs no new geometry for each frame as a color would.
        Shape {
            id: targetArc
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: ring.targetShown

            // A slow breath while the car charges, and a short way back to full strength
            // once it ends. The breath's pace is its own, as a spinner's is, and doesn't
            // follow the animation speed, which is for transitions. Plasma never lets
            // longDuration go below 1, so that is its value while animations are turned off.
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
                capStyle: ring.limit < 1 ? ShapePath.FlatCap : ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: 135 + 270 * ring.shown; sweepAngle: 270 * (ring.limit - ring.shown)
                }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // A stroke without length draws nothing, round ends or not, so an empty battery
            // keeps a sliver of it, which shows as a dot where the track starts.
            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.levelKnown ? ring.shownColor : "transparent"
                strokeWidth: ring.thickness
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.cx; centerY: ring.cy
                    radiusX: ring.radius; radiusY: ring.radius
                    startAngle: 135; sweepAngle: 270 * Math.max(ring.shown, 0.001)
                }
            }
        }
    }

    // The middle. Each part sits at a height of its own, measured from the center, so the
    // level stays where it is when the bolt comes and goes above it, or the note below the
    // range. Text is placed on whole pixels, which keeps it sharp.

    // The panel icon's bolt: boltPath in CarBattery.qml, moved to the origin, 44 by 90.
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

    // The level and its unit, centered as one. "72%" keeps this order in a right-to-left
    // layout.
    Row {
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(ring.cy + ring.diameter * 0.02 - number.baselineOffset)

        PlasmaComponents3.Label {
            id: number
            // A whole number of pixels, so the unit after it starts on one.
            width: Math.ceil(implicitWidth)
            text: ring.numberText
            font.pixelSize: Math.round(ring.diameter * 0.235)
            font.weight: ring.levelKnown ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
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

    // The range. Without a level, its dash under the level's dash would look like an equals
    // sign, so the one dash then stands for both.
    PlasmaComponents3.Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(ring.cy + ring.diameter * 0.15 - baselineOffset)
        visible: text !== "" && (ring.levelKnown || text !== ring.dash)
        text: ring.subText
        font.pixelSize: Math.round(ring.diameter * 0.10)
        font.features: { "tnum": 1 }
        opacity: text !== ring.dash ? 1 : look.faint
    }

    // A caveat about the numbers above it, such as how much of a cold battery is usable,
    // so it takes the neutral color.
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
