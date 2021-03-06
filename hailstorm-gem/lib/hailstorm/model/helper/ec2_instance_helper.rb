# frozen_string_literal: true

require 'hailstorm/model/helper'
require 'hailstorm/behavior/loggable'
require 'hailstorm/support/waiter'

# Helper methods for EC2 instances
class Hailstorm::Model::Helper::Ec2InstanceHelper
  include Hailstorm::Behavior::Loggable
  include Hailstorm::Support::Waiter

  attr_reader :instance_client, :ssh_options, :key_name, :instance_type, :vpc_subnet_id, :zone, :region, :user_name

  # @param [Hailstorm::Model::AmazonCloud] aws_clusterable
  # @param [Hailstorm::Behavior::AwsAdaptable::InstanceClient] instance_client
  def initialize(aws_clusterable:, instance_client:)
    @instance_client = instance_client
    @ssh_options = aws_clusterable.ssh_options
    @key_name = aws_clusterable.ssh_identity
    @instance_type = aws_clusterable.instance_type
    @vpc_subnet_id = aws_clusterable.vpc_subnet_id
    @zone = aws_clusterable.zone
    @region = aws_clusterable.region
    @user_name = aws_clusterable.user_name
  end

  # Creates a new EC2 instance and returns the instance once it passes all checks.
  # @param [String] ami_id
  # @param [Array<String>] security_group_ids
  # @return [Hailstorm::Behavior::AwsAdaptable::Instance]
  def create_ec2_instance(ami_id:, security_group_ids:)
    attrs = new_ec2_instance_attrs(ami_id,
                                   security_group_ids.is_a?(Array) ? security_group_ids : [security_group_ids])
    instance = instance_client.create(attrs)
    perform_instance_checks(instance)
    instance = instance_client.find(instance_id: instance.id)
    ensure_ssh_connectivity(instance)
    instance
  end

  private

  # Builds the Hash attributes for creating a new EC2 instance.
  # @param [String] ami_id
  # @param [Array] security_group_ids
  # @return [Hash]
  def new_ec2_instance_attrs(ami_id, security_group_ids)
    attrs = { image_id: ami_id, key_name: self.key_name, security_group_ids: security_group_ids,
              instance_type: self.instance_type, subnet_id: self.vpc_subnet_id }
    attrs[:availability_zone] = self.zone if self.zone
    attrs
  end

  def perform_instance_checks(instance)
    logger.info { "Instance #{instance.id} in #{self.region} running, waiting for system checks..." }
    wait_for("#{instance.id} to start and successful system checks",
             timeout_sec: 600,
             sleep_duration: 10,
             err_attrs: { region: self.region }) { instance_client.ready?(instance_id: instance.id) }
  rescue Exception => ex
    logger.warn("Failed to create new instance: #{ex.message}")
    raise(ex)
  end

  def ensure_ssh_connectivity(instance)
    logger.info { "Ensuring SSH access to Instance #{instance.id} in #{self.region}..." }
    return if Hailstorm::Support::SSH.ensure_connection(instance.public_ip_address, self.user_name, ssh_options)

    raise(Hailstorm::Exception, "Failed to connect to #{instance.id}")
  end
end
