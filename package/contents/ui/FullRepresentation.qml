import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// The widget as a card, in the popup or on the desktop: a header, the battery and what the
// car is doing, anything that needs attention, a strip of readings, the car from above and
// a footer. Without data it shows what is missing instead.
Item {
    id: card

    // main.qml's root item, which knows the car.
    required property PlasmoidItem widget

    // What every row but the car's needs, with the margins around them. Wrapped lines
    // make the rows taller at a narrow width, and this follows them.
    readonly property real rowsHeight: content.implicitHeight - carStatus.implicitHeight
                                       + 2 * content.anchors.margins

    // A message that needs attention makes the popup taller rather than the car
    // smaller: one line of it, with its frame and the space before it, is three grid
    // units high. This goes by whether there is one and not by its height, which
    // Kirigami animates. Rows that need more than usual, as they do in a larger font
    // or with a second line in the footer, make the popup taller by as much, so the
    // car keeps its width: 10.5 grid units is nearly what the rows of a parked card
    // leave it in the 27, and still leaves a card with a two-line message at its 30.
    readonly property real usualHeight: Kirigami.Units.gridUnit * (widget.attentionLines.length > 0 ? 30 : 27)
    readonly property real popupHeight: Math.max(usualHeight, rowsHeight + Kirigami.Units.gridUnit * 10.5)

    Layout.preferredWidth: Kirigami.Units.gridUnit * 21
    // A card on the desktop keeps one height to ask for: Plasma lets a widget there
    // grow to a larger one, and never shrinks it again.
    Layout.preferredHeight: widget.onDesktop ? Kirigami.Units.gridUnit * 27 : popupHeight
    Layout.minimumWidth: Kirigami.Units.gridUnit * 17
    // Room for every row at its own height and the car drawing at its smallest, so an
    // attention message or extra charging lines can't push the drawing and the footer
    // out of the bottom of the card.
    // In the popup this stops at the height the popup has without tall rows. For a
    // moment after a message appears its text is wrapped a word to a line, and Plasma
    // makes a popup as tall as its minimum but never shorter again when that falls.
    Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 20,
                                   widget.onDesktop
                                   ? rowsHeight + carStatus.Layout.minimumHeight
                                   : Math.min(rowsHeight + carStatus.Layout.minimumHeight, usualHeight))

    // Created here rather than on the root item, which lives in the panel: the card's
    // colors have to be the popup's.
    Look { id: look }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: !widget.configured
        iconName: "battery-080"
        text: i18n("Connect to TeslaMate")
        explanation: widget.cfg.brokerHost.trim() !== ""
            ? i18n("The broker host isn't valid. Check it in the widget settings.")
            : i18n("Add your MQTT broker in the widget settings.")
        helpfulAction: QQC2.Action {
            text: i18n("Configure…")
            icon.name: "configure"
            onTriggered: Plasmoid.internalAction("configure").trigger()
        }
    }

    // Retry swaps the old error for the spinner until the new result arrives, so the
    // click visibly does something.
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: widget.configured && !widget.hasData && widget.errorText.length > 0 && !widget.userRefreshing
        iconName: "network-disconnect"
        text: i18n("No data yet")
        explanation: widget.errorText
        helpfulAction: QQC2.Action {
            text: i18n("Retry")
            icon.name: "view-refresh"
            onTriggered: widget.refresh(true)
        }
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        visible: widget.configured && !widget.hasData && (widget.errorText.length === 0 || widget.userRefreshing)
        running: visible
    }

    ColumnLayout {
        id: content

        // The rows that show the car fade while the data is old, as the panel icon
        // does, so a level from hours ago doesn't pass for now. They fade less than
        // the icon: old values are all there is to read then, and their text has to
        // stay readable. The header and the footer stay as they are: they say what is
        // shown and how old it is.
        property real dataOpacity: widget.stale ? 0.7 : 1
        Behavior on dataOpacity {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
        }

        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        visible: widget.hasData
        spacing: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

        CardHeader {
            Layout.fillWidth: true
            widget: card.widget
            look: look
        }

        // Battery, and what the car is doing. The ring is open at the bottom: its arc
        // ends well above the edge of its square, which leaves more than a row's
        // distance already, so the next row follows the square without another.
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: -content.spacing
            spacing: Kirigami.Units.largeSpacing * 2
            opacity: content.dataOpacity

            BatteryRing {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                value: widget.level >= 0 ? widget.level / 100 : 0
                marker: widget.limit >= 0 ? widget.limit / 100 : -1
                color: look.batteryColor(widget.level, widget.charging)
                numberText: widget.level >= 0 ? String(widget.level) : "—"
                unitText: widget.level >= 0 ? "%" : ""
                charging: widget.charging
                // Old data can't say that the car is charging right now.
                animated: widget.popupOpen && !widget.stale
                faded: content.dataOpacity < 1
                subText: widget.fmtDistance(widget.rangeKm)
                noteText: widget.usableCold !== null ? i18n("%1% usable", widget.usableCold) : ""
            }

            CardDetails {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                // The lines have no such space below them and keep the distance
                // themselves, above as well, which leaves them level with the middle
                // of the ring. The row grows when they need more than the ring.
                Layout.topMargin: content.spacing
                Layout.bottomMargin: content.spacing
                widget: card.widget
                look: look
            }
        }

        // Anything that needs attention. Past two lines it shows the first and a count,
        // so the car drawing keeps its room; hovering, and the panel tooltip, list all.
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: widget.attentionLines.length > 0
            type: Kirigami.MessageType.Warning
            text: widget.attentionLines.length <= 2 ? widget.attentionLines.join("\n")
                : widget.attentionLines[0] + "\n"
                  + i18np("And %1 more", "And %1 more", widget.attentionLines.length - 1)

            HoverHandler { id: attentionHover }
            PlasmaComponents3.ToolTip {
                visible: attentionHover.hovered && widget.attentionLines.length > 2
                text: widget.attentionLines.join("\n")
            }
        }

        StatsStrip {
            Layout.fillWidth: true
            opacity: content.dataOpacity
            widget: card.widget
            look: look
        }

        // Tires, doors, windows, openings, lock and Sentry on one car
        CarStatus {
            id: carStatus
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Enough for the car to lie on its side, as it does in the popup, however
            // large the font of its readings is. In less it stands nose up and is a
            // third of the size.
            Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 5, carStatus.sidewaysHeight)
            opacity: content.dataOpacity
            car: widget.car
            model: widget.carModel
            rightHandDrive: widget.cfg.rightHandDrive
            paint: widget.paint
            fl: widget.tire("fl")
            fr: widget.tire("fr")
            rl: widget.tire("rl")
            rr: widget.tire("rr")
        }

        CardFooter {
            Layout.fillWidth: true
            widget: card.widget
            look: look
        }
    }
}
