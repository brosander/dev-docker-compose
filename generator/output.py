#!/usr/bin/env python

import os
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
import shutil
import sys

class Output(object):
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
    return self.args
