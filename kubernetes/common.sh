#!/bin/bash

export KUBE_CLUSTER_NAME=$(hostname -s)
export KUBE_MASTER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)

function mk_k8s_bar ()
{
	echo "######################################################################"
	echo -e "\033[47;30mINFO: $*\033[0m"
	echo "######################################################################"
}

function install_etcd {
	install -Dm644 ./etcd.yaml-3.5  /etc/etcd/conf.yml
	install -Dm644 ./etcd.confd /etc/conf.d/etcd
	install -Dm755 ./etcd.initd /etc/init.d/etcd
}


function install_flanneld {
	install -Dm644 ./flanneld.confd  /etc/conf.d/flanneld
	install -Dm755 ./flanneld.initd /etc/init.d/flanneld
}

function install_packages {
	mk_k8s_bar "install packages"

	apk update 

	apk add docker docker-openrc
	apk add cfssl iptables iptables-openrc
	apk add kube-controller-manager-openrc kube-controller-manager
	apk add kube-scheduler-openrc kube-scheduler
	apk add kube-apiserver kube-apiserver-openrc
	apk add kubectl  kubernetes lrzsz

	apk add kubelet kube-proxy

	apk add python3

	rc-update add docker default
}
