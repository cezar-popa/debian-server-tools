#!/bin/bash
#
# Set up certificate for use.
#
# VERSION       :0.8.0
# DATE          :2016-02-16
# AUTHOR        :Viktor Szépe <viktor@szepe.net>
# LICENSE       :The MIT License (MIT)
# URL           :https://github.com/szepeviktor/debian-server-tools
# BASH-VERSION  :4.2+
# DEPENDS       :apt-get install openssl ca-certificates

# Intermediate certificates and root certificates
#
# StartSSL Class 1 DV
#     https://www.startssl.com/root "Intermediate CA Certificates"
#     wget https://www.startssl.com/certs/sca.server1.crt && dos2unix sca.server1.crt
# StartSSL Class 2 IV
#     wget https://www.startssl.com/certs/sca.server2.crt && dos2unix sca.server2.crt
# Comodo (PositiveSSL)
#     https://support.comodo.com/index.php?/Default/Knowledgebase/Article/View/620/0/which-is-root-which-is-intermediate
# GeoTrust
#     https://www.geotrust.com/resources/root-certificates/
# CAcert
#     http://www.cacert.org/index.php?id=3
# NetLock
#     https://www.netlock.hu/html/cacrl.html
# Microsec
#     https://e-szigno.hu/hitelesites-szolgaltatas/tanusitvanyok/szolgaltatoi-tanusitvanyok.html
# szepenet
#     http://ca.szepe.net/szepenet-ca.pem
#
# Saving certificate from the issuer
#     D=$(date +%Y%m%d); read -r -p "? " DOMAIN; cd /root/ssl/; mkdir "${D}-${DOMAIN}"; cd "${D}-${DOMAIN}"
#     editor "priv-key-${D}-encrypted.key"
#     openssl rsa -in "priv-key-${D}-encrypted.key" -out "priv-key-${D}.key"
#     editor "pub-key-${D}.pem"

# @TODO Add apache SSLOpenSSLConfCmd for OpenSSL 1.0.2+

TODAY="$(date +%Y%m%d)"
INT="sca.server1.crt"
#touch null.crt; INT="null.crt"
PRIV="priv-key-${TODAY}.key"
PUB="pub-key-${TODAY}.pem"
CABUNDLE="/etc/ssl/certs/ca-certificates.crt"
PRIV_DIR="/etc/ssl/private"
PUB_DIR="/etc/ssl/localcerts"

# Apache2: public + intermediate
# "include intermediate CA certificates, sorted from leaf to root"
#
# Use Common Name
APACHE_DOMAIN="$(openssl x509 -in "$PUB" -noout -subject|sed -ne 's;^.*/CN=\([^/]\+\).*$;\1;p')"
#
# Use last Subject Alternative Name
#APACHE_DOMAIN="$(openssl x509 -in "$PUB" -text|sed -ne '/^\s*X509v3 Subject Alternative Name:/{n;s/^.*DNS://p}')"
#
# Replace wildcard prefix
APACHE_DOMAIN="${APACHE_DOMAIN/\*./wildcard.}"
#
# Use $APACHE_DOMAIN
APACHE_VHOST_CONFIG="/etc/apache2/sites-available/${APACHE_DOMAIN}.conf"
#
# Use apache.vhost
[ -r apache.vhost ] && APACHE_VHOST_CONFIG="/etc/apache2/sites-available/$(head -n 1 apache.vhost).conf"
#
#APACHE_PUB="${PUB_DIR}/${APACHE_DOMAIN}-public.pem"
#APACHE_PRIV="${PRIV_DIR}/${APACHE_DOMAIN}-private.key"

# Nginx: public + intermediate
# "the primary certificate comes first, then the intermediate certificates"
#
# Use Common Name
NGINX_DOMAIN="$(openssl x509 -in "$PUB" -noout -subject|sed -ne 's;^.*/CN=\([^/]\+\).*$;\1;p')"
#
# Replace wildcard prefix
NGINX_DOMAIN="${NGINX_DOMAIN/\*./wildcard.}"
#
NGINX_VHOST_CONFIG="/etc/nginx/sites-available/${NGINX_DOMAIN}"
#
# Use nginx.vhost
[ -r nginx.vhost ] && NGINX_VHOST_CONFIG="/etc/nginx/sites-available/$(head -n 1 nginx.vhost)"
#
#NGINX_PUB="${PUB_DIR}/${NGINX_DOMAIN}-public.pem"
#NGINX_DHPARAM="${PRIV_DIR}/${NGINX_DOMAIN}-dhparam.pem"
#NGINX_PRIV="${PRIV_DIR}/${NGINX_DOMAIN}-private.key"

