#!/bin/bash

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function configure_kubelet {

	mk_k8s_bar "configure kubelet"

cat > "/etc/conf.d/kubelet" <<-EOF
command_args=" --alsologtostderr=true \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--cluster-dns=10.10.0.2 \
--cluster-domain=k8s.local \
--docker-tls \
--docker-tls-ca=/etc/kubernetes/ssl/ca.pem \
--docker-tls-cert=/etc/kubernetes/ssl/docker.pem \
--docker-tls-key=/etc/kubernetes/ssl/docker-key.pem \
--fail-swap-on=true \
--healthz-port=10248 \
--hostname-override= \
--image-pull-progress-deadline=30m \
--kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=5s \
--logtostderr=false \
--pod-infra-container-image=alpine:latest \
--port=10250 \
--read-only-port=10255 \
--register-node=true \
--root-dir=/var/lib/kubelet \
--runtime-request-timeout=10m \
--serialize-image-pulls=false \
--tls-cert-file=/etc/kubernetes/ssl/kubelet-$(hostname).pem \
--tls-private-key-file=/etc/kubernetes/ssl/kubelet-$(hostname)-key.pem \
--v=4"
EOF

}

# kubectl get node

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置node kube-proxy

function configure_kube_proxy {

	mk_k8s_bar "configure kube proxy"

	cat > "/etc/conf.d/kube-proxy" <<-EOF
command_args=" --alsologtostderr=true \
--bind-address=$KUBE_MASTER_IP \
--cluster-cidr=172.17.0.0/16 \
--hostname-override= \
--kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=5s \
--logtostderr=false \
--proxy-mode=iptables \
--v=4"
EOF
}

function boot_kubelet_proxy {

	mk_k8s_bar "generate_ca_certificates"

	for svc in {kube-proxy,kubelet}; do
	    rc-update add ${svc} default
	    rc-service  ${svc} start
	done
}
# kubectl get node
