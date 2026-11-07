module DevelopmentReadingScenarioSetup
  private

  def prepare_scenario_data
    manifest = DevelopmentReadingScenarioManifest.new(path: @paths.fetch(:manifest_path), lock_path: @paths.fetch(:lock_path))
    manifest.with_exclusive_access do
      # Setup must finish successfully. Save once here; the operation under test still checkpoints each record.
      result = manifest.stub(:save_scenario, nil) { yield manifest }
      manifest.save_scenario
      result
    end
  end
end
