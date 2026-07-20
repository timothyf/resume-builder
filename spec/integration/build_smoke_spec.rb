require 'spec_helper'

RSpec.describe 'Build smoke test', :integration do
  it 'builds successfully and emits key artifacts', :integration do
    skip 'Set RUN_INTEGRATION=1 to run integration specs' unless ENV['RUN_INTEGRATION'] == '1'

    root = File.expand_path('../..', __dir__)
    cmd = "cd #{root} && RESUME_DEPLOYED_AT=2026-07-20T20:15:30Z " \
          "./build_resume.bash --resume-user timothyfisher --resume-name resume_dev_refined"
    output = `#{cmd} 2>&1`
    status = $?.exitstatus

    expect(status).to eq(0), "Build failed:\n#{output}"
    expect(File.exist?(File.join(root, 'build', 'index.html'))).to be(true)
    expect(File.exist?(File.join(root, 'build', 'pdf.html'))).to be(true)
    expect(File.exist?(File.join(root, 'dist', 'timothyfisher', 'resume_dev_refined', 'index.html'))).to be(true)
    deployed_html = File.read(File.join(root, 'dist', 'timothyfisher', 'resume_dev_refined', 'index.html'))
    expect(deployed_html).to include('Last deployed:')
    expect(deployed_html).to include('datetime="2026-07-20T16:15:30-04:00"')
    expect(deployed_html).to include('July 20, 2026 at 04:15 PM EDT')
    expect(File.read(File.join(root, 'build', 'pdf.html'))).not_to include('Last deployed:')
    deployed_pdf = File.join(
      root,
      'dist',
      'timothyfisher',
      'resume_dev_refined',
      'pdf',
      'TimothyFisher-Res-Dev.pdf'
    )
    expect(File.exist?(deployed_pdf)).to be(true)
  end
end
