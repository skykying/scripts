###
# DOCKER config
#
# The following values are used to configure the DOCKER
#
# https://blog.csdn.net/iov_aaron/article/details/94389426


command_args="                                        \
            $DOCKER_NETWORK_OPTIONS                   \
            --data-root=/var/lib/docker               \
            --host=tcp://172.16.9.202:2375            \
            --host=unix:///var/run/docker.sock        \
            --insecure-registry=k8s.gcr.io            \
            --insecure-registry=quay.io               \
            --ip-forward=true                         \
            --live-restore=true                       \
            --log-driver=json-file                    \
            --log-level=warn                          \
            --registry-mirror=https://registry.docker-cn.com \
            --selinux-enabled=false                   \
            --storage-driver=overlay2                 \
            --tlscacert=/etc/kubernetes/ssl/ca.pem    \
            --tlscert=/etc/kubernetes/ssl/docker.pem  \
            --tlskey=/etc/kubernetes/ssl/docker-key.pem \
            --tlsverify"