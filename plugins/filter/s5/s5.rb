author       'Daniel Mendler'
description  'S5 presentation filter'
dependencies 'filter/xslt'

Application.assets 'ui/**/*', 'ui/default/*'

class S5 < XSLT
  def initialize(options)
    super(:stylesheet => 's5/s5.xsl')
  end

  def params
    themes = Dir.glob(File.join(File.dirname(__FILE__), 'ui', '*')).map {|name| File.basename(name) }
    themes.delete('common')
    themes.delete('default')
    super.merge(:themes => 'default ' + themes.join(' '), :s5_path => '/_/filter/s5/')
  end
end

Filter.register :s5, S5
