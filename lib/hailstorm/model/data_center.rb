# DataCenter model - models the configuration for creating load agent
# on the Data Center.

require 'aws'
require 'hailstorm'
require 'hailstorm/model'
require 'hailstorm/behavior/clusterable'
require 'hailstorm/support/ssh'
require 'hailstorm/support/amazon_account_cleaner'

class Hailstorm::Model::DataCenter < ActiveRecord::Base
  include Hailstorm::Behavior::Clusterable

  before_validation :set_defaults

  before_save :check_machine_status, :if => proc {|r| r.active? and r.agent_ami.nil?}

  after_destroy :cleanup

  # Seconds between successive Data Center status checks
  DOZE_TIME = 5

  # Creates a data center load agent with all required packages pre-installed and
  # starts requisite number of instances
  def setup(force = false)
    logger.debug { "#{self.class}##{__method__}" }
    if self.active?
      self.agent_ami = nil if force
      self.save!()
      provision_agents()
      File.chmod(0400, identity_file_path())
    else
      self.update_column(:active, false) if self.persisted?
    end
  end

  # start the agent and update agent ip_address and identifier
  def start_agent(load_agent)
    logger.debug { load_agent.attributes.inspect }
    unless load_agent.running?
      agent_data_center_instance = nil
      unless load_agent.identifier.nil?
        agent_data_center_instance = data_center.instances[load_agent.identifier]
        if :stopped == agent_data_center_instance.status
          logger.info("Restarting agent##{load_agent.identifier}...")
          agent_data_center_instance.start()
          timeout_message("#{agent_data_center_instance.id} to restart") do
            wait_until { agent_data_center_instance.status.eql?(:running) }
          end
        end
      else
        logger.info("Starting new agent on #{self.region}...")
        agent_data_center_instance = ec2.instances.create(
            {:image_id => self.agent_ami,
             :key_name => self.ssh_identity,
             :security_groups => self.security_group.split(/\s*,\s*/),
             :instance_type => self.instance_type}.merge(
                self.zone.nil? ? {} : {:availability_zone => self.zone}
            )
        )
        timeout_message("#{agent_data_center_instance.id} to start") do
          wait_until { agent_data_center_instance.exists? && agent_data_center_instance.status.eql?(:running) }
        end
      end

      # update attributes
      load_agent.identifier = agent_data_center_instance.instance_id
      load_agent.public_ip_address = agent_data_center_instance.public_ip_address
      load_agent.private_ip_address = agent_data_center_instance.private_ip_address

      # SSH is available a while later even though status may be running
      logger.info { "agent##{load_agent.identifier} is running, ensuring SSH access..." }
      sleep(120)
      logger.debug { "sleep over..."}
      Hailstorm::Support::SSH.ensure_connection(load_agent.public_ip_address,
                                                self.user_name, ssh_options)

    end
  end

  # stop the load agent
  def stop_agent(load_agent)
    logger.debug { "#{self.class}##{__method__}" }
    unless load_agent.identifier.nil?
      agent_data_center_instance = data_center.instances[load_agent.identifier]
      if :running == agent_data_center_instance.status
        logger.info("Stopping agent##{load_agent.identifier}...")
        agent_data_center_instance.stop()
        timeout_message("#{agent_data_center_instance.id} to stop") do
          wait_until { agent_data_center_instance.status.eql?(:stopped) }
        end
      end
    else
      logger.warn("Could not stop agent as identifier is not available")
    end
  end

  # @return [Hash] of SSH options
  # (see Hailstorm::Behavior::Clusterable#ssh_options)
  def ssh_options()
    @ssh_options ||= {:keys => identity_file_path()}
  end

  # Start load agents if not started
  # (see Hailstorm::Behavior::Clusterable#before_generate_load)
  def before_generate_load()

    logger.debug { "#{self.class}##{__method__}" }
    self.load_agents.where(:active => true).each do |agent|
      unless agent.running?
        start_agent(agent)
        agent.save!
      end
    end
  end

  # Terminate load agent
  # (see Hailstorm::Behavior::Clusterable#before_destroy_load_agent)
  def before_destroy_load_agent(load_agent)

    logger.debug { "#{self.class}##{__method__}" }
    agent_data_center_instance = data_center.instances[load_agent.identifier]
    if agent_data_center_instance.exists?
      logger.info("Terminating agent##{load_agent.identifier}...")
      agent_data_center_instance.terminate()
      timeout_message("#{agent_data_center_instance.id} to terminate") do
        wait_until { agent_data_center_instance.status.eql?(:terminated) }
      end
    else
      logger.warn("Agent ##{load_agent.identifier} does not exist on EC2")
    end
  end



  # Delete SSH key-pair and identity once all load agents have been terminated
  # (see Hailstorm::Behavior::Clusterable#cleanup)

  ### DO WE NEED THIS #############################################
  def cleanup()

    logger.debug { "#{self.class}##{__method__}" }
    if self.autogenerated_ssh_key?
      if self.load_agents(true).empty?
        key_pair = data_center.key_pairs[self.ssh_identity]
        if key_pair.exists?
          key_pair.delete()
          FileUtils.safe_unlink(identity_file_path)
        end
      end
    end
  end


  # (see Hailstorm::Behavior::Clusterable#slug)
  def slug()
    @slug ||= "#{self.class.name.demodulize.titlecase}, region: #{self.region}"
  end

  # (see Hailstorm::Behavior::Clusterable#public_properties)
  def public_properties()
    columns = [:region]
    self.attributes.symbolize_keys.slice(*columns)
  end

  # Purges the Amazon accounts used of Hailstorm related artifacts

  ################## NEED TO MODIFY ACCORDING TO SCHEMA
  def self.purge()
    self.group(:access_key, :secret_key)
    .select("access_key, secret_key")
    .each do |item|
      cleaner = Hailstorm::Support::AmazonAccountCleaner.new(
          :access_key_id => item.access_key,
          :secret_access_key => item.secret_key
      )
      regions = []
      self.where(:access_key => item.access_key, :secret_key => item.secret_key)
      .each do |record|
        record.update_column(:agent_ami, nil)
        regions.push(record.region)
      end
      cleaner.cleanup(false, regions)
    end
  end


  ######################### PRIVATE METHODS ####################################
  private

  #################### WE ARE NOY USING KEY FOR NOW SO WE DON'T NEED THESE FUNCTIONS
  # def identity_file_exists()
  #
  # end
  #
  # def identity_file_path()
  #
  # end
  #
  # def identity_file_name()
  #
  # end


  def set_defaults()
    self.user_name ||= Defaults::SSH_USER
    self.password ||= Defaults::Defaults
    self.ip_address ||= Defaults::IP_ADDRESS
    self.machine_type ||= Defaults::MACHINE_TYPE
    self.max_threads_per_machine ||= default_max_threads_per_machine()

    if self.ssh_identity.nil?
      self.ssh_identity = [Defaults::SSH_IDENTITY, Hailstorm.app_name].join('_')
      self.autogenerated_ssh_key = true
    end

  end

  def check_machine_status

  end

  def data_center
    @data_center ||= AWS::EC2.new(aws_config)
    .regions[self.region]
  end

  def java_download_url()
    @java_download_url ||= s3_bucket().objects[java_download_file_path()]
    .public_url(:secure => false)
  end

  def jmeter_download_url()
    @jmeter_download_url ||= jmeter_s3_object().public_url(:secure => false)
  end

  def jmeter_s3_object()
    s3_bucket().objects[jmeter_download_file_path]
  end

  def s3_bucket()
    @s3_bucket ||= s3.buckets[Defaults::BUCKET_NAME]
  end

  def jmeter_download_file()
    "#{jmeter_directory}.tgz"
  end

  # Path relative to S3 bucket
  def jmeter_download_file_path()
    "open-source/#{jmeter_download_file}"
  end

  # Expanded JMeter directory
  def jmeter_directory
    version = self.project.jmeter_version
    "#{version == '2.4' ? 'jakarta' : 'apache'}-jmeter-#{version}"
  end

  # Architecture as per instance_type - i386 or x86_64, if internal is true,
  # 32-bit or 64-bit. Everything other than m1.small instance_type is x86_64.
  def arch(internal = false)

    if self.instance_type == InstanceTypes::Hydrogen
      internal ? '32-bit' : 'i386'
    else
      internal ? '64-bit' : 'x86_64'
    end
  end

  ################# NEED TO CHK AND CHANGE ACCORDINGLY
  # The AMI ID to search for and create
  # def ami_id
  #   "#{Defaults::AMI_ID}-j#{self.project.jmeter_version}-#{arch()}"
  # end

  # # Base AMI to use to create Hailstorm AMI based on the region and instance_type
  # # @return [String] Base AMI ID
  # def base_ami()
  #   region_base_ami_map[self.region][arch(true)]
  # end

  ############################## WE DON't NEED THIS
  # def region_base_ami_map()
  #
  # end

  def java_download_file()
    @java_download_file ||= {
        '32-bit' => 'jre-6u31-linux-i586.bin',
        '64-bit' => 'jre-6u33-linux-x64.bin'
    }[arch(true)]
  end

  def java_download_file_path()
    "open-source/#{java_download_file()}"
  end

  def jre_directory()
    @jre_directory ||= {
        '32-bit' => 'jre1.6.0_31',
        '64-bit' => 'jre1.6.0_33'
    }[arch(true)]
  end

  def instance_type_supported()

    unless InstanceTypes.valid?(self.instance_type)
      errors.add(:instance_type,
                 "not in supported list (#{InstanceTypes.allowed})")
    end
  end

  # @return [String] thead-safe name for the downloaded environment file
  def current_env_file_name()
    "environment-#{self.id}~"
  end

  # @return [String] thread-safe name for environment file to be written locally
  # for upload to agent.
  def new_env_file_name()
    "environment-#{self.id}"
  end

  # Waits for <tt>timeout_sec</tt> seconds for condition in <tt>block</tt>
  # to return true, else throws a Timeout::Error
  # @param [Integer] timeout_sec
  # @param [Proc] block
  # @raise [Timeout::Error] if block does not return true within timeout_sec
  def wait_until(timeout_sec = 300, &block)
    # make the timeout configurable by an environment variable
    timeout_sec = ENV['HAILSTORM_EC2_TIMEOUT'] || timeout_sec
    total_elapsed = 0
    while total_elapsed <= (timeout_sec * 1000)
      before_yield_time = Time.now.to_i
      result = yield
      if result
        break
      else
        sleep(DOZE_TIME)
        total_elapsed += (Time.now.to_i - before_yield_time)
      end
    end
  end

  def timeout_message(message, &block)
    begin
      yield
    rescue Timeout::Error
      raise(Hailstorm::Exception, "Timeout while waiting for #{message} on #{self.region}.")
    end
  end

  def default_max_threads_per_machine()
    @default_max_threads_per_machine ||= 100
  end

  # Data center default settings
  class Defaults
    BUCKET_NAME         = 'brickred-perftest'
    SSH_USER            = 'ubuntu'
    SSH_PASS            = 'hailstorm'
    MACHINE_TYPE        = '64-bit'
    IP_ADDRESS          = '127.0.0.1'
  end


end