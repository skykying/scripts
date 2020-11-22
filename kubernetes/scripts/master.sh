#!/bin/bash

[ -f common.sh ] &&  source common.sh

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置master kube-apiserver

function configure_kube_apiserver {

	mk_k8s_bar "configure kube apiserver"

	cat > "/etc/conf.d/kube-apiserver" <<-EOF
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

command_args=" \
--advertise-address=$KUBE_MASTER_IP \
--allow-privileged=true \
--alsologtostderr=true \
--apiserver-count=1 \
--authorization-mode=Node,RBAC \
--anonymous-auth=false \
--bind-address=$KUBE_MASTER_IP \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--etcd-cafile=/etc/kubernetes/ssl/ca.pem \
--etcd-certfile=/etc/kubernetes/ssl/etcd.pem \
--etcd-keyfile=/etc/kubernetes/ssl/etcd-key.pem \
--etcd-prefix=/kubernetes \
--etcd-servers=https://$KUBE_MASTER_IP:2379 \
--event-ttl=1h \
--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
--kubelet-certificate-authority=/etc/kubernetes/ssl/ca.pem \
--kubelet-client-certificate=/etc/kubernetes/ssl/kube-apiserver.pem \
--kubelet-client-key=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--runtime-config=api/all=true \
--secure-port=5443 \
--service-account-key-file=/etc/kubernetes/ssl/service-account.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--service-node-port-range=30000-32767 \
--tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--v=4 \
--enable-aggregator-routing=true
--requestheader-client-ca-file=/etc/kubernetes/ssl/ca-agg.pem \
--requestheader-allowed-names="" \
--requestheader-extra-headers-prefix=X-Remote-Extra- \
--requestheader-group-headers=X-Remote-Group \
--requestheader-username-headers=X-Remote-User \
--proxy-client-cert-file=/etc/kubernetes/ssl/aggregator.pem \
--proxy-client-key-file=/etc/kubernetes/ssl/aggregator-key.pem"
EOF
}

# kubectl get roles -n kube-system extension-apiserver-authentication-reader

function configure_kube_controller_manager {

	mk_k8s_bar "configure kube controller manager"

cat > "/etc/conf.d/kube-controller-manager" <<-EOF
command_args=" \
--allocate-node-cidrs=false \
--alsologtostderr=true \
--authentication-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--authorization-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--bind-address=127.0.0.1 \
--cluster-cidr=192.168.0.0/16 \
--cluster-name=kubernetes \
--cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
--cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
--controller-start-interval=0 \
--kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--leader-elect=true \
--leader-elect-lease-duration=15s \
--leader-elect-renew-deadline=10s \
--leader-elect-retry-period=2s \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--node-cidr-mask-size=16 \
--node-monitor-grace-period=30s \
--node-monitor-period=3s \
--pod-eviction-timeout=30s \
--root-ca-file=/etc/kubernetes/ssl/ca.pem \
--service-account-private-key-file=/etc/kubernetes/ssl/service-account-key.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \
--use-service-account-credentials=true \
--v=4"
EOF
}

function configure_kube_scheduler {

	mk_k8s_bar "configure kube scheduler"

cat > "/etc/conf.d/kube-scheduler" <<-EOF
command_args=" --address=127.0.0.1 \
--alsologtostderr=true \
--bind-address=127.0.0.1 \
--authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--leader-elect-lease-duration=15s \
--leader-elect-renew-deadline=10s \
--leader-elect-retry-period=2s \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--tls-cert-file=/etc/kubernetes/ssl/kube-scheduler.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-scheduler-key.pem \
--v=4"
EOF
}
# kubectl create rolebinding -n kube-system ROLEBINDING_NAME --role=extension-apiserver-authentication-reader --serviceaccount=YOUR_NS:YOUR_SA

function boot_kube_components {

	mk_k8s_bar "boot kube components"

	for svc in kube-{apiserver,controller-manager,scheduler}; do
	    rc-update add ${svc} default
	    rc-service  ${svc} start
	done
}

# export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
# kubectl get node
# kubectl get cs