# Courier MTA: public + intermediate + private
# From Debian jessie on: private + public + intermediate
#
#COURIER_COMBINED="${PRIV_DIR}/courier-comb3.pem"
#COURIER_DHPARAMS="${PRIV_DIR}/courier-dhparams.pem"

# Dovecot: public + intermediate
# http://wiki2.dovecot.org/SSL/DovecotConfiguration#Chained_SSL_certificates
#
#DOVECOT_PUB="/etc/dovecot/dovecot.pem"
#DOVECOT_PRIV="/etc/dovecot/private/dovecot.key"

# Proftpd
#
#PROFTPD_PUB="/etc/proftpd/ssl-pub.pem"
#PROFTPD_PRIV="/etc/proftpd/ssl-priv.key"
#PROFTPD_INT="/etc/proftpd/sub.class1.server.ca.pem"

# Webmin: private + public
# SSL check: https://www.digicert.com/help/
#
#WEBMIN_COMBINED="/etc/webmin/miniserv.pem"
#WEBMIN_INT="/etc/webmin/sub.class1.server.ca.pem"

Die() {
    local RET="$1"
    shift
    echo -e "$*" 1>&2
    exit "$RET"
}

Readkey() {
    read -p "Press any key ..." -n 1 -s
    echo
}

Check_requirements() {
    if [ "$(id --user)" != 0 ]; then
        Die 1 "You need to be root."
    fi
    if [ "$(stat --format=%a .)" != 700 ] \
        || [ "$(stat --format=%u .)" != 0 ]; then
        Die 2 "This directory needs to be private (0700) and owned by root."
    fi
    if ! [ -f "$INT" ] || ! [ -f "$PRIV" ] || ! [ -f "$PUB" ]; then
        Die 3 "Missing cert."
    fi
    if ! [ -d "$PRIV_DIR" ] || ! [ -d "$PUB_DIR" ]; then
        Die 4 "Missing cert directory."
    fi
    if [ "$(stat --format=%a "$PRIV_DIR")" != 710 ] \
        || [ "$(stat --format=%u "$PRIV_DIR")" != 0 ]; then
        Die 5 "Private cert directory needs to be private (0710) and owned by root."
    fi
    if ! [ -f /usr/local/bin/cert-expiry.sh ] || ! [ -f /etc/cron.weekly/cert-expiry1 ]; then
        Die 6 "./install.sh security/cert-expiry.sh"
    fi

    # Check certs' moduli
    PUB_MOD="$(openssl x509 -noout -modulus -in "$PUB" | openssl sha256)"
    PRIV_MOD="$(openssl rsa -noout -modulus -in "$PRIV" | openssl sha256)"
    if [ "$PUB_MOD" != "$PRIV_MOD" ]; then
        Die 7 "Mismatching certs."
    fi
}

Protect_certs() {
    # Are certificates are readable?
    chown root:root "$INT" "$PRIV" "$PUB" || Die 10 "certs owner"
    chmod 600 "$INT" "$PRIV" "$PUB" || Die 11 "certs perms"
}

Courier_mta() {
    [ -z "$COURIER_COMBINED" ] && return 1
    [ -z "$COURIER_DHPARAMS" ] && return 1

    [ -d "$(dirname "$COURIER_COMBINED")" ] || Die 20 "courier ssl dir"

    #cat "$PUB" "$INT" "$PRIV" > "$COURIER_COMBINED" || Die 21 "courier cert creation"
    # From Debian jessie on: private + public + intermediate
    cat "$PRIV" "$PUB" "$INT" > "$COURIER_COMBINED" || Die 21 "courier cert creation"
    chown daemon:root "$COURIER_COMBINED" || Die 22 "courier owner"
    chmod 600 "$COURIER_COMBINED" || Die 23 "courier perms"
    nice openssl dhparam 2048 > "$COURIER_DHPARAMS" || Die 24 "courier DH params"
    chown daemon:root "$COURIER_DHPARAMS" || Die 25 "courier DH params owner"
    chmod 600 "$COURIER_DHPARAMS" || Die 26 "courier DH params perms"

    # Check config files for STARTTLS, SMTPS, IMAP STARTTLS IMAPS
    if grep -q "^TLS_CERTFILE=${COURIER_COMBINED}\$" /etc/courier/esmtpd \
        && grep -q "^TLS_CERTFILE=${COURIER_COMBINED}\$" /etc/courier/esmtpd-ssl \
        && grep -q "^TLS_CERTFILE=${COURIER_COMBINED}\$" /etc/courier/imapd-ssl \
        && grep -q "^TLS_DHCERTFILE=${COURIER_DHPARAMS}\$" /etc/courier/courierd; then

        service courier-mta restart
        service courier-mta-ssl restart
        service courier-imap restart
        service courier-imap-ssl restart

        # Tests SMTP, SMTPS, IMAP, IMAPS
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:25 -starttls smtp
        echo "SMTP STARTTLS result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:465
        echo "SMTPS result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:143 -starttls imap
        echo "IMAP STARTTLS result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:993
        echo "IMAPS result=$?"
    else
        echo "Add 'TLS_CERTFILE=${COURIER_COMBINED}' to courier configs: esmtpd, esmtpd-ssl, imapd-ssl" 1>&2
    fi

    echo "$(tput setaf 1)WARNING: Update msmtprc on SMTP clients.$(tput sgr0)"
}

