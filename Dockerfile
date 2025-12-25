FROM rockylinux:9.6

MAINTAINER The xCAT Project

ENV container docker

ARG xcat_version=latest
ARG xcat_reporoot=https://xcat.org/files/xcat/repos/yum
ARG xcat_baseos=rh9
ARG OPENSSL_FILE=/opt/xcat/share/xcat/ca/openssl.cnf.tmpl
ARG OPENSSL_BACKUP_FILE=/opt/xcat/share/xcat/ca/openssl.cnf.tmpl.orig
ARG DOCKERHOST_CERT_FILE=/opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh
ARG DOCKERHOST_CERT_BACKUP_FILE=/opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh.orig

RUN mkdir -p /lib/systemd/system/sysinit.target.wants /etc/systemd/system /lib/systemd/system/multi-user.target.wants && \
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

RUN mkdir -p /xcatdata/etc/{dhcp,goconserver,xcat} && ln -sf -t /etc /xcatdata/etc/{dhcp,goconserver,xcat} && \
    mkdir -p /xcatdata/{install,tftpboot} && ln -sf -t / /xcatdata/{install,tftpboot} && \
    mkdir -p /xcatdata/dhcpd && ln -sf -t /var/lib /xcatdata/dhcpd && \
    mkdir -p /xcatdata/opt/xcat && ln -sf -t /opt/ /xcatdata/opt/xcat && \
    mkdir -p /nodeadd_def

RUN dnf install -y epel-release && \
    dnf -y install \
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
        hostname \
        ca-certificates \
        python3 \
        dbus \
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
    dnf clean all && dnf -y install supervisor && \
    dnf -y install wget && \
    dnf clean all && \
    rm -rf /var/cache/dnf /tmp/* /var/tmp/*

RUN wget ${xcat_reporoot}/${xcat_version}/$([[ "devel" = "${xcat_version}" ]] && echo 'core-snap' || echo 'xcat-core')/xcat-core.repo -O /etc/yum.repos.d/xcat-core.repo && \
    wget ${xcat_reporoot}/${xcat_version}/xcat-dep/${xcat_baseos}/$(uname -m)/xcat-dep.repo -O /etc/yum.repos.d/xcat-dep.repo && \
    dnf --enablerepo=crb install perl perl-IO-Tty perl-IO-Stty perl-Crypt-CBC -y && yum install -y -q wget which 

ADD ./go-xcat /tmp/go-xcat
RUN set +e && \
    chmod +x /tmp/go-xcat && \
    /tmp/go-xcat -x ${xcat_version} install -y; \
    set -e


RUN cp -n ${OPENSSL_FILE} ${OPENSSL_BACKUP_FILE} && \
    sed -i 's/^[[:space:]]*authorityKeyIdentifier/#&/' ${OPENSSL_FILE} && \
    cp -n ${DOCKERHOST_CERT_FILE} ${DOCKERHOST_CERT_BACKUP_FILE} && \
    sed -i 's|openssl req -config ca/openssl.cnf -new -key ca/dockerhost-key.pem -out cert/dockerhost-req.pem -extensions server -subj "/CN=\$CNA"|openssl req -config ca/openssl.cnf -new -key ca/dockerhost-key.pem -out cert/dockerhost-req.pem -subj "/CN=\$CNA"|' ${DOCKERHOST_CERT_FILE} 



RUN   yum install -y \
       openssh-server \
       rsyslog \
       createrepo \
       iproute \
       chrony \
       dhcp-client \
       procps-ng \
       man

RUN yum install -y  gettext


RUN sed -i -e 's|#PermitRootLogin yes|PermitRootLogin yes|g' \
           -e 's|#Port 22|Port 2200|g' \
           -e 's|#UseDNS yes|UseDNS no|g' /etc/ssh/sshd_config && \
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "root:Rudra@@123" | chpasswd && \
    rm -rf /root/.ssh && \
    mv /xcatdata /xcatdata.NEEDINIT

RUN systemctl enable httpd && \
    systemctl enable sshd && \
    systemctl enable dhcpd && \
    systemctl enable rsyslog && \
    systemctl enable xcatd

COPY ./initscripts/* /etc/init.d/
RUN chmod +x /etc/init.d/*
# Copy supervisor configuration fileis
COPY supervisord.conf /etc/supervisord.conf


ADD mysqlsetup.mod /
RUN chmod +x /mysqlsetup.mod

ADD mysqlsetup.sh.template /mysqlsetup.sh.template
RUN chmod +x /mysqlsetup.sh.template

ADD makedhcp.sh /
RUN chmod +x /makedhcp.sh

ADD ./nodeadd_def/add_nodedef.py /nodeadd_def
RUN chmod +x /nodeadd_def/add_nodedef.py

ADD ./etc/sysctl.conf /etc/sysctl.conf
ADD ./etc/profile.d/xcat.sh /etc/profile.d/xcat.sh
ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XCATROOT /opt/xcat
ENV PATH="$XCATROOT/bin:$XCATROOT/sbin:$XCATROOT/share/xcat/tools:$PATH" MANPATH="$XCATROOT/share/man:$MANPATH"
VOLUME [ "/xcatdata", "/var/log/xcat" ]

CMD [ "/entrypoint.sh" ]


