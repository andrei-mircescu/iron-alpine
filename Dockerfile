FROM alpine:3.8
ENV alpine_version="v3.8"

# ensure we only use apk repositories over HTTPS (altough APK contain an embedded signature)
RUN echo "https://alpine.global.ssl.fastly.net/alpine/${alpine_version}/main" > /etc/apk/repositories \
	&& echo "https://alpine.global.ssl.fastly.net/alpine/${alpine_version}/community" >> /etc/apk/repositories

# The user the app should run as
ENV APP_USER=app
# The home directory
ENV APP_DIR="/$APP_USER"
# Where persistent data (volume) should be stored
ENV DATA_DIR "$APP_DIR/data"
# Where configuration should be stored
ENV CONF_DIR "$APP_DIR/conf"

# Update base system
RUN apk --no-cache upgrade && apk add --no-cache ca-certificates

# Add our security scanner
RUN wget -O /microscanner https://get.aquasec.com/microscanner \
  && chmod +x /microscanner

# Add custom user and setup home directory
RUN adduser -s /bin/true -u 1000 -D -h $APP_DIR $APP_USER \
  && mkdir "$DATA_DIR" "$CONF_DIR" \
  && chown -R "$APP_USER" "$APP_DIR" "$CONF_DIR" \
  && chmod 700 "$APP_DIR" "$DATA_DIR" "$CONF_DIR"

# Remove existing crontabs, if any.
RUN rm -fr /var/spool/cron \
	&& rm -fr /etc/crontabs \
	&& rm -fr /etc/periodic

# Remove all but a handful of admin commands.
RUN find /sbin /usr/sbin \
  ! -type d -a ! -name apk -a ! -name ln \
  -delete

# Remove world-writeable permissions except for /tmp/
RUN find / -xdev -type d -perm +0002 -exec chmod o-w {} + \
	&& find / -xdev -type f -perm +0002 -exec chmod o-w {} + \
	&& chmod 777 /tmp/ \
  && chown $APP_USER:root /tmp/

# Remove unnecessary accounts, excluding current app user and root
RUN sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/group \
  && sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/passwd

# Remove interactive login shell for everybody
RUN sed -i -r 's#^(.*):[^:]*$#\1:/sbin/nologin#' /etc/passwd

# Disable password login for everybody
RUN while IFS=: read -r username _; do passwd -l "$username"; done < /etc/passwd || true

# Remove apk configs. -> Commented out because we need apk to install other stuff
#RUN find /bin /etc /lib /sbin /usr \
#  -xdev -type f -regex '.*apk.*' \
#  ! -name apk \
#  -exec rm -fr {} +

# Remove temp shadow,passwd,group
RUN find /bin /etc /lib /sbin /usr -xdev -type f -regex '.*-$' -exec rm -f {} +

# Ensure system dirs are owned by root and not writable by anybody else.
RUN find /bin /etc /lib /sbin /usr -xdev -type d \
  -exec chown root:root {} \; \
  -exec chmod 0755 {} \;

# Remove suid & sgid files
RUN find /bin /etc /lib /sbin /usr -xdev -type f -a \( -perm +4000 -o -perm +2000 \) -delete

# Remove dangerous commands
RUN find /bin /etc /lib /sbin /usr -xdev \( \
  -name hexdump -o \
  -name chgrp -o \
  -name chown -o \
  -name ln -o \
  -name od -o \
  -name strings -o \
  -name su \
  -name sudo \
  \) -delete

# Remove init scripts since we do not use them.
RUN rm -fr /etc/init.d /lib/rc /etc/conf.d /etc/inittab /etc/runlevels /etc/rc.conf /etc/logrotate.d

# Remove kernel tunables
RUN rm -fr /etc/sysctl* /etc/modprobe.d /etc/modules /etc/mdev.conf /etc/acpi

# Remove root home dir
RUN rm -fr /root

# Remove fstab
RUN rm -f /etc/fstab

# Remove any symlinks that we broke during previous steps
RUN find /bin /etc /lib /sbin /usr -xdev -type l -exec test ! -e {} \; -delete

# add-in security scan
COPY secscan.sh $APP_DIR/

# add-in post installation file for permissions
COPY post-install.sh $APP_DIR/
RUN chmod 500 $APP_DIR/post-install.sh $APP_DIR/secscan.sh

WORKDIR $APP_DIR
