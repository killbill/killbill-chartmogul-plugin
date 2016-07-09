require 'sinatra'

require 'killbill'

require 'chart_mogul/updater'
require 'chart_mogul/updater_initializer'

module Killbill::Chartmogul
  class ChartmogulPlugin < Killbill::Plugin::Notification

    # For testing
    attr_reader :initializer

    def initialize
      super

      @config_key_name = 'PLUGIN_CONFIG_killbill-chartmogul'.to_sym
    end

    def start_plugin
      @logger.progname = 'chartmogul-plugin'

      super

      @initializer = Killbill::Chartmogul::UpdaterInitializer.instance
      @initializer.initialize!(@config_key_name, "#{@conf_dir}/chartmogul.yml", @kb_apis, @logger)
    end

    def on_event(event)
      if (event.event_type == :TENANT_CONFIG_CHANGE || event.event_type == :TENANT_CONFIG_DELETION) &&
          event.meta_data.to_sym == @config_key_name
        @logger.info("Invalidating plugin key='#{@config_key_name}', tenant='#{event.tenant_id}'")
        @initializer.recycle_updater(event.tenant_id)
      elsif !@initializer.nil?
        updater = @initializer.updater(event.tenant_id)
        updater.update(event.event_type, event.object_id, event.account_id, event.tenant_id) unless updater.nil?
      else
        @logger.warn "ChartMogul wasn't started properly - check logs"
      end
    end
  end
end
