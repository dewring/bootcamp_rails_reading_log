require_relative "20261110232000_create_discovery_exposures"

class DropDiscoveryExposures < ActiveRecord::Migration[8.1]
  def change
    revert CreateDiscoveryExposures
  end
end
