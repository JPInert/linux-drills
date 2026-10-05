# fixes the cause but the running daemon never re-reads its config and still holds the deleted file
sed -i 's/^TRACE=.*/TRACE=off/' /etc/cam-poller.conf
