import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

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

        // Footer. An update's status moves to a line of its own when one line can't
        // hold everything, as on a narrow card or during a download. The version and
        // the status are as wide as their texts, to the next whole pixel, and give way
        // when even that is too much, so a long version elides rather than widen the
        // card.
        GridLayout {
            id: footer

            // Moving the status to the other line resizes the car, which mustn't
            // happen each time a poll fails or the hour gains a digit. So the warning
            // icon keeps its place while it's hidden, and the time counts as wide as
            // it gets.
            readonly property bool oneLine: softwareVersion.implicitWidth + updateStatus.implicitWidth
                                            + freshness.implicitWidth
                                            + Math.max(0, widestUpdated.advanceWidth - updated.implicitWidth)
                                            + 2 * columnSpacing <= width

            Layout.fillWidth: true
            columns: 3
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing * 1.5

            // An hour of two digits, on a 12 hour clock and on a 24 hour clock, and
            // today, so no weekday comes with it.
            TextMetrics {
                id: widestUpdated
                font: updated.font
                text: {
                    const late = new Date()
                    late.setHours(22, 0, 0, 0)
                    return widget.updatedText(late)
                }
            }

            PlasmaComponents3.Label {
                id: softwareVersion
                Layout.row: 0
                Layout.column: 0
                Layout.fillWidth: true
                Layout.maximumWidth: Math.ceil(implicitWidth)
                visible: text !== ""
                elide: Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.features: { "tnum": 1 }
                opacity: look.secondary
                text: widget.car.version ? i18n("Software %1", widget.car.version) : ""
                textFormat: Text.PlainText
            }

            // The update's status on a tint of the highlight color, which fills from
            // the start as the download or the installation goes on. The tint is a
            // little taller than the line of text, without making the footer taller.
            Item {
                id: updateStatus

                property real progress: widget.softwareUpdate.percent !== null
                    ? Math.max(0, Math.min(1, widget.softwareUpdate.percent / 100)) : 0
                Behavior on progress {
                    NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                }

                Layout.row: footer.oneLine ? 0 : 1
                Layout.column: footer.oneLine ? 1 : 0
                Layout.columnSpan: footer.oneLine ? 1 : 3
                Layout.fillWidth: true
                Layout.maximumWidth: Math.ceil(implicitWidth)
                visible: widget.softwareUpdate.phase !== ""
                implicitWidth: updateLabel.implicitWidth + 2 * updateLabel.anchors.leftMargin
                implicitHeight: updateLabel.implicitHeight

                Rectangle {
                    id: pill
                    anchors.fill: parent
                    anchors.topMargin: -Kirigami.Units.smallSpacing / 2
                    anchors.bottomMargin: -Kirigami.Units.smallSpacing / 2
                    radius: height / 2
                    color: look.tint(Kirigami.Theme.highlightColor, 0.2)

                    Item {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * updateStatus.progress
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: pill.width
                            radius: pill.radius
                            color: look.tint(Kirigami.Theme.highlightColor, 0.3)
                        }
                    }
                }

                PlasmaComponents3.Label {
                    id: updateLabel
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                    text: widget.updateText()
                }
            }

            RowLayout {
                id: freshness
                Layout.row: 0
                Layout.column: 2
                Layout.fillWidth: true
                // The filler before the icon would count a spacing as width the row
                // needs, so the time keeps its distance from the icon by a margin.
                spacing: 0

                Item { Layout.fillWidth: true }

                // The icon is a pixel taller than the line of text. It hangs over the
                // line rather than stretch it, so the rows above don't move each time
                // a poll fails or works again.
                Item {
                    implicitWidth: warning.width
                    implicitHeight: updated.implicitHeight

                    Kirigami.Icon {
                        id: warning
                        y: Math.round((parent.height - height) / 2)
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        visible: widget.errorText.length > 0
                        source: "data-warning"
                        HoverHandler { id: warnHover }
                        PlasmaComponents3.ToolTip {
                            visible: warnHover.hovered
                            text: i18n("Showing last good data.\n%1", widget.errorText)
                        }
                    }
                }

                // At full strength while the data is old, since this time then says how
                // old. It stays in the text color: the icon before it carries the
                // warning's color, which some themes make too pale to read as text.
                PlasmaComponents3.Label {
                    id: updated
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                    opacity: widget.stale ? 1 : look.secondary
                    color: Kirigami.Theme.textColor
                    text: {
                        widget.now // re-evaluate on tick: at midnight the time gets its weekday
                        return widget.lastUpdated ? widget.updatedText(widget.lastUpdated) : ""
                    }
                }
            }
        }
    }
}
