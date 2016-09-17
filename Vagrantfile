require 'yaml'
puppetdev = YAML::load_file("puppetdev_vagrant.config.yaml")
Vagrant.configure(2) do |config|
 config.vm.define "puppetmaster" do |puppetmaster|
  puppetmaster.vm.provider :virtualbox do |c|
   c.memory = 2048 
   c.cpus = 2
   c.gui = true
   c.name = puppetdev['puppetmaster']['hostname'] 
   end
  puppetmaster.vm.box = "debian/jessie64"
  puppetmaster.vm.hostname = puppetdev['puppetmaster']['hostname']
  puppetmaster.vm.network :private_network, ip: "10.0.3.42",
   virtualbox__intnet: "puppetdevnetwork"  
  puppetmaster.ssh.username = 'vagrant'
  puppetmaster.ssh.password = 'vagrant'
  puppetmaster.vm.provision "file", source: "puppetdev_deploykey", destination: "/tmp/id_rsa"
  puppetmaster.vm.provision "file", source: "puppetdev_deploykey.pub", destination: "/tmp/id_rsa.pub"
  puppetmaster.vm.provision "file", source: "puppetmaster.conf", destination: "/tmp/puppet.conf"
  puppetmaster.vm.provision "file", source: "puppet_private_key.pkcs7.pem", destination: "/tmp/private_key.pkcs7.pem"
  puppetmaster.vm.provision "file", source: "puppet_public_key.pkcs7.pem", destination: "/tmp/public_key.pkcs7.pem"
  puppetmaster.vm.provision :shell, inline: <<-SHELL
   sudo mkdir /root/.ssh
   sudo mv /tmp/id_rsa* /root/.ssh
   sudo chown -R root:root /root/.ssh/
   sudo chmod 700 /root/.ssh
   sudo chmod 600 /root/.ssh/id_rsa
   sudo chmod 644 /root/.ssh/id_rsa.pub
   sudo apt-get update
   sudo apt-get install -y --fix-missing net-tools git activemq emacs-nox postgresql mcollective postgresql-contrib ntp ntpdate puppetmaster-passenger augeas-doc mcollective-common augeas-tools ruby-rrd librrd-ruby puppet-el ruby-ldap ruby-stomp stompserver vim-puppet ruby-builder-doc rails ruby-passenger-doc debian-keyring g++-multilib g++-4.9-multilib libstdc++6-4.9-dbg libgmp10-doc libmpfr-dev libstdc++-4.8-doc mcollective-doc doc-base ruby-compass iptables treetop tree gdb strace tcpdump dkms
   sudo service apache2 stop
   sudo gem install hiera-eyaml 
   sudo puppet agent --enable
   sudo echo "10.0.3.42 puppet" >> /etc/hosts
   sudo cp /tmp/puppet.conf /etc/puppet/puppet.conf
   sudo mkdir /var/lib/puppet/keys
   sudo mv /tmp/*.pem /var/lib/puppet/keys/
   sudo chown -R puppet:puppet /var/lib/puppet/keys
   sudo chmod 400 /var/lib/puppet/keys/private_key.pkcs7.pem
   sudo chmod 400 /var/lib/puppet/keys/public_key.pkcs7.pem
   sudo service apache2 start 
   SHELL
 end
 config.vm.define "puppetclient" do |puppetclient|
   puppetclient.vm.provider :virtualbox do |c|
   c.memory = 8192 
   c.cpus = 2
   c.gui = true
   c.name = puppetdev['puppetclient']['hostname'] 
   end
   puppetclient.vm.box  = "debian/jessie64"
   puppetclient.vm.hostname  = puppetdev['puppetclient']['hostname']
   puppetclient.vm.network :private_network, ip:  "10.0.3.43",
     virtualbox__intnet: "puppetdevnetwork"
   puppetclient.ssh.username = 'vagrant'
   puppetclient.ssh.password = 'vagrant' 
   puppetclient.vm.provision "file", source: "puppetclient.conf", destination: "/tmp/puppet.conf"
   puppetclient.vm.provision :shell, inline: <<-SHELL
    sudo apt-get update
    sudo apt-get install -y --fix-missing puppet net-tools emacs-nox 
    puppet agent --enable
    echo "10.0.3.42 puppet" >> /etc/hosts
    sudo cp /tmp/puppet.conf /etc/puppet/puppet.conf
    sudo rm /tmp/puppet.conf
    sudo service puppet stop
    sudo update-rc.d puppet remove
   SHELL
 end   
end
