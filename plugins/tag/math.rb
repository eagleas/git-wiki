author       'Daniel Mendler'
description  'LaTeX rendering (math tags)'
dependencies 'filter/tag'

class Renderer
  include Util

  def initialize
    @loaded = false
  end

  def init
    @loaded ||= load rescue false
  end

  class << self
    attr_accessor :registry

    def get_first(renderers)
      renderers.each do |r|
        r = get(r)
        return r if r
      end
    end

    def get(name)
      renderer = registry[name] || raise("Renderer #{name} not found")
      if Array === renderer
        get_first(renderer)
      elsif String === renderer
        get(renderer)
      elsif renderer.init
        renderer
      end
    end

    def choose(name)
      get(name) || get_first(registry.keys) || raise('No renderer found')
    end
  end
end

class ImaginatorRenderer < Renderer
  def load
    Plugin.load('utils/imaginator')
  end

  def render(code, display)
    name = Plugin['utils/imaginator'].imaginator.enqueue('math', code)
    %{<img src="/_/utils/imaginator/#{name}" alt="#{escape_html code}" class="math #{display}"/>}
  end
end

class RitexRenderer < Renderer
  def load
    require 'ritex'
    true
  end

  def render(code, display)
    Ritex::Parser.new.parse(code)
  end
end

class ItexRenderer < Renderer
  def load
    `itex2MML --version`
  end

  def render(code, display)
    shell_filter("itex2MML --#{display == 'block' ? 'display' : 'inline'}", code.strip)
  end
end

class BlahtexMLRenderer < Renderer
  def load
    `blahtex`
  end

  def render(code, display)
    content = shell_filter('blahtex --mathml', code.strip)
    content =~ %r{<mathml>(.*)</mathml>}m
    '<mathml xmlns="http://www.w3.org/1998/Math/MathML" display="' + display + '">' + $1.to_s + '</mathml>'
  end
end

class BlahtexImageRenderer < Renderer
  def load
    `blahtex`
  end

  def directory
    @directory ||= File.join(Config.cache, 'blahtex').tap {|dir| FileUtils.mkdir_p dir, :mode => 0755 }
  end

  def render(code, display)
    content = shell_filter("blahtex --png --png-directory '#{directory}'", code.strip)
    content =~ %r{<md5>(.*)</md5>}m
    %{<img src="/_/tag/math/blahtex/#{$1}.png" alt="#{escape_html code}" class="math #{display}"/>}
  end
end

Renderer.registry = {
  'imaginator'   => ImaginatorRenderer.new,
  'itex'         => ItexRenderer.new,
  'ritex'        => RitexRenderer.new,
  'blahtexml'    => BlahtexMLRenderer.new,
  'blahteximage' => BlahtexImageRenderer.new,
  'image'        => %w(imaginator blahteximage),
  'mathml'       => %w(blahtexml itex ritex),
}

Tag.define :math do |context, attrs, code|
  raise('Limits exceeded') if code.size > 10240
  mode = attrs['mode'] || context.page.metadata['math'] || 'image'
  Renderer.choose(mode).render(code, attrs['display'] == 'block' ? 'block' : 'inline')
end

class Wiki::Application
  get '/_/tag/math/blahtex/:name', :name => /[\w\.]+/ do
    begin
      send_file File.join(Renderer.get('blahteximage').directory, params[:name])
    rescue => ex
      `convert -pointsize 16 -background transparent "label:#{ex.message}" PNG:-` rescue nil
    end
  end
end
