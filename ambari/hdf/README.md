## HDF Cluster with Apache Ambari

Getting a cluster running for dev-testing purposes can be tedious, this is an attempt to alleviate the tedium.

After starting the cluster, it is useful to use the gateway container as a SOCKS proxy in order to facilitate browser usage, DNS, etc.

```
Usage:
  ./build.sh NIFI_ARCIVE [NUM_NIFI_NODES]      generate docker-compose config for cluster
  ./clean.sh                                   remove target directory
  ./clean-all.sh                               remove target directory and other resources (e.g. dev-dockerfiles)
```

Example:
```
./build.sh ~/Downloads/nifi-1.0.0-bin.zip
cd target/
docker-compose up -d

# Will ssh into gateway container on Mac and expose localhost:1025 as a SOCKS proxy
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ../ssh-key/id_rsa -p "$(docker port gateway | sed 's/.*://g')" -D 1025 root@"$(docker-machine ip)"
```

From here, just configure your browser (I prefer to use Firefox as my "Docker browser") to use localhost:1025 as a SOCKS proxy with DNS lookup.
