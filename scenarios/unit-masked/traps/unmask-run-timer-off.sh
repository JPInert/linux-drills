# catches up once, but nothing re-enables the 15-minute schedule
systemctl unmask feedrelay-sync.service
systemctl start feedrelay-sync.service
