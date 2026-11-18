import QtQuick
import org.kde.plasma.plasmoid
import org.kde.notification

import "logic.js" as Logic
import "notifyhub.js" as Hub

// The widget's desktop notifications. Logic.notifyStep() decides which events a poll calls
// for, notifyhub.js lets copies of the widget share them, and this words and sends them.
QtObject {
    id: notifier

    // main.qml's root item, which has the car's state.
    required property PlasmoidItem widget
    readonly property var cfg: widget.cfg
    readonly property Texts texts: Texts {}

    // Logic.notifyStep()'s state after the last poll, or null to start over.
    property var state: null
    // Identifies the car to notifyhub.js, so copies showing the same car share claims.
    readonly property string carKey: Logic.carKey(widget.source, cfg)

    // For a new broker or car: what it already shows isn't news.
    function startOver() {
        state = null
    }

    // Call after every poll that got data. The state advances even for notifications that
    // are turned off, so turning one on later doesn't bring up something old.
    function process() {
        const step = Logic.notifyStep(state, widget.car, Date.now(), {
            leftOpenMs: cfg.leftOpenMinutes * 60 * 1000,
            // Three polls at the slower rate, at least 15 minutes: only a suspend or a
            // broker outage should count as a gap.
            staleMs: Math.max(15 * 60 * 1000, 3 * 1000 * Math.max(cfg.refreshSeconds, cfg.idleRefreshSeconds)),
            okGeofences: widget.okGeofences
        })
        state = step.state
        // What is fine again releases its claim for every copy.
        for (const key of step.released) Hub.release(carKey + "|" + key)
        for (const event of step.events) send(event)
    }

    function send(event) {
        const wanted = {
            chargeComplete: cfg.notifyChargeComplete,
            chargeStopped: cfg.notifyChargeStopped,
            chargerNoPower: cfg.notifyChargeStopped,
            leftOpen: cfg.notifyLeftOpen,
            unlocked: cfg.notifyUnlocked,
            tires: cfg.notifyTires,
            update: cfg.notifyUpdates
        }
        if (!wanted[event.type]) return
        // Every copy showing this car sees the event on its own poll. Only the first to
        // claim each part sends it.
        const at = Date.now()
        const mine = Logic.claimEvent(event, (key, windowMs) => Hub.claim(carKey + "|" + key, at, windowMs))
        if (!mine) return
        const words = content(mine, widget.carName)
        if (!words) return
        const note = notification.createObject(widget, {
            title: words.title,
            text: Logic.escapeMarkup(words.body),
            iconName: words.icon
        })
        if (note) note.sendEvent()
    }

    // The title, body and icon for an event. A body with a missing value says less rather
    // than leave a gap.
    function content(event, name) {
        const minutes = cfg.leftOpenMinutes
        switch (event.type) {
        case "chargeComplete":
            return {
                title: i18n("%1 finished charging", name),
                body: event.level === null ? i18n("Charging is complete.")
                    : widget.rangeKm !== null ? i18n("Charged to %1% (%2).", event.level, widget.fmtDistance(widget.rangeKm))
                    : i18n("Charged to %1%.", event.level),
                icon: Logic.batteryIcon(event.level, false)
            }
        case "chargeStopped":
            return {
                title: i18n("%1 stopped charging", name),
                body: event.level === null ? i18n("Charging stopped before the limit.")
                    : event.limit !== null ? i18n("Stopped at %1%, below the %2% limit.", event.level, event.limit)
                    : i18n("Stopped at %1%.", event.level),
                icon: Logic.batteryIcon(event.level, false)
            }
        case "chargerNoPower":
            return {
                title: i18n("%1 can't charge", name),
                body: event.level === null ? i18n("The charger stopped supplying power.")
                    : i18n("The charger stopped supplying power at %1%.", event.level),
                icon: "dialog-warning"
            }
        case "leftOpen":
            return {
                title: i18n("%1 needs attention", name),
                body: texts.attentionLines(event.items)
                    .concat(i18np("Like this for %1 minute.", "Like this for %1 minutes.", minutes)).join("\n"),
                icon: "dialog-warning"
            }
        case "unlocked":
            return {
                title: i18n("%1 is unlocked", name),
                body: i18np("Nobody has been inside for %1 minute.", "Nobody has been inside for %1 minutes.", minutes),
                icon: "object-unlocked"
            }
        case "tires":
            return {
                title: i18n("%1 has low tire pressure", name),
                body: i18n("Check %1.", event.items.map(pos => {
                    const pressure = widget.tire(pos).text
                    return pressure === "—" ? texts.tireName(pos)
                        : i18nc("tire position (pressure)", "%1 (%2)", texts.tireName(pos), pressure)
                }).join(", ")),
                icon: "dialog-warning"
            }
        case "update":
            return {
                title: i18n("Software update for %1", name),
                body: event.version ? i18n("Version %1 is available.", event.version) : i18n("An update is available."),
                icon: "system-software-update"
            }
        }
        return null
    }

    // One object per notification, deleted once Plasma is done with it. Plasma drops a
    // notification without a componentName, so it is sent as Plasma's own.
    readonly property Component notification: Component {
        Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
            urgency: Notification.NormalUrgency
            autoDelete: true
            defaultAction: NotificationAction {
                label: i18n("Show")
                onActivated: notifier.widget.expanded = true
            }
        }
    }
}
