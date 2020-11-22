#!/bin/bash
ip link set eth0 up
ip addr add 192.168.168.122/24 dev eth0
ip route add default via  192.168.168.1  dev eth0
