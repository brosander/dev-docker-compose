#!/usr/bin/env python

import os
import shutil
import xml.etree.ElementTree as ET
from nifi.main import NifiCluster
from collections import OrderedDict
from distutils.dir_util import copy_tree
from docker import Docker
from output import Output
from properties import Properties
from subprocess import Popen, PIPE
from yaml import Yaml

class C2Demo(NifiCluster):
  def __init__(self):
    super(C2Demo, self).__init__()

  def get_compose_data(self):
    result = super(C2Demo, self).get_compose_data()
    services = result['services']
    networks = result['networks']

    services['c2-authoritative'] = OrderedDict([
      ('hostname', 'c2-authoritative'),
      ('image', self.args.c2Image),
      ('ports', [10443]),
      ('volumes', ['./c2-authoritative/:' + self.c2_conf_dir]),
      ('networks', ['cluster'])
    ])

    services['squid-edge1'] = OrderedDict([
      ('image', 'squid-alpine'),
      ('ports', [3128]),
      ('volumes', ['./squid-gateway/:/opt/squid-conf/']),
      ('entrypoint', ['/root/start.sh']),
      ('networks', ['cluster', 'edge1'])
    ])
    
    services['c2-edge1'] = OrderedDict([
      ('hostname', 'c2-edge1'),
      ('image', self.args.c2Image),
      ('ports', [10080]),
      ('volumes', ['./c2-edge1/:' + self.c2_conf_dir]),
      ('networks', ['edge1'])
    ])

    for minifi_edge1_name in self.minifi_edge1_names:
      services[minifi_edge1_name] = OrderedDict([
        ('hostname', minifi_edge1_name),
        ('image', self.args.minifiImage),
        ('volumes', ['./' + minifi_edge1_name + '/:' + self.minifi_conf_dir]),
        ('networks', ['edge1'])
      ])

    networks['edge1'] = OrderedDict([('driver', 'bridge')])

    return result

  def get_parser(self):
    parser = super(C2Demo, self).get_parser()
    parser.add_argument('--c2Image', help="Docker image for C2 server", default='apacheminific2:0.2.0')
    parser.add_argument('--minifiImage', help="Docker image for MiNiFi", default='apacheminifi:0.2.0')
    parser.add_argument('--minifiNodes', help="Number of MiNiFi nodes", type=int, default=5)
    return parser

  def generate_resources(self):
    super(C2Demo, self).generate_resources()

    base_c2 = os.path.join(self.args.output, 'base_c2')
    self.docker.copy(self.args.c2Image, self.c2_conf_dir, base_c2)

    base_minifi = os.path.join(self.args.output, 'base_minifi')
    self.docker.copy(self.args.minifiImage, self.minifi_conf_dir, base_minifi)

    c2_authoritative_dir = os.path.join(self.args.output, 'c2-authoritative')
    copy_tree(base_c2, c2_authoritative_dir, update = 1)
    if self.args.tlsToolkit:
      toolkit_process = Popen([self.args.tlsToolkit, 'standalone', '-n', 'c2-authoritative', '-o', self.args.output, '-O'], stdout = PIPE)
      toolkit_output = toolkit_process.communicate()
      if toolkit_process.returncode != 0:
        raise Exception("TLS toolkit failed: " + toolkit_output[0])
      c2_authoritative_nifi_props_file = os.path.join(c2_authoritative_dir, 'nifi.properties')
      c2_authoritative_nifi_props = Properties(c2_authoritative_nifi_props_file).get_all() 
      Properties(os.path.join(c2_authoritative_dir, 'c2.properties')).update({
        'minifi.c2.server.port': '10443',
        'minifi.c2.server.secure': 'true',
        'minifi.c2.server.keystore': c2_authoritative_nifi_props['nifi.security.keystore'],
        'minifi.c2.server.keystoreType': c2_authoritative_nifi_props['nifi.security.keystoreType'],
        'minifi.c2.server.keystorePasswd': c2_authoritative_nifi_props['nifi.security.keystorePasswd'],
        'minifi.c2.server.keyPasswd': c2_authoritative_nifi_props['nifi.security.keystorePasswd'],
        'minifi.c2.server.truststore': c2_authoritative_nifi_props['nifi.security.truststore'],
        'minifi.c2.server.truststoreType': c2_authoritative_nifi_props['nifi.security.truststoreType'],
        'minifi.c2.server.truststorePasswd': c2_authoritative_nifi_props['nifi.security.truststorePasswd'],
      })
      with open(os.path.join(c2_authoritative_dir, 'authorities.yaml'), 'w') as f:
        Yaml().render(f, OrderedDict([('CN=c2-edge1, OU=NIFI', ['EDGE_1'])]))
      with open(os.path.join(c2_authoritative_dir, 'authorizations.yaml'), 'w') as f:
        Yaml().render(f, OrderedDict([
          ('Default Action', 'deny'),
          ('Paths', OrderedDict([
            ('/c2/config', OrderedDict([
              ('Default Action', 'deny'),
              ('Actions', [
                OrderedDict([
                  ('Authorization', 'EDGE_1'),
                  ('Query Parameters', OrderedDict([
                    ('net', 'edge1'),
                    ('class', 'raspi3')
                  ])),
                  ('Action', 'allow')
                ])
              ])
            ])),
            ('/c2/config/contentTypes', OrderedDict([
              ('Default Action', 'deny'),
              ('Actions', [
                OrderedDict([
                  ('Authorization', 'EDGE_1'),
                  ('Action', 'allow')
                ])
              ])
            ]))
          ]))
        ]))
      os.remove(c2_authoritative_nifi_props_file)

    c2_edge1_dir = os.path.join(self.args.output, 'c2-edge1')
    copy_tree(base_c2, c2_edge1_dir, update = 1)

    nifi_url = 'http://nifi-node1:8080/nifi-api'
    authoritative_url = 'http://c2-authoritative:10080'
    if self.args.tlsToolkit:
      nifi_url = 'https://nifi-node1:9443/nifi-api'
      authoritative_url = 'https://c2-authoritative:10443'

    ET.register_namespace('', 'http://www.springframework.org/schema/beans')

    c2_authoritative_minifi_c2_context_xml = os.path.join(c2_authoritative_dir, 'minifi-c2-context.xml')
    c2_authoritative_minifi_c2_context = ET.parse(c2_authoritative_minifi_c2_context_xml)

    c2_authoritative_list = c2_authoritative_minifi_c2_context.find('.//beans:list', {'beans': 'http://www.springframework.org/schema/beans'})
    c2_authoritative_list.clear()
    c2_authoritative_list.append(ET.fromstring('''
      <bean class="org.apache.nifi.minifi.c2.provider.nifi.rest.NiFiRestConfigurationProvider">
          <constructor-arg>
              <bean class="org.apache.nifi.minifi.c2.cache.filesystem.FileSystemConfigurationCache">
                  <constructor-arg>
                      <value>./cache</value>
                  </constructor-arg>
                  <constructor-arg>
                      <value>${net}/${class}</value>
                  </constructor-arg>
              </bean>
          </constructor-arg>
          <constructor-arg>
              <value>''' + nifi_url + '''</value>
          </constructor-arg>
          <constructor-arg>
              <value>${net}-${class}.v${version}</value>
          </constructor-arg>
      </bean>'''))

    c2_authoritative_config_service = c2_authoritative_minifi_c2_context.find(".//beans:bean[@id='configService']", {'beans': 'http://www.springframework.org/schema/beans'})
    c2_authoritative_config_service.append(ET.fromstring('''
        <constructor-arg>
            <value>1000</value>
        </constructor-arg>
    '''))
    c2_authoritative_config_service.append(ET.fromstring('''
        <constructor-arg>
            <value>3000</value>
        </constructor-arg>
    '''))
    c2_authoritative_minifi_c2_context.write(c2_authoritative_minifi_c2_context_xml)

    c2_edge1_minifi_c2_context_xml = os.path.join(c2_edge1_dir, 'minifi-c2-context.xml')
    c2_edge1_minifi_c2_context = ET.parse(c2_edge1_minifi_c2_context_xml)

    c2_edge1_list = c2_edge1_minifi_c2_context.find('.//beans:list', {'beans': 'http://www.springframework.org/schema/beans'})
    c2_edge1_list.clear()
    c2_edge1_list.append(ET.fromstring('''
      <bean class="org.apache.nifi.minifi.c2.provider.delegating.DelegatingConfigurationProvider">
          <constructor-arg>
              <bean class="org.apache.nifi.minifi.c2.cache.filesystem.FileSystemConfigurationCache">
                  <constructor-arg>
                      <value>./cache</value>
                  </constructor-arg>
                  <constructor-arg>
                      <value>${net}/${class}</value>
                  </constructor-arg>
              </bean>
          </constructor-arg>
          <constructor-arg>
              <bean class="org.apache.nifi.minifi.c2.provider.util.HttpConnector">
                  <constructor-arg>
                      <value>''' + authoritative_url + '''</value>
                  </constructor-arg>
                  <constructor-arg>
                      <value>squid-edge1</value>
                  </constructor-arg>
                  <constructor-arg>
                      <value>3128</value>
                  </constructor-arg>
              </bean>
          </constructor-arg>
      </bean>
    '''))

    c2_edge1_config_service = c2_edge1_minifi_c2_context.find(".//beans:bean[@id='configService']", {'beans': 'http://www.springframework.org/schema/beans'})
    c2_edge1_config_service.append(ET.fromstring('''
        <constructor-arg>
            <value>1000</value>
        </constructor-arg>
    '''))
    c2_edge1_config_service.append(ET.fromstring('''
        <constructor-arg>
            <value>3000</value>
        </constructor-arg>
    '''))
    c2_edge1_minifi_c2_context.write(c2_edge1_minifi_c2_context_xml)
    ET.register_namespace('', '')

    if self.args.tlsToolkit:
      toolkit_process = Popen([self.args.tlsToolkit, 'standalone', '-n', 'c2-edge1', '-o', self.args.output, '-O'], stdout = PIPE)
      toolkit_output = toolkit_process.communicate()
      if toolkit_process.returncode != 0:
        raise Exception("TLS toolkit failed: " + toolkit_output[0])
      c2_edge1_nifi_props_file = os.path.join(c2_edge1_dir, 'nifi.properties')
      c2_edge1_nifi_props = Properties(c2_edge1_nifi_props_file).get_all() 
      Properties(os.path.join(c2_edge1_dir, 'c2.properties')).update({
        'minifi.c2.server.keystore': c2_edge1_nifi_props['nifi.security.keystore'],
        'minifi.c2.server.keystoreType': c2_edge1_nifi_props['nifi.security.keystoreType'],
        'minifi.c2.server.keystorePasswd': c2_edge1_nifi_props['nifi.security.keystorePasswd'],
        'minifi.c2.server.keyPasswd': c2_edge1_nifi_props['nifi.security.keystorePasswd'],
        'minifi.c2.server.truststore': c2_edge1_nifi_props['nifi.security.truststore'],
        'minifi.c2.server.truststoreType': c2_edge1_nifi_props['nifi.security.truststoreType'],
        'minifi.c2.server.truststorePasswd': c2_edge1_nifi_props['nifi.security.truststorePasswd'],
      })
      os.remove(c2_edge1_nifi_props_file)
    shutil.rmtree(base_c2)

    Properties(os.path.join(base_minifi, 'bootstrap.conf')).update({
      'nifi.minifi.notifier.ingestors' : 'org.apache.nifi.minifi.bootstrap.configuration.ingestors.PullHttpChangeIngestor',
      'nifi.minifi.notifier.ingestors.pull.http.hostname': 'c2-edge1',
      'nifi.minifi.notifier.ingestors.pull.http.port': '10080',
      'nifi.minifi.notifier.ingestors.pull.http.path': '/c2/config',
      'nifi.minifi.notifier.ingestors.pull.http.query': 'net=edge1&class=raspi3',
      'nifi.minifi.notifier.ingestors.pull.http.period.ms': '3000'
    })
    for name in self.minifi_edge1_names:
      node_directory = os.path.join(self.args.output, name)
      copy_tree(base_minifi, node_directory, update = 1)
      if self.args.tlsToolkit:
        toolkit_process = Popen([self.args.tlsToolkit, 'standalone', '-n', name, '-o', self.args.output, '-O'], stdout = PIPE)
        toolkit_output = toolkit_process.communicate()
        if toolkit_process.returncode != 0:
          raise Exception("TLS toolkit failed: " + toolkit_output[0])
    shutil.rmtree(base_minifi)

  def handle_cli(self):
    super(C2Demo, self).handle_cli()
    self.minifi_edge1_names = ['minifi-edge1-node' + str(i) for i in range(1, self.args.minifiNodes + 1)]
    self.c2_conf_dir = os.path.dirname(self.docker.find(self.args.c2Image, '*/conf/c2.properties', '/opt', 'f')[0])
    self.minifi_conf_dir = os.path.dirname(self.docker.find(self.args.minifiImage, '*/conf/config.yml', '/opt', 'f')[0])

if __name__ == '__main__':
  C2Demo().generate()
