
module PdfMaker
  class << self
    def registered(app)
      app.after_build do |builder|
        active_resume = data.active_resume.name
        @resume_data = eval("data.#{active_resume}")
        begin
          require 'pdfkit'

          kit = PDFKit.new(File.new('build/pdf.html'),
                      :page_size => 'Letter',
                      :viewport_size => '2480x3508',
                      :zoom => 0.7,
                      # :dpi => 300
                      :print_media_type => false
                    )

          kit.to_file("build/#{@resume_data.pdf.filename}.pdf")
          builder.say_status "PDF Maker",  "PDF file available at build/#{@resume_data.pdf.filename}.pdf"
        rescue Exception =>e
            builder.say_status "PDF Maker",  "Error: #{e.message}", Thor::Shell::Color::RED
            raise
        end

        begin
          kit = PDFKit.new(File.new('build/pdf-brief.html'),
                      :page_size => 'Letter',
                      :viewport_size => '2480x3508',
                      :zoom => 0.7,
                      # :dpi => 300
                      :print_media_type => false
                    )

          kit.to_file("build/#{@resume_data.pdf.filename}-brief.pdf")
          builder.say_status "PDF Maker",  "PDF file available at build/#{@resume_data.pdf.filename}-brief.pdf"
          rescue Exception =>e
              builder.say_status "PDF Maker",  "Error: #{e.message}", Thor::Shell::Color::RED
              raise
          end

      end
      alias :included :registered
    end
  end
end

::Middleman::Extensions.register(:pdfmaker, PdfMaker)
