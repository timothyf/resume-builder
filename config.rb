## Used for parsing markdown docs in the resume.yml
require 'maruku'

## For generating gravatar hash
require 'digest/md5'


#activate :livereload

# Per-page layout changes:
#
# With no layout
page "index.html", :layout => false
page "pdf.html", :layout => false

if data.active_resume.generate_brief == false
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

after_build do |builder|
  active_resume_user = data.active_resume.user
  active_resume_name = data.active_resume.name
  @resume_data = eval("data.#{active_resume_user}.#{active_resume_name}")

  new_dir_path = "./dist/#{active_resume_user}/#{@resume_data.name}"

  root = "./build"
  Dir.glob(File.join(root, "**", "*.html")).each do |html_file|
    inline_css(html_file, root)
  end

  FileUtils.remove_dir(new_dir_path, true)

  begin
    Dir.mkdir("./dist")
  rescue
    # do nothing if dir already exists
  end
  begin
    Dir.mkdir("./dist/#{active_resume_user}")
  rescue
    # do nothing if dir already exists
  end
  begin
    Dir.mkdir(new_dir_path)
  rescue
  end
  # generate pdf directory
  begin
    Dir.mkdir("#{new_dir_path}/pdf")
  rescue
  end

  File.rename("./build/stylesheets", "#{new_dir_path}/stylesheets")
  File.rename("./build/index.html", "#{new_dir_path}/index-#{@resume_data.name}.html")
  begin
    File.rename("./build/index-brief.html", "#{new_dir_path}/index-brief-#{@resume_data.name}.html")
  rescue
  end
  File.rename("./build/pdf.html", "#{new_dir_path}/pdf-#{@resume_data.name}.html")
  begin
    File.rename("./build/pdf-brief.html", "#{new_dir_path}/pdf-brief-#{@resume_data.name}.html")
  rescue
  end
end

activate :deploy do |deploy|
  deploy.method = :git
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
