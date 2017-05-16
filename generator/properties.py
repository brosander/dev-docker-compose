class Properties(object):
  def __init__(self, props_file):
    self.props_file = props_file

  def update(self, new_properties):
    updated = set([]) 
    lines = []
    with open(self.props_file) as f:
      for line in f.readlines():
        split_line = line.split('=')
        if split_line[0] in new_properties:
          lines.append(split_line[0] + '=' + new_properties[split_line[0]])
          updated.add(split_line[0])
        else:
          lines.append(line.strip())
    with open(self.props_file, 'w') as f:
      f.write('\n'.join(lines))
      f.write('\n')
      for key, value in new_properties.iteritems():
        if key not in updated:
          f.write(key + '=' + value + '\n')

  def get_all(self):
    result = {}
    with open(self.props_file) as f:
      for line in f.readlines():
        split_line = line.split('=', 1)
        if len(split_line) == 2:
          result[split_line[0]] = split_line[1].strip()
    return result
