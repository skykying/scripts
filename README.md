# scripts

setenv boot_normal 'sunxi_flash read 45000000 fit;bootm 45000000#config@2'
setenv boot_normal 'sunxi_flash read 0x45000000 fit;bootm 0x45000000#config@1'
setenv boot_normal boot

#######################################################################################################

echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

ip link set eth0 up
ip addr add 192.168.168.122/24 dev eth0
ip route add default via  192.168.168.1  dev eth0


echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/main" > /etc/apk/repositories
echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/community" >> /etc/apk/repositories
echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/testing" >> /etc/apk/repositories

rm arch/arm64/configs/sun50iw1p1smp_linux_vir_defconfig -rf; cp defconfig arch/arm64/configs/sun50iw1p1smp_linux_vir_defconfig

scp root@192.168.168.102:/mnt/sdb1/tulip-m64-2020-1-16/A81/tools/pack/sun50iw1p1_vir_vir_uart0.img .
#######################################################################################################
# 2020 11-09 17:19:10
date 111709382020.10
hwclock -w

ulimit -SHn 65535

sysctl -w user.max_user_namespaces=15000

#######################################################################################################
openstack 
monmaptool --create --add ceph0 192.168.168.122 --fsid 241da498-6c50-4a44-af7c-7ed3275b0393 /etc/ceph/monmap

apk add postgresql-bdr-dev py3-psycopg2

apk add py3-configobj libusb py3-pip python3-dev gcc linux-headers  py3-yaml
apk add musl-dev musl-utils libffi-dev openssl openssl-dev make m4
apk add liberasurecode-dev libxml2 libxslt libxml2-dev libxml2-utils libxslt-dev

pip3 install --upgrade pip -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com
pip3 install -U setuptools -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com
pip3 install pyyaml -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v


pip3 install pynacl -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install swift -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install cinder -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install horizon -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install neutron -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install keystone -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install numpy -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install nova -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install glance -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install trove -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install ironic -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install masakari -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install octavia -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v



pip3 install ceph-deploy -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

pip3 install six -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install python-rbd -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

pip3 install prettytable -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install shyaml -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

apk add device-mapper-udev udev  device-mapper-libs


cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "http://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF

kubeadm config print init-defaults > kubeadm-config.yaml
kubeadm init --config=kubeadm-config.yaml



kubeadm init phase certs all
kubeadm init phase kubeconfig all
kubeadm init phase etcd local


cat conf.yml | shyaml get-value peer-transport-security.key-file

install_packages
generate_docker_mirror
generate_net_conf
generate_system_conf
generate_nginx_configure
generate_ca_certificates
generate_ssl_certificates
generate_kubes_certificates
generate_kubelet_ssl
generate_etcd_conf
generate_docker_conf
confiure_kube_components
configure_kube_apiserver
configure_kube_controller_manager
configure_kube_scheduler
boot_kube_components
configure_kubelet
configure_kube_proxy
boot_kubelet_proxy