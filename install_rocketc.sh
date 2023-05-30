#!/bin/bash
set -e

function check_package() {
    dpkg -s "$1" >/dev/null 2>&1
}

function check_command() {
    command -v "$1" >/dev/null 2>&1
}

function install_package() {
    if check_package "$1"; then
        echo "$1 já está instalado."
    else
        echo "Instalando $1..."
        sudo apt-get -y install "$1"
        echo "Instalação de $1 concluída."
    fi
}

function install_global_npm_package() {
    if check_command "$1"; then
        echo "$1 já está instalado."
    else
        echo "Instalando $1..."
        sudo npm install -g "$1"
        echo "Instalação de $1 concluída."
    fi
}

if ! check_command sudo; then
    echo "Erro: 'sudo' não encontrado. Este script deve ser executado com privilégios de sudo."
    exit 1
fi

echo "Atualizando os pacotes do sistema..."
sudo apt-get -y update
echo "Atualização concluída."

install_package "gnupg"

echo "Importando chave GPG do MongoDB..."
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-4.4.gpg --dearmor
echo "Chave GPG importada."

echo "Adicionando repositório do MongoDB..."
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
echo "Repositório adicionado."

echo "Atualizando os pacotes do sistema novamente..."
sudo apt-get -y update
echo "Atualização concluída."

install_package "build-essential"
install_package "mongodb-org"
install_package "graphicsmagick"
install_package "curl"

echo "Instalando o Node Version Manager (NVM)..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 12.18.4
nvm alias default 12.18.4
nvm use default
echo "Node.js 12.18.4 instalado."

echo "Verificando a versão do Node.js..."
node_version=$(node -v)
if [ "$node_version" = "v12.18.4" ]; then
    echo "Node.js 12.18.4 instalado com sucesso."
else
    echo "Erro: Node.js 12.18.4 não foi instalado corretamente."
    exit 1
fi

echo "Baixando o Rocket.Chat..."
cd /opt
curl -L https://releases.rocket.chat/3.0.0 -o rocket.chat.tgz
tar -xzf rocket.chat.tgz

if [ -d "/opt/bundle" ]; then
    echo "Pasta bundle criada corretamente."
else
    echo "Erro: Pasta bundle não encontrada. Verifique o processo de descompactação."
    exit 1
fi

echo "Rocket.Chat instalado."

if [ -d "/opt/bundle" ]; then
    echo "Pasta bundle criada corretamente."
else
    echo "Erro: Pasta bundle não encontrada. Verifique o processo de descompactação."
    exit 1
fi

sudo chown -R $USER:$USER /opt/bundle

chmod +x "$(command -v node)"

cd bundle/programs/server

echo "Instalando as dependências do Rocket.Chat..."
sudo env PATH="$PATH" $(command -v npm) install --production
echo "Dependências do Rocket.Chat instaladas."

if [ -d "/opt/Rocket.Chat" ]; then
    echo "Diretório Rocket.Chat já existe."
else
    echo "Movendo instalação para o diretório final..."
    mv /opt/bundle /opt/Rocket.Chat
    echo "Instalação movida."
fi

if ! id -u rocketchat >/dev/null 2>&1; then
    echo "Criando usuário rocketchat..."
    sudo useradd -M rocketchat
    echo "Usuário rocketchat criado."
else
    echo "Usuário rocketchat já existe."
fi

if [ -d "/opt/Rocket.Chat" ]; then
    echo "Definindo as permissões para o diretório Rocket.Chat..."
    sudo chown -R rocketchat:rocketchat /opt/Rocket.Chat
    echo "Permissões definidas."
else
    echo "Erro: Diretório Rocket.Chat não encontrado."
    exit 1
fi

cat << EOF | sudo tee -a /lib/systemd/system/rocketchat.service 
[Unit]
Description=The Rocket.Chat server
After=network.target remote-fs.target nss-lookup.target nginx.service mongod.service mongod.target

[Service]
ExecStart=/root/.nvm/versions/node/v12.18.4/bin/node /opt/Rocket.Chat/main.js
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=rocketchat
#User=rocketchat
Environment=ROOT_URL=http://localhost:3000
Environment=PORT=3000
Environment=MONGO_URL=mongodb://localhost:27017/rocketchat?replicaSet=rs01
Environment=MONGO_OPLOG_URL=mongodb://localhost:27017/local?replicaSet=rs01

[Install]
WantedBy=multi-user.target
EOF

echo "Configurando o MongoDB..."
sudo sed -i "s/^#  engine:/  engine: wiredTiger/" /etc/mongod.conf
sudo sed -i "s/^#replication:/replication:\n  replSetName: rs01/" /etc/mongod.conf

echo "Iniciando o serviço do MongoDB..."
sudo systemctl enable --now mongod

echo "Iniciando o MongoDB..."
sudo systemctl start mongod

sleep 15

echo "Inicializando replica set do MongoDB..."
mongo --eval "printjson(rs.initiate())"

echo "Iniciando o serviço do Rocket.Chat..."
sudo systemctl enable --now rocketchat
sudo systemctl start rocketchat

echo "Instalação concluída com sucesso!"
echo "Verificando o status do serviço MongoDB..."

if systemctl is-active --quiet mongod; then
    echo "Serviço MongoDB está ativo."
else
    echo "Erro: Serviço MongoDB não está ativo."
    exit 1
fi

echo "Verificando o status do serviço Rocket.Chat..."
if systemctl is-active --quiet rocketchat; then
    echo "Serviço Rocket.Chat está ativo."
else
    echo "Erro: Serviço Rocket.Chat não está ativo."
    exit 