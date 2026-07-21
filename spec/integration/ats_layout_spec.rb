require 'spec_helper'
require 'fileutils'
require 'nokogiri'
require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'ATS layout', :integration do
  if ENV['RUN_INTEGRATION'] != '1'
    it 'runs only when integration testing is enabled' do
      skip 'Set RUN_INTEGRATION=1 to build the ATS layout'
    end
  else
    it 'builds a semantic single-column screen and PDF resume' do
      source_root = File.expand_path('../..', __dir__)
      test_root = Dir.mktmpdir('resume-builder-ats-')
      excluded = %w[.bundle .git build dist node_modules tmp vendor]
      entries = Dir.children(source_root).reject { |entry| excluded.include?(entry) }
      FileUtils.cp_r(entries.map { |entry| File.join(source_root, entry) }, test_root)

      resume_path = File.join(test_root, 'data', 'timothyfisher', 'resume_dev_refined.yml')
      resume = YAML.safe_load_file(resume_path, aliases: true)
      resume['layout'] = 'layout_ats'
      resume['pdf']['useicons'] = false
      File.write(resume_path, YAML.dump(resume))

      stdout, stderr, status = Open3.capture3(
        './build_resume.bash',
        '--resume-user', 'timothyfisher',
        '--resume-name', 'resume_dev_refined',
        chdir: test_root
      )
      expect(status).to be_success, "ATS build failed:\n#{stdout}\n#{stderr}"

      artifact_root = File.join(test_root, 'dist', 'timothyfisher', 'resume_dev_refined')
      %w[index.html pdf.html].each do |filename|
        document = Nokogiri::HTML5.parse(File.read(File.join(artifact_root, filename)))
        expect(document.at_css('body')['class']).to include('layout-layout_ats')
        expect(document.css('.sidebar-wrapper > *')).to be_empty
        expect(document.at_css('.main-wrapper .profile-container .name').text).to include('Timothy Fisher')
        expect(document.at_css('.ats-contact-container')).not_to be_nil
        expect(document.at_css('.ats-skills-section')).not_to be_nil
        expect(document.at_css('.experiences-section')).not_to be_nil
        expect(document.at_css('.education-container')).not_to be_nil
      end

      expect(File.read(File.join(artifact_root, 'stylesheets', 'styles.css'))).to include('.layout-layout_ats')
      expect(File.read(File.join(artifact_root, 'stylesheets', 'pdf.css'))).to include('.layout-layout_ats')
    ensure
      FileUtils.remove_entry(test_root) if test_root && File.exist?(test_root)
    end
  end
end
