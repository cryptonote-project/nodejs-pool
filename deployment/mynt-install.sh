#!/bin/bash
echo "This assumes that you are doing a green-field install.  If you're not, please exit in the next 15 seconds."
sleep 15
echo "Continuing install, this will prompt you for your password if you're not already running as root and you didn't enable passwordless sudo.  Please do not run me as root!"
if [[ `whoami` == "root" ]]; then
    echo "You ran me as root! Do not run me as root!"
    exit 1
fi
ROOT_SQL_PASS=
CURUSER=$(whoami)
sudo timedatectl set-timezone Etc/UTC
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $ROOT_SQL_PASS"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $ROOT_SQL_PASS"
echo -e "[client]\nuser=root\npassword=$ROOT_SQL_PASS" | sudo tee /root/.my.cnf
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install git python-virtualenv python3-virtualenv curl ntp build-essential screen cmake pkg-config libboost-all-dev libevent-dev libunbound-dev libminiupnpc-dev libunwind8-dev liblzma-dev libldns-dev libexpat1-dev libgtest-dev mysql-server lmdb-utils libzmq3-dev
cd ~
git clone https://github.com/Venthos/nodejs-pool.git  # Change this depending on how the deployment goes.
cd /usr/src/gtest
sudo cmake .
sudo make
sudo mv libg* /usr/lib/
cd ~
sudo systemctl enable ntp
cd /usr/local/src
sudo git clone https://github.com/altcoincoop/mynt.git
cd mynt
#sudo git checkout master
sudo make -j$(nproc)
sudo cp ~/nodejs-pool/deployment/mynt.service /lib/systemd/system/
sudo useradd -m coindaemon -d /home/coindaemon
BLOCKCHAIN_DOWNLOAD_DIR=$(sudo -u coindaemon mktemp -d)
sudo -u coindaemon wget --limit-rate=50m -O $BLOCKCHAIN_DOWNLOAD_DIR/blockchain.raw https://coinmine.network/blockchain.raw
sudo -u coindaemon /usr/local/src/mynt/build/release/bin/mynt-blockchain-import --input-file $BLOCKCHAIN_DOWNLOAD_DIR/blockchain.raw --batch-size 20000 --database lmdb#fastest --verify off --data-dir /home/coindaemon/.mynt
sudo -u coindaemon rm -rf $BLOCKCHAIN_DOWNLOAD_DIR
sudo systemctl daemon-reload
sudo systemctl enable mynt
sudo systemctl start mynt
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
source ~/.nvm/nvm.sh
nvm install v8.9.3
cd ~/nodejs-pool
nvm use v8.9.3
npm install
npm install -g pm2
openssl req -subj "/C=IT/ST=Pool/L=Daemon/O=Mining Pool/CN=mining.pool" -newkey rsa:2048 -nodes -keyout cert.key -x509 -out cert.pem -days 36500
mkdir ~/pool_db/
sed -r "s/(\"db_storage_path\": ).*/\1\"\/home\/$CURUSER\/pool_db\/\",/" config_example.json > config.json
cd ~
git clone https://github.com/cryptonote-project/poolui.git
cd poolui
npm install
./node_modules/bower/bin/bower update
./node_modules/gulp/bin/gulp.js build
cd build
sudo ln -s `pwd` /var/www
sudo groupadd -g 33 www-data
sudo useradd -g www-data --no-user-group --home-dir /var/www --no-create-home --shell /usr/sbin/nologin --system --uid 33 www-data
cd ~
sudo env PATH=$PATH:`pwd`/.nvm/versions/node/v8.9.3/bin `pwd`/.nvm/versions/node/v8.9.3/lib/node_modules/pm2/bin/pm2 startup systemd -u $CURUSER --hp `pwd`
cd ~/nodejs-pool
sudo chown -R $CURUSER. ~/.pm2
echo "Installing pm2-logrotate in the background!"
pm2 install pm2-logrotate &
mysql -u root --password=$ROOT_SQL_PASS < deployment/base.sql
mysql -u root --password=$ROOT_SQL_PASS pool -e "INSERT INTO pool.config (module, item, item_value, item_type, Item_desc) VALUES ('api', 'authKey', '`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`', 'string', 'Auth key sent with all Websocket frames for validation.')"
mysql -u root --password=$ROOT_SQL_PASS pool -e "INSERT INTO pool.config (module, item, item_value, item_type, Item_desc) VALUES ('api', 'secKey', '`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`', 'string', 'HMAC key for Passwords.  JWT Secret Key.  Changing this will invalidate all current logins.')"
pm2 start init.js --name=api --log-date-format="YYYY-MM-DD HH:mm Z" -- --module=api
bash ~/nodejs-pool/deployment/install_lmdb_tools.sh
cd ~/nodejs-pool/sql_sync/
env PATH=$PATH:`pwd`/.nvm/versions/node/v8.9.3/bin node sql_sync.js
echo "You're setup!  Please read the rest of the readme for the remainder of your setup and configuration.  These steps include: Setting your Fee Address, Pool Address, Global Domain, and the Mailgun setup!"
