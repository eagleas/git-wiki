# -*- coding: utf-8 -*-
module Wiki
  # Main class of the application
  class Application
    include Util
    include Routing
    include Templates
    include ApplicationHelper
    extend Assets

    patterns :path => Resource::PATH_PATTERN
    attr_reader :logger, :user

    def user=(user)
      @user = user
      logged_in? ? session[:user]=user : session.delete(:user)
    end

    def initialize(app = nil, opts = {})
      @app = app
      @logger = opts[:logger] || Logger.new(nil)

      String.root_path = Config.root_path

      I18n.locale = Config.locale
      I18n.load(File.join(File.dirname(__FILE__), 'locale.yml'))

      Templates.enable_caching if Config.production?
      Templates.paths << File.join(Config.app_path, 'views')

      run_initializers

      logger.debug self.class.dump_routes
    end

    # Executed before each request
    before :routing do
      @timer = Timer.start

      # Set request ip as progname
      @logger = logger.dup
      logger.progname = request.ip

      logger.debug env

      @user = session[:user]
      if !@user
        invoke_hook(:auto_login)
        @user ||= User.anonymous(request)
      end

      content_type 'application/xhtml+xml', :charset => 'utf-8'
    end

    # Purge memory cache after request
    after :request do
      Repository.instance.clean_cache
    end

    # Handle 404s
    hook NotFound do |ex|
      if redirect_to_new
        # Redirect to create new page if flag is set
        path = (params[:path]/'new').urlpath
        path += '?' + request.query_string if !request.query_string.blank?
        redirect path
      end
    end

    hook StandardError do |ex|
      if on_error
        logger.error ex
        (ex.try(:messages) || [ex.message]).each {|msg| flash.error(msg) }
        halt render(on_error)
      end
    end

    # Show wiki error page
    hook Exception do |ex|
      cache_control :no_cache => true
      @error = ex
      logger.error @error
      render :error
    end

    get '/_/user' do
      render :user, :layout => false
    end

    get '/login', '/signup' do
      render :login
    end

    post '/login' do
      on_error :login
      self.user = User.authenticate(params[:user], params[:password])
      redirect session.delete(:goto) || '/'
    end

    post '/signup' do
      on_error :login
      self.user = User.create(params[:user], params[:password],
                              params[:confirm], params[:email])
      redirect '/'
    end

    get '/logout' do
      self.user = nil
      redirect '/'
    end

    get '/profile' do
      render :profile
    end

    post '/profile' do
      on_error :profile
      if !user.anonymous?
        user.modify do |u|
          u.change_password(params[:oldpassword], params[:password], params[:confirm]) if !params[:password].blank?
          u.email = params[:email]
        end
        flash.info :changes_saved.t
        session[:user] = user
      end
      render :profile
    end

    get '/changes/:version' do
      @version = Version.find!(params[:version])
      cache_control :etag => @version, :last_modified => @version.date
      @diff = Version.diff(@version.parents.first, @version)
      render :changes
    end

    get '/?:path?/history' do
      @resource = Resource.find!(params[:path])
      cache_control :etag => @resource.version, :last_modified => @resource.version.date
      render :history
    end

    get '/:path/move' do
      @resource = Resource.find!(params[:path])
      render :move
    end

    get '/:path/delete' do
      @resource = Resource.find!(params[:path])
      render :delete
    end

    post '/:path/move' do
      on_error :move
      Resource.transaction(:resource_moved.t(:path => params[:path].cleanpath, :destination => params[:destination].cleanpath), user) do
        @resource = Resource.find!(params[:path])
        with_hooks(:move, @resource, params[:destination]) do
          @resource.move(params[:destination])
          Page.new(@resource.path).write("redirect: #{params[:destination].urlpath}") if params[:create_redirect]
        end
      end
      redirect @resource.path.urlpath
    end

    delete '/:path' do
      pass if reserved_path?(params[:path])
      Resource.transaction(:resource_deleted.t(:path => params[:path].cleanpath), user) do
        @resource = Resource.find!(params[:path])
        with_hooks(:delete, @resource) do
          @resource.delete
        end
      end
      render :deleted
    end

    get '/?:path?/diff' do
      on_error :history
      @resource = Resource.find!(params[:path])
      check do |errors|
        errors << :from_missing.t if params[:from].blank?
        errors << :to_missing.t  if params[:to].blank?
      end
      @diff = @resource.diff(params[:from], params[:to])
      render :diff
    end

    get '/:path/edit' do
      @resource = Page.find(params[:path])
      redirect((params[:path]/'new').urlpath) if !@resource
      flash.warn :warn_binary.t(:page => @resource.path, :type => "#{@resource.mime.comment} (#{@resource.mime})") if @resource.content =~ /[^[:print:][:space:]]/
      render :edit
    end

    get '/?:path?/new', '/?:path?/upload' do
      on_error :new
      if params[:path] && @resource = Resource.find(params[:path])
        return render(:edit) if @resource.page? && action?(:upload)
        redirect((params[:path]/(@resource.tree? ? 'new page' : 'edit')).urlpath)
      end
      @resource = Page.new(params[:path])
      raise :reserved_path.t if reserved_path?(params[:path])
      render :new
    end

    get '/?:path?/version/?:version?', '/:path' do
      begin
        pass if reserved_path?(params[:path])
        @resource = Resource.find!(params[:path], params[:version])
        cache_control :etag => @resource.version, :last_modified => @resource.version.date
        with_hooks(:show) do
          @content = @resource.try(:content)
          halt render(:show)
        end
      rescue ObjectNotFound => ex
        redirect_to_new params[:version].blank?
        pass
      end
    end

    # Edit form sends put requests
    put '/:path' do
      on_error :edit

      @resource = Page.find!(params[:path])

      # TODO: Implement conflict diffs
      raise :version_conflict.t if @resource.version.to_s != params[:version]

      if action?(:upload) && params[:file]
        with_hooks :save, @resource do
          Resource.transaction(:page_uploaded.t(:path => params[:path].cleanpath), user) do
            @resource.write(params[:file][:tempfile])
          end
        end
      elsif action?(:edit) && params[:content]
        with_hooks :save, @resource do
          raise :empty_comment.t if params[:comment].blank?
          Resource.transaction(:page_edited.t(:path => @resource.path, :comment => params[:comment]), user) do
            content = if params[:pos]
                        pos = [[0, params[:pos].to_i].max, @resource.content.size].min
                        len = [0, params[:len].to_i].max
                        @resource.content(0, pos) + params[:content] + @resource.content(pos + len, @resource.content.size)
                      else
                        params[:content]
                      end
            @resource.write(content)
          end
        end
      else
        redirect((params[:path]/'edit').urlpath)
      end
      redirect @resource.path.urlpath
    end

    # New form sends post request
    post '/', '/:path' do
      on_error :new

      pass if reserved_path?(params[:path])

      @resource = Page.new(params[:path])

      if action?(:upload) && params[:file]
        with_hooks :save, @resource do
          Resource.transaction(:page_uploaded.t(:path => @resource.path), user) do
            @resource.write(params[:file][:tempfile])
          end
        end
      elsif action?(:new)
        with_hooks :save, @resource do
          raise :empty_comment.t if params[:comment].blank?
          Resource.transaction(:page_edited.t(:path => @resource.path, :comment => params[:comment]), user) do
            @resource.write(params[:content])
          end
        end
      else
        redirect '/new'
      end

      redirect @resource.path.urlpath
    end

    private

    def run_initializers
      Dir[File.join(Config.initializers_path, '*.rb')].sort_by do |f|
        File.basename(f)
      end.each do |f|
        logger.debug "Running initializer #{f}"
	instance_eval(File.read(f), f)
      end
    end

    def reserved_path?(path)
      path = path.to_s.urlpath
      self.class.routes.any? do |method, routes|
        routes.any? do |name,pattern|
          name != '/' && name != '/:path' && (path =~ pattern || path =~ /#{pattern.source[0..-2]}\//)
        end
      end
    end

  end
end
