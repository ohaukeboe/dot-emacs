# BlueZ pairing agent for the Quickshell rail (Rail.qml runs it).
# Each request BlueZ sends is one JSON line on stdout:
#   {"id": 3, "kind": "confirm", "device": "/org/bluez/hci0/dev_..",
#    "name": "Pixel", "code": "123456"}
# kind is "confirm", "authorize", "pin" or "passkey" (answer needed),
# "display" (show the code; no answer) or "cancel" (drop the open request).
# Answers come back on stdin as "<id> <value>": "yes" for confirm and
# authorize, the PIN or passkey otherwise; "<id>" alone rejects.
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

PATH = "/org/mango/bt_agent"
REJECTED = "org.bluez.Error.Rejected"

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
pending = {}
next_id = 0


def emit(kind, device, code=""):
    global next_id
    next_id += 1
    try:
        props = dbus.Interface(bus.get_object("org.bluez", device),
                               "org.freedesktop.DBus.Properties")
        name = str(props.Get("org.bluez.Device1", "Alias"))
    except dbus.DBusException:
        name = str(device)
    print(json.dumps({"id": next_id, "kind": kind, "device": str(device),
                      "name": name, "code": code}), flush=True)
    return next_id


class Rejected(dbus.DBusException):
    _dbus_error_name = REJECTED


class Agent(dbus.service.Object):
    def ask(self, kind, device, code, ok, err, convert):
        for done in pending.values():
            done(None)
        pending.clear()

        def done(value):
            if value is None:
                err(Rejected("Rejected"))
                return
            try:
                ok(*convert(value))
            except ValueError:
                err(Rejected("Bad answer"))
        pending[emit(kind, device, code)] = done

    @dbus.service.method("org.bluez.Agent1", in_signature="",
                         out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="o",
                         out_signature="s", async_callbacks=("ok", "err"))
    def RequestPinCode(self, device, ok, err):
        self.ask("pin", device, "", ok, err, lambda v: (v,))

    @dbus.service.method("org.bluez.Agent1", in_signature="o",
                         out_signature="u", async_callbacks=("ok", "err"))
    def RequestPasskey(self, device, ok, err):
        self.ask("passkey", device, "", ok, err,
                 lambda v: (dbus.UInt32(int(v)),))

    @dbus.service.method("org.bluez.Agent1", in_signature="os",
                         out_signature="")
    def DisplayPinCode(self, device, pincode):
        emit("display", device, str(pincode))

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq",
                         out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit("display", device, "%06d" % passkey)

    @dbus.service.method("org.bluez.Agent1", in_signature="ou",
                         out_signature="", async_callbacks=("ok", "err"))
    def RequestConfirmation(self, device, passkey, ok, err):
        self.ask("confirm", device, "%06d" % passkey, ok, err, self.yes)

    @dbus.service.method("org.bluez.Agent1", in_signature="o",
                         out_signature="", async_callbacks=("ok", "err"))
    def RequestAuthorization(self, device, ok, err):
        self.ask("authorize", device, "", ok, err, self.yes)

    @dbus.service.method("org.bluez.Agent1", in_signature="os",
                         out_signature="", async_callbacks=("ok", "err"))
    def AuthorizeService(self, device, uuid, ok, err):
        self.ask("authorize", device, "", ok, err, self.yes)

    @dbus.service.method("org.bluez.Agent1", in_signature="",
                         out_signature="")
    def Cancel(self):
        pending.clear()
        print(json.dumps({"kind": "cancel"}), flush=True)

    @staticmethod
    def yes(value):
        if value != "yes":
            raise ValueError(value)
        return ()


def answer(source, condition):
    line = sys.stdin.readline()
    if not line:
        loop.quit()
        return False
    rid, _, value = line.rstrip("\n").partition(" ")
    done = pending.pop(int(rid), None) if rid.isdigit() else None
    if done:
        done(value or None)
    return True


def register(owner):
    # Also runs when bluetoothd restarts, which drops every agent.
    if not owner:
        return
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"),
                             "org.bluez.AgentManager1")
    try:
        manager.RegisterAgent(PATH, "KeyboardDisplay")
    except dbus.DBusException as e:
        if e.get_dbus_name() != "org.bluez.Error.AlreadyExists":
            raise
    manager.RequestDefaultAgent(PATH)


Agent(bus, PATH)
loop = GLib.MainLoop()
bus.watch_name_owner("org.bluez", register)
GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, answer)
loop.run()