Apache2() {
    [ -z "$APACHE_PUB" ] && return 1
    [ -z "$APACHE_PRIV" ] && return 1
    [ -z "$APACHE_VHOST_CONFIG" ] && return 1

    [ -d "$(dirname "$APACHE_PUB")" ] || Die 40 "apache ssl dir"

    {
        cat "$PUB" "$INT"
        #nice openssl dhparam 4096
        nice openssl dhparam 2048
    } > "$APACHE_PUB" || Die 41 "apache cert creation"
    cp "$PRIV" "$APACHE_PRIV" || Die 42 "apache private"
    chown root:root "$APACHE_PUB" "$APACHE_PRIV" || Die 43 "apache owner"
    chmod 640 "$APACHE_PUB" "$APACHE_PRIV" || Die 44 "apache perms"

    # Check config
    if  grep -q "^\s*SSLCertificateFile\s\+${APACHE_PUB}$" "$APACHE_VHOST_CONFIG" \
        && grep -q "^\s*SSLCertificateKeyFile\s\+${APACHE_PRIV}$" "$APACHE_VHOST_CONFIG" \
        && grep -q "^\s*SSLCACertificatePath\s\+/etc/ssl/certs$" "$APACHE_VHOST_CONFIG" \
        && grep -q "^\s*SSLCACertificateFile\s\+${CABUNDLE}$" "$APACHE_VHOST_CONFIG"; then

        service apache2 restart

        # Test HTTPS
        SERVER_NAME="$(grep -i -o -m1 "ServerName\s\+\S\+" "$APACHE_VHOST_CONFIG"|cut -d' ' -f2)"
        timeout 3 openssl s_client -CAfile "$CABUNDLE" -connect "${SERVER_NAME}:443" < /dev/null
        echo "HTTPS result=$?"
    else
        echo "Edit Apache SSLCertificateFile, SSLCertificateKeyFile, SSLCACertificatePath and SSLCACertificateFile" 1>&2
    fi
}

Nginx() {
    [ -z "$NGINX_PUB" ] && return 1
    [ -z "$NGINX_DHPARAM" ] && return 1
    [ -z "$NGINX_PRIV" ] && return 1
    [ -z "$NGINX_VHOST_CONFIG" ] && return 1

    [ -d "$(dirname "$NGINX_PUB")" ] || Die 70 "nginx ssl dir"

    cat "$PUB" "$INT" > "$NGINX_PUB" || Die 71 "nginx cert creation"
    nice openssl dhparam 2048 > "$NGINX_DHPARAM" || Die 72 "nginx private"
    cp "$PRIV" "$NGINX_PRIV" || Die 73 "nginx private"
    chown root:root "$NGINX_PUB" "$NGINX_PRIV" || Die 74 "nginx owner"
    chmod 640 "$NGINX_PUB" "$NGINX_PRIV" || Die 75 "nginx perms"

    # Check config
    if  grep -q "^\s*ssl_certificate\s\+${NGINX_PUB}\$" "$NGINX_VHOST_CONFIG" \
        && grep -q "^\s*ssl_certificate_key\s\+${NGINX_PRIV}\$" "$NGINX_VHOST_CONFIG" \
        && grep -q "^\s*ssl_dhparam\s\+${NGINX_DHPARAM}\$" "$NGINX_VHOST_CONFIG"; then

        service nginx restart

        # Test HTTPS
        SERVER_NAME="$(sed -ne '/^\s*server_name\s\+\(\S\+\);.*$/{s//\1/p;q;}' "$NGINX_VHOST_CONFIG")"
        timeout 3 openssl s_client -CAfile "$CABUNDLE" -connect "${SERVER_NAME}:443" < /dev/null
        echo "HTTPS result=$?"
    else
        echo "Edit Nginx ssl_certificate and ssl_certificate_key and ssl_dhparam" 1>&2
    fi
}

