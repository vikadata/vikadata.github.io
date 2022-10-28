#!/bin/bash -v

download_url='https://download.vika.cn/vika/docker-compose/docker-compose.tar.gz'

# --- helper functions for logs ---
info()
{
    echo '[INFO] ' "$@"
}
warn()
{
    echo '[WARN] ' "$@" >&2
}
fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

_has_app(){
  which $1 >/dev/null
  echo $?
}

install_system() {
  #关闭selinux
  has_selinux=$(_has_app getenforce)
  if [ $has_selinux -ne 0 ];then
    setenforce 0
    sed -i 's/SELINUX=enforcing/\SELINUX=permissive/' /etc/selinux/config
  fi

  has_docker=$(_has_app docker)
  if [ $has_docker -ne 0 ];then
    #安装docker && docker-compose
    yum install -y docker> /tmp/install.log
    systemctl start docker
  fi

  ##执行安装,todo
  has_docker_compose=$(_has_app docker-compose)
  if [ $has_docker_compose -ne 0 ];then
    curl -L https://get.daocloud.io/docker/compose/releases/download/2.12.1/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    chmod 755 /usr/local/bin/docker-compose
  fi
}


#安装vika
install_vika() {
   info "install vika" >> /tmp/install.log
   mkdir /data/vika && cd  /data/vika
   wget "${download_url}" -O vika_install.tar.gz
   if [ -f vika_install.tar.gz ];then
      tar -zxvf vika_install.tar.gz
      # test retry  pull
      docker-compose pull >> /tmp/install.log
      sleep 3
      docker-compose pull >> /tmp/install.log
      docker-compose up -d >> /tmp/install.log
   fi
}

## 安装成功后通知
_on_success(){
    num=0
    while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://localhost/api/v1/actuator/health/liveness)" != "200" ]]
    do
          sleep 10
          let num++
          info "等待中，每5秒检查一次，超过15次超时退出，这是：$num："
          # 超过10则退出
          if [ $num -eq 120 ]
          then
            warn "服务启动超时，请手工检查......"
            exit 1
          fi
    done
    ##
}

install_system
install_vika

info "install ok" >> /tmp/install.log
