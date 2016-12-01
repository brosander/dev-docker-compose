## HDF Cluster with Apache Ambari

Getting a cluster running for dev-testing purposes can be tedious, this is an attempt to alleviate the tedium.

After starting the cluster, it is useful to use the gateway container as a SOCKS proxy in order to facilitate browser usage, DNS, etc.

```
usage: ./build.sh -m mpack_dir -p pub_key_file [-n num_target_nodes] [-a] [-h]
       -h or --help                    print this message and exit
       -a or --ambariUrl               URL of ambari repo (default: http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.4.0.1/ambari.repo)
       -m or --mpackUrl                URL of Mpack to download, only used if no mpack dir present (default: http://public-repo-1.hortonworks.com/HDF/centos6/2.x/updates/2.0.0.0/tars/hdf_ambari_mp/hdf-ambari-mpack-2.0.0.0-579.tar.gz)
       -n or --numNodes                number of hdf nodes (default: 3)
       -s or --suffix                  Image suffix for built images (default: _compose)
```

Example:
```
./build.sh
cd target/
./startup.sh

# Will ssh into gateway container on Mac and expose localhost:1025 as a SOCKS proxy
./socks.sh start
```

From here, just configure your browser (I prefer to use Firefox as my "Docker browser") to use localhost:1025 as a SOCKS proxy with DNS lookup.


Convenience scripts:

snapshot.sh - Pauses cluster containers, commits their filesystem to images, and then unpauses them.
restore.sh - Kills and removes cluster containers, restores a previously created set of snapshot images, starts cluster containers.
socks.sh - Manages socks proxy.