Proftpd() {
    [ -z "$PROFTPD_PUB" ] && return 1
    [ -z "$PROFTPD_PRIV" ] && return 1
    [ -z "$PROFTPD_INT" ] && return 1

    [ -d "$(dirname "$APACHE_PUB")" ] || Die 30 "proftpd ssl dir"

    cp "$PUB" "$PROFTPD_PUB" || Die 31 "proftpd public"
    cp "$PRIV" "$PROFTPD_PRIV" || Die 32 "proftpd private"
    cp "$INT" "$PROFTPD_INT" || Die 33 "proftpd intermediate"
    chown root:root "$PROFTPD_PUB" "$PROFTPD_PRIV" "$PROFTPD_INT" || Die 34 "proftpd owner"
    chmod 600 "$PROFTPD_PUB" "$PROFTPD_PRIV" "$PROFTPD_INT" || Die 35 "proftpd perms"

    # Check config
    if  grep -q "^TLSRSACertificateFile\s*${PROFTPD_PUB}\$" /etc/proftpd/tls.conf \
        && grep -q "^TLSRSACertificateKeyFile\s*${PROFTPD_PRIV}\$" /etc/proftpd/tls.conf \
        && grep -q "^TLSCACertificateFile\s*${PROFTPD_INT}\$" /etc/proftpd/tls.conf; then

        service proftpd restart

        # Test FTP
        echo "QUIT"|openssl s_client -crlf -CAfile "$CABUNDLE" -connect localhost:21 -starttls ftp
        echo "AUTH TLS result=$?"
    else
        echo "Edit ProFTPd TLSRSACertificateFile, TLSRSACertificateKeyFile and TLSCACertificateFile" 1>&2
    fi
}

Dovecot() {
    [ -z "$DOVECOT_PUB" ] && return 1
    [ -z "$DOVECOT_PRIV" ] && return 1

    [ -d "$(dirname "$DOVECOT_PUB")" ] || Die 50 "dovecot ssl dir"

    # Dovecot: public + intermediate
    cat "$PUB" "$INT" > "$DOVECOT_PUB" || Die 51 "dovecot cert creation"
    cat "$PRIV" > "$DOVECOT_PRIV" || Die 52 "dovecot private cert creation"
    chown root:root "$DOVECOT_PUB" "$DOVECOT_PRIV" || Die 53 "dovecot owner"
    chmod 600 "$DOVECOT_PUB" "$DOVECOT_PRIV" || Die 54 "dovecot perms"

    # Check config files for ssl_cert, ssl_key
    if grep -q "^ssl_cert\s*=\s*<${DOVECOT_PUB}\$" /etc/dovecot/conf.d/10-ssl.conf \
        && grep -q "^ssl_key\s*=\s*<${DOVECOT_PRIV}\$" /etc/dovecot/conf.d/10-ssl.conf; then

        service dovecot restart

        # Tests POP3, POP3S, IMAP, IMAPS
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:110 -starttls pop3
        echo "POP3 STARTTLS result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:995
        echo "POP3S result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:143 -starttls imap
        echo "IMAP STARTTLS result=$?"
        Readkey
        echo QUIT|openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:993
        echo "IMAPS result=$?"
    else
        echo "Edit Dovecot ssl_cert and ssl_key" 1>&2
    fi
}

Webmin() {
    [ -z "$WEBMIN_COMBINED" ] && return 1
# @FIXME Could be a separate public key: "certfile="
    [ -z "$WEBMIN_INT" ] && return 1

    [ -d "$(dirname "$WEBMIN_COMBINED")" ] || Die 60 "webmin ssl dir"

    # Webmin: private + public
    cat "$PRIV" "$PUB" > "$WEBMIN_COMBINED" || Die 61 "webmin public"
    cp "$INT" "$WEBMIN_INT" || Die 62 "webmin intermediate"
    chown root:root "$WEBMIN_COMBINED" "$WEBMIN_INT" || Die 63 "webmin owner"
    chmod 600 "$WEBMIN_COMBINED" "$WEBMIN_INT" || Die 64 "webmin perms"

    # Check config
    if  grep -q "^keyfile=${WEBMIN_COMBINED}\$" /etc/webmin/miniserv.conf \
        && grep -q "^extracas=${WEBMIN_INT}\$" /etc/webmin/miniserv.conf; then

        service webmin restart

        # Test HTTPS:10000
        timeout 3 openssl s_client -CAfile "$CABUNDLE" -crlf -connect localhost:10000
        echo "HTTPS result=$?"
    else
        echo "Edit Webmin keyfile and extracas" 1>&2
    fi
}

Check_requirements
Protect_certs

Courier_mta && Readkey

Proftpd && Readkey

Apache2 && Readkey

Nginx && Readkey

Dovecot && Readkey

Webmin
# no ReadKey here

echo "Done."