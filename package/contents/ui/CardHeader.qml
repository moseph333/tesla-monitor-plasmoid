import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// The card's header: the car's name (a link to TeslaMate if its address is set), what the
// car is doing, where and since when, and the refresh button.
RowLayout {
    // main.qml's root item, which has the car's state, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    spacing: Kirigami.Units.largeSpacing

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        PlasmaExtras.Heading {
            id: nameHeading
            Layout.fillWidth: true
            level: 3
            font.weight: Font.DemiBold
            text: widget.carName
            textFormat: Text.PlainText
            elide: Text.ElideRight
            // Underlined like a link when hovered or focused, if it is one.
            font.underline: widget.teslamateUrl !== "" && (nameHover.hovered || nameLink.activeFocus)

            // The link. It covers only the text, not the heading's full width, and is what
            // Tab and screen readers reach, so the heading keeps its own role when there is
            // no link. In right-to-left layouts the text is at the right edge, and the link
            // follows it.
            Item {
                id: nameLink
                x: nameHeading.effectiveHorizontalAlignment === Text.AlignRight ? nameHeading.width - width : 0
                width: Math.min(nameHeading.contentWidth, nameHeading.width)
                height: nameHeading.height
                activeFocusOnTab: widget.teslamateUrl !== ""

                Keys.onPressed: (event) => {
                    if (!widget.isActivationKey(event.key)) return
                    widget.openTeslaMate()
                    event.accepted = true
                }

                Accessible.role: Accessible.Link
                Accessible.name: nameHeading.text
                Accessible.description: i18n("Open TeslaMate")
                Accessible.ignored: widget.teslamateUrl === ""
                Accessible.onPressAction: widget.openTeslaMate()

                HoverHandler {
                    id: nameHover
                    enabled: widget.teslamateUrl !== ""
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: widget.teslamateUrl !== ""
                    onTapped: widget.openTeslaMate()
                }
                PlasmaComponents3.ToolTip {
                    visible: nameHover.hovered
                    text: i18n("Open TeslaMate")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // The state's dot in a halo of its own color. The halo is the layout item, so
            // it stays within the line.
            Rectangle {
                implicitWidth: stateDot.width + 2 * Math.round(Kirigami.Units.smallSpacing * 0.75)
                implicitHeight: implicitWidth
                radius: width / 2
                color: look.tint(stateDot.color, stateDot.color.a * 0.25)

                Rectangle {
                    id: stateDot
                    anchors.centerIn: parent
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    color: look.stateColor(widget.carState)
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.features: { "tnum": 1 }
                opacity: look.secondary
                textFormat: Text.PlainText
                text: {
                    widget.now // re-evaluate on tick
                    const parts = [widget.stateLabel()]
                    if (widget.car.geofence) parts.push(widget.car.geofence)
                    const since = widget.car.since ? Logic.formatSince(widget.car.since, widget.now) : ""
                    if (since && widget.carState !== "driving") parts.push(since)
                    return parts.join(" · ")
                }
            }
        }
    }

    // The spinner for a manual refresh. It sits beside the button, not over it, and keeps
    // its space when hidden so the header doesn't shift.
    Item {
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        PlasmaComponents3.BusyIndicator {
            anchors.fill: parent
            visible: widget.userRefreshing
            running: visible
        }
    }

    // Always visible and enabled, so it never drops keyboard focus mid-refresh.
    PlasmaComponents3.ToolButton {
        id: refreshButton
        icon.name: "view-refresh"
        display: QQC2.AbstractButton.IconOnly
        text: i18n("Refresh")
        onClicked: widget.refresh(true)

        PlasmaComponents3.ToolTip {
            visible: refreshButton.hovered
            text: refreshButton.text
        }
    }
}
