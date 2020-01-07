require 'ostruct'

include CliStepHelper
include ConsoleAppHelper

Given(/^I have [hH]ailstorm installed$/) do
  $LOAD_PATH.unshift(File.expand_path('../../../../hailstorm-gem/lib', __FILE__))
  $LOAD_PATH.unshift(File.expand_path('../../../lib', __FILE__))
  require 'hailstorm/initializer'
end

When(/^I created? (a new|the) project "([^"]*)"$/) do |new_str, project_name|
  project_path = File.join(tmp_path, project_name)
  FileUtils.rmtree(project_path) if new_str =~ /new/
  unless File.exists?(project_path)
    gems = [
        OpenStruct.new(name: 'hailstorm', path: File.expand_path('../../../../hailstorm-gem', __FILE__)),
        OpenStruct.new(name: 'hailstorm-cli', path: File.expand_path('../../..', __FILE__)),
    ]

    Hailstorm::Initializer.create_project!(tmp_path, project_name, false, gems)
  end
end

Then(/^the project structure for "([^"]*)" (?:should be|is) created$/) do |top_folder|
  project_path = File.join(tmp_path, top_folder)
  expect(File).to exist(project_path)
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.db_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.app_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.log_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.tmp_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.reports_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.config_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.vendor_dir))
  expect(File).to be_a_directory(File.join(project_path, Hailstorm.script_dir))
  expect(File).to be_a_directory(project_path)
  expect(File).to be_a_directory(project_path)
  expect(File).to exist(File.join(project_path, 'Gemfile'))
  expect(File).to exist(File.join(project_path, Hailstorm.script_dir, 'hailstorm'))
  expect(File).to exist(File.join(project_path, Hailstorm.config_dir, 'environment.rb'))
  expect(File).to exist(File.join(project_path, Hailstorm.config_dir, 'database.properties'))
  expect(File).to exist(File.join(project_path, Hailstorm.config_dir, 'boot.rb'))
end

When(/^I launch the hailstorm console within "([^"]*)" project$/) do |project_name|
  require 'pty'
  @master, slave = PTY.open
  read, @write = IO.pipe
  @pid = spawn(File.join(tmp_path, project_name, Hailstorm.script_dir, 'hailstorm'), in: read, out: slave)
  sleep 10
  read.close
  slave.close
  puts @master.read_nonblock(4096)
  # current_project(project_name)
  # write_config(@monitor_active) # reset
  # Dir[File.join(tmp_path, project_name, Hailstorm.reports_dir, '*')].each do |file|
  #   FileUtils.rm(file)
  # end
  # if cli.blank?
  #   boot_file_path = File.join(tmp_path, project_name, Hailstorm.config_dir, 'boot.rb')
  #   Hailstorm::Initializer.create_middleware(project_name, boot_file_path)
  # else
  #   spawn_hailstorm(File.join(tmp_path, project_name, Hailstorm.script_dir, 'hailstorm'))
  # end
end

Then(/^the application should (be ready to accept|execute) commands?(?:|\s+"([^"]*)")$/) do |exec, command|
  if exec =~ /execute/
    @write.puts command
    sleep 3
    response = @master.read_nonblock(4096)
    puts response
    expect(response).to_not be_blank
    @write.puts 'exit'
    sleep 3
    @write.close
    @master.close
    Process.wait(@pid)
  end
  # if exec =~ /execute/ #&& hailstorm_spawned?
  #   # exec_hailstorm(File.join(tmp_path, current_project, Hailstorm.script_dir, "hailstorm --cmd #{command}"))
  #   puts "Going to issue command '#{command}'..."
  #   write_hailstorm_pty(command)
  #   sleep(5)
  #   cmd_response = read_hailstorm_pty
  #   puts cmd_response
  #   expect(cmd_response).to_not be_blank
  #   expect(cmd_response).to_not match('ERROR')
  # # elsif hailstorm_spawned?
  # #   write_hailstorm_pty(command || 'purge')
  # #   sleep(5)
  # #   cmd_response = read_hailstorm_pty
  # #   expect(cmd_response).to_not match('ERROR')
  # # else
  # #   Hailstorm.application.interpret_command('purge')
  # #   expect(Hailstorm::Model::ExecutionCycle.count).to eql(0)
  # #   Hailstorm::Model::Project.first.update_attribute(:serial_version, nil)
  # #   expect(Dir[File.join(tmp_path, current_project, Hailstorm.tmp_dir, '*')].count).to eql(0)
  # end
