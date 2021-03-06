author      'Daniel Mendler'
description 'Image information engine'
dependencies 'engine/image'

Engine.create(:imageinfo, :priority => 1, :layout => true, :cacheable => true) do
  def accepts?(page); page.mime.image?; end
  def output(context)
    @page = context.page
    identify = shell_filter("#{Plugin['engine/image'].magick_prefix}identify -format '%m %h %w' -", context.page.content).split(' ')
    @type = identify[0]
    @geometry = "#{identify[1]}x#{identify[2]}"
    @exif = shell_filter('exif -m /dev/stdin 2>&1', context.page.content).split("\n").map {|line| line.split("\t") }
    @exif = nil if !@exif[0] || !@exif[0][1]
    render :imageinfo
  end
end
