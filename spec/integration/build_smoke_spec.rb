require 'spec_helper'
require 'fileutils'
require 'kramdown'
require 'nokogiri'
require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'Supported resume build matrix', :integration do
  project_root = File.expand_path('../..', __dir__)
  support_manifest = YAML.safe_load_file(
    File.join(project_root, 'data', 'resume_support.yml'),
    aliases: false
  )
  supported_resumes = support_manifest.fetch('supported')
  build_matrix = supported_resumes.product(ResumeSelection::AVAILABLE_THEMES, [true, false])

  if ENV['RUN_INTEGRATION'] != '1'
    it 'runs only when integration testing is enabled' do
      skip 'Set RUN_INTEGRATION=1 to run the 132-build integration matrix'
    end
  else
    before(:context) do
      @source_root = project_root
      @test_root = Dir.mktmpdir('resume-builder-integration-')
      @yaml_cache = {}
      excluded_entries = %w[.bundle .git build dist node_modules tmp vendor]
      entries = Dir.children(@source_root).reject { |entry| excluded_entries.include?(entry) }
      FileUtils.cp_r(entries.map { |entry| File.join(@source_root, entry) }, @test_root)
    end

    after(:context) do
      FileUtils.remove_entry(@test_root) if @test_root && File.exist?(@test_root)
    end

    build_matrix.each do |resume_entry, theme, generate_brief|
      user = resume_entry.fetch('user')
      resume_name = resume_entry.fetch('name')
      brief_label = generate_brief ? 'brief enabled' : 'brief disabled'

      it "builds #{user}/#{resume_name} with #{theme} and #{brief_label}" do
        FileUtils.rm_rf(File.join(@test_root, 'build'))
        FileUtils.rm_rf(File.join(@test_root, 'dist'))

        env = {
          'ACTIVE_RESUME_GENERATE_BRIEF' => generate_brief.to_s,
          'RESUME_DEPLOYED_AT' => '2026-07-20T20:15:30Z'
        }
        stdout, stderr, status = Open3.capture3(
          env,
          './build_resume.bash',
          '--resume-user', user,
          '--resume-name', resume_name,
          '--theme', theme,
          chdir: @test_root
        )

        expect(status).to be_success, <<~MESSAGE
          Build failed for #{user}/#{resume_name}, #{theme}, #{brief_label}.
          STDOUT:
          #{stdout}
          STDERR:
          #{stderr}
        MESSAGE

        resume = load_yaml('data', user, "#{resume_name}.yml")
        artifact_name = resume.fetch('name')
        build_root = File.join(@test_root, 'build')
        artifact_root = File.join(@test_root, 'dist', user, resume_name)
        theme_color = theme_color_for(theme)

        screen_path = File.join(build_root, 'index.html')
        pdf_path = File.join(build_root, 'pdf.html')
        deployed_screen_path = File.join(artifact_root, 'index.html')
        deployed_pdf_path = File.join(artifact_root, 'pdf.html')
        screen_html = File.read(screen_path)
        pdf_html = File.read(pdf_path)
        deployed_screen_html = File.read(deployed_screen_path)
        deployed_pdf_html = File.read(deployed_pdf_path)

        expect(screen_html).to include('<body>')
        expect(pdf_html).to include('<body class="pdf">')
        expect(deployed_screen_html.downcase).to include(theme_color)
        expect(deployed_pdf_html.downcase).to include(theme_color)
        expect(deployed_screen_html).to include('Last deployed:')
        expect(deployed_screen_html).to include('July 20, 2026 at 04:15 PM EDT')
        expect(deployed_pdf_html).not_to include('Last deployed:')

        rendered_documents = {
          screen: parse_valid_html(screen_path),
          pdf: parse_valid_html(pdf_path),
          deployed_screen: parse_valid_html(deployed_screen_path),
          deployed_pdf: parse_valid_html(deployed_pdf_path)
        }
        rendered_documents.each_value do |document|
          assert_resume_content(document, user, resume)
        end

        screen_css = File.read(File.join(build_root, 'stylesheets', 'styles.css')).downcase
        pdf_css = File.read(File.join(build_root, 'stylesheets', 'pdf.css')).downcase
        expect(screen_css).to include(theme_color)
        expect(pdf_css).to include(theme_color)

        brief_paths = {
          build_screen: File.join(build_root, 'index-brief.html'),
          build_pdf: File.join(build_root, 'pdf-brief.html'),
          deployed_screen: File.join(artifact_root, "index-brief-#{artifact_name}.html"),
          deployed_pdf: File.join(artifact_root, "pdf-brief-#{artifact_name}.html")
        }

        if generate_brief
          expect(brief_paths.values).to all(satisfy { |path| File.file?(path) })
          brief_screen = parse_valid_html(brief_paths.fetch(:build_screen))
          brief_pdf = parse_valid_html(brief_paths.fetch(:build_pdf))
          deployed_brief_screen = parse_valid_html(brief_paths.fetch(:deployed_screen))
          deployed_brief_pdf = parse_valid_html(brief_paths.fetch(:deployed_pdf))
          expect(brief_screen.at_css('body')['class'].to_s).not_to include('pdf')
          expect(brief_pdf.at_css('body')['class'].to_s).to include('pdf')
          expect(File.read(brief_paths.fetch(:deployed_screen)).downcase).to include(theme_color)
          expect(File.read(brief_paths.fetch(:deployed_pdf)).downcase).to include(theme_color)
          [brief_screen, brief_pdf, deployed_brief_screen, deployed_brief_pdf].each do |document|
            assert_resume_content(document, user, resume)
          end
        else
          expect(brief_paths.values).to all(satisfy { |path| !File.exist?(path) })
        end

        assert_pdf_downloads_exist(rendered_documents.values, artifact_root, resume)
      end
    end
  end

  def theme_color_for(theme)
    theme_path = File.join(@test_root, 'source', 'stylesheets', "_#{theme}.scss")
    match = File.read(theme_path).match(/^\$theme-color:\s*(#[0-9a-f]{6})/i)
    raise "Theme color not found in #{theme_path}" unless match

    match[1].downcase
  end

  def load_yaml(*segments)
    path = File.join(@test_root, *segments)
    @yaml_cache[path] ||= YAML.safe_load_file(path, aliases: true)
  end

  def parse_valid_html(path)
    document = Nokogiri::HTML5.parse(File.read(path))
    expect(document.errors).to be_empty, "Invalid HTML in #{path}:\n#{document.errors.join("\n")}"
    expect(document.at_css('html')).not_to be_nil
    expect(document.at_css('head')).not_to be_nil
    expect(document.at_css('body')).not_to be_nil
    document
  end

  def assert_resume_content(document, user, resume)
    document_text = normalized_text(document.text)
    layout = load_yaml('data', user, 'layouts', "#{resume.fetch('layout')}.yml")

    assert_layout_sections(document, layout)
    assert_profile(document_text, layout, resume)
    assert_summary(document_text, user, layout, resume)
    assert_education(document_text, layout, resume)
    assert_skills(document_text, user, layout, resume)
    assert_representative_jobs(document_text, user, layout, resume)
    assert_external_links(document, user, layout, resume)

    expected_pdf_url = "#{resume.fetch('pdf').fetch('filename')}.pdf"
    expect(document.css("a[href='#{expected_pdf_url}']")).not_to be_empty
  end

  def assert_layout_sections(document, layout)
    layout.fetch('content').values.compact.flat_map { |sections| Array(sections) }.each do |section|
      template = section.fetch('template')
      selector = layout_selector_for(template)
      nodes = document.css(selector)
      expect(nodes).not_to be_empty, "Expected layout template '#{template}' (#{selector}) to render"

      display_name = normalized_text(section['display_name'])
      expect(normalized_text(nodes.text)).to include(display_name) unless display_name.empty?
    end
  end

  def assert_profile(document_text, layout, resume)
    return unless layout_templates(layout).include?('profile')

    expect(document_text).to include(normalized_text(resume.fetch('contact_info').fetch('name')))
  end

  def assert_summary(document_text, user, layout, resume)
    return unless layout_templates(layout).include?('summary')

    summary_name = resume.fetch('summary').fetch('file')
    summary = load_yaml('data', user, 'summaries', "#{summary_name}.yml").fetch('summary').fetch('text')
    rendered_summary = Nokogiri::HTML5.fragment(Kramdown::Document.new(summary.to_s).to_html).text
    expect(document_text).to include(normalized_text(rendered_summary))
  end

  def assert_education(document_text, layout, resume)
    return unless layout_templates(layout).include?('education')

    resume.fetch('education').each do |education|
      expect(document_text).to include(normalized_text(education.fetch('name')))
      expect(document_text).to include(normalized_text(education.fetch('degree')))
    end
  end

  def assert_skills(document_text, user, layout, resume)
    return unless layout_templates(layout).include?('skills')

    skills_by_id = load_yaml('data', user, 'skills.yml').to_h { |skill| [skill.fetch('id').to_s, skill] }
    resume.fetch('skills').each do |category|
      expect(document_text).to include(normalized_text(category.fetch('name')))
      category.fetch('skills').each do |skill_id|
        expect(document_text).to include(normalized_text(skills_by_id.fetch(skill_id.to_s).fetch('label')))
      end
    end
  end

  def assert_representative_jobs(document_text, user, layout, resume)
    experience_templates = layout_templates(layout) & %w[experiences experience_highlights experience_other]
    return if experience_templates.empty?

    jobs_by_id = load_yaml('data', user, "#{resume.fetch('jobs_filename')}.yml")
      .to_h { |job| [job.fetch('id').to_s, job] }

    experience_templates.each do |template|
      section_name = template == 'experience_other' ? 'experience_other' : 'experiences'
      reference = resume.fetch('jobs').find do |job|
        job.fetch('section') == section_name && (section_name == 'experience_other' || job['include'] != false)
      end
      next unless reference

      job = jobs_by_id.fetch(reference.fetch('id').to_s)
      expect(document_text).to include(normalized_text(job.fetch('company')))
      expect(document_text).to include(normalized_text(job.fetch('title')))
    end
  end

  def assert_external_links(document, user, layout, resume)
    return unless layout_templates(layout).include?('contact') && resume.key?('links')

    links_by_name = load_yaml('data', user, 'links.yml').fetch('links').to_h do |link|
      [link.fetch('name'), link]
    end
    resume.fetch('links').each do |reference|
      link = links_by_name.fetch(reference.fetch('name'))
      node = document.at_css("a[href='#{link.fetch('url')}']")
      expect(node).not_to be_nil
      expect(normalized_text(node.text)).to eq(normalized_text(link.fetch('name')))
    end
  end

  def assert_pdf_downloads_exist(documents, artifact_root, resume)
    pdf = resume.fetch('pdf')
    expected_url = "#{pdf.fetch('filename')}.pdf"
    expected_target = File.expand_path(expected_url, artifact_root)
    artifact_prefix = "#{File.expand_path(artifact_root)}#{File::SEPARATOR}"
    expect(expected_target).to start_with(artifact_prefix)
    expect(File.file?(expected_target)).to be(true), "Missing PDF download target #{expected_target}"

    documents.each do |document|
      document.css("a[href='#{expected_url}']").each do |link|
        expect(File.expand_path(link['href'], artifact_root)).to eq(expected_target)
      end
    end

    source_path = File.join(@test_root, pdf.fetch('source'))
    expect(FileUtils.compare_file(source_path, expected_target)).to be(true)
  end

  def layout_templates(layout)
    layout.fetch('content').values.compact.flat_map { |sections| Array(sections) }
      .map { |section| section.fetch('template') }
  end

  def layout_selector_for(template)
    {
      'profile' => '.profile-container',
      'contact' => '.contact-container',
      'summary' => '.summary-section',
      'skills' => '.interests-container',
      'education' => '.education-container',
      'download' => '.align-bottom',
      'experiences' => '.experiences-section',
      'experience_highlights' => '.experiences-section',
      'experience_other' => '.experience-other-section'
    }.fetch(template)
  end

  def normalized_text(value)
    value.to_s.gsub(/\s+/, ' ').strip
  end
end
