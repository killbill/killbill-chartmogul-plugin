require 'active_support/core_ext/string'
require 'erb'
require 'pathname'
require 'thread_safe'

module Killbill::Chartmogul
  class UpdaterInitializer
    include Singleton

    def initialize!(config_key_name, config_file, kb_apis, logger)
      @config_key_name = config_key_name
      @kb_apis = kb_apis
      @logger = logger

      @per_tenant_config_cache = ThreadSafe::Cache.new

      # Look for global config
      if !config_file.blank? && Pathname.new(config_file).file?
        path = Pathname.new(config_file).expand_path
        @glob_config = YAML.load(ERB.new(File.read(path.to_s)).result)
      else
        @glob_config = {}
      end
    end

    def recycle_updater(kb_tenant_id)
      @per_tenant_config_cache[kb_tenant_id] = nil
    end

    def updater(kb_tenant_id)
      config = get_tenant_config(kb_tenant_id)
      if config.nil?
        @logger.warn "ChartMogul wasn't configured properly for kbTenantId='#{kb_tenant_id}'"
        return nil
      else
        ::Killbill::Chartmogul::Updater.new(config[:chartmogul], @kb_apis, @logger)
      end
    end

    private

    def get_tenant_config(kb_tenant_id)
      if @per_tenant_config_cache[kb_tenant_id].nil?
        # Make the api api to verify if there is a per tenant value
        context = @kb_apis.create_context(kb_tenant_id) if kb_tenant_id
        values = @kb_apis.tenant_user_api.get_tenant_values_for_key(@config_key_name, context) if context
        # If we have a per tenant value, insert it into the cache
        if values && values[0]
          parsed_config = YAML.load(values[0])
          @per_tenant_config_cache[kb_tenant_id] = parsed_config
        else
          # Otherwise, add global config so we don't have to make the tenant call on each operation
          @per_tenant_config_cache[kb_tenant_id] = @glob_config
        end
      end
      # Return value from cache in any case
      @per_tenant_config_cache[kb_tenant_id]
    end
  end
end
