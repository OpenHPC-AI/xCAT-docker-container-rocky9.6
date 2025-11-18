# ------------------------------------------------------------------------------
# Secure and hardened xCAT Dockerfile
# Compatible with Rocky Linux 9.3 (Minimal) and OCI security practices
# ------------------------------------------------------------------------------

FROM rockylinux:9.6

LABEL maintainer="The xCAT Project <https://xcat.org>"
LABEL org.opencontainers.image.title="xCAT HPC Management System"
LABEL org.opencontainers.image.description="Secure and containerized xCAT environment for HPC cluster management"
LABEL org.opencontainers.image.version="2.17.x"
LABEL org.opencontainers.image.licenses="GPL-2.0-or-later"

# ------------------------------------------------------------------------------
# Environment configuration
# ------------------------------------------------------------------------------
ENV container=docker
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV XCATROOT=/opt/xcat
ENV PATH="$XCATROOT/bin:$XCATROOT/sbin:$XCATROOT/share/xcat/tools:$PATH"
ENV MANPATH="$XCATROOT/share/man:$MANPATH"

ARG xcat_version=latest
ARG xcat_reporoot=https://xcat.org/files/xcat/repos/yum
ARG xcat_baseos=rh9

# --------------------------------------------------------------------------
# Bootstrap basic system utilities (for minimal image missing dnf/systemd)
# --------------------------------------------------------------------------
#RUN set -eux && \
#    microdnf install -y dnf && \
#    rm -rf /var/cache/dnf

