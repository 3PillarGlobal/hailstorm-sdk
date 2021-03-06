# frozen_string_literal: true

require 'spec_helper'

require 'hailstorm/support/workspace'
require 'stringio'

describe Hailstorm::Support::Workspace do
  context '#make_app_layout' do
    it 'should create the directory layout' do
      rel_paths = []
      allow(FileUtils).to receive(:mkdir_p) { |path| rel_paths << path }
      allow_any_instance_of(Hailstorm::Support::Workspace).to receive(:create_file_layout)
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      layout = {
        jmeter: {
          a: nil,
          b: {
            c: nil,
            d: { e: nil }
          }
        }
      }.deep_stringify_keys
      workspace.make_app_layout(layout)
      expect(rel_paths).to include(workspace.app_path)
      expect(rel_paths).to include("#{workspace.app_path}/a")
      expect(rel_paths).to include("#{workspace.app_path}/b")
      expect(rel_paths).to include("#{workspace.app_path}/b/c")
      expect(rel_paths).to include("#{workspace.app_path}/b/d")
      expect(rel_paths).to include("#{workspace.app_path}/b/d/e")
    end
  end

  context '#open_app_file' do
    it 'should yield a file object' do
      allow_any_instance_of(Hailstorm::Support::Workspace).to receive(:create_file_layout)
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      jmx_path = File.expand_path('../../../features/data/hailstorm-site-basic.jmx', __FILE__)
      allow(File).to receive(:join).and_return(jmx_path)
      file_objects = []
      workspace.open_app_file('any') { |io| file_objects << io }
      expect(file_objects).to_not be_empty
    end
  end

  context '#app_entries' do
    it 'should return list of full paths to artifacts in app directory' do
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      expect(workspace.app_entries).to be_empty
    end
  end

  context '#remove_workspace' do
    it 'should delete the project workspace directory' do
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      workspace.create_file_layout
      expect(File.exist?(workspace.workspace_path)).to be true
      workspace.remove_workspace
      expect(File.exist?(workspace.workspace_path)).to be false
    end
  end

  context '#write_identity_file' do
    it 'should copy from io' do
      read_io = StringIO.new('Hello World')
      write_io = StringIO.new(+'', 'w')
      allow(File).to receive(:open).and_yield(write_io)
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      abs_path = workspace.write_identity_file('insecure', read_io)
      expect(abs_path).to_not be_nil
      expect(read_io.string).to eq(write_io.string)
    end
  end

  context '#purge' do
    it 'should re-create file layout and remove files' do
      allow(FileUtils).to receive(:rm_rf)
      workspace = Hailstorm::Support::Workspace.new('workspace_spec')
      expect(workspace).to receive(:create_file_layout)
      workspace.purge
    end
  end
end
