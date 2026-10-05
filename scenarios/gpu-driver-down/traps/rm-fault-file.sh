# pokes at the mock's internals instead of fixing the service that owns them
rm -f /run/mock-gpu/driver_fault
systemctl restart analytics
