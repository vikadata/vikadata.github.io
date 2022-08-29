# -*- mode: ruby -*-
# vi: set ft=ruby :


Vagrant.configure("2") do |config|
#  if Vagrant.has_plugin?("vagrant-cachier")
#     config.cache.scope = :box
#  end
  config.vm.box = "centos/7"
  config.vm.box_check_update = false
  config.vm.network "forwarded_port", guest: 80, host: 80
  config.vm.network "forwarded_port", guest: 6443, host: 6443
  config.vm.network "public_network", bridge: "enp88s0"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.memory = 10240
    vb.cpus = 8
  end
  config.vm.provision "shell", inline: <<-SHELL
    echo "sudo su -" >> .bashrc
    # sh /tmp/vika/prepare_deploy.sh
  SHELL
end
