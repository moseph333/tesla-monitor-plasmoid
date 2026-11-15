import QtQuick
import org.kde.plasma.plasmoid
import org.kde.notification

import "logic.js" as Logic
import "notifyhub.js" as Hub

// The widget's desktop notifications. Logic.notifyStep() says which events a poll calls
// for and notifyhub.js lets copies of the widget share them; this words them and sends them.
QtObject {
    id: notifier

    // main.qml's root item, which knows the car.
    required property PlasmoidItem widget
    readonly property var cfg: widget.cfg
    readonly property Texts texts: Texts {}

    // What Logic.notifyStep() knew after the last poll, or null to start over.
    property var state: null
    // The car, as notifyhub.js knows it, so copies of the widget that show it share claims.
    readonly property string source: {
        const broker = Logic.parseBrokerHost(cfg.brokerHost)
        return broker.host.toLowerCase() + ":" + (broker.port || cfg.brokerPort) + "|" + widget.prefix
    }

    // Another broker or car starts over, so what it already shows isn't news.
    function startOver() {
        state = null
    }

    // After every poll that got data. The state moves on even while a notification is
    // turned off, so turning it on later doesn't bring up something old.
    function process() {
        const r = Logic.notifyStep(state, widget.car, Date.now(), {
            leftOpenMs: cfg.leftOpenMinutes * 60 * 1000,
            // Three polls at the slower rate and at least 15 minutes, so only something like
            // a suspend or a broker outage counts as a gap that starts over.
            staleMs: Math.max(15 * 60 * 1000, 3 * 1000 * Math.max(cfg.refreshSeconds, cfg.idleRefreshSeconds)),
            okGeofences: widget.okGeofences
        })
        state = r.state
        // What's fine again ends its claim for every copy, so the next time is news.
        for (const key of r.released) Hub.release(source + "|" + key)
        for (const e of r.events) send(e)
    }

    function send(e) {
        const wanted = {
            chargeComplete: cfg.notifyChargeComplete,
            chargeStopped: cfg.notifyChargeStopped,
            chargerNoPower: cfg.notifyChargeStopped,
            leftOpen: cfg.notifyLeftOpen,
            unlocked: cfg.notifyUnlocked,
            tires: cfg.notifyTires,
            update: cfg.notifyUpdates
        }
        if (!wanted[e.type]) return
        // Every copy of the widget that shows this car sees the event on its own poll, and
        // only the first to claim each part of it sends that part.
        const at = Date.now()
        const mine = Logic.claimEvent(e, (key, windowMs) => Hub.claim(source + "|" + key, at, windowMs))
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

    // The title, body and icon for an event from Logic.notifyStep(). A body says less when
    // a value is missing, rather than leave a gap.
    function content(e, name) {
        const minutes = cfg.leftOpenMinutes
        switch (e.type) {
        case "chargeComplete":
            return {
                title: i18n("%1 finished charging", name),
                body: e.level === null ? i18n("Charging is complete.")
                    : widget.rangeKm !== null ? i18n("Charged to %1% (%2).", e.level, widget.fmtDistance(widget.rangeKm))
                    : i18n("Charged to %1%.", e.level),
                icon: Logic.batteryIcon(e.level, false)
            }
        case "chargeStopped":
            return {
                title: i18n("%1 stopped charging", name),
                body: e.level === null ? i18n("Charging stopped before the limit.")
                    : e.limit !== null ? i18n("Stopped at %1%, below the %2% limit.", e.level, e.limit)
                    : i18n("Stopped at %1%.", e.level),
                icon: Logic.batteryIcon(e.level, false)
            }
        case "chargerNoPower":
            return {
                title: i18n("%1 can't charge", name),
                body: e.level === null ? i18n("The charger stopped supplying power.")
                    : i18n("The charger stopped supplying power at %1%.", e.level),
                icon: "dialog-warning"
            }
        case "leftOpen":
            return {
                title: i18n("%1 needs attention", name),
                body: texts.attentionLines(e.items)
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
                body: i18n("Check %1.", e.items.map(pos => {
                    const pressure = widget.tire(pos).text
                    return pressure === "—" ? texts.tireName(pos)
                        : i18nc("tire position (pressure)", "%1 (%2)", texts.tireName(pos), pressure)
                }).join(", ")),
                icon: "dialog-warning"
            }
        case "update":
            return {
                title: i18n("Software update for %1", name),
                body: e.version ? i18n("Version %1 is available.", e.version) : i18n("An update is available."),
                icon: "system-software-update"
            }
        }
        return null
    }

    // One object per notification, which deletes itself once Plasma is done with it.
    // Plasma drops a notification without a componentName, so it goes out as Plasma's own.
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
