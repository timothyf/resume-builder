require 'spec_helper'
require 'fileutils'
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

        resume = YAML.safe_load_file(
          File.join(@test_root, 'data', user, "#{resume_name}.yml"),
          aliases: true
        )
        artifact_name = resume.fetch('name')
        build_root = File.join(@test_root, 'build')
        artifact_root = File.join(@test_root, 'dist', user, resume_name)
        theme_color = theme_color_for(theme)

        screen_html = File.read(File.join(build_root, 'index.html'))
        pdf_html = File.read(File.join(build_root, 'pdf.html'))
        deployed_screen_html = File.read(File.join(artifact_root, 'index.html'))
        deployed_pdf_html = File.read(File.join(artifact_root, 'pdf.html'))

        expect(screen_html).to include('<body>')
        expect(pdf_html).to include('<body class="pdf">')
        expect(deployed_screen_html.downcase).to include(theme_color)
        expect(deployed_pdf_html.downcase).to include(theme_color)
        expect(deployed_screen_html).to include('Last deployed:')
        expect(deployed_screen_html).to include('July 20, 2026 at 04:15 PM EDT')
        expect(deployed_pdf_html).not_to include('Last deployed:')

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
          expect(File.read(brief_paths.fetch(:build_screen))).to include('<body>')
          expect(File.read(brief_paths.fetch(:build_pdf))).to include('<body class="pdf">')
          expect(File.read(brief_paths.fetch(:deployed_screen)).downcase).to include(theme_color)
          expect(File.read(brief_paths.fetch(:deployed_pdf)).downcase).to include(theme_color)
        else
          expect(brief_paths.values).to all(satisfy { |path| !File.exist?(path) })
        end
      end
    end
  end

  def theme_color_for(theme)
    theme_path = File.join(@test_root, 'source', 'stylesheets', "_#{theme}.scss")
    match = File.read(theme_path).match(/^\$theme-color:\s*(#[0-9a-f]{6})/i)
    raise "Theme color not found in #{theme_path}" unless match

    match[1].downcase
  end
end
