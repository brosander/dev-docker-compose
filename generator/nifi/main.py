#!/usr/bin/env python

import jinja2
import os
import shutil
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict
from distutils.dir_util import copy_tree
from docker import Docker
from generate import Generator
from output import Output
from properties import Properties
from subprocess import Popen, PIPE

class NifiCluster(Generator):
  def __init__(self):
    self.docker = Docker()

  def get_compose_data(self):
    services = [
      ('squid-gateway', OrderedDict([
        ('image', 'squid-alpine'),
        ('ports', [3128]),
        ('volumes', ['./squid-gateway/:/opt/squid-conf/']),
        ('entrypoint', ['/root/start.sh']),
        ('networks', ['cluster'])
      ]))]
    if self.args.tlsToolkit:
      services.append(('ldap', OrderedDict([
          ('hostname', 'ldap'),
          ('image', 'dinkel/openldap'),
          ('environment', OrderedDict([
            ('SLAPD_DOMAIN', 'nifi.apache.org'),
            ('SLAPD_PASSWORD', self.args.slapdPassword)
          ])),
          ('ports', [389]),
          ('volumes', ['./ldap/:/etc/ldap.dist/prepopulate/']),
          ('networks', ['cluster'])
        ])))
    for name in self.nifi_names:
      services.append((name, OrderedDict([
        ('hostname', name),
        ('image', self.args.nifiImage),
        ('ports', [9443]),
        ('volumes', ['./' + name + ':' + self.nifi_conf_dir]),
        ('networks', ['cluster'])
      ])))
    return OrderedDict([
      ('services', OrderedDict(services)),
      ('networks', OrderedDict([
        ('cluster', OrderedDict([('driver', 'bridge')]))
      ]))
    ])

  def get_parser(self):
    parser = super(NifiCluster, self).get_parser()
    parser.add_argument('-t', '--tlsToolkit', help="Tls toolkit command for certificate generation. Ex: ~/Downloads/nifi-toolkit/bin/tls-toolkit.sh")
    parser.add_argument('--slapdPassword', help="The slapd password (default: RANDOMLY_GENERATED)")
    parser.add_argument('--adminPassword', help="Password for admin ldap user", default="admin-password")
    parser.add_argument('--ldapuser', help="Username and optional password separted by colon.  If password not specified will default to USERNAME-password", default=['user1', 'user2', 'user3'], action="append")
    parser.add_argument('--nifiNodes', help="Number of nifi nodes", type=int, default=3)
    parser.add_argument('--nifiImage', help="Docker image for NiFi", default='apachenifi:1.2.0')
    return parser

  def generate_resources(self):
    templates_dir = os.path.join(os.path.dirname(__file__), 'templates')
    jinja_environment = jinja2.Environment(loader=jinja2.FileSystemLoader(templates_dir))
    copy_tree(os.path.join(os.path.dirname(__file__), 'support'), self.args.output)

    for subdir, dirs, files in os.walk(templates_dir):
      for filename in files:
        fname = os.path.join(subdir, filename)
        with open(fname, 'a'):
          os.utime(fname, None)

    for subdir, dirs, files in os.walk(self.args.output):
      for filename in files:
        fname = os.path.join(subdir, filename)
        with open(fname, 'a'):
          os.utime(fname, None)

    basenode = os.path.join(self.args.output, 'basenode')
    self.docker.copy(self.args.nifiImage, self.nifi_conf_dir, basenode)
    nifi_overlay = os.path.join(self.args.output, 'nifi')
    copy_tree(nifi_overlay, basenode)
    shutil.rmtree(nifi_overlay)

    if self.args.tlsToolkit:
      ldap = os.path.join(self.args.output, 'ldap')
      os.makedirs(ldap)
      users = []
      for user in self.args.ldapuser:
        split_user = user.split(':', 1)
        if len(split_user) == 1:
          users.append({'name': user, 'password': user + '-password'})
        else:
          users.append({'name': split_user[0], 'password': split_user[1]})
      with open(os.path.join(ldap, 'users.ldif'), 'w') as f:
        f.write(jinja_environment.get_template('ldap/users.ldif').render({
          'admin_password': self.args.adminPassword,
          'users': users
        }))

    zookeeper_connect_string = ','.join([name + ':2181' for name in self.nifi_names])

    state_management_xml = os.path.join(basenode, 'state-management.xml')
    state_management = ET.parse(state_management_xml)
    state_management.find('cluster-provider').find(".//property[@name='Connect String']").text = zookeeper_connect_string
    state_management.write(state_management_xml)

    authorizers_xml = os.path.join(basenode, 'authorizers.xml')
    authorizers = ET.parse(authorizers_xml)
    authorizer = authorizers.find('authorizer')
    authorizer.find(".//property[@name='Initial Admin Identity']").text = 'admin'
    for index, name in enumerate(self.nifi_names):
      ET.SubElement(authorizer, 'property', {'name': 'Node Identity ' + str(index + 1)}).text = 'CN=' + name + ', OU=NIFI'
    authorizers.write(authorizers_xml)

    Properties(os.path.join(basenode, 'nifi.properties')).update({
      'nifi.security.user.login.identity.provider': 'ldap-provider',
      'nifi.security.identity.mapping.pattern.dn': '^uid=(.*?),ou=people,dc=nifi,dc=apache,dc=org$',
      'nifi.security.identity.mapping.value.dn': '$1',
      'nifi.security.identity.mapping.pattern.cert': '^CN=(.*?), OU=NIFI$',
      'nifi.security.identity.mapping.value.cert': '$1',
      'nifi.cluster.is.node': 'true',
      'nifi.cluster.node.protocol.port': '9001',
      'nifi.state.management.embedded.zookeeper.start': 'true',
      'nifi.cluster.flow.election.max.candidates': '3',
      'nifi.zookeeper.connect.string': zookeeper_connect_string
    })

    zk_props = OrderedDict([
      ('dataDir', './conf/state/zookeeper')
    ])
    for index, name in enumerate(self.nifi_names):
      zk_props['server.' + str(index + 1)] = name + ':2888:3888'
    Properties(os.path.join(basenode, 'zookeeper.properties')).update(zk_props)
    
    for index, name in enumerate(self.nifi_names):
      nodedir = os.path.join(self.args.output, name)
      shutil.copytree(basenode, nodedir)
      node_nifi_props = os.path.join(nodedir, 'nifi.properties')
      Properties(node_nifi_props).update({
        'nifi.web.http.host': name,
        'nifi.cluster.node.address': name,
        'nifi.remote.input.socket.host': name
      })
      zk_state_dir = os.path.join(nodedir, 'state', 'zookeeper')
      os.makedirs(zk_state_dir)
      with open(os.path.join(zk_state_dir, 'myid'), 'w') as f:
        f.write(str(index + 1) + '\n')
      if self.args.tlsToolkit:
        toolkit_process = Popen([self.args.tlsToolkit, 'standalone', '-f', node_nifi_props, '-n', name, '-o', self.args.output, '-O'], stdout = PIPE)
        toolkit_output = toolkit_process.communicate()
        if toolkit_process.returncode != 0:
          raise Exception("TLS toolkit failed: " + toolkit_output[0])

    shutil.rmtree(basenode)

  def handle_cli(self):
    super(NifiCluster, self).handle_cli()
    self.nifi_names = ['nifi-node' + str(i) for i in range(1, self.args.nifiNodes + 1)]
    self.nifi_conf_dir = os.path.dirname(self.docker.find(self.args.nifiImage, '*/conf/nifi.properties', '/opt', 'f')[0])
    self.generate_resources()

if __name__ == '__main__':
  NifiCluster().generate()
