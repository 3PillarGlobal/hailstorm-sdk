# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'web_file_store'
require 'hailstorm/support/configuration'

describe WebFileStore do
  context '#fetch_file' do
    it 'should fetch an existing file' do
      mock_response = instance_double(Net::HTTPSuccess)
      allow(mock_response).to receive(:is_a?).and_return(true)
      allow(mock_response).to receive(:body).and_return('<xml></xml>')
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      Dir.mktmpdir do |tmp_path|
        wfs = WebFileStore.new
        args = { file_id: '123', file_name: 'a.xml', to_path: tmp_path }
        local_path = wfs.fetch_file(args)
        expect(local_path).to eq("#{tmp_path}/#{args[:file_name]}")
        expect(File.read(local_path)).to eq(mock_response.body)
      end
    end

    it 'should raise error if file not found' do
      mock_response = instance_double(Net::HTTPNotFound)
      allow(mock_response).to receive(:is_a?).and_return(false)
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      wfs = WebFileStore.new
      Dir.mktmpdir do |tmp_path|
        expect do
          wfs.fetch_file({ file_id: '123', file_name: 'a.xml', to_path: tmp_path })
        end.to raise_error(Net::HTTPError)
      end
    end
  end

  context '#fetch_jmeter_plans' do
    it 'should fetch list of all plans' do
      project = Hailstorm::Model::Project.create!(project_code: 'web_file_store')
      hailstorm_config = Hailstorm::Support::Configuration.new
      hailstorm_config.jmeter.add_test_plan('123/a.jmx')
      ProjectConfiguration.create!(project_id: project.id, stringified_config: deep_encode(hailstorm_config))

      wfs = WebFileStore.new
      expect(wfs.fetch_jmeter_plans(project.project_code)).to eq(['123/a'])
    end
  end

  context '#app_dir_tree' do
    it 'should fetch a hierarchy of plans' do
      project = Hailstorm::Model::Project.create!(project_code: 'web_file_store')
      hailstorm_config = Hailstorm::Support::Configuration.new
      hailstorm_config.jmeter.add_test_plan('123/a.jmx')
      hailstorm_config.jmeter.add_test_plan('234/b.jmx')
      ProjectConfiguration.create!(project_id: project.id, stringified_config: deep_encode(hailstorm_config))

      wfs = WebFileStore.new
      parent_node = wfs.app_dir_tree(project.project_code)
      expect(parent_node.keys.size).to be == 1
      expect(parent_node.keys.first).to eq(Hailstorm.app_dir)
      expect(parent_node[Hailstorm.app_dir]).to be_nil
    end
  end

  context '#transfer_jmeter_artifacts' do
    it 'should copy all files to provided path' do
      mock_response = instance_double(Net::HTTPSuccess)
      allow(mock_response).to receive(:is_a?).and_return(true)
      allow(mock_response).to receive(:body).and_return('<xml></xml>')
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)

      project = Hailstorm::Model::Project.create!(project_code: 'web_file_store')
      hailstorm_config = Hailstorm::Support::Configuration.new
      hailstorm_config.jmeter.add_test_plan('123/a.jmx')
      hailstorm_config.jmeter.add_test_plan('234/b.jmx')
      hailstorm_config.jmeter.data_files = ['456/data.csv']
      ProjectConfiguration.create!(project_id: project.id, stringified_config: deep_encode(hailstorm_config))

      Dir.mktmpdir do |tmp_path|
        wfs = WebFileStore.new
        wfs.transfer_jmeter_artifacts(project.project_code, tmp_path)
        expect(File.exist?(File.join(tmp_path, 'a.jmx'))).to be true
        expect(File.exist?(File.join(tmp_path, 'b.jmx'))).to be true
        expect(File.exist?(File.join(tmp_path, 'data.csv'))).to be true
      end
    end
  end

  context '#normalize_file_path' do
    it 'should return second component or original' do
      wfs = WebFileStore.new
      expect(wfs.normalize_file_path('123/foo.jtl')).to eq('foo.jtl')
      expect(wfs.normalize_file_path('foo.jtl')).to eq('foo.jtl')
    end
  end

  context '#export_report' do
    it 'should upload report to file server' do
      mock_response = instance_double(Net::HTTPResponse)
      allow(mock_response).to receive(:body).and_return(JSON.dump(id: 123, originalName: 'foo.docx'))
      allow(mock_response).to receive(:is_a?).and_return(Net::HTTPSuccess)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
      wfs = WebFileStore.new
      data = wfs.export_report('acme_test', __FILE__)
      expect(data.size).to be == 2
      expect(data[0]).to be == 'http://webfs.hailstorm:9000/reports/acme_test/123/foo.docx'
    end
  end

  context '#fetch_reports' do
    it 'should fetch report list from file server' do
      mock_response = instance_double(Net::HTTPResponse)
      allow(mock_response).to receive(:body).and_return(
        JSON.dump(
          [
            { id: 123, title: 'a.docx' },
            { id: 456, title: 'b.docx' }
          ]
        )
      )

      allow(mock_response).to receive(:is_a?).and_return(Net::HTTPSuccess)
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
      wfs = WebFileStore.new
      data = wfs.fetch_reports('acme_test')
      expect(data.size).to be == 2
      expect(data[0].keys.sort).to eq(%i[id uri title].sort)
      expect(data[0][:uri]).to be == 'http://webfs.hailstorm:9000/123/a.docx'
      expect(data[1][:uri]).to be == 'http://webfs.hailstorm:9000/456/b.docx'
    end
  end

  context '#export_jtl' do
    it 'should upload the jtl to the file server' do
      mock_response = instance_double(Net::HTTPResponse)
      allow(mock_response).to receive(:body).and_return(JSON.dump(id: 123, originalName: 'foo.jtl'))
      allow(mock_response).to receive(:is_a?).and_return(Net::HTTPSuccess)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(mock_response)
      wfs = WebFileStore.new
      data = wfs.export_jtl('acme_test', __FILE__)
      expect(data.keys.sort).to eq(%i[title url].sort)
      expect(data[:url]).to be == 'http://webfs.hailstorm:9000/123/foo.jtl'
    end
  end

  context '#read_identity_file' do
    it 'should yield the response' do
      http_response = instance_double(Net::HTTPResponse)
      allow(http_response).to receive(:is_a?).and_return(true)
      allow(http_response).to receive(:body).and_return('---')
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).and_yield(http_response)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      wfs = WebFileStore.new
      wfs.read_identity_file('123/foo.pem') do |io|
        expect(io.read).to eq('---')
      end
    end
  end

  context '#purge_project' do
    it 'should delete the project resources on the file server' do
      expect(HTTParty).to receive(:delete)
      wfs = WebFileStore.new
      wfs.purge_project('project_code')
    end
  end
end