end

When(/^I type command '(.+?)'(| and exit)$/) do |command, exit|
  @write.puts command
  sleep 3
  # if hailstorm_spawned?
  # write_hailstorm_pty(command)
    # else
    #   Hailstorm.application.interpret_command(command)
  # end
end

Then(/^the application should show the response and exit$/) do
  response = @master.read_nonblock(4096)
  puts response
  expect(response).to_not be_blank
  @write.puts 'exit'
  sleep 3
  @write.close
  @master.close
  Process.wait(@pid)
  # if hailstorm_spawned?
  # expect(hailstorm_exit_ok?).to be_true
  # else
  #   expect(Hailstorm.application.instance_variable_get('@exit_command_counter')).to be < 0
  # end
end

# Given(/^the "([^"]*)" project(?:| is active)$/) do |project_name|
#   current_project(project_name)
# end

When(/^(?:I |)configure JMeter with following properties$/) do |table|
  [
      'hailstorm-site-basic.jmx'
  ].each do |test_file|
    file_path = File.join(tmp_path, current_project, Hailstorm.app_dir, test_file)
    unless File.exist? file_path
      FileUtils.cp(File.join(data_path, test_file), file_path)
    end
  end
  jmeter_properties(table.hashes)
end

When(/^(?:I |)configure following amazon clusters$/) do |table|
  clusters(table.hashes.collect { |e| e.merge(cluster_type: :amazon_cloud) })
end

When(/^(?:I |)configure target monitoring$/) do
  identity_file = File.join(tmp_path, current_project, Hailstorm.config_dir, 'all_purpose.pem')
  unless File.exists?(identity_file)
    FileUtils.cp(File.join(data_path, 'all_purpose.pem'),
               File.join(tmp_path, current_project, Hailstorm.config_dir))
    File.chmod(0400, identity_file)
  end
end

When(/^(?:I |)execute "(.*?)" command$/) do |command|
  write_config(@monitor_active) if config_changed?
  Hailstorm.application.interpret_command(command)
end

Then(/^(\d+) (active |)load agents? should exist$/) do |expected_load_agent_count, active|
  if active.blank?
    Hailstorm::Model::LoadAgent.count.should == expected_load_agent_count.to_i
  else
    Hailstorm::Model::LoadAgent.active.count.should == expected_load_agent_count.to_i
  end
end

Then(/^(\d+) Jmeter instances? should be running$/) do |expected_pid_count|
  Hailstorm::Model::LoadAgent.active.where('jmeter_pid IS NOT NULL').count.should == expected_pid_count.to_i
end

When /^(?:I |)wait for (\d+) seconds$/ do |wait_seconds|
  sleep(wait_seconds.to_i)
end

When /^(\d+) (total|reportable) execution cycles? should exist$/ do |expected_count, total|
  if total.to_sym == :reportable
    Hailstorm::Model::ExecutionCycle.where(:status => 'stopped').count.should == expected_count.to_i
  else
    Hailstorm::Model::ExecutionCycle.count.should == expected_count.to_i
  end
end

Then /^a report file should be created$/ do
  Dir[File.join(tmp_path, current_project, Hailstorm.reports_dir, '*.docx')].count.should == 1
end

And(/^results import '(.+?)'$/) do |file_path|
  Hailstorm.application.interpret_command('purge')
  expect(Hailstorm::Model::ExecutionCycle.count).to eql(0)
  abs_path = File.expand_path(file_path, __FILE__)
  Hailstorm.application.interpret_command("results import #{abs_path}")
  expect(Hailstorm::Model::ExecutionCycle.count).to eql(1)
end

And(/^(?:disable |)target monitoring(?:| is disabled)$/) do
  @monitor_active = false
end
