import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// The widget as a card, in the popup or on the desktop: header, battery and activity,
// anything needing attention, a strip of readings, the car from above, and a footer.
// Without data it shows a placeholder instead.
Item {
    id: card

    // main.qml's root item, which has the car's state.
    required property PlasmoidItem widget

    // The height of every row except the car's, plus margins. It grows when lines wrap.
    readonly property real rowsHeight: content.implicitHeight - carStatus.implicitHeight
                                       + 2 * content.anchors.margins

    // The popup is 27 grid units tall, or 30 with an attention message, so the message
    // doesn't shrink the car. This goes by whether there is a message, not by its height,
    // which Kirigami animates. Rows taller than usual (a larger font, a second footer line)
    // make the popup taller too: 10.5 grid units is about what a parked card leaves the
    // car.
    readonly property real usualHeight: Kirigami.Units.gridUnit * (widget.attentionLines.length > 0 ? 30 : 27)
    readonly property real popupHeight: Math.max(usualHeight, rowsHeight + Kirigami.Units.gridUnit * 10.5)

    Layout.preferredWidth: Kirigami.Units.gridUnit * 21
    // A desktop card always asks for the same height: Plasma lets a widget there grow, but
    // never shrinks it again.
    Layout.preferredHeight: widget.onDesktop ? Kirigami.Units.gridUnit * 27 : popupHeight
    Layout.minimumWidth: Kirigami.Units.gridUnit * 17
    // Room for every row and the car at its smallest, so tall rows can't push the car and
    // footer off the card. In the popup this is capped at the usual height: right after a
    // message appears its text is briefly wrapped one word per line, and Plasma grows a
    // popup to its minimum but never shrinks it back.
    Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 20,
                                   widget.onDesktop
                                   ? rowsHeight + carStatus.Layout.minimumHeight
                                   : Math.min(rowsHeight + carStatus.Layout.minimumHeight, usualHeight))

    // Created here, not on the root item: the root lives in the panel, and the card needs
    // the popup's colors.
    Look { id: look }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        visible: !widget.configured
        iconName: "battery-080"
        text: widget.source.kind === "fleet" ? i18n("Connect to Tesla") : i18n("Connect to TeslaMate")
        explanation: widget.source.kind === "fleet"
            ? i18n("Add your Tesla API access token and your car's VIN in the widget settings.")
            : widget.source.key === "tessie"
            ? i18n("Add your Tessie access token and your car's VIN in the widget settings.")
            : widget.source.key === "homeAssistant"
            ? i18n("Add your Home Assistant's address, an access token and the car in the widget settings.")
            : widget.source.key === "teslamateApi"
            ? i18n("Add the TeslaMate API's address in the widget settings.")
            : widget.cfg.brokerHost.trim() !== ""
            ? i18n("The broker host isn't valid. Check it in the widget settings.")
            : i18n("Add your MQTT broker in the widget settings.")
        helpfulAction: QQC2.Action {
            text: i18n("Configure…")
            icon.name: "configure"
            onTriggered: Plasmoid.internalAction("configure").trigger()
        }
    }

    // Hidden while a manual refresh runs, so Retry visibly does something.
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

        // The rows showing the car fade while the data is stale, less than the panel icon
        // does, so they stay readable. The header and footer don't fade: they say what is
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

        // Battery and activity. The ring's arc ends well above the bottom of its square,
        // which already leaves enough space before the next row.
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
                // Stale data can't say the car is charging right now.
                animated: widget.popupOpen && !widget.stale
                faded: content.dataOpacity < 1
                subText: widget.fmtDistance(widget.rangeKm)
                noteText: widget.usableCold !== null ? i18n("%1% usable", widget.usableCold) : ""
            }

            CardDetails {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                // The row's negative bottom margin removes the usual spacing, so the lines
                // add it back themselves, above and below, which centers them on the ring.
                Layout.topMargin: content.spacing
                Layout.bottomMargin: content.spacing
                widget: card.widget
                look: look
            }
        }

        // Anything needing attention. Beyond two lines it shows the first and a count, to
        // keep room for the car. Hovering, and the panel tooltip, list everything.
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

        // Tires, doors, windows, frunk, trunk, lock and Sentry on one drawing.
        CarStatus {
            id: carStatus
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Enough height for the car to lie sideways, whatever the readings' font size.
            // Standing nose up it would be a third of the size.
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
