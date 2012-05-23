# Report builder

require 'nokogiri'
require 'zip/zipfilesystem'

require 'hailstorm/support'

class Hailstorm::Support::ReportBuilder

  attr_accessor :title

  attr_accessor :jmeter_plans

  attr_reader :images

  attr_reader :current_report_path

  attr_reader :report_type

  attr_reader :report_format

  def initialize(options = {})
    @images = []
    @report_format = options[:format] || 'docx'
    @report_type = options[:type] || 'standard'
  end

  def test_summary_rows(&block)

    @test_summary_rows ||= []
    if block_given?
      row = TestSummaryRow.new()
      yield row
      row.index = @test_summary_rows.size + 1
      @test_summary_rows.push(row)
    else
      @test_summary_rows
    end
  end

  class TestSummaryRow

    attr_accessor :index
    attr_accessor :jmeter_plans
    attr_accessor :test_duration
    attr_accessor :total_threads_count

    attr_writer :target_hosts
    def target_hosts()
      (@target_hosts || []).collect(&:host_name).join(', ')
    end
  end

  def execution_detail_items(&block)

    @execution_detail_items ||= []
    if block_given?
      item = ExecutionDetail.new(self)
      yield item
      item.index = @execution_detail_items.size + 1
      @execution_detail_items.push(item)
    else
      @execution_detail_items
    end
  end

  class TocItem

    attr_accessor :builder
    attr_accessor :toc_id

    def initialize(builder)
      self.toc_id = self.object_id
      self.builder = builder
    end
  end

  class ExecutionDetail < TocItem

    attr_accessor :index

    def clusters(&block)

      @clusters ||= []
      if block_given?
        item = ClusterItem.new(builder)
        yield item
        @clusters.push(item)
      else
        @clusters
      end
    end

    def target_stats(&block)

      @target_stats ||= []
      if block_given?
        item = TargetStatItem.new(builder)
        yield item
        @target_stats.push(item)
      else
        @target_stats
      end
    end
  end

  def client_comparison_graph(&block)

    @client_comparison_graph ||= Graph.new()
    if block_given?
      yield @client_comparison_graph
      @client_comparison_graph.enlist(self)
    else
      @client_comparison_graph
    end
  end

  def target_cpu_comparison_graph(&block)

    @target_cpu_comparison_graph ||= Graph.new()
    if block_given?
      yield @target_cpu_comparison_graph
      @target_cpu_comparison_graph.enlist(self)
    else
      @target_cpu_comparison_graph
    end
  end

  def target_memory_comparison_graph(&block)

    @target_memory_comparison_graph ||= Graph.new()
    if block_given?
      yield @target_memory_comparison_graph
      @target_memory_comparison_graph.enlist(self)
    else
      @target_memory_comparison_graph
    end
  end

  class ClusterItem < TocItem

    attr_accessor :name

    def client_stats(&block)

      @client_stats ||= []
      if block_given?
        item = ClientStatItem.new(builder)
        yield item
        @client_stats.push(item)
      else
        @client_stats
      end
    end

    def comparison_graph(&block)
      @comparison_graph ||= Hailstorm::Support::ReportBuilder::Graph.new()
      if block_given?
        yield @comparison_graph
        @comparison_graph.enlist(builder)
      else
        @comparison_graph
      end
    end

    class ClientStatItem < Hailstorm::Support::ReportBuilder::TocItem

      attr_accessor :name
      attr_accessor :threads_count

      def aggregate_graph(&block)
        @aggregate_graph ||= Hailstorm::Support::ReportBuilder::Graph.new()
        if block_given?
          yield @aggregate_graph
          @aggregate_graph.enlist(builder)
        else
          @aggregate_graph
        end
      end

    end
  end

  class TargetStatItem < TocItem

    attr_accessor :role_name
    attr_accessor :host_name

    def utilization_graph(&block)
      @utilization_graph ||= Graph.new()
      if block_given?
        yield @utilization_graph
        @utilization_graph.enlist(builder)
      else
        @utilization_graph
      end
    end

    def comparison_graph(&block)
      @comparison_graph ||= Graph.new()
      if block_given?
        yield @comparison_graph
        @comparison_graph.enlist(builder)
      else
        @comparison_graph
      end
    end
  end

  class Graph
    
    attr_accessor :image_path

    # internal attributes
    attr_reader :docpr_id
    attr_reader :docpr_name
    attr_reader :cnvpr_id
    attr_reader :cnvpr_name
    attr_reader :embed_id

    def enlist(builder)

      @docpr_id = self.object_id
      @docpr_name = "Picture #{@docpr_id}"
      @cnvpr_id = @image_path.object_id
      @cnvpr_name = File.basename(@image_path)
      @embed_id = "rId#{self.object_id}"

      builder.images.push(self)
    end

  end

  def build(reports_path, report_file_name)

    @current_report_path = File.join(reports_path, report_file_name.gsub(/\/$/, ''))

    extract_docx_template()

    evaluate_template()

    report_file_path = zip_to_docx()

    #cleanup
    FileUtils.rmtree(current_report_path)

    return report_file_path
  end

  private

  def canned_doc_path
    @canned_doc_path ||= File.join(report_templates_path, report_format,
                                   "#{report_type}.docx")
  end

  def extract_docx_template()
    FileUtils.mkdir_p(current_report_path)

    Zip::ZipFile.foreach(canned_doc_path) do |zip_entry|
      disk_dir = File.dirname(zip_entry.to_s)
      FileUtils.mkdir_p(File.join(current_report_path, disk_dir))
      zip_entry.extract(File.join(current_report_path, zip_entry.to_s)) { true } # overwrite existing files
    end
  end

  def evaluate_template()

    # process images
    rels_doc_xml = nil
    rels_xml = File.join(current_report_path, 'word', '_rels', 'document.xml.rels')
    File.open(rels_xml, 'r') do |io|
      rels_doc_xml = Nokogiri::XML.parse(io)
    end
    media_path = File.join(current_report_path, 'word', 'media')

    # Remove template image reference and source
    template_image_nodeset = rels_doc_xml.xpath('//xmlns:Relationship[@Id="rId9"]')
    unless template_image_nodeset.blank?
      template_image_name = File.basename(template_image_nodeset.first['Target'])
      File.unlink(File.join(media_path, template_image_name))
      template_image_nodeset.remove()
    end

    self.images.each do |graph|
      relationship = Nokogiri::XML::Element.new('Relationship', rels_doc_xml)
      relationship['Id'] = graph.embed_id
      relationship['Type'] = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'
      relationship['Target'] = "media/#{File.basename(graph.image_path)}"
      rels_doc_xml.elements.first.add_child(relationship)
      FileUtils.move(graph.image_path, media_path)
    end
    File.open(rels_xml, 'w') do |io|
      rels_doc_xml.write_xml_to(io)
    end

    context_vars = {:report => self }

    template_file_path = File.join(report_templates_path, report_format,
                                   report_type, 'document') # document.xml.erb

    engine = ActionView::Base.new()
    engine.view_paths.push(File.dirname(template_file_path))
    engine.assign(context_vars)
    File.open(File.join(current_report_path, 'word', 'document.xml'), 'w') do |docxml|
      docxml.print(engine.render(:file => template_file_path,
                                 :formats => [:xml],
                                 :handlers => [:erb]))
    end

  end

  def zip_to_docx()

    rexp = Regexp.compile("#{current_report_path}/")
    patterns = [File.join(current_report_path, '**', '*'),
                File.join(current_report_path, '_rels', '.rels')] # explicitly add hidden file

    report_file_path = "#{current_report_path}.docx"

    FileUtils.safe_unlink(report_file_path)

    Zip::ZipFile.open(report_file_path, Zip::ZipFile::CREATE) do |zipfile|
      Dir[*patterns].sort.each do |entry|
        zip_entry = entry.gsub(rexp, '')
        if File.directory?(entry)
          zipfile.mkdir(zip_entry)
        else
          zipfile.add(zip_entry, entry) { true }
        end
      end
    end

    return report_file_path
  end

  def report_templates_path
    @report_templates_path ||= File.join(Hailstorm.templates_path, 'report')
  end

end