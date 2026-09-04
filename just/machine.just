# Provisioning a machine. The full procedure, including the firmware
# preparation these recipes cannot do for you, is in docs/new-machine.md.

# Scaffold and register a new machine (run on the machine itself)
new-machine hostname device:
    ./scripts/new-machine.sh {{ hostname }} {{ device }}

# ERASES THE DISK. Partition, install and seed a scaffolded machine
install-machine hostname mode="format":
    ./scripts/install-machine.sh {{ hostname }} {{ mode }}

# Post-boot setup on a freshly installed machine (safe to re-run)
finish-install hostname="":
    ./scripts/finish-install.sh {{ hostname }}
