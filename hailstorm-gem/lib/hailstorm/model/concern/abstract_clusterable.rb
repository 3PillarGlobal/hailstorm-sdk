# frozen_string_literal: true

require 'hailstorm/model/concern'
require 'fileutils'
require 'hailstorm/support/amazon_account_cleaner'

# Method implementation of `Clusterable` interface
module Hailstorm::Model::Concern::AbstractClusterable

  # Creates an load agent AMI with all required packages pre-installed and
  # starts requisite number of instances
  def setup(force: false)
    logger.debug { "#{self.class}##{__method__}" }
    self.save! if self.changed? || self.new_record?
    return unless self.active? || force

    provision_agents
  end

  # Delete SSH key-pair and identity once all load agents have been terminated
  # (see Hailstorm::Behavior::Clusterable#cleanup)
  def cleanup
    logger.debug { "#{self.class}##{__method__}" }
    return unless self.active? && self.autogenerated_ssh_key? && self.load_agents.reload.empty?

    key_pair_id = client_factory.key_pair_client.find(name: self.ssh_identity)
    return unless key_pair_id

    client_factory.key_pair_client.delete(key_pair_id: key_pair_id)
    FileUtils.safe_unlink(identity_file_path)
  end

  # Purges the Amazon accounts used of Hailstorm related artifacts
  def purge(cleaner = nil)
    logger.debug { "#{self}.#{__method__}" }
    cleaner ||= Hailstorm::Support::AmazonAccountCleaner.new(client_factory: client_factory,
                                                             region_code: self.region)
    cleaner.cleanup
    self.update_column(:agent_ami, nil)
  end
end
