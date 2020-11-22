#!/bin/bash


set -e 

export KUBE_CLUSTER_NAME=$(hostname -s)
export KUBE_MASTER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)

function mk_k8s_bar ()
{
	echo "######################################################################"
	echo -e "\033[47;30mINFO: $*\033[0m"
	echo "######################################################################"
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
	apk add coredns coredns-openrc

	apk add python3

	# rc-update add docker default
}



function install_etcd {
	install -Dm644 ./conf.d/etcd.yaml-3.5  /etc/etcd/conf.yml
	install -Dm644 ./conf.d/etcd.confd /etc/conf.d/etcd
	install -Dm755 ./init.d/etcd.initd /etc/init.d/etcd
}

function install_docker {
	install -Dm644 ./conf.d/docker.confd /etc/conf.d/docker
	install -Dm755 ./init.d/docker.initd /etc/init.d/docker
}

function install_flanneld {
	install -Dm644 ./conf.d/flanneld.confd  /etc/conf.d/flanneld
	install -Dm755 ./init.d/flanneld.initd /etc/init.d/flanneld
}

function install_kubernetes {
	install -Dm644 ./conf.d/kube-apiserver.confd  /etc/conf.d/kube-apiserver
	install -Dm755 ./init.d/kube-apiserver.initd /etc/init.d/kube-apiserver

	install -Dm644 ./conf.d/kube-controller-manager.confd  /etc/conf.d/kube-controller-manager
	install -Dm755 ./init.d/kube-controller-manager.initd /etc/init.d/kube-controller-manager

	install -Dm644 ./conf.d/kube-scheduler.confd  /etc/conf.d/kube-scheduler
	install -Dm755 ./init.d/kube-scheduler.initd /etc/init.d/kube-scheduler

	install -Dm644 ./conf.d/kube-proxy.confd  /etc/conf.d/kube-proxy
	install -Dm755 ./init.d/kube-proxy.initd /etc/init.d/kube-proxy

	install -Dm644 ./conf.d/kubelet.confd  /etc/conf.d/kubelet
	install -Dm755 ./init.d/kubelet.initd /etc/init.d/kubelet
}

# echo "1" >/proc/sys/net/bridge/bridge-nf-call-iptables
# swapoff -a && sysctl -w vm.swappiness=0