#!/bin/sh
addgroup -S etcd 2>/dev/null
# adduser -S -D -H -h /dev/null -s /sbin/nologin -G etcd -g etcd etcd 2>/dev/null
exit 0