# --------------------------------------------------------------------------
# Base system initialization (required dirs may be missing in minimal)
# --------------------------------------------------------------------------
RUN set -eux && \
    mkdir -p /lib/systemd/system/sysinit.target.wants /etc/systemd/system /lib/systemd/system/multi-user.target.wants && \
    for i in $(ls /lib/systemd/system/sysinit.target.wants || true); do \
        [ "$i" = "systemd-tmpfiles-setup.service" ] || rm -f "/lib/systemd/system/sysinit.target.wants/$i"; \
    done && \
    rm -f /lib/systemd/system/multi-user.target.wants/* || true && \
    rm -f /etc/systemd/system/*.wants/* || true && \
    rm -f /lib/systemd/system/local-fs.target.wants/* || true && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* || true && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* || true && \
    rm -f /lib/systemd/system/basic.target.wants/* || true && \
    rm -f /lib/systemd/system/anaconda.target.wants/* || true

# --------------------------------------------------------------------------
# Install required system utilities and dependencies for xCAT
# --------------------------------------------------------------------------
RUN set -eux && \
    # Enable EPEL first to get supervisor and other extras
    dnf -y install epel-release && \
    dnf -y update
RUN dnf -y install \
        systemd \
        util-linux \
        passwd \
        bash \
        iproute \
        iputils \
        net-tools \
        tar \
        sudo \
        vim-minimal \
        ncurses \
        shadow-utils \
        procps-ng \
        less \
        which \
        curl \
        hostname \
        ca-certificates \
        python3 \
        dbus \
        coreutils \
        findutils \
        glibc-langpack-en \
        policycoreutils \
        selinux-policy \
        selinux-policy-targeted \
        openssh-server \
        openssh-clients \
        rsyslog \
        man-db \
        chrony \
        dhcp-client \
        initscripts \
        createrepo_c \
        perl \
        perl-DBD-MySQL \
        mariadb \
        mariadb-server \
        dnsmasq && \
    # Install supervisor separately after EPEL repo is confirmed
    dnf -y install supervisor || (dnf clean all && dnf -y install supervisor) && \
    dnf -y install wget && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/*

RUN set -eux && \
    wget -q "${xcat_reporoot}/${xcat_version}/$([[ ${xcat_version} == "devel" ]] && echo 'core-snap' || echo 'xcat-core')/xcat-core.repo" -O /etc/yum.repos.d/xcat-core.repo && \
    wget -q "${xcat_reporoot}/${xcat_version}/xcat-dep/${xcat_baseos}/$(uname -m)/xcat-dep.repo" -O /etc/yum.repos.d/xcat-dep.repo

# ------------------------------------------------------------------------------
# Safe systemd cleanup (skip missing dirs)
# ------------------------------------------------------------------------------
RUN set -eux && \
    for dir in \
        /lib/systemd/system/sysinit.target.wants \
        /lib/systemd/system/multi-user.target.wants \
        /etc/systemd/system/*.wants \
        /lib/systemd/system/local-fs.target.wants \
        /lib/systemd/system/sockets.target.wants \
        /lib/systemd/system/basic.target.wants \
        /lib/systemd/system/anaconda.target.wants; do \
        [ -d "$dir" ] && find "$dir" -type l ! -name 'systemd-tmpfiles-setup.service' -delete || true; \
    done

# ------------------------------------------------------------------------------
# Directory and symlink setup for persistent data
# ------------------------------------------------------------------------------
RUN set -eux && \
    mkdir -p /xcatdata/etc/{dhcp,goconserver,xcat} && \
    for d in dhcp goconserver xcat; do ln -sf /xcatdata/etc/$d /etc/$d; done && \
    mkdir -p /xcatdata/{install,tftpboot,dhcpd,opt/xcat} && \
    ln -sf /xcatdata/install /install && \
    ln -sf /xcatdata/tftpboot /tftpboot && \
    ln -sf /xcatdata/dhcpd /var/lib/dhcpd && \
    ln -sf /xcatdata/opt/xcat /opt/xcat && \
    mkdir -p /nodeadd_def

# ------------------------------------------------------------------------------
# Install xCAT and dependencies
# ------------------------------------------------------------------------------
RUN dnf --enablerepo=crb install perl-IO-Tty  perl-Crypt-CBC -y


RUN  dnf -y install xCAT \
        rsyslog \
        createrepo_c \
        chrony \
        dhcp-client \
        man-db \
        gettext \
        initscripts \
        dnsmasq \
        mariadb \
        mariadb-server \
        openssh-server \
        openssh-clients \
        perl-DBD-mysql && \
    dnf clean all && rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# ------------------------------------------------------------------------------
# SSH Hardening and security setup
# ------------------------------------------------------------------------------
RUN set -eux && \
    sed -i \
        -e 's|#PermitRootLogin yes|PermitRootLogin prohibit-password|g' \
        -e 's|#Port 22|Port 2200|g' \
        -e 's|#UseDNS yes|UseDNS no|g' /etc/ssh/sshd_config && \
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    useradd -m -s /bin/bash xcatadmin && \
    echo 'xcatadmin:xcatadmin' | chpasswd && \
    echo 'root:ChangeMeNow!' | chpasswd && \
    passwd -l root && \
    rm -rf /root/.ssh && \
    mv /xcatdata /xcatdata.NEEDINIT

# ------------------------------------------------------------------------------
# Enable services for container boot
# ------------------------------------------------------------------------------
RUN systemctl enable sshd rsyslog dhcpd chronyd mariadb xcatd || true

# ------------------------------------------------------------------------------
# Copy initialization scripts and set permissions
# ------------------------------------------------------------------------------
COPY ./initscripts/* /etc/init.d/
COPY supervisord.conf /etc/supervisord.conf
COPY mysqlsetup.mod /mysqlsetup.mod
COPY mysqlsetup.sh.template /mysqlsetup.sh.template
COPY makedhcp.sh /makedhcp.sh
COPY ./nodeadd_def/add_nodedef.py /nodeadd_def/add_nodedef.py
COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 \
    /mysqlsetup.mod \
    /mysqlsetup.sh.template \
    /makedhcp.sh \
    /nodeadd_def/add_nodedef.py \
    /entrypoint.sh \
    /etc/init.d/*

# ------------------------------------------------------------------------------
# Runtime user and volume setup
# ------------------------------------------------------------------------------
USER xcatadmin

VOLUME ["/xcatdata", "/var/log/xcat"]

ENTRYPOINT ["/entrypoint.sh"]
