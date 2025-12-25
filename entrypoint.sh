#!/bin/bash

set -e

variable_set() {
    # Check if required environment variables are set
    required_vars=(XCAT_VIP MYSQL_PORT MYSQL_ADMIN_PW MYSQL_ROOT_USER MYSQL_ROOT_PW TIMEZONE DHCP_INTERFACE DOMAIN FORWARDERS MASTER NAMESERVERS IB_NET IB_MASK XCAT_MASTER OBJECT_NAME DHCP_SERVER GATEWAY IP_MASK IP_NET MGT_IF_NAME TFTP_SERVER)

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done

    # Generate configuration files from templates
    envsubst < /mysqlsetup.sh.template > /mysqlsetup.sh

}


start_supervisord() {
    echo "Starting supervisord to manage xCAT services..."
    /usr/bin/supervisord -c /etc/supervisord.conf
}

fix_log_permissions() {
    local logadm
    if [[ -f /etc/debian_version ]]; then
        logadm="syslog:adm"
    else
        logadm="root:"
    fi
    chown -R "$logadm" /var/log/xcat/
}

initialize_loop_devices() {
    echo "Initializing loop devices..."
    for i in {0..7}; do
        [[ ! -b /dev/loop$i ]] && mknod /dev/loop$i -m0660 b 7 "$i"
    done
}

configure_site_table() {
    export XCATBYPASS=1
    chtab key=timezone site.value="$TIMEZONE"
    chtab key=dhcpinterfaces site.value="$DHCP_INTERFACE"
    chtab key=domain site.value="$DOMAIN"
    chtab key=forwarders site.value="$FORWARDERS"
    chtab key=master site.value="$MASTER"
    chtab key=nameservers site.value="$NAMESERVERS"
}

setup_ib_network() {
    if ! tabdump networks | grep -q "ib0"; then
        chdef -t network -o ib0 net="$IB_NET" mask="$IB_MASK" gateway="$XCAT_MASTER" \
              tftpserver="$XCAT_MASTER" mgtifname=ib0 mtu=2044
    else
        echo "IB network 'ib0' already exists."
    fi
}

configure_main_network() {
    if tabdump networks | grep -q "$OBJECT_NAME"; then
        echo "Updating network: $OBJECT_NAME"
    else
        echo "Creating network: $OBJECT_NAME"
    fi

    chdef -t network -o "$OBJECT_NAME" \
          dhcpserver="$DHCP_SERVER" gateway="$GATEWAY" \
          mask="$IP_MASK" mgtifname="$MGT_IF_NAME" \
          mtu=1500 net="$IP_NET" tftpserver="$TFTP_SERVER"
}

initialize_xcat() {
    echo "Initializing xCAT from /xcatdata.NEEDINIT..."
    rsync -a /xcatdata.NEEDINIT/ /xcatdata
    mv /xcatdata.NEEDINIT /xcatdata.orig
    source /etc/profile.d/xcat.sh
    set +e
    xcatconfig -d
    xcatconfig -i -c -s
    set -e
    restartxcatd
    configure_site_table
    setup_ib_network
    configure_main_network

    echo "Syncing .xcat config..."
    rsync -a /root/.xcat/* /xcatdata/.xcat
    rm -rf /root/.xcat/
    ln -sf -t /root /xcatdata/.xcat

    ln -sf /opt/xcat/bin/xcatclient /opt/xcat/probe/subcmds/bin/switchprobe
}

print_access_info() {
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    echo "Welcome to Dockerized xCAT. Access via:"
    ip -o -4 addr show up | grep -v "\<lo\>" | awk '{print $4}' | cut -d/ -f1 | while read -r ip; do
        echo "   ssh root@$ip -p 2200"
    done
    echo "Initial password: \"Rudra@@123\""
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

main() {

    variable_set # Ensure required environment variables are set

    if [[ -f /var/lib/mysql/xcatdb/db.opt && -f /etc/xcat/cfgloc ]]; then
        rm -rf /root/.xcat/
        ln -sf -t /root /xcatdata/.xcat
        start_supervisord
    else
        fix_log_permissions

        if [[ -d "/xcatdata.NEEDINIT" ]]; then
            initialize_xcat
        fi
        mv /opt/xcat/bin/mysqlsetup /opt/xcat/bin/mysqlsetup.bk
        mv -f /mysqlsetup.mod /opt/xcat/bin/mysqlsetup
        start_supervisord
        cat /etc/motd
        print_access_info
        initialize_loop_devices
        exec /sbin/init
    fi
}


main
