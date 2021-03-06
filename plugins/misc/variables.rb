author       'Daniel Mendler'
description  'Export variables to context and javascript'
dependencies 'engine/engine'
require      'json'

def variables(page, engine)
  vars = {
    'page_name'             => page.name,
    'page_path'             => page.path,
    'page_namespace'        => page.namespace,
    'page_title'            => page.title,
    'page_version'          => page.version.to_s,
    'page_next_version'     => page.next_version.to_s,
    'page_previous_version' => page.previous_version.to_s,
    'page_type'             => page.tree? ? 'tree' : 'page',
    'page_mime'             => page.mime.to_s,
    'page_current'          => page.current? }
  if engine
    vars.merge!({
      'engine_name'      => engine.name,
      'engine_layout'    => engine.layout?,
      'engine_cacheable' => engine.cacheable?,
      'engine_priority'  => engine.priority })
  end
  vars
end

# Export variables to engine context
Wiki::Context.hook(:initialized) do
  params.merge!(Plugin.current.variables(page, engine))
end

# Export variables to javascript for client extensions
class Wiki::Application
  hook :layout do |name, doc|
    vars = @resource ? params.merge(Plugin.current.variables(@resource, @engine)) : params
    doc.css('head').children.before %{<script type="text/javascript">
                                      Wiki = #{escape_json(vars.to_json)};
                                      </script>}.unindent
  end

  get '/_/user' do
    %{<script type="text/javascript">
      Wiki.user_anonymous = #{escape_json(@user.anonymous?.to_json)};
      Wiki.user_name = #{escape_json(@user.name.to_json)};
    </script>}.unindent + super()
  end
end
