# -*- coding: utf-8 -*-
module Wiki
  module BlockHelper
    def blocks
      @blocks ||= Hash.with_indifferent_access('')
    end

    def define_block(name, content = nil, &block)
      blocks[name] = block ? capture_haml(&block) : content
    end

    def footnote(content = nil, &block); define_block(:footnote, content, &block); end
    def title(content = nil, &block);    define_block(:title, content, &block);    end
  end

  module FlashHelper
    include Util

    class Flash < Hash
      def error(msg); (self[:error] ||= []) << msg; end
      def warn(msg);  (self[:warn]  ||= []) << msg; end
      def info(msg);  (self[:info]  ||= []) << msg; end
    end

    def flash
      session[:flash] ||= Flash.new
    end

    def flash_messages
      if !flash.empty?
        builder do
          ul do
            flash.each do |level, list|
              list.each do |msg|
                li msg, :class => level
              end
            end
            flash.clear
          end
        end
      end
    end
  end

  module PageHelper
    include Util

    def pagination(resource, pages, curpage, opts)
      if pages > 0
        builder do
          ul.pagination {
            if curpage > 0
              li { a '«', :href => resource_path(resource, opts.merge(:curpage => 0)) }
              li { a '‹', :href => resource_path(resource, opts.merge(:curpage => curpage - 1)) }
            end
            min = curpage - 3
            max = curpage + 3
            if min > 0
              min -= max - pages if max > pages
            else
              max -= min if min < 0
            end
            max = [max, pages].min
            min = [min, 0].max
            li '…' if min != 0
            (min..max).each do |i|
              li {
                if i == curpage
                  a.current i + 1, :href => '#'
                else
                  a i + 1, :href => resource_path(resource, opts.merge(:curpage => i))
                end
              }
            end
            li '…' if max != pages
            if curpage < pages
              li { a '›', :href => resource_path(resource, opts.merge(:curpage => curpage + 1)) }
              li { a '»', :href => resource_path(resource, opts.merge(:curpage => pages)) }
            end
          }
        end
      end
    end

    def theme_links
      default = File.basename(File.readlink(File.join(Config.app_path, 'static', 'themes', 'default')))
      Dir.glob(File.join(Config.app_path, 'static', 'themes', '*', 'style.css')).map do |file|
        name = File.basename(File.dirname(file))
        next if name == 'default'
        %{<link rel="#{name == default ? '' : 'alternate '}stylesheet"
          href="/static/themes/#{name}/style.css" type="text/css" title="#{name}"/>}.unindent
      end.compact.join("\n")
    end

    def format_patch(patch, opts = {})
      lines = patch.split("\n")
      html, path, header, last = '', nil, true, nil
      files, count = [], 0
      lines.each do |line|
        case line
        when %r{^diff ([\w\-\s]+?) "?a/(.+?)"? "?b/(.+?)"?$}
          path = unescape_backslash($2)
          count += 1
          header = true
        when /^\+\+\+/
          html << '</span>' if last
          last = nil
          html << '</td></tr></tbody></table>' if !html.empty?
          if path
            html << %{<table class="changes" id="file-#{count}">}
            if opts[:from] && opts[:to]
              html << %{<thead><tr><th>
                          <a class="left" href="#{escape_html path.urlpath}">#{path}</a>
                          <span class="right">
                            <a href="#{escape_html((path/'version'/opts[:from]).urlpath)}">#{opts[:from].short}</a> to
                            <a href="#{escape_html((path/'version'/opts[:to]).urlpath)}">#{opts[:to].short}</a>
                          </span>
                         </th></tr></thead>}.unindent
            else
              html << %{<thead><tr><th><a class="left" href="#{escape_html path.urlpath}">#{escape_html path}</a></th></tr></thead>}
            end
          else
            html << %{<table class="changes">}
          end
          html << %{<tbody><tr><td>}
        when /^(new|deleted)/
          files << [$1, path, count]
        else
          ch = line[0..0]
          if header
            header = false if ch == '@'
          else
            case ch
            when '@'
              html << '</span>' if last
              html << '</td></tr><tr><td>'
              last = nil
            when /-|\+| /
              html << '</span>' if last && last != ch
              html << "<span#{{'-' => ' class="minus"', '+' => ' class="plus"'}[ch]}>" if last != ch
              html << (line.length > 1 ? escape_html(line[1..-1]) : '&#160;') << "\n"
              last = ch
            end
          end
        end
      end
      html << '</span>' if last
      html << '</td></tr></tbody></table>' if !html.empty?
      if files.empty?
        html
      else
        result = '<ul class="files">'
        files.each do |clazz, name, id|
          result << %{<li class="#{clazz}"><a href="#file-#{id}">#{escape_html name}</a></li>}
        end
        result << '</ul>' << html
      end
    end

    def date(t)
      %{<span class="date epoch-#{t.to_i}">#{t.strftime('%d %h %Y %H:%M')}</span>}
    end

    def breadcrumbs(resource)
      path = resource.try(:path) || ''
      builder do
        li.first.breadcrumb(:class => '' == path ? 'last' : '') {
          a Wiki::Config.root_path, :accesskey=>'z', :class => 'root', :href => resource_path(resource, :path => '/')
        }
        path.split('/').inject('') do |parent,elem|
          li.breadcrumb '/'
          current = parent/elem
          li.breadcrumb(:class => current == path ? 'last' : '') {
            a elem, :href => resource_path(resource, :path => current.urlpath)
          }
          current
        end
      end
    end

    def resource_path(resource, opts = {})
      version = opts.delete(:version) || (resource && !resource.current? && resource.tree_version) || ''
      if path = opts.delete(:path)
        if !path.begins_with? '/'
          path = resource.page? ? resource.path/'..'/path : resource.path/path
        end
      else
        path = resource.path
      end
      path = (version.blank? ? path : path/'version'/version).urlpath
      path << '?' << build_query(opts) if !opts.empty?
      path
    end

    def action_path(path, action)
      path = path.try(:path) || path
      (path.to_s/action.to_s).urlpath
    end

    def edit_content(page)
      if params[:content]
        params[:content]
      elsif page.content.respond_to?(:encoding) && page.content.encoding != __ENCODING__
	:error_binary.t(:page => page.path, :type => "#{page.mime.comment} (#{page.mime})")
      else
        page.content(params[:pos], params[:len])
      end
    end
  end

  module HttpHelper
    include Util

    # Cache control for resource
    def cache_control(opts)
      return if !Config.production?

      if opts[:no_cache]
        response.headers.delete('ETag')
        response.headers.delete('Last-Modified')
        response['Cache-Control'] = 'no-cache'
        return
      end

      last_modified = opts.delete(:last_modified)
      modified_since = env['HTTP_IF_MODIFIED_SINCE']
      last_modified = last_modified.try(:to_time) || last_modified
      last_modified = last_modified.try(:httpdate) || last_modified

      if logged_in?
        # Always private mode if user is logged in
        opts[:private] = true

        # Special etag for authenticated user
        opts[:etag] = md5("#{user.name}#{opts[:etag]}") if opts[:etag]
      end

      if opts[:etag]
        value = '"%s"' % opts.delete(:etag)
        response['ETag'] = value.to_s
        response['Last-Modified'] = last_modified if last_modified
        if etags = env['HTTP_IF_NONE_MATCH']
          etags = etags.split(/\s*,\s*/)
          # Etag is matching and modification date matches (HTTP Spec §14.26)
          halt(304) if (etags.include?(value) || etags.include?('*')) && (!last_modified || last_modified == modified_since)
        end
      elsif last_modified
        # If-Modified-Since is only processed if no etag supplied.
        # If the etag match failed the If-Modified-Since has to be ignored (HTTP Spec §14.26)
        response['Last-Modified'] = last_modified
        halt(304) if last_modified == modified_since
      end

      opts[:public] = !opts[:private]
      opts[:max_age] ||= 0
      opts[:must_revalidate] ||= true if !opts.include?(:must_revalidate) && !opts[:proxy_revalidate]

      response['Cache-Control'] = opts.map do |k, v|
        if v == true
          k.to_s.tr('_', '-')
        elsif v
          v = 31536000 if v.to_s == 'static'
          "#{k.to_s.tr('_', '-')}=#{v}"
        end
      end.compact.join(', ')
    end

    def content_type(type, params={})
      type = type.to_s
      if params.any?
        params = params.collect { |kv| "%s=%s" % kv }.join(', ')
        response['Content-Type'] = [type, params].join(";")
      else
        response['Content-Type'] = type
      end
    end

    def send_file(file, opts = {})
      content_type(opts[:content_type] || MimeMagic.by_extension(File.extname(file)) || 'application/octet-stream')
      if opts[:disposition] == 'attachment' || opts[:filename]
        response['Content-Disposition'] = 'attachment; filename="%s"' % (opts[:filename] || File.basename(file))
      elsif opts[:disposition] == 'inline'
        response['Content-Disposition'] = 'inline'
      end
      response['Content-Length'] ||= File.stat(file).size.to_s
      halt BlockFile.open(file, 'rb')
    rescue Errno::ENOENT => ex
      @logger.error(ex) if @logger
      raise Wiki::Routing::NotFound(file)
    end
  end

  module ApplicationHelper
    include BlockHelper
    include FlashHelper
    include PageHelper
    include HttpHelper

    attr_setter :on_error, :redirect_to_new

    def tab(name, &block)
      "<li#{action?(name) ? ' class="tabs-selected"' : ''}>#{capture_haml(&block)}</li>"
    end

    def action?(name)
      if params[:action]
        params[:action] == name.to_s
      else
        unescape(request.path_info).ends_with? '/' + name.to_s
      end
    end

    def session
      env['rack.session'] ||= {}
    end

    def render(name, opts = {})
      layout = opts.delete(:layout)
      output = super(name, opts)
      if layout != false
        doc = Nokogiri::XML(super(:layout, opts) { output })
        invoke_hook :layout, name, doc
        output = doc.to_xhtml(:encoding => 'UTF-8')
      end
      output
    end

    def logged_in?
      user && !user.anonimous?
    end
  end

  module Assets
    def self.extended(base)
      base.class_eval do
        get "/_/:file", :file => /.*/ do
          if path = self.class.asset_paths[params[:file]]
            cache_control :last_modified => File.mtime(path), :max_age => :static
            send_file path
          else
            pass
          end
        end
      end
    end

    def asset_paths
      @asset_paths ||= {}
    end

    def assets(*files)
      name = File.dirname(Plugin.current.name)
      dir = File.dirname(Plugin.current.file)
      files.each do |file|
        Dir[File.join(dir, file)].each do |path|
          asset_paths[name/path[dir.length+1..-1]] = path if File.file?(path)
        end
      end
    end
  end
end
