from subprocess import Popen, PIPE

class Docker(object):
  def __exec(self, cmd):
    process = Popen(cmd, stdout = PIPE, stderr = PIPE)
    result = process.communicate()
    if process.returncode != 0:
      raise Exception('Error running command ' + str(cmd) + ' stdout: ' + str(result[0]) + ' stderr : ' + str(result[1]))
    return result[0]

  def find(self, image, path, base_dir = '/', typeArg = None):
    cmd = ['docker', 'run', '-ti', '--rm', '--entrypoint', 'find', image, base_dir]
    if typeArg:
      cmd.extend(['-type', typeArg])
    cmd.extend(['-path', path])
    result = self.__exec(cmd)
    return [filename for filename in [ filename.strip() for filename in result.split('\n') ] if len(filename) > 0]

  def copy(self, image, source, dest):
    container_id = self.__exec(['docker', 'create', image]).strip()
    try:
      self.__exec(['docker', 'cp', container_id + ':' + source, dest])
    finally:
      self.__exec(['docker', 'rm', container_id])
