#!/bin/bash

# https://www.jianshu.com/p/ea126909457e/

export HOSENAME=$hosename
export CEPH_MASTER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)


apk add ceph 

cat > /etc/ceph/ceph.conf <<EOF
fsid = 4299abf0-4901-497a-9bb5-59325a1e757f

mon_initial_members = ${HOSENAME}
mon_host = $CEPH_MASTER_IP
public_network = 192.168.168.1/24

auth cluster required = cephx
auth service required = cephx
auth client required = cephx
osd journal size = 1024
filestore xattr use omap = true
osd pool default size = 1
osd pool default min size = 1
osd pool default pg num = 333
osd pool default pgp num = 333
osd crush chooseleaf type = 1

osd max object name len = 256 
osd max object namespace len = 64
EOF


# 为此集群创建密钥环、并生成监视器密钥
ceph-authtool \
	--create-keyring /etc/ceph/ceph.mon.keyring \
	--gen-key -n mon. \
	--cap mon 'allow *'

# 生成管理员密钥环，生成 client.admin 用户创建管理集群的密钥并赋予访问权限
ceph-authtool \
	--create-keyring /etc/ceph/ceph.client.admin.keyring \
	--gen-key -n client.admin  \
	--cap mon 'allow *' \
	--cap osd 'allow *' \
	--cap mds 'allow'

# 把 client.admin 密钥加入 ceph.mon.keyring
ceph-authtool /etc/ceph/ceph.mon.keyring \
	--import-keyring /etc/ceph/ceph.client.admin.keyring


# 生成Monitor map
# 用规划好的主机名、对应 IP 地址、和 FSID 生成一个监视器图，并保存为
# /etc/ceph/monmap
monmaptool \
	--create --add ${HOSENAME} $CEPH_MASTER_IP \
	--fsid 4299abf0-4901-497a-9bb5-59325a1e757f  /etc/ceph/monmap


# 在监视器主机上分别创建数据目录
mkdir -p /var/lib/ceph/mon/ceph-${HOSENAME}
chown -R ceph.ceph /var/lib/ceph/mon/ceph-${HOSENAME}


# 初始化Monitor的文件系统
ceph-mon --mkfs -i ${HOSENAME} --monmap /etc/ceph/monmap \
 	--keyring /etc/ceph/ceph.mon.keyring

# ls /var/lib/ceph/mon/ceph-${HOSENAME}/

# 检查Ceph 配置文件
# 建一个空文件 done ，表示监视器已创建、可以启动了
touch /var/lib/ceph/mon/ceph-${HOSENAME}/done

# 启动Monitor
ceph-mon --id ${HOSENAME}
ceph mon enable-msgr2

# ssh ${HOSENAME}
# sudo \
# ceph-disk prepare \
# 	--cluster ceph \
# 	--cluster-uuid a7f64266-0894-4f1e-a635-d0aeaca0e993 \
# 	--fs-type ext4 /dev/hdd1

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 添加 OSD

uuidgen
# 4c0a02e2-e577-4778-b775-8b636926bb2d

# 创建OSD
ceph osd create 4c0a02e2-e577-4778-b775-8b636926bb2d

# 创建OSD目录
mkdir -p /var/lib/ceph/osd/ceph-0

# 改权限
chown ceph.ceph /var/lib/ceph/osd/ceph-1

# 格式化OSD磁盘
mkfs.ext4 /dev/mmcblk0p1

# 挂载OSD磁盘
mount /dev/mmcblk0p1 /var/lib/ceph/osd/ceph-0/

# 初始化OSD
ceph-osd -i 0 --mkfs --mkkey --osd-uuid 4c0a02e2-e577-4778-b775-8b636926bb2d

# 注册OSD keyring
ceph auth add osd.0 osd 'allow *' mon 'allow profile osd' -i /var/lib/ceph/osd/ceph-0/keyring

# 把此节点加入 CRUSH 图
ceph osd crush add-bucket ${HOSENAME} host

# 把此 Ceph 节点放入 default 根下
ceph osd crush move ${HOSENAME} root=default

# 把此 OSD 加入 CRUSH 图之后，它就能接收数据了。你也可以反编译 CRUSH 图、
# 把此 OSD 加入设备列表、对应主机作为桶加入（如果它还不在 CRUSH 图里）、
# 然后此设备作为主机的一个条目、分配权重、重新编译、注入集群
ceph osd crush add osd.0 1.0 host=${HOSENAME}

# 要让守护进程开机自启，必须创建一个空文件
sudo touch /var/lib/ceph/osd/ceph-0/sysvinit

# 启动osd
ceph-osd --id 0

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 部署radosgw rgw

# 创建keyring
ceph-authtool --create-keyring /etc/ceph/ceph.client.radosgw.keyring

# 修改文件权限
chown ceph:ceph /etc/ceph/ceph.client.radosgw.keyring

# 生成ceph-radosgw服务对应的用户和key
ceph-authtool /etc/ceph/ceph.client.radosgw.keyring -n client.rgw.${HOSENAME} --gen-key

# 为用户添加访问权限
ceph-authtool -n client.rgw.${HOSENAME} --cap osd 'allow rwx' --cap mon 'allow rwx' /etc/ceph/ceph.client.radosgw.keyring

# 导入keyring到集群中
ceph -k /etc/ceph/ceph.client.admin.keyring auth add client.rgw.${HOSENAME} -i /etc/ceph/ceph.client.radosgw.keyring

# 配置ceph.conf

cat >/etc/ceph/ceph_rgw.conf <<EOF
[client.rgw.${HOSENAME}]

host=${HOSENAME}
keyring=/etc/ceph/ceph.client.radosgw.keyring
log file=/var/log/radosgw/client.radosgw.gateway.log
rgw_s3_auth_use_keystone = False
rgw print continue = False
#rgw_frontends = civetweb port=8080
debug rgw = 0
EOF

# 创建日志目录并修改权限
mkdir -p /var/log/radosgw
chown ceph:ceph /var/log/radosgw

# 启动rgw
# systemctl start ceph-radosgw@rgw.${HOSENAME}
# 或者:
radosgw -c /etc/ceph/ceph_rgw.conf -n client.rgw.${HOSENAME}

# 查看端口监听状态
netstat -antpu | grep 8080

# 设置rgw开机自动启动
# systemctl enable ceph-radosgw@rgw.${HOSENAME}

# 查看7480的数据
# curl http://127.0.0.1:7480
# ceph -s
# netstat -tnlp |grep ceph-mon
# ceph mon enable-msgr2
# netstat -tnlp
# lsblk
# ceph osd lspools
# rbd pool init rbd

# 按照官方说明BLUESTORE方式效率比FILESTORE方式效率更高，对SSD优化良好
ceph-volume lvm create --data /dev/sdb
ceph-volume lvm list
