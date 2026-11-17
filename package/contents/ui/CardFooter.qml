import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// The card's footer: the software version, an update's status, and when the data arrived.
// The update's status moves to its own line when one line can't hold everything. The
// version and status are as wide as their text and shrink when there isn't room, so a long
// version elides instead of widening the card.
GridLayout {
    id: footer

    // main.qml's root item, which has the car's state, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    // Whether everything fits on one line. Switching lines resizes the car, so this must
    // not flip when a poll fails or the hour gains a digit: the warning icon keeps its
    // space when hidden, and the time is measured at its widest.
    readonly property bool oneLine: softwareVersion.implicitWidth + updateStatus.implicitWidth
                                    + freshness.implicitWidth
                                    + Math.max(0, widestUpdated.advanceWidth - updated.implicitWidth)
                                    + 2 * columnSpacing <= width

    columns: 3
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: Kirigami.Units.smallSpacing * 1.5

    // The update's status.
    function updateText() {
        const v = widget.car.update_version || ""
        switch (widget.softwareUpdate.phase) {
        case "downloading": {
            const p = widget.softwareUpdate.percent !== null ? Math.round(widget.softwareUpdate.percent) : 0
            return v ? i18n("Downloading %1 · %2%", v, p) : i18n("Downloading update · %1%", p)
        }
        case "installing": {
            const left = Logic.formatHours((Logic.installMinutesLeft(widget.car) ?? 0) / 60)
            if (left) return v ? i18n("Installing %1 · about %2 left", v, left) : i18n("Installing update · about %1 left", left)
            return v ? i18n("Installing %1", v) : i18n("Installing update")
        }
        default: {
            const at = Logic.updateSchedule(widget.car, widget.now)
            if (at !== null) return v ? i18n("%1 installs at %2", v, widget.clock(at)) : i18n("Update installs at %1", widget.clock(at))
            return v ? i18n("%1 available", v) : i18n("Update available")
        }
        }
    }

    // "Updated 2:30 PM", or "Updated Mon 2:30 PM" if that wasn't today.
    function updatedText(time) {
        return i18n("Updated %1", widget.clock(time.getTime()))
    }

    // The widest the time gets: a two-digit hour, today (so no weekday).
    TextMetrics {
        id: widestUpdated
        font: updated.font
        text: {
            const late = new Date()
            late.setHours(22, 0, 0, 0)
            return footer.updatedText(late)
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

    // The update's status on a tinted pill, which fills from the start as the download or
    // installation progresses. The pill is slightly taller than the text without making the
    // footer taller.
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
            text: footer.updateText()
        }
    }

    RowLayout {
        id: freshness
        Layout.row: 0
        Layout.column: 2
        Layout.fillWidth: true
        // The filler would count a spacing as required width, so the time uses a margin
        // instead.
        spacing: 0

        Item { Layout.fillWidth: true }

        // The icon is a pixel taller than the text. It overhangs rather than stretch the
        // line, so the rows above don't move when a poll fails or recovers.
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

        // Full opacity while stale, since this is what says how old the data is. It stays
        // in the text color: the warning color is too pale to read in some themes.
        PlasmaComponents3.Label {
            id: updated
            Layout.leftMargin: Kirigami.Units.smallSpacing
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            opacity: widget.stale ? 1 : look.secondary
            color: Kirigami.Theme.textColor
            text: {
                widget.now // re-evaluate on tick: at midnight the time gets its weekday
                return widget.lastUpdated ? footer.updatedText(widget.lastUpdated) : ""
            }
        }
    }
}
