namespace :development_scenario do
  desc "Capture 100 Open Library Works for offline development seed replay (development only)"
  task capture_catalog: :environment do
    snapshot = OpenLibraryCatalogCapture.new.capture_catalog
    $stdout.write("Captured #{snapshot.fetch('selected').length} Works in #{snapshot.fetch('http_attempts')} HTTP attempts.\n")
    $stdout.write("Snapshot: #{Rails.root.join('db/seeds/open_library_catalog.json')}\n")
    $stdout.write("Snapshot ID: #{snapshot.fetch('snapshot_id')}\n")
    $stdout.write("Skipped records: #{snapshot.fetch('skipped').length}\n")
    snapshot.fetch("skipped").each { |record| $stdout.write("#{record.to_json}\n") }
  rescue OpenLibraryCatalogCapture::CaptureError => error
    $stderr.write("#{error.message}\n")
    $stderr.write("#{JSON.pretty_generate(error.report)}\n")
    abort "Catalog capture failed."
  end
end
