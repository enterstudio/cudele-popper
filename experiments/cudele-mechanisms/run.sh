#!/bin/bash
# This file should contain the series of steps that are required to execute 
# the experiment. Any non-zero exit code will be interpreted as a failure
# by the 'popper check' command.
set -ex

rm -fr results || true

# if you know Ansible and Docker, the below should make sense
# - we attach ceph-ansible to root because they expect us to be in that dir
SITE=`cat vars.yml | grep "site: " | grep -v "#" | awk '{print $2}'`
ROOT=`dirname $PWD | xargs dirname`
NETW="--net host -v $HOME/.ssh:/root/.ssh"
DIRS="-v `pwd`:/popper \
      -v $ROOT/ansible/ceph:/root \
      -v $ROOT/ansible/srl:/popper/ansible/roles/srl \
      -w /root "
ANSB="-v `pwd`/ansible/group_vars/:/root/group_vars \
      -v `pwd`/hosts:/etc/ansible/hosts \
      -v `pwd`/ansible/ansible.cfg:/etc/ansible/ansible.cfg \
      -e ANSIBLE_CONFIG=/etc/ansible/ansible.cfg"
CODE="-v `pwd`/ansible/ceph.yml:/root/ceph.yml \
      -v `pwd`/ansible/monitor.yml:/root/monitor.yml"
WORK="-v `pwd`/ansible/workloads:/workloads"
ARGS="--forks 50 --skip-tags package-install,with_pkg"
VARS="-e @/popper/vars.yml \
      -e @/popper/ansible/vars.yml \
      -i /etc/ansible/hosts"
DOCKER="docker run -it --rm $NETW $DIRS $ANSB $CODE $WORK michaelsevilla/ansible $ARGS $VARS"

# debug mode
if [ ! -z $1 ]; then
  docker run -it --rm $NETW $DIRS $ANSB $CODE $WORK --entrypoint=ansible michaelsevilla/ansible $VARS $@
  exit
fi

cp configs_$SITE/hosts hosts
for run in 0 1 2; do
  for nfiles in 100000; do
    for stream in "stream" "nostream"; do
      mkdir -p results/${nfiles}/logs || true
      cp configs_cloudlab/${stream}.yml ansible/group_vars/all
      ./teardown.sh
      $DOCKER -e nfiles=$nfiles -e stream=$stream ceph.yml /workloads/journal-rpcs.yml
      ./teardown.sh
      $DOCKER -e nfiles=$nfiles -e stream=$stream ceph.yml /workloads/journal-vapply.yml
    done
  done
  mv results results-$SITE-$stream-run$run
done

exit 0
