require "pathname"
require "nokogiri"

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

root = "build/"

Dir.glob(File.join(root, "**", "*.html")).each do |html_file|
  inline_css(html_file, root)
end
