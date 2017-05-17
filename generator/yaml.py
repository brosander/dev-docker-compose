class Yaml(object):
  def render(self, f, data):
    self.__render(data, '', f)

  def _print(self, data, f):
    f.write(data)
    f.write('\n')

  def __render(self, data, prefix, f):
    if hasattr(data, 'iteritems'):
      for key, value in data.iteritems():
        if hasattr(value, 'iteritems') or hasattr(value, '__iter__'):
          if len(value) > 0:
            self._print(prefix + key + ':', f)
            self.__render(value, ''.join([' ' for i in range(len(prefix) + 2)]), f)
          elif hasattr(value, 'iteritems'):
            self._print(prefix + key + ': {}', f)
          else:
            self._print(prefix + key + ': []', f)
        else:
          self._print(prefix + key + ': ' + str(value), f)
        prefix = ''.join([' ' for i in range(len(prefix))])
    elif hasattr(data, '__iter__'):
      for item in data:
        self.__render(item, ''.join([' ' for i in range(len(prefix))]) + '- ', f)
    else:
      self._print(prefix + str(data), f)
