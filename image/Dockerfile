FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Deliberately NOT installed: net-tools (ifconfig/netstat/route), parted, htop, man pages.
# Modern servers often lack them; reaching for them is a habit worth breaking.
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus \
        iproute2 iputils-ping traceroute bind9-dnsutils netcat-openbsd curl tcpdump iptables \
        lsof psmisc procps strace fdisk rfkill \
        openssh-server openssh-client sudo logrotate cron \
        python3 vim-tiny nano less ca-certificates dnsmasq \
        isc-dhcp-client iputils-arping \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl disable dnsmasq cron 2>/dev/null; \
    systemctl mask getty.target console-getty.service getty@.service \
        systemd-remount-fs.service systemd-update-utmp.service apt-daily.timer apt-daily-upgrade.timer \
        dpkg-db-backup.timer e2scrub_all.timer fstrim.timer 2>/dev/null; \
    useradd -m -s /bin/bash -u 1000 tech \
    && passwd -l tech >/dev/null \
    && mkdir -p /var/lib/drill /home/tech/.ssh \
    && chmod 0755 /var/lib/drill \
    && touch /var/lib/drill/typos /var/lib/drill/cmdlog && chmod 0666 /var/lib/drill/typos /var/lib/drill/cmdlog \
    && chown -R tech:tech /home/tech/.ssh && chmod 700 /home/tech/.ssh

COPY rootfs/ /
RUN mkdir -p /usr/local/cuda/lib64 \
    && : > /usr/local/cuda/lib64/libcudart.so.12.2.140 \
    && ln -s libcudart.so.12.2.140 /usr/local/cuda/lib64/libcudart.so.12 \
    && mkdir -p /opt/analytics/models && : > /opt/analytics/models/person-vehicle.engine
# COPY keeps the host's umask-002 modes (dirs 0775, files 0664): real boxes are 0755/0644
# (sshd StrictModes and "why is /etc group-writable" both care)
RUN chmod 0755 / /usr /etc /opt \
    && find /etc /opt /usr/local -xdev ! -type l -perm -g+w ! -perm -2000 -exec chmod g-w,o-w {} + \
    && chmod 0440 /etc/sudoers.d/tech \
    && chmod 0755 /usr/local/bin/* /usr/local/lib/drill/run-check /usr/local/lib/drill/drill-report /usr/local/lib/drill/analytics-install \
        /usr/local/lib/drill/docker-install /usr/local/lib/drill/lived-in \
        /usr/local/lib/mock-docker/docker.py /usr/local/lib/mock-docker/dockerd.py \
    && for u in tech root; do \
         h=$(getent passwd $u | cut -d: -f6); \
         printf '. /usr/local/lib/drill/shellrc\n' > $h/.bashrc; \
         printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > $h/.bash_profile; \
         rm -f $h/.profile; \
       done \
    && chown tech:tech /home/tech/.bashrc /home/tech/.bash_profile

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
