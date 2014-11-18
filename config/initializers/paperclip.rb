Paperclip.options[:content_type_mappings] = {
    :jmx => 'application/xml'
}


module Paperclip
  module Interpolations
    def project_id(attachment, style_name)
      attachment.instance.project_id
    end
  end
end