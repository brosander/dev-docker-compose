#!/usr/bin/env python

import os
import shutil

from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from collections import OrderedDict

class Generator(object):
  def render(self, output_filename):
    data = self.get_compose_data()
    if not data:
      return
    with open(output_filename, 'w') as f:
      self.__print("version: '3'", f)
      self.__print("", f)
      self.__render(data, '', f)

  def get_compose_data(self):
    return None

  def __print(self, data, f):
    f.write(data)
    f.write('\n')

  def __render(self, data, prefix, f):
    if hasattr(data, 'iteritems'):
      for key, value in data.iteritems():
        if hasattr(value, 'iteritems') or hasattr(value, '__iter__'):
          if len(value) > 0:
            self.__print(prefix + key + ':', f)
            self.__render(value, ''.join([' ' for i in range(len(prefix) + 2)]), f)
          elif hasattr(value, 'iteritems'):
            self.__print(prefix + key + ': {}', f)
          else:
            self.__print(prefix + key + ': []', f)
        else:
          self.__print(prefix + key + ': ' + str(value), f)
    elif hasattr(data, '__iter__'):
      for item in data:
        self.__render(item, ''.join([' ' for i in range(len(prefix))]) + '- ', f)
    else:
      self.__print(prefix + str(data), f)

  def generate(self):
    self.handle_cli()
    self.render(os.path.join(self.args.output, 'docker-compose.yml'))

  def get_parser(self):
    parser = ArgumentParser(description = 'Utility to generate docker-compose files and associated resources for dev-testing clustered things.',
        formatter_class=lambda prog: ArgumentDefaultsHelpFormatter(prog, width=120))
    parser.add_argument("-f", "--force", help="Force generation even if directory already exists", action='store_true', default = False)
    parser.add_argument("-o", "--output", help="Directory to write output to", default=os.path.join(os.getcwd(), 'default'))
    return parser

  def handle_cli(self):
    base_dir = os.path.dirname(os.path.realpath(__file__))
    templates = os.path.join(base_dir, 'templates')

    self.args = self.get_parser().parse_args()

    if os.path.exists(self.args.output):
      if self.args.force:
        if os.path.exists(os.path.join(self.args.output, '.dev_docker_compose_autogen_marker')):
          shutil.rmtree(self.args.output)
        else:
          raise Exception("Refusing to delete directory that wasn't created by us.  Please manually delete " + self.args.output + " if you want to use it.")
      else:
        raise Exception("Output directory " + self.args.output + " exists already and -f is not set.")

    os.makedirs(self.args.output)
    with open(os.path.join(self.args.output, '.dev_docker_compose_autogen_marker'), 'w') as f:
      f.write("This is a marker file so later invocations with -f will know this directory is safe to delete.\n")
