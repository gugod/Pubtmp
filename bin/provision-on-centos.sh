yum update -y
# yum groupinstall -y "Development Tools"
yum install -y git rsync bzip2 tmux gcc libjpeg-devel libpng-devel

export PERLBREW_ROOT="/usr/local/perlbrew"
mkdir -p $PERLBREW_ROOT

curl -L https://install.perlbrew.pl -o install_perlbrew.sh &&
sh -x install_perlbrew.sh

source ${PERLBREW_ROOT}/etc/bashrc

perlbrew install -n -j4 --as v24 perl-5.24.1
perlbrew use v24
perlbrew install-cpanm
