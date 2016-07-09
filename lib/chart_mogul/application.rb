configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    require 'logger'
    Killbill::Chartmogul::UpdaterInitializer.instance.initialize! 'PLUGIN_CONFIG_killbill-chartmogul'.to_sym,
                                                                  nil,
                                                                  Logger.new(STDOUT)
  end
end
