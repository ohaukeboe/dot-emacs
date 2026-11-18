# org.kde.JobViewServer for Mango. KDE programs (KDE Connect transfers, KIO
# copies) report job progress to this name once org.kde.kuiserver says it
# is there; with no owner KIO opens its own progress window instead. Each
# job becomes one desktop notification, updated in place, with the percentage
# in the "value" hint (Notifications.qml draws it). Dismissing the card hides
# the job; its Cancel action cancels it.
# The program reports the end of the job itself, so the card just closes.
# shortcut: a client that dies without terminate() leaves its card up until
# dismissed; watch the sender's bus name if that shows up.
import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GioUnix, GLib

NOTIFICATIONS = "org.freedesktop.Notifications"

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
views = {}  # notification id -> JobView
count = 0


def notifications(method, signature, *args):
    return bus.call_blocking(NOTIFICATIONS, "/org/freedesktop/Notifications",
                             NOTIFICATIONS, method, signature, args)


class JobView(dbus.service.Object):
    def __init__(self, path, entry, cancellable, props):
        super().__init__(bus, path)
        try:
            app = GioUnix.DesktopAppInfo.new(entry + ".desktop")
        except TypeError:  # no such desktop file
            app = None
        self.entry = entry
        self.app = app.get_name() if app else entry
        icon = app.get_icon() if app else None
        self.icon = icon.to_string() if icon else ""
        self.actions = ["cancel", "Cancel"] if cancellable else []
        self.props = {}
        self.id = 0
        self.sent = None
        self.dismissed = False
        self.update(props)

    @dbus.service.method("org.kde.JobViewV3", in_signature="a{sv}")
    def update(self, props):
        self.props.update(props)
        if self.dismissed:
            return
        p = self.props
        body = "\n".join(str(p[key]) for key in (
            "descriptionValue1", "descriptionValue2", "infoMessage")
            if p.get(key))
        content = (str(p.get("title") or self.app), body,
                   min(int(p.get("percent", 0)), 100))
        if content == self.sent:
            return
        self.sent = content
        views.pop(self.id, None)
        self.id = int(notifications(
            "Notify", "susssasa{sv}i", self.app, self.id, self.icon,
            content[0], body, self.actions,
            {"value": dbus.Int32(content[2]), "desktop-entry": self.entry},
            0))
        views[self.id] = self

    @dbus.service.method("org.kde.JobViewV3", in_signature="usa{sv}")
    def terminate(self, code, message, hints):
        self.remove_from_connection()
        if not self.dismissed:
            self.dismissed = True
            views.pop(self.id, None)
            notifications("CloseNotification", "u", self.id)

    @dbus.service.signal("org.kde.JobViewV3")
    def cancelRequested(self):
        pass

    # Never sent, but the client connects to both.
    @dbus.service.signal("org.kde.JobViewV3")
    def suspendRequested(self):
        pass

    @dbus.service.signal("org.kde.JobViewV3")
    def resumeRequested(self):
        pass


class Server(dbus.service.Object):
    @dbus.service.method("org.kde.JobViewServerV2", in_signature="sia{sv}",
                         out_signature="o")
    def requestView(self, entry, capabilities, hints):
        global count
        count += 1
        path = "/org/mango/JobView/%d" % count
        JobView(path, str(entry), capabilities & 1, hints)
        return dbus.ObjectPath(path)

    # KIO asks this of org.kde.kuiserver before it uses the views at all;
    # no answer, or True, and it opens its own window as well.
    @dbus.service.method("org.kde.kuiserver", out_signature="b")
    def requiresJobTracker(self):
        return False


def closed(nid, reason):
    view = views.pop(int(nid), None)
    if view:
        view.dismissed = True


def invoked(nid, action):
    view = views.get(int(nid))
    if view and action == "cancel":
        view.cancelRequested()


bus.add_signal_receiver(closed, "NotificationClosed", NOTIFICATIONS)
bus.add_signal_receiver(invoked, "ActionInvoked", NOTIFICATIONS)
server = Server(bus, "/JobViewServer")
names = [dbus.service.BusName(name, bus)
         for name in ("org.kde.JobViewServer", "org.kde.kuiserver")]
GLib.MainLoop().run()
