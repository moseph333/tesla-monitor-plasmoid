import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The small print under a setting on the settings pages, as wide as the fields above it.
QQC2.Label {
    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
    wrapMode: Text.Wrap
    font: Kirigami.Theme.smallFont
    opacity: 0.7
}
