## Used for parsing markdown docs in the resume.yml
require 'kramdown'

## For generating gravatar hash
require 'digest/md5'


#activate :livereload

# Per-page layout changes:
#
# With no layout
page "index.html", :layout => false
page "pdf.html", :layout => false

if @app.data.active_resume.generate_brief == false
  ignore "/index-brief.html"
  ignore "/pdf-brief.html"
end

###
# Helpers
###

# Methods defined in the helpers block are available in templates
# helpers do
#   def some_helper
#     "Helping"
#   end
# end

helpers do
  def resolve_data_segment(current, segment)
    key = segment.to_s

    return current.public_send(key) if current.respond_to?(key)

    if current.respond_to?(:[])
      return current[key] if current[key]

      sym_key = key.to_sym
      return current[sym_key] if current[sym_key]
    end

    raise KeyError, "Missing data segment '#{key}' while resolving resume context"
  end

  def resolve_data_path(root, *segments)
    segments.reduce(root) { |current, segment| resolve_data_segment(current, segment) }
  end

  def build_resume_context(active_resume)
    env_user = ENV.fetch('ACTIVE_RESUME_USER', '').strip
    env_name = ENV.fetch('ACTIVE_RESUME_NAME', '').strip
    user = env_user.empty? ? active_resume.user : env_user
    name = env_name.empty? ? active_resume.name : env_name
    user_data = resolve_data_path(data, user)
    resume = resolve_data_path(user_data, name)
    jobs_filename = resume.jobs_filename

    {
      user: user,
      name: name,
      resume: resume,
      layout: resolve_data_path(user_data, 'layouts', resume.layout),
      skills: resolve_data_path(user_data, 'skills'),
      jobs: resolve_data_path(user_data, jobs_filename)
    }
  end

    def render_markdown(text)
        Kramdown::Document.new(text.to_s).to_html
    end

    def display_date(date)
        if date.is_a?(Date)
            # Change this if you prefer another date format:
            # http://www.ruby-doc.org/stdlib-1.9.3/libdoc/date/rdoc/Date.html#method-i-strftime
            date.strftime("%Y-%m")
            # Comment above and uncomment this if you want days displayed
            # date.strftime("%Y-%m-%d")
        else
            date
        end
    end

    def gravatar_url(email)
      hash = Digest::MD5.hexdigest email.downcase
      "https://www.gravatar.com/avatar/#{hash}?s=130&d=mm"
    end
end

set :css_dir, 'stylesheets'
set :js_dir, 'javascripts'
set :images_dir, 'images'

# Build-specific configuration
configure :build do
  # For example, change the Compass output style for deployment
  activate :minify_css

  #activate :asset_hash

  # Minify Javascript on build
  # activate :minify_javascript

  # Enable cache buster
  # activate :cache_buster

  # Use relative URLs
  activate :relative_assets

  # Or use a different image path
  # set :http_path, "/Content/images/"
end

def ensure_directory(path)
  Dir.mkdir(path)
rescue Errno::EEXIST
  nil
end

def copy_optional_file(source, destination, label)
  FileUtils.cp(source, destination)
rescue Errno::ENOENT
  warn "Skipping optional #{label}: #{source} not found"
end

after_build do |builder|
  env_user = ENV.fetch('ACTIVE_RESUME_USER', '').strip
  env_name = ENV.fetch('ACTIVE_RESUME_NAME', '').strip
  active_resume_user = env_user.empty? ? @app.data.active_resume.user : env_user
  active_resume_name = env_name.empty? ? @app.data.active_resume.name : env_name
  user_data = @app.data.public_send(active_resume_user)
  resume_data = user_data.public_send(active_resume_name)

  new_dir_path = "./dist/#{active_resume_user}/#{active_resume_name}"

  root = "./build"
  Dir.glob(File.join(root, "**", "*.html")).each do |html_file|
    inline_css(html_file, root)
  end

  FileUtils.remove_dir(new_dir_path, true)

  ensure_directory("./dist")
  ensure_directory("./dist/#{active_resume_user}")
  ensure_directory(new_dir_path)
  # generate pdf directory
  ensure_directory("#{new_dir_path}/pdf")

  FileUtils.cp_r("./build/stylesheets", "#{new_dir_path}/stylesheets")
  FileUtils.cp("./build/index.html", "#{new_dir_path}/index.html")
  copy_optional_file(
    "./build/index-brief.html",
    "#{new_dir_path}/index-brief-#{resume_data.name}.html",
    'index brief artifact'
  )
  FileUtils.cp("./build/pdf.html", "#{new_dir_path}/pdf.html")
  copy_optional_file(
    "./build/pdf-brief.html",
    "#{new_dir_path}/pdf-brief-#{resume_data.name}.html",
    'pdf brief artifact'
  )
end

# activate :deploy do |deploy|
#   deploy.method = :git
# end

activate :deploy do |deploy|
  deploy.deploy_method = :git
end

require "pathname"

def inline_css(html_file, root)
  doc = File.open(html_file) { |f| Nokogiri::HTML(f) }

  stylesheet_tags = doc.css("link[id=theme-style]")
  puts "Inlining css in #{html_file}" if stylesheet_tags.any?

  stylesheet_tags.each do |stylesheet_tag|
    href = stylesheet_tag["href"]
    href = href[1..-1] if Pathname.new(href).absolute?

    css_file_path = File.expand_path(href, root)
    css = File.read(css_file_path)

    style_tag = Nokogiri::XML::Node.new "style", doc
    style_tag.content = css

    stylesheet_tag.add_previous_sibling style_tag
    stylesheet_tag.remove
  end

  File.write(html_file, doc.to_s)
end
