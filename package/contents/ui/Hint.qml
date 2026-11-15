import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Small print under a setting, as wide as the fields.
QQC2.Label {
    Layout.preferredWidth: Kirigami.Units.gridUnit * 16
    wrapMode: Text.Wrap
    font: Kirigami.Theme.smallFont
    opacity: 0.7
}
