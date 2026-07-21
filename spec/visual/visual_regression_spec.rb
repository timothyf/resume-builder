require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

RSpec.describe 'Visual regression', :visual do
  if ENV['RUN_VISUAL'] != '1'
    it 'runs only when visual testing is enabled' do
      skip 'Set RUN_VISUAL=1 to run visual regression coverage'
    end
  else
    it 'matches desktop, mobile, theme, print, and PDF baselines' do
      source_root = File.expand_path('../..', __dir__)
      test_root = Dir.mktmpdir('resume-builder-visual-')
      excluded_entries = %w[.bundle .git build dist node_modules tmp vendor]
      entries = Dir.children(source_root).reject { |entry| excluded_entries.include?(entry) }
      FileUtils.cp_r(entries.map { |entry| File.join(source_root, entry) }, test_root)

      output_dir = File.join(source_root, 'tmp', 'visual-regression', 'current')
      pdf_output_dir = File.join(source_root, 'tmp', 'pdfs', 'visual-regression')
      node = ENV.fetch('VISUAL_NODE_BIN', 'node')
      env = { 'VISUAL_PYTHON_BIN' => ENV.fetch('VISUAL_PYTHON_BIN', 'python3') }
      arguments = [
        File.join(source_root, 'scripts', 'visual_regression.mjs'),
        '--project-root', test_root,
        '--baseline-dir', File.join(source_root, 'spec', 'visual', 'baselines'),
        '--output-dir', output_dir,
        '--pdf-output-dir', pdf_output_dir
      ]
      arguments << '--update' if ENV['UPDATE_VISUAL'] == '1'
      stdout, stderr, status = Open3.capture3(
        env,
        node,
        *arguments,
        chdir: source_root
      )

      expect(status).to be_success, <<~MESSAGE
        Visual regression failed.
        Current screenshots: #{output_dir}
        Rendered PDF pages: #{pdf_output_dir}
        STDOUT:
        #{stdout}
        STDERR:
        #{stderr}
      MESSAGE
    ensure
      FileUtils.remove_entry(test_root) if test_root && File.exist?(test_root)
    end
  end
end
