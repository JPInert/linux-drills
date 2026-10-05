# turn the detector off and on (and clear the old Xid worry): the card is still capped
systemctl restart analytics
systemctl reset-failed
sleep 6
