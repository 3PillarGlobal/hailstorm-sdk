# DataCenter model - models the configuration for creating load agent
# on the Data Center.

require 'hailstorm'
require 'hailstorm/model'
require 'hailstorm/behavior/clusterable'
require 'hailstorm/support/ssh'

class Hailstorm::Model::DataCenter < ActiveRecord::Base
  include Hailstorm::Behavior::Clusterable

  serialize :machines

  before_validation :set_defaults

  validate :identity_file_exists, :if => proc {|r| r.active?}

  validates_presence_of :user_name, :machines, :ssh_identity

  after_destroy :cleanup

  # Seconds between successive Data Center status checks
  DOZE_TIME = 5

  # Creates a data center load agent with all required packages pre-installed and
  # starts requisite number of instances
  def setup(force = false)
    logger.debug { "#{self.class}##{__method__}" }

    puts "\tTotal machines available for this cluster : #{self.machines.count()}"

    # create load agents
    if self.active?
      self.save!()
      puts "\tProvisioning data-center agents"
      provision_agents()
    else
      self.update_column(:active, false) if self.persisted?
    end
  end

  # check ssh access to agent and update agent ip_address and identifier
  def start_agent(load_agent)
    logger.debug { "#{self.class}##{__method__}" }
    if load_agent.private_ip_address.nil?
      ip = self.machines.shift()
      # update attributes
      load_agent.identifier = ip
      load_agent.public_ip_address = nil
      load_agent.private_ip_address = ip

      puts "\t\tData-center agent##{load_agent.private_ip_address} checking SSH connection..."
      if !check_connection?(load_agent.private_ip_address)
        raise(Hailstorm::DataCenterAccessFailure.new(self.user_name, self.machines, self.ssh_identity))
      end

      # puts "\t\tData-center agent##{load_agent.private_ip_address} checking jmeter install..."
      # if !jmeter_installed?(load_agent)
      #   raise(new Exception('Error:JMeter is not installed'))
      # end
      #
      # puts "\t\tData-center agent##{load_agent.private_ip_address} checking java install..."
      # if !java_installed?(load_agent)
      #   raise(new Exception('Error:Java is not installed'))
      # end

      #TODO: Check JMeter and Java version
    end
  end

  # stop the load agent
  def stop_agent(load_agent)
    logger.debug { "#{self.class}##{__method__}" }
  end

  #@return [Hash] of SSH options
  #(see Hailstorm::Behavior::Clusterable#ssh_options)
  def ssh_options()
    @ssh_options ||= {:keys => [identity_file_path()] }
  end

  # Start load agents if not started
  # (see Hailstorm::Behavior::Clusterable#before_generate_load)
  def before_generate_load()
    logger.debug { "#{self.class}##{__method__}" }
    self.load_agents.where(:active => true).each do |agent|
      unless agent.private_ip_address.nil?
        start_agent(agent)
        agent.save!
      end
    end
  end

  # Process the suspend option. Must be specified as {:suspend => true}
  # @param [Hash] options
  # (see Hailstorm::Behavior::Clusterable#after_stop_load_generation)
  def after_stop_load_generation(options = nil)

    logger.debug { "#{self.class}##{__method__}" }
    suspend = (options.nil? ? false : options[:suspend])
    if suspend
      self.load_agents.where(:active => true).each do |agent|
        if agent.running?
          stop_agent(agent)
          agent.private_ip_address = nil
          agent.save!
        end
      end
    end
  end

  def required_load_agent_count()
    return self.machines.count()
  end

  # Terminate load agent
  # (see Hailstorm::Behavior::Clusterable#before_destroy_load_agent)
  def before_destroy_load_agent(load_agent)
    logger.debug { "#{self.class}##{__method__}" }
  end

  # (see Hailstorm::Behavior::Clusterable#slug)
  def slug()
    @slug ||= "#{self.class.name.demodulize.titlecase}, data center: #{self.title}"
  end

  # Purges the artifacts created on data center machines.
  def self.purge()
    logger.debug { "#{self.class}##{__method__}" }
  end

  ######################### PRIVATE METHODS ####################################
  private

  def identity_file_exists()
    return File.exists?(identity_file_path)
  end

  def identity_file_path()
    @identity_file_path ||= File.join(Hailstorm.root, Hailstorm.db_dir, self.ssh_identity)
  end

  def set_defaults()

    self.user_name = Defaults::SSH_USER if self.user_name.blank?
    #self.user_name ||= Defaults::SSH_USER
    self.title = Defaults::TITLE if self.title.blank?
    #self.title ||= Defaults::TITLE
    if self.ssh_identity.nil?
      self.ssh_identity = [Defaults::SSH_IDENTITY, Hailstorm.app_name].join('_')
    end
  end

  def check_connection?(ip_address)

    connection_obtained = false
    begin
      Hailstorm::Support::SSH.start(ip_address, self.user_name, ssh_options()) do |ssh|
        ssh.exec!("ls")
        connection_obtained = true
      end
    rescue Errno::ECONNREFUSED, Net::SSH::ConnectionTimeout
      logger.debug { "Failed to ssh to machine : #{ip_address}" }
    end

    return connection_obtained
  end

  # check if java is installed on agent or not
  # @return
  def java_installed?(load_agent)
    logger.debug { "#{self.class}##{__method__}" }
    java_available = false
    Hailstorm::Support::SSH.start(load_agent.private_ip_address,self.user_name, ssh_options) do |ssh|
      output = ssh.exec!("command -pv java")
      logger.debugger ("output of java check #{output}")
      if not output.nil? and output.include? "java"
        java_available = true
      end
    end
    return java_available
  end

  def jmeter_installed?(load_agent)
    jmeter_available = false
    Hailstorm::Support::SSH.start(load_agent.private_ip_address,self.user_name, ssh_options) do |ssh|
      output = ssh.exec!("command -pv jmeter")
      logger.debugger ("output of java check #{output}")
      if not output.nil? and output.include? "jmeter"
        jmeter_available = true
      end
    end
    return jmeter_available
  end

  def java_version_ok?

  end

  def jmeter_version_ok?

  end

  # Data center default settings
  class Defaults
    SSH_USER            = 'ubuntu'
    SSH_IDENTITY        = 'server.pem'
    TITLE               = 'Hailstorm'
  end
end